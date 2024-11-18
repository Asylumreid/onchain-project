// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

contract P2PExchange is AccessControl {
    // Enum for listing types (e.g., fixed price, auction, offer)
    enum ListingType { FixedPrice, Auction, Offer }
    enum Status { Listed, BuyerPaid, Shipped, Received, Completed, Cancelled, Dispute }

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

    // // Constants for roles
    string public constant DISPUTE_HANDLER_ROLE_NAME = "p2p.disputeHandler";
    string public constant FEE_ADMIN_ROLE_NAME = "p2p.feeAdmin";


    // Public role constants that can be accessed externally
    bytes32 public constant DISPUTE_HANDLER_ROLE = keccak256(abi.encodePacked(DISPUTE_HANDLER_ROLE_NAME));
    bytes32 public constant FEE_ADMIN_ROLE = keccak256(abi.encodePacked(FEE_ADMIN_ROLE_NAME));

    IERC20 public usdcToken; // USDC token used for transactions
    Listing[] public listings; // Array to store all listings
    uint256 public listingCount; // Counter for total listings

    uint256 private feeBps; // Platform fee in basis points
    uint256 private collectedFees; // Accumulated fees

    // Events
    event ListingCreated(uint256 listingId, address indexed seller, uint256 price, string title);
    event StatusUpdated(uint256 listingId, Status newStatus);
    event BuyerSet(uint256 listingId, address indexed buyer);
    event FundsReleased(uint256 listingId, address indexed seller, uint256 amount);
    event FeeSet(uint256 feeBps);
    event FeeWithdrawn(uint256 amount, address indexed admin);
    event DisputeResolved(uint256 listingId, address indexed handler, uint256 fee, bool refundedToBuyer);


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

    constructor(address _usdcToken, address disputeHandler, address feeAdmin) {
        require(_usdcToken != address(0), "Invalid USDC token address");
        require(disputeHandler != address(0), "Invalid dispute handler address");
        require(feeAdmin != address(0), "Invalid fee admin address");
        require(disputeHandler != feeAdmin, "Dispute handler and fee admin must be different addresses");

        usdcToken = IERC20(_usdcToken);

        // Set up the default admin role
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);

        // Grant roles
        _grantRole(DISPUTE_HANDLER_ROLE, disputeHandler);
        _grantRole(FEE_ADMIN_ROLE, feeAdmin);

        // Set default fee to 1% (10 basis points)
        feeBps = 10;
    }
        

    // Add a public method to check role
    function hasRole(bytes32 role, address account) public view override returns (bool) {
        return super.hasRole(role, account);
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

        if (msg.sender == listing.seller) {
            require(newStatus != Status.Received, "Seller cannot mark the item as received");
            require(newStatus != Status.Listed, "Invalid status update");
        } else if (msg.sender == listing.buyer) {
            require(listing.status == Status.Shipped, "Can only mark as received if item is shipped");
            require(newStatus == Status.Received, "Buyer can only mark the item as received");
        } else {
            revert("Only seller or buyer can update status");
        }

        listing.status = newStatus;
        emit StatusUpdated(listingId, newStatus);
    }

    // Buyer or seller marks a dispute
    function markDispute(uint256 listingId) public {
        require(listingId < listings.length, "Listing does not exist");
        Listing storage listing = listings[listingId];
        require(
            msg.sender == listing.buyer || msg.sender == listing.seller,
            "Only buyer or seller can mark dispute"
        );
        require(
            listing.status == Status.BuyerPaid || listing.status == Status.Shipped,
            "Dispute only allowed in BuyerPaid or Shipped status"
        );

        listing.status = Status.Dispute;
        emit StatusUpdated(listingId, Status.Dispute);
    }

    // Handle disputes
    function handleDispute(uint256 listingId, bool isRefundBuyer) public onlyRole(DISPUTE_HANDLER_ROLE) {
        require(listingId < listings.length, "Listing does not exist");
        Listing storage listing = listings[listingId];
        require(listing.status == Status.Dispute, "No dispute to handle");

        // Calculate platform fee
        uint256 fee = (listing.price * feeBps) / 10_000;
        uint256 refundAmount = listing.price - fee;

        // Collect the fee first
        collectedFees += fee;

        // Transfer fee to dispute handler
        require(usdcToken.transfer(msg.sender, fee), "Dispute handler fee transfer failed");

        // Refund buyer or release funds to seller
        if (isRefundBuyer) {
            // Refund buyer with the remaining amount after fee
            require(usdcToken.transfer(listing.buyer, refundAmount), "Refund to buyer failed");
        } else {
            // Pay seller the remaining amount after fee
            require(usdcToken.transfer(listing.seller, refundAmount), "Payment to seller failed");
        }

        // Update listing status
        listing.status = Status.Cancelled;
        
        // Emit events
        emit StatusUpdated(listingId, Status.Cancelled);
        emit DisputeResolved(listingId, msg.sender, fee, isRefundBuyer);
    }

    // Set platform fee
    function setFee(uint256 _feeBps) public onlyRole(FEE_ADMIN_ROLE) {
        require(_feeBps <= 100, "Fee cannot exceed 1%");
        feeBps = _feeBps;
        emit FeeSet(_feeBps);
    }

    // Get platform fee
    function getFee() public view returns (uint256) {
        return feeBps;
    }

    // View collected fees
    function viewCollectedFee() public view onlyRole(FEE_ADMIN_ROLE) returns (uint256) {
        return collectedFees;
    }

    // Withdraw collected fees
    function withdrawFee() public onlyRole(FEE_ADMIN_ROLE) {
        uint256 amount = collectedFees;
        collectedFees = 0;
        require(usdcToken.transfer(msg.sender, amount), "Fee withdrawal failed");
        emit FeeWithdrawn(amount, msg.sender);
    }

    // Buyer confirms receipt and releases funds to seller
    function confirmReceiptAndReleaseFunds(uint256 listingId) public buyerOnly(listingId) {
        Listing storage listing = listings[listingId];
        require(listing.status == Status.Received, "Can only confirm after marking as received");

        // Calculate platform fee
        uint256 fee = (listing.price * feeBps) / 10_000;
        uint256 sellerAmount = listing.price - fee;

        // Update fee collection
        collectedFees += fee;

        // Transfer funds to seller
        require(usdcToken.transfer(listing.seller, sellerAmount), "Payment to seller failed");

        // Update listing status
        listing.status = Status.Completed;

        // Emit events
        emit FundsReleased(listingId, listing.seller, sellerAmount);
        emit StatusUpdated(listingId, Status.Completed);
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