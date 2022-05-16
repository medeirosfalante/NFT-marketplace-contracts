//SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "./IERC20.sol";
import "./IERC721.sol";

import "@openzeppelin/contracts/utils/Counters.sol";

interface IMarketplace {
    struct Order {
        // Order ID
        bytes32 id;
        // Owner of the NFT
        address seller;
        // NFT registry address
        address nftAddress;
        // Price (in wei) for the published item
        uint256 price;
        // Time when this sale ends
        uint256 expiresAt;
        uint256 _assetId;
        address tokenContract;
        uint256 category;
    }

    struct CollectionItem {
        // Order ID
        bytes32 id;
        // Owner of the NFT
        address creator;
        // NFT registry address
        address nftAddress;
        // Price (in wei) for the published item
        uint256 price;
        // Time when this sale ends
        uint256 expiresAt;
        uint256 assetId;
        address tokenContract;
        uint256 collectionId;
    }

    struct Collection {
        uint256 id;
        // Owner of the NFT
        address creator;
        // Collectio name
        string name;
        string icon;
        Counters.Counter total;
        // NFT registry address
    }

    struct Bid {
        // Bid Id
        bytes32 id;
        // Bidder address
        address bidder;
        // Price for the bid in wei
        uint256 price;
        // Time when this bid ends
        uint256 expiresAt;
    }

    struct Category {
        // Bid Id
        uint256 id;
        string name;
        string icon;
    }

    struct Token {
        string symbolName;
        uint256 decimal;
        address tokenContract;
    }

    // ORDER EVENTS
    event OrderCreated(
        bytes32 id,
        address indexed seller,
        address indexed nftAddress,
        uint256 indexed assetId,
        uint256 priceInWei,
        uint256 expiresAt,
        address tokenContract,
        uint256 category
    );

    event TokenAdd(IERC20 token);

    event OrderUpdated(bytes32 id, uint256 priceInWei, uint256 expiresAt);

    event OrderSuccessful(
        bytes32 id,
        address indexed buyer,
        uint256 priceInWei
    );

    event OrderCancelled(bytes32 id);

    // BID EVENTS
    event BidCreated(
        bytes32 id,
        address indexed nftAddress,
        uint256 indexed assetId,
        address indexed bidder,
        uint256 priceInWei,
        uint256 expiresAt
    );

    event BidAccepted(bytes32 id);
    event BidCancelled(bytes32 id);

    event Buycreate(
        address indexed nftAddress,
        uint256 indexed assetId,
        address indexed bidder,
        address seller,
        uint256 priceInWei
    );

    function createOrder(
        address _nftAddress,
        uint256 _assetId,
        uint256 _priceInWei,
        uint256 _expiresAt,
        address _tokenContract,
        uint256 _category
    ) external;

    // function createCollection(string memory name, string memory icon) external;
    function listOrders() external view returns (Order[] memory);

    function getMyOrders() external view returns (Order[] memory orders);

    function listTokens() external view returns (Token[] memory tokens);

    function listCollections()
        external
        view
        returns (Collection[] memory collections);

    function Buy(
        address _nftAddress,
        uint256 _assetId,
        uint256 _priceInWei
    ) external;

    function createCollection(string memory name, string memory icon)
        external
        returns (uint256);

    function addItemCollection(uint256 _id, uint256 orderID)
        external
        returns (CollectionItem memory);

    function listItemsCollection(uint256 _id)
        external
        view
        returns (CollectionItem[] memory collections);

    function createCategory(string memory name, string memory icon)
        external
        returns (uint256);

    function listCategory()
        external
        view
        returns (Category[] memory categories);

    function listOrdersByCategory(uint256 _id)
        external
        view
        returns (Order[] memory orders);
}
