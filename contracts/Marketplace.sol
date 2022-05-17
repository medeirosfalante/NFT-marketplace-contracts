//SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

import "@openzeppelin/contracts/access/Ownable.sol";

import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

import "./interfaces/IMarketplace.sol";

import "./interfaces/IERC721.sol";
import "./interfaces/IERC20.sol";
import "./interfaces/IERC20Metadata.sol";

import "./FeeManager.sol";

// todo: think about how on transfer we can delete the ask of prev owner
// might not be necessary if we bake in checks, and if checks fail: delete
// todo: check out 0.8.9 custom types
contract Marketplace is Pausable, FeeManager, IMarketplace, AccessControl {
    using Address for address;
    using SafeMath for uint256;
    using Counters for Counters.Counter;

    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    string public constant UNAUTHORIZED_SENDER =
        "Marketplace: unauthorized sender";

    string public constant ASSET_NOT_PUBLISHED =
        "Marketplace: asset not published";

    string public constant SENDER_NOT_ALLOWED =
        "Marketplace: sender not allowed";
    string public constant ORDER_EXPIRED = "Marketplace: order expired";

    string public constant PRICE_SHOULD_BE_BIGGER_THAN =
        "Marketplace: Price should be bigger than 0";
    string public constant EXPIRE_TIME_SHOULD_BE_MORE_THAN =
        "Marketplace: Expire time should be more than 1 minute in the future";

    string public constant INVALID_PRICE = "Marketplace: invalid price";

    string public constant PRICE_IS_NOT_RIGHT =
        "Marketplace : price is not right";

    string public constant BID_SHOULD_BE_ZERO =
        "Marketplace: bid should be > 0";

    string public constant ONLY_THE_ASSET_OWNER_CAN_CREATE_ORDERS =
        "Marketplace: Only the asset owner can create orders";

    string
        public constant PUBLICATION_SHOULD_BE_MORE_THAT_ONE_MINUTE_IN_THE_FUTURE =
        "Marketplace: Publication should be more than 1 minute in the future";

    string public constant INVALID_BID_PRICE = "Marketplace: invalid bid price";
    string public constant BID_EXPIRED = "Marketplace: the bid expired";

    string public constant BID_PRICE_SHOULD_BE_HIGHER_THAT_LAST_BID =
        "Marketplace: bid price should be higher than last bid";

    string public constant ADDRESS_SHOULD_BE_A_CONTRACT =
        "The NFT Address should be a contract";
    string public constant TOKEN_IS_IVALID =
        "StableCoin: token not support in marketplace call listTokens() and check tokens supported";

    string public constant OWNER_COLLECTION_INVALID =
        "Collection: Only the collection owner can add nft";

    string public constant NFT_ASSET_DONT_EXISTS =
        "Collection: Only the assset owner can add nft";
    IERC20 public acceptedToken;

    string public constant COLLECTION_DONT_EXISTS =
        "Collection: you need create collection before add nft";
    string public constant COLLECTION_NAME_EMPATY =
        "Collection: Name cannot be empty";
    string public constant COLLECTION_ICON_EMPATY =
        "Collection: Icon cannot be empty";

    string public constant CATEGORY_IS_IVALID = "Category: invalid category";

    Counters.Counter private _itemIds;
    Counters.Counter private _itemsSold;
    Counters.Counter private _totalTokens;
    Counters.Counter public _totalCollection;
    Counters.Counter private _totalCollectionItems;
    Counters.Counter private _totalCategory;
    // From ERC721 registry assetId to Order (to avoid asset collision)
    mapping(address => mapping(uint256 => Order)) public orderByAssetId;

    // From ERC721 registry assetId to Bid (to avoid asset collision)
    mapping(address => mapping(uint256 => Bid)) public bidByOrderId;
    mapping(address => IERC721) public nftRegistered;
    mapping(uint256 => Token) public tokensSupport;
    mapping(address => Order[]) private _ordersByUsers;
    mapping(uint256 => Order) private _orders;
    mapping(uint256 => Category) private _categories;
    mapping(uint256 => Collection) private _collections;
    mapping(uint256 => mapping(uint256 => CollectionItem))
        private _collectionsItems;

    mapping(address => mapping(uint256 => Bid[])) public bidHistoryByOrderId;
    mapping(address => mapping(uint256 => address[]))
        public ownerHistoryByOrderId;

    // 721 Interfaces
    bytes4 public constant _INTERFACE_ID_ERC721 = 0x80ac58cd;

    /**
     * @dev Initialize this contract. Acts as a constructor
     */
    constructor() Ownable() {
        _setupRole(MANAGER_ROLE, msg.sender);
    }

    /**
     * @dev Sets the paused failsafe. Can only be called by owner
     * @param _setPaused - paused state
     */
    function setPaused(bool _setPaused) public onlyRole(MANAGER_ROLE) {
        return (_setPaused) ? _pause() : _unpause();
    }

    /**
     * @dev Creates a new order
     * @param _nftAddress - Non fungible registry address
     * @param _assetId - ID of the published NFT
     * @param _priceInWei - Price in Wei for the supported coin
     * @param _expiresAt - Duration of the order (in hours)
     */
    function createOrder(
        address _nftAddress,
        uint256 _assetId,
        uint256 _priceInWei,
        uint256 _expiresAt,
        address _tokenContract,
        uint256 _category
    ) public whenNotPaused {
        _createOrder(
            _nftAddress,
            _assetId,
            _priceInWei,
            _expiresAt,
            _tokenContract,
            _category
        );
    }

    /**
     * @dev Cancel an already published order
     *  can only be canceled by seller or the contract owner
     * @param _nftAddress - Address of the NFT registry
     * @param _assetId - ID of the published NFT
     */
    function cancelOrder(address _nftAddress, uint256 _assetId)
        public
        whenNotPaused
    {
        Order memory order = orderByAssetId[_nftAddress][_assetId];

        require(
            order.seller == msg.sender || msg.sender == owner(),
            UNAUTHORIZED_SENDER
        );

        // Remove pending bid if any
        Bid memory bid = bidByOrderId[_nftAddress][_assetId];

        if (bid.id != 0) {
            _cancelBid(bid.id, _nftAddress, _assetId, bid.bidder, bid.price);
        }

        // Cancel order.
        _cancelOrder(order.id, _nftAddress, _assetId, msg.sender);
    }

    /**
     * @dev Update an already published order
     *  can only be updated by seller
     * @param _nftAddress - Address of the NFT registry
     * @param _assetId - ID of the published NFT
     */
    function updateOrder(
        address _nftAddress,
        uint256 _assetId,
        uint256 _priceInWei,
        uint256 _expiresAt
    ) public whenNotPaused {
        Order memory order = orderByAssetId[_nftAddress][_assetId];

        // Check valid order to update
        require(order.id != 0, ASSET_NOT_PUBLISHED);
        require(order.seller == msg.sender, SENDER_NOT_ALLOWED);
        require(order.expiresAt >= block.timestamp, ORDER_EXPIRED);

        // check order updated params
        require(_priceInWei > 0, PRICE_SHOULD_BE_BIGGER_THAN);
        require(
            _expiresAt > block.timestamp.add(1 minutes),
            EXPIRE_TIME_SHOULD_BE_MORE_THAN
        );

        order.price = _priceInWei;
        order.expiresAt = _expiresAt;

        emit OrderUpdated(order.id, _priceInWei, _expiresAt);
    }

    /**
     * @dev Executes the sale for a published NFT and checks for the asset fingerprint
     * @param _nftAddress - Address of the NFT registry
     * @param _assetId - ID of the published NFT
     * @param _priceInWei - Order price
     */
    function safeExecuteOrder(
        address _nftAddress,
        uint256 _assetId,
        uint256 _priceInWei
    ) public whenNotPaused {
        // Get the current valid order for the asset or fail
        Order memory order = _getValidOrder(_nftAddress, _assetId);

        /// Check the execution price matches the order price
        require(order.price == _priceInWei, INVALID_PRICE);
        require(order.seller != msg.sender, UNAUTHORIZED_SENDER);

        // market fee to cut
        uint256 saleShareAmount = 0;

        // Send market fees to owner
        if (FeeManager.cutPerMillion > 0) {
            // Calculate sale share
            saleShareAmount = _priceInWei.mul(FeeManager.cutPerMillion).div(
                1e6
            );

            // Transfer share amount for marketplace Owner
            acceptedToken.transferFrom(
                msg.sender, //buyer
                owner(),
                saleShareAmount
            );
        }

        // Transfer accepted token amount minus market fee to seller
        acceptedToken.transferFrom(
            msg.sender, // buyer
            order.seller, // seller
            order.price.sub(saleShareAmount)
        );

        // Remove pending bid if any
        Bid memory bid = bidByOrderId[_nftAddress][_assetId];

        if (bid.id != 0) {
            _cancelBid(bid.id, _nftAddress, _assetId, bid.bidder, bid.price);
        }

        _executeOrder(
            order.id,
            msg.sender, // buyer
            _nftAddress,
            _assetId,
            _priceInWei
        );
    }

    /*
    buy
    */
    function Buy(
        address _nftAddress,
        uint256 _assetId,
        uint256 _priceInWei
    ) public whenNotPaused {
        // Checks order validity
        Order memory order = _getValidOrder(_nftAddress, _assetId);

        require(_priceInWei == order.price, PRICE_IS_NOT_RIGHT);

        // Check price if theres previous a bid
        Bid memory bid = bidByOrderId[_nftAddress][_assetId];

        // if theres no previous bid, just check price > 0
        if (bid.id != 0) {
            _cancelBid(bid.id, _nftAddress, _assetId, bid.bidder, bid.price);
        } else {
            require(_priceInWei > 0, BID_SHOULD_BE_ZERO);
        }

        IERC20Metadata token = IERC20Metadata(order.tokenContract);
        // Transfer sale amount from bidder to escrow
        token.transferFrom(
            msg.sender, // bidder
            address(this),
            _priceInWei
        );

        // calc market fees
        uint256 saleShareAmount = _priceInWei.mul(FeeManager.cutPerMillion).div(
            1e6
        );

        // to owner
        token.transfer(owner(), saleShareAmount);

        //royallty
        uint256 royalltyShareAmount = _priceInWei
            .mul(FeeManager.royaltyPerMillion)
            .div(1e18);
        token.transfer(
            IERC721(_nftAddress).ownerOf(_assetId),
            royalltyShareAmount
        );

        // transfer escrowed bid amount minus market fee to seller
        token.transfer(
            order.seller,
            _priceInWei.sub(saleShareAmount).sub(royalltyShareAmount)
        );

        // Transfer NFT asset
        IERC721(_nftAddress).transferFrom(address(this), msg.sender, _assetId);

        ownerHistoryByOrderId[_nftAddress][_assetId].push(msg.sender);

        _itemsSold.increment();

        emit Buycreate(
            _nftAddress,
            _assetId,
            order.seller,
            msg.sender,
            _priceInWei
        );
    }

    /**
     * @dev Places a bid for a published NFT and checks for the asset fingerprint
     * @param _nftAddress - Address of the NFT registry
     * @param _assetId - ID of the published NFT
     * @param _priceInWei - Bid price in acceptedToken currency
     * @param _expiresAt - Bid expiration time
     */
    function PlaceBid(
        address _nftAddress,
        uint256 _assetId,
        uint256 _priceInWei,
        uint256 _expiresAt
    ) public whenNotPaused {
        _createBid(_nftAddress, _assetId, _priceInWei, _expiresAt);
    }

    /**
     * @dev Cancel an already published bid
     *  can only be canceled by seller or the contract owner
     * @param _nftAddress - Address of the NFT registry
     * @param _assetId - ID of the published NFT
     */
    function cancelBid(address _nftAddress, uint256 _assetId)
        public
        whenNotPaused
    {
        Bid memory bid = bidByOrderId[_nftAddress][_assetId];

        require(
            bid.bidder == msg.sender || msg.sender == owner(),
            UNAUTHORIZED_SENDER
        );

        _cancelBid(bid.id, _nftAddress, _assetId, bid.bidder, bid.price);
    }

    /**
     * @dev Executes the sale for a published NFT by accepting a current bid
     * @param _nftAddress - Address of the NFT registry
     * @param _assetId - ID of the published NFT
     * @param _priceInWei - Bid price in wei in acceptedTokens currency
     */
    function acceptBid(
        address _nftAddress,
        uint256 _assetId,
        uint256 _priceInWei
    ) public whenNotPaused {
        // check order validity
        Order memory order = _getValidOrder(_nftAddress, _assetId);

        // item seller is the only allowed to accept a bid
        require(order.seller == msg.sender, UNAUTHORIZED_SENDER);

        Bid memory bid = bidByOrderId[_nftAddress][_assetId];

        require(bid.price == _priceInWei, INVALID_BID_PRICE);
        require(bid.expiresAt >= block.timestamp, BID_EXPIRED);

        // remove bid
        delete bidByOrderId[_nftAddress][_assetId];

        emit BidAccepted(bid.id);

        // calc market fees
        uint256 saleShareAmount = bid.price.mul(FeeManager.cutPerMillion).div(
            1e6
        );

        // to owner
        acceptedToken.transfer(owner(), saleShareAmount);

        //royallty
        uint256 royalltyShareAmount = bid
            .price
            .mul(FeeManager.royaltyPerMillion)
            .div(1e6);

        acceptedToken.transfer(
            IERC721(_nftAddress).createrOf(_assetId),
            royalltyShareAmount
        );

        // transfer escrowed bid amount minus market fee to seller
        acceptedToken.transfer(
            order.seller,
            bid.price.sub(saleShareAmount).sub(royalltyShareAmount)
        );

        _executeOrder(order.id, bid.bidder, _nftAddress, _assetId, _priceInWei);
    }

    /**
     * @dev Internal function gets Order by nftRegistry and assetId. Checks for the order validity
     * @param _nftAddress - Address of the NFT registry
     * @param _assetId - ID of the published NFT
     */
    function _getValidOrder(address _nftAddress, uint256 _assetId)
        internal
        view
        returns (Order memory order)
    {
        order = orderByAssetId[_nftAddress][_assetId];

        require(order.id != 0, ASSET_NOT_PUBLISHED);
        require(order.expiresAt >= block.timestamp, ORDER_EXPIRED);
    }

    /**
     * @dev Executes the sale for a published NFT
     * @param _orderId - Order Id to execute
     * @param _buyer - address
     * @param _nftAddress - Address of the NFT registry
     * @param _assetId - NFT id
     * @param _priceInWei - Order price
     */
    function _executeOrder(
        bytes32 _orderId,
        address _buyer,
        address _nftAddress,
        uint256 _assetId,
        uint256 _priceInWei
    ) internal {
        // remove order
        delete orderByAssetId[_nftAddress][_assetId];
        _removeOrderInlist(_orderId);

        // Transfer NFT asset
        IERC721(_nftAddress).transferFrom(address(this), _buyer, _assetId);
        ownerHistoryByOrderId[_nftAddress][_assetId].push(_buyer);

        // Notify ..
        emit OrderSuccessful(_orderId, _buyer, _priceInWei);
    }

    /**
     * @dev Creates a new order
     * @param tokenAddress - fungible registry address
     */
    function AddToken(address tokenAddress) public onlyRole(MANAGER_ROLE) {
        IERC20Metadata newToken = IERC20Metadata(tokenAddress);
        _totalTokens.increment();
        uint256 itemId = _totalTokens.current();
        tokensSupport[itemId] = Token({
            symbolName: newToken.symbol(),
            decimal: newToken.decimals(),
            tokenContract: tokenAddress
        });

        emit TokenAdd(newToken);
    }

    function addItemCollection(uint256 _id, uint256 orderID)
        public
        returns (CollectionItem memory)
    {
        require(_collections[_id].id > 0, COLLECTION_DONT_EXISTS);
        require(
            _collections[_id].creator == msg.sender,
            OWNER_COLLECTION_INVALID
        );
        require(_orders[_id].id > 0, UNAUTHORIZED_SENDER);
        Order storage order = _orders[orderID];
        _totalCollectionItems.increment();

        CollectionItem memory item = CollectionItem({
            id: order.id,
            creator: order.seller,
            nftAddress: order.nftAddress,
            price: order.price,
            expiresAt: order.expiresAt,
            assetId: order._assetId,
            tokenContract: order.tokenContract,
            collectionId: _id
        });

        _collectionsItems[_id][_totalCollectionItems.current()] = item;
        _collections[_id].total.increment();

        return item;
    }

    function createCategory(string memory name, string memory icon)
        public
        onlyRole(MANAGER_ROLE)
        returns (uint256)
    {
        bytes memory nameBytes = bytes(name);
        bytes memory iconBytes = bytes(icon);
        require(nameBytes.length > 0, COLLECTION_NAME_EMPATY);
        require(iconBytes.length > 0, COLLECTION_ICON_EMPATY);
        _totalCategory.increment();
        _categories[_totalCategory.current()] = Category({
            id: _totalCategory.current(),
            name: name,
            icon: icon
        });
        return _totalCategory.current();
    }

    function createCollection(string memory name, string memory icon)
        public
        returns (uint256)
    {
        bytes memory nameBytes = bytes(name);
        bytes memory iconBytes = bytes(icon);
        _totalCollection.increment();

        Counters.Counter memory total = Counters.Counter(0);
        require(nameBytes.length > 0, COLLECTION_NAME_EMPATY);
        require(iconBytes.length > 0, COLLECTION_ICON_EMPATY);
        _collections[_totalCollection.current()] = Collection({
            id: _totalCollection.current(),
            creator: msg.sender,
            name: name,
            icon: icon,
            total: total
        });
        return _totalCollection.current();
    }

    function removeToken(address tokenAddress) public onlyRole(MANAGER_ROLE) {
        uint256 itemId = _totalTokens.current();
        for (uint256 i = 0; i < itemId; i++) {
            if (tokensSupport[i + 1].tokenContract == tokenAddress) {
                uint256 currentId = i + 1;
                delete tokensSupport[currentId];
            }
        }
        _totalTokens.decrement();
    }

    /**
     * @dev Creates a new order
     * @param _nftAddress - Non fungible registry address
     * @param _assetId - ID of the published NFT
     * @param _priceInWei - Price in Wei for the supported coin
     * @param _expiresAt - Expiration time for the order
     */
    function _createOrder(
        address _nftAddress,
        uint256 _assetId,
        uint256 _priceInWei,
        uint256 _expiresAt,
        address _tokenContract,
        uint256 _category
    ) internal {
        // Check nft registry
        IERC721 nftRegistry = _requireERC721(_nftAddress);

        IERC20Metadata token = IERC20Metadata(_tokenContract);
        require(getSymbolIndex(token.symbol()) > 0, TOKEN_IS_IVALID);

        nftRegistered[_nftAddress] = nftRegistry;

        // Check order creator is the asset owner
        address assetOwner = nftRegistry.ownerOf(_assetId);

        require(
            assetOwner == msg.sender,
            ONLY_THE_ASSET_OWNER_CAN_CREATE_ORDERS
        );

        require(_priceInWei > 0, PRICE_SHOULD_BE_BIGGER_THAN);

        require(
            _expiresAt > block.timestamp.add(1 minutes),
            PUBLICATION_SHOULD_BE_MORE_THAT_ONE_MINUTE_IN_THE_FUTURE
        );

        // get NFT asset from seller
        nftRegistry.transferFrom(assetOwner, address(this), _assetId);

        // create the orderId
        bytes32 orderId = keccak256(
            abi.encodePacked(
                block.timestamp,
                assetOwner,
                _nftAddress,
                _assetId,
                _priceInWei
            )
        );

        // save order
        orderByAssetId[_nftAddress][_assetId] = Order({
            id: orderId,
            seller: assetOwner,
            nftAddress: _nftAddress,
            price: _priceInWei,
            expiresAt: _expiresAt,
            _assetId: _assetId,
            tokenContract: _tokenContract,
            category: _category
        });

        _itemIds.increment();
        uint256 itemId = _itemIds.current();

        _orders[itemId] = Order({
            id: orderId,
            seller: assetOwner,
            nftAddress: _nftAddress,
            price: _priceInWei,
            expiresAt: _expiresAt,
            _assetId: _assetId,
            tokenContract: _tokenContract,
            category: _category
        });

        emit OrderCreated(
            orderId,
            assetOwner,
            _nftAddress,
            _assetId,
            _priceInWei,
            _expiresAt,
            _tokenContract,
            _category
        );
    }

    /**
     * @dev Creates a new bid on a existing order
     * @param _nftAddress - Non fungible registry address
     * @param _assetId - ID of the published NFT
     * @param _priceInWei - Price in Wei for the supported coin
     * @param _expiresAt - expires time
     */
    function _createBid(
        address _nftAddress,
        uint256 _assetId,
        uint256 _priceInWei,
        uint256 _expiresAt
    ) internal {
        // Checks order validity
        Order memory order = _getValidOrder(_nftAddress, _assetId);

        // check on expire time
        if (_expiresAt > order.expiresAt) {
            _expiresAt = order.expiresAt;
        }

        // Check price if theres previous a bid
        Bid memory bid = bidByOrderId[_nftAddress][_assetId];

        bidHistoryByOrderId[_nftAddress][_assetId].push(bid);
        // if theres no previous bid, just check price > 0
        if (bid.id != 0) {
            if (bid.expiresAt >= block.timestamp) {
                require(
                    _priceInWei > bid.price,
                    BID_PRICE_SHOULD_BE_HIGHER_THAT_LAST_BID
                );
            } else {
                require(_priceInWei > 0, BID_SHOULD_BE_ZERO);
            }

            _cancelBid(bid.id, _nftAddress, _assetId, bid.bidder, bid.price);
        } else {
            require(_priceInWei > 0, BID_SHOULD_BE_ZERO);
        }
        IERC20Metadata token = IERC20Metadata(order.tokenContract);
        // Transfer sale amount from bidder to escrow
        token.transferFrom(
            msg.sender, // bidder
            address(this),
            _priceInWei
        );

        // Create bid
        bytes32 bidId = keccak256(
            abi.encodePacked(
                block.timestamp,
                msg.sender,
                order.id,
                _priceInWei,
                _expiresAt
            )
        );

        // Save Bid for this order
        bidByOrderId[_nftAddress][_assetId] = Bid({
            id: bidId,
            bidder: msg.sender,
            price: _priceInWei,
            expiresAt: _expiresAt
        });

        emit BidCreated(
            bidId,
            _nftAddress,
            _assetId,
            msg.sender, // bidder
            _priceInWei,
            _expiresAt
        );
    }

    /**
     * @dev Cancel an already published order
     *  can only be canceled by seller or the contract owner
     * @param _orderId - Bid identifier
     * @param _nftAddress - Address of the NFT registry
     * @param _assetId - ID of the published NFT
     * @param _seller - Address
     */
    function _cancelOrder(
        bytes32 _orderId,
        address _nftAddress,
        uint256 _assetId,
        address _seller
    ) internal {
        delete orderByAssetId[_nftAddress][_assetId];
        _removeOrderInlist(_orderId);
        IERC721(_nftAddress).transferFrom(address(this), _seller, _assetId);

        emit OrderCancelled(_orderId);
    }

    /**
     * @dev Cancel bid from an already published order
     *  can only be canceled by seller or the contract owner
     * @param _bidId - Bid identifier
     * @param _nftAddress - registry address
     * @param _assetId - ID of the published NFT
     * @param _bidder - Address
     * @param _escrowAmount - in acceptenToken currency
     */
    function _cancelBid(
        bytes32 _bidId,
        address _nftAddress,
        uint256 _assetId,
        address _bidder,
        uint256 _escrowAmount
    ) internal {
        delete bidByOrderId[_nftAddress][_assetId];

        // return escrow to canceled bidder
        acceptedToken.transfer(_bidder, _escrowAmount);

        emit BidCancelled(_bidId);
    }

    function _requireERC721(address _nftAddress)
        internal
        view
        returns (IERC721)
    {
        require(_nftAddress.isContract(), ADDRESS_SHOULD_BE_A_CONTRACT);
        // require(
        //     IERC721(_nftAddress).supportsInterface(_INTERFACE_ID_ERC721),
        //     "The NFT contract has an invalid ERC721 implementation"
        // );
        return IERC721(_nftAddress);
    }

    function getOrderByAssetIds(address _nftAddress, uint256[] memory _assetIds)
        external
        view
        returns (Order[] memory orders)
    {
        orders = new Order[](_assetIds.length);
        for (uint256 i = 0; i < _assetIds.length; i++) {
            orders[i] = orderByAssetId[_nftAddress][_assetIds[i]];
        }
    }

    function listOrders() public view returns (Order[] memory) {
        uint256 itemCount = _itemIds.current();
        uint256 unsoldItemCount = _itemIds.current() - _itemsSold.current();
        uint256 currentIndex = 0;
        Order[] memory items = new Order[](unsoldItemCount);
        for (uint256 i = 0; i < itemCount; i++) {
            uint256 currentId = i + 1;
            Order memory currentItem = _orders[currentId];
            items[currentIndex] = currentItem;
            currentIndex += 1;
        }

        return items;
    }

    function listTokens() public view returns (Token[] memory tokens) {
        uint256 totalItemCount = _totalTokens.current();
        uint256 currentIndex = 0;
        uint256 itemCount = 0;
        tokens = new Token[](totalItemCount);
        for (uint256 i = 0; i < totalItemCount; i++) {
            uint256 currentId = 1;
            Token storage currentItem = tokensSupport[currentId];
            itemCount += 1;
            tokens[currentIndex] = currentItem;
            currentIndex += 1;
        }
    }

    function listOrdersByCategory(uint256 _id)
        public
        view
        returns (Order[] memory orders)
    {
        uint256 totalItemCount = _itemIds.current();
        uint256 totalItemCountlist = _itemIds.current();
        uint256 itemCount = 0;
        uint256 currentIndex = 0;

        for (uint256 i = 0; i < totalItemCount; i++) {
            if (_orders[i + 1].category == _id) {
                itemCount += 1;
            }
        }

        orders = new Order[](itemCount);
        for (uint256 i = 0; i < totalItemCountlist; i++) {
            if (_orders[i + 1].category == _id) {
                uint256 currentId = i + 1;
                Order storage currentItem = _orders[currentId];
                orders[currentIndex] = currentItem;
                currentIndex += 1;
            }
        }
    }

    function listCategory() public view returns (Category[] memory categories) {
        uint256 totalItemCount = _totalCategory.current();
        uint256 currentIndex = 0;
        categories = new Category[](totalItemCount);
        for (uint256 i = 0; i < totalItemCount; i++) {
            uint256 currentId = i + 1;
            Category storage currentItem = _categories[currentId];
            categories[currentIndex] = currentItem;
            currentIndex += 1;
        }
    }

    function listCollections()
        public
        view
        returns (Collection[] memory collections)
    {
        uint256 totalItemCount = _totalCollection.current();
        uint256 currentIndex = 0;
        uint256 itemCount = 0;
        collections = new Collection[](totalItemCount);
        for (uint256 i = 0; i < totalItemCount; i++) {
            uint256 currentId = i + 1;
            Collection storage currentItem = _collections[currentId];
            itemCount += 1;
            collections[currentIndex] = currentItem;
            currentIndex += 1;
        }
    }

    function listItemsCollection(uint256 _id)
        public
        view
        returns (CollectionItem[] memory collections)
    {
        Collection storage colleciton = _collections[_id];
        require(colleciton.id > 0, COLLECTION_DONT_EXISTS);
        uint256 totalItemCount = colleciton.total.current();
        uint256 currentIndex = 0;
        uint256 itemCount = 0;
        collections = new CollectionItem[](totalItemCount);
        for (uint256 i = 0; i < totalItemCount; i++) {
            uint256 currentId = i + 1;
            CollectionItem memory currentItem = _collectionsItems[_id][
                currentId
            ];
            itemCount += 1;
            collections[currentIndex] = currentItem;
            currentIndex += 1;
        }
    }

    function getMyOrders() public view returns (Order[] memory orders) {
        uint256 totalItemCount = _itemIds.current();
        uint256 totalItemCountlist = _itemIds.current();
        uint256 itemCount = 0;
        uint256 currentIndex = 0;

        for (uint256 i = 0; i < totalItemCount; i++) {
            if (_orders[i + 1].seller == msg.sender) {
                itemCount += 1;
            }
        }

        orders = new Order[](itemCount);
        for (uint256 i = 0; i < totalItemCountlist; i++) {
            if (_orders[i + 1].seller == msg.sender) {
                uint256 currentId = 1;
                Order storage currentItem = _orders[currentId];
                itemCount += 1;
                orders[currentIndex] = currentItem;
                currentIndex += 1;
            }
        }
    }

    function getBidByAssetIds(address _nftAddress, uint256[] memory _assetIds)
        external
        view
        returns (Bid[] memory bids)
    {
        bids = new Bid[](_assetIds.length);
        for (uint256 i = 0; i < _assetIds.length; i++) {
            bids[i] = bidByOrderId[_nftAddress][_assetIds[i]];
        }
    }

    function getBidHistoryByAssetIds(
        address _nftAddress,
        uint256[] memory _assetIds
    ) external view returns (Bid[][] memory bids) {
        bids = new Bid[][](_assetIds.length);
        for (uint256 i = 0; i < _assetIds.length; i++) {
            bids[i] = bidHistoryByOrderId[_nftAddress][_assetIds[i]];
        }
    }

    /**
     * @dev Remove item list user
     *  can only remove item in user list
     * @param _orderId - Bid identifier
     */

    function _removeOrderInlist(bytes32 _orderId) internal {
        uint256 itemId = _itemIds.current();
        for (uint256 i = 0; i < itemId; i++) {
            if (_orders[i + 1].id == _orderId) {
                uint256 currentId = i + 1;
                delete _orders[currentId];
            }
        }
        _itemIds.decrement();
    }

    function getSymbolIndex(string memory symbolName)
        internal
        view
        returns (uint256)
    {
        for (uint256 i = 1; i <= _totalTokens.current(); i++) {
            if (stringsEqual(tokensSupport[i].symbolName, symbolName)) {
                return i;
            }
        }
        return 0;
    }

    function stringsEqual(string storage _a, string memory _b)
        internal
        pure
        returns (bool)
    {
        bytes storage a = bytes(_a);
        bytes memory b = bytes(_b);

        if (keccak256(a) != keccak256(b)) {
            return false;
        }
        return true;
    }
}
