// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract P2PExchange {
    // Enum for listing types (e.g., fixed price, auction, offer)
    enum ListingType { FixedPrice, Auction, Offer }
    // Enum for the status of a listing
    enum Status { Listed, BuyerPaid, Shipped, Received, Completed, Cancelled }

    // Struct for a listing
    struct Listing {
        address seller;
        address buyer;
        uint256 price;
        string title;
        Status status;
        ListingType listingType;
        uint256 creationTime;
    }

    IERC20 public usdcToken; // USDC token used for transactions
    Listing[] public listings; // Array to store all listings
    uint256 public listingCount; // Counter for total listings

    // Events
    event ListingCreated(uint256 listingId, address indexed seller, uint256 price, string title);
    event StatusUpdated(uint256 listingId, Status newStatus);
    event BuyerSet(uint256 listingId, address indexed buyer);
    event FundsWithdrawn(uint256 listingId, address indexed seller);
    event ListingCancelled(uint256 listingId);

    // Modifier to ensure only the buyer can access specific functions
    modifier buyerOnly(uint256 listingId) {
        require(listingId < listings.length, "Listing does not exist");
        require(msg.sender == listings[listingId].buyer, "Only the buyer can perform this action");
        _;
    }

    // Modifier to ensure only the seller can access specific functions
    modifier sellerOnly(uint256 listingId) {
        require(listingId < listings.length, "Listing does not exist");
        require(msg.sender == listings[listingId].seller, "Only the seller can perform this action");
        _;
    }

    // Constructor to initialize the USDC token address
    constructor(address _usdcToken) {
        require(_usdcToken != address(0), "Invalid USDC token address");
        usdcToken = IERC20(_usdcToken);
    }

    // Create a new listing
    function createListing(uint256 price, string memory title) public returns (uint256 listingId) {
        require(price > 0, "Price must be greater than 0");
        require(bytes(title).length > 0, "Title cannot be empty");

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

    // Buyer initiates a purchase
    function initiateBuy(uint256 listingId) public {
        require(listingId < listings.length, "Listing does not exist");
        Listing storage listing = listings[listingId];
        require(listing.status == Status.Listed, "Listing not available");
        require(msg.sender != listing.seller, "Seller cannot be the buyer");
        require(listing.buyer == address(0), "Buyer already set");

        // Transfer USDC from buyer to the contract
        require(usdcToken.transferFrom(msg.sender, address(this), listing.price), "Token transfer failed");

        listing.buyer = msg.sender;
        listing.status = Status.BuyerPaid;
        emit BuyerSet(listingId, msg.sender);
        emit StatusUpdated(listingId, Status.BuyerPaid);
    }

    // Update the status of a listing
    function updateStatus(uint256 listingId, Status newStatus) public {
        require(listingId < listings.length, "Listing does not exist");
        Listing storage listing = listings[listingId];

        // Seller can update most statuses except "Received"
        if (msg.sender == listing.seller) {
            require(newStatus != Status.Received, "Seller cannot mark the item as received");
            require(newStatus != Status.Listed, "Invalid status update");
        } 
        // Buyer can only update to "Received" if current status is "Shipped"
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

    // Buyer confirms the transaction
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

    // Seller withdraws funds for a completed transaction
    function withdrawFunds(uint256 listingId) public sellerOnly(listingId) {
        Listing storage listing = listings[listingId];
        require(listing.status == Status.Completed, "Listing not completed");

        uint256 amount = listing.price;
        listing.status = Status.Completed;

        // Transfer USDC to the seller
        require(usdcToken.transfer(listing.seller, amount), "Withdrawal failed");

        emit FundsWithdrawn(listingId, listing.seller);
    }

    // Seller cancels a listing before it is purchased
    function cancelListing(uint256 listingId) public sellerOnly(listingId) {
        Listing storage listing = listings[listingId];
        require(listing.status == Status.Listed, "Cannot cancel a non-listed item");

        listing.status = Status.Cancelled;
        emit ListingCancelled(listingId);
    }

    // Get all listings
    function getAllListings() public view returns (Listing[] memory _listings) {
        return listings;
    }

    // Get a specific listing by ID
    function getListing(uint256 listingId) public view returns (Listing memory _listing) {
        require(listingId < listings.length, "Listing does not exist");
        return listings[listingId];
    }

    // Get the total count of listings
    function getListingCount() public view returns (uint256) {
        return listings.length;
    }
}
