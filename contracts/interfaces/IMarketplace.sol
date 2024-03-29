//SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

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

    // ORDER EVENTS
    event OrderCreated(
        bytes32 id,
        address indexed seller,
        address indexed nftAddress,
        uint256 indexed assetId,
        uint256 priceInWei,
        uint256 expiresAt
    );

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
        uint256 _expiresAt
    ) external;

    function getOrders() external view returns (Order[] memory);
}
