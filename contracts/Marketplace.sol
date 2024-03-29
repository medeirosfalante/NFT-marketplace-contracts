//SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

import "@openzeppelin/contracts/access/Ownable.sol";

import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

import "./interfaces/IMarketplace.sol";

import "./interfaces/IERC721.sol";
import "./interfaces/IERC20.sol";

import "./FeeManager.sol";

// todo: think about how on transfer we can delete the ask of prev owner
// might not be necessary if we bake in checks, and if checks fail: delete
// todo: check out 0.8.9 custom types
contract Marketplace is Ownable, Pausable, FeeManager, IMarketplace {
    using Address for address;
    using SafeMath for uint256;
    using Counters for Counters.Counter;
    Counters.Counter private _itemIds;
    Counters.Counter private _itemsSold;

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

    IERC20 public acceptedToken;

    // From ERC721 registry assetId to Order (to avoid asset collision)
    mapping(address => mapping(uint256 => Order)) public orderByAssetId;

    // From ERC721 registry assetId to Bid (to avoid asset collision)
    mapping(address => mapping(uint256 => Bid)) public bidByOrderId;
    mapping(address => IERC721) public nftRegistered;

    mapping(uint256 => Order) private _orders;

    mapping(address => mapping(uint256 => Bid[])) public bidHistoryByOrderId;
    mapping(address => mapping(uint256 => address[]))
        public ownerHistoryByOrderId;

    // 721 Interfaces
    bytes4 public constant _INTERFACE_ID_ERC721 = 0x80ac58cd;

    /**
     * @dev Initialize this contract. Acts as a constructor
     */
    constructor() Ownable() {}

    /**
     * @dev Sets the paused failsafe. Can only be called by owner
     * @param _setPaused - paused state
     */
    function setPaused(bool _setPaused) public onlyOwner {
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
        uint256 _expiresAt
    ) public whenNotPaused {
        _createOrder(_nftAddress, _assetId, _priceInWei, _expiresAt);
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

        // Transfer sale amount from bidder to escrow
        acceptedToken.transferFrom(
            msg.sender, // bidder
            address(this),
            _priceInWei
        );

        // calc market fees
        uint256 saleShareAmount = _priceInWei.mul(FeeManager.cutPerMillion).div(
            1e6
        );

        // to owner
        acceptedToken.transfer(owner(), saleShareAmount);

        //royallty
        uint256 royalltyShareAmount = _priceInWei
            .mul(FeeManager.royaltyPerMillion)
            .div(1e6);

        acceptedToken.transfer(
            IERC721(_nftAddress).createrOf(_assetId),
            royalltyShareAmount
        );

        // transfer escrowed bid amount minus market fee to seller
        acceptedToken.transfer(
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

        // Transfer NFT asset
        IERC721(_nftAddress).transferFrom(address(this), _buyer, _assetId);
        ownerHistoryByOrderId[_nftAddress][_assetId].push(_buyer);

        // Notify ..
        emit OrderSuccessful(_orderId, _buyer, _priceInWei);
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
        uint256 _expiresAt
    ) internal {
        // Check nft registry
        IERC721 nftRegistry = _requireERC721(_nftAddress);

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
            _assetId: _assetId
        });

        _itemIds.increment();
        uint256 itemId = _itemIds.current();

        _orders[itemId] = Order({
            id: orderId,
            seller: assetOwner,
            nftAddress: _nftAddress,
            price: _priceInWei,
            expiresAt: _expiresAt,
            _assetId: _assetId
        });

        emit OrderCreated(
            orderId,
            assetOwner,
            _nftAddress,
            _assetId,
            _priceInWei,
            _expiresAt
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

        // Transfer sale amount from bidder to escrow
        acceptedToken.transferFrom(
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

        /// send asset back to seller
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

    function getOrders() public view returns (Order[] memory) {
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
}
