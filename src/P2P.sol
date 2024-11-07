// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";


contract P2PExchange {
    enum ListingType { FixedPrice, Auction, Offer }
    enum Status { Listed, BuyerPaid, Shipped, Received, Completed, Cancelled }

    struct Listing {
        address seller;
        address buyer;
        uint256 price;
        string title;
        Status status;
        ListingType listingType;
        uint256 creationTime;
    }

    IERC20 public usdcToken;
    Listing[] public listings;
    uint256 public listingCount;

    event ListingCreated(uint256 listingId, address indexed seller, uint256 price, string title);
    event StatusUpdated(uint256 listingId, Status newStatus);
    event BuyerSet(uint256 listingId, address indexed buyer);
    event FundsWithdrawn(uint256 listingId, address indexed seller);

    modifier buyerOnly(uint256 listingId) {
        require(listingId < listings.length, "Listing does not exist");
        require(msg.sender == listings[listingId].buyer, "Only the buyer can perform this action");
        _;
    }

    modifier sellerOnly(uint256 listingId) {
        require(listingId < listings.length, "Listing does not exist");
        require(msg.sender == listings[listingId].seller, "Only the seller can perform this action");
        _;
    }

    constructor(address _usdcToken) {
        usdcToken = IERC20(_usdcToken);
    }

    function createListing(uint256 price, string memory title) public returns (uint256 listingId) {
        listings.push(Listing({
            seller: msg.sender,
            buyer: address(0),
            price: price,
            title: title,
            status: Status.Listed,
            listingType: ListingType.FixedPrice,
            creationTime: block.timestamp
        }));
        
        listingId = listingCount;
        emit ListingCreated(listingId, msg.sender, price, title);
        listingCount++;
    }

    function initiateBuy(uint256 listingId) public {
        require(listingId < listings.length, "Listing does not exist");
        Listing storage listing = listings[listingId];
        require(listing.status == Status.Listed, "Listing not available");
        require(msg.sender != listing.seller, "Seller cannot be the buyer");
        require(listing.buyer == address(0), "Buyer already set");

        require(usdcToken.transferFrom(msg.sender, address(this), listing.price), "Token transfer failed");

        listing.buyer = msg.sender;
        listing.status = Status.BuyerPaid;
        emit BuyerSet(listingId, msg.sender);
        emit StatusUpdated(listingId, Status.BuyerPaid);
    }

    function updateStatus(uint256 listingId, Status newStatus) public {
        require(listingId < listings.length, "Listing does not exist");
        Listing storage listing = listings[listingId];

        if (msg.sender == listing.seller) {
            require(newStatus != Status.Received, "Seller cannot mark the item as received");
            require(newStatus != Status.Listed, "Invalid status update");
        } 
        else if (msg.sender == listing.buyer) {
            require(listing.status == Status.Shipped, "Can only mark as received if item is shipped");
            require(newStatus == Status.Received, "Buyer can only mark the item as received");
        } 
        else {
            revert("Only seller or buyer can update status");
        }

        listing.status = newStatus;
        emit StatusUpdated(listingId, newStatus);
    }

    function confirmTransaction(uint256 listingId) public buyerOnly(listingId) {
        Listing storage listing = listings[listingId];
        require(
            listing.status == Status.BuyerPaid ||
            listing.status == Status.Shipped ||
            listing.status == Status.Received,
            "Payment not yet completed by the buyer"
        );

        listing.status = Status.Completed;
        emit StatusUpdated(listingId, Status.Completed);
    }

    function withdrawFunds(uint256 listingId) public sellerOnly(listingId) {
        Listing storage listing = listings[listingId];
        require(listing.status == Status.Completed, "Listing not completed");

        uint256 amount = listing.price;
        listing.status = Status.Cancelled;
       
        require(usdcToken.transfer(listing.seller, amount), "Withdrawal failed");

        emit FundsWithdrawn(listingId, listing.seller);
        emit StatusUpdated(listingId, Status.Cancelled);
    }

    function getAllListings() public view returns (Listing[] memory _listings) {
        return listings;
    }

    function getListing(uint256 listingId) public view returns (Listing memory _listing) {
        require(listingId < listings.length, "Listing does not exist");
        return listings[listingId];
    }

    function getListingCount() public view returns (uint256) {
        return listings.length;
    }
}