// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

contract P2PExchange is AccessControl {
    enum Status { Listed, BuyerPaid, Shipped, Finalized, Cancelled, Dispute, Expired }
    
    struct Escrow {
        uint256 amount;
        uint256 fee;
        uint256 lockedTime;
        bool isReleased;
    }
    
    struct Listing {
        address seller;
        address buyer;
        uint256 price;
        string title;
        Status status;
        uint256 fee;        
        uint256 creationTime;
        Escrow escrow;
        uint256 expiryTime; 
    }

    bytes32 public constant DISPUTE_HANDLER_ROLE = keccak256("DISPUTE_HANDLER_ROLE");
    bytes32 public constant FEE_ADMIN_ROLE = keccak256("FEE_ADMIN_ROLE");

    IERC20 public usdcToken;
    Listing[] public listings;
    uint256 private feeBps;
    uint256 private collectedFees;
    uint256 public constant ESCROW_LOCK_PERIOD = 7 days;
    uint256 public listingDuration = 30 days; 
    uint256 public MAX_PRICE = 100000 ether;

    event ListingCreated(uint256 listingId, address indexed seller, uint256 price, string title);
    event StatusUpdated(uint256 listingId, Status newStatus);
    event BuyerSet(uint256 listingId, address indexed buyer);
    event FundsReleased(uint256 listingId, address indexed seller, uint256 amount);
    event FeeSet(uint256 feeBps);
    event FeeWithdrawn(uint256 amount, address indexed admin);
    event DisputeResolved(uint256 listingId, address indexed handler, bool refundedToBuyer);
    event EscrowFundsLocked(uint256 listingId, uint256 amount, uint256 fee);
    event ListingExpired(uint256 listingId);              
    event ListingRelisted(uint256 listingId);            
    event ListingDurationUpdated(uint256 newDuration); 

    constructor(address _usdcToken, address disputeHandler, address feeAdmin) {
        require(_usdcToken != address(0), "Invalid USDC token address");
        require(disputeHandler != address(0), "Invalid dispute handler address");
        require(feeAdmin != address(0), "Invalid fee admin address");
        require(disputeHandler != feeAdmin, "Dispute handler and fee admin must be different");
        require(_usdcToken != disputeHandler, "USDC token and dispute handler must be different");
        require(_usdcToken != feeAdmin, "USDC token and fee admin must be different");

        usdcToken = IERC20(_usdcToken);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(DISPUTE_HANDLER_ROLE, disputeHandler);
        _grantRole(FEE_ADMIN_ROLE, feeAdmin);
        feeBps = 0;
    }

    
    function createListing(uint256 price, string memory title) public returns (uint256) {
        require(price > 0, "Price must be greater than 0");
        require(price <= MAX_PRICE, "Price exceeds maximum allowed");
        require(bytes(title).length > 0, "Title cannot be empty");
        require(bytes(title).length <= 200, "Title too long");

        uint256 listingFee = (price * feeBps) / 10000;
        require(listingFee <= price, "Fee calculation overflow");
        uint256 expiryTime = block.timestamp + listingDuration;
        
        listings.push(Listing({
            seller: msg.sender,
            buyer: address(0),
            price: price,
            title: title,
            status: Status.Listed,
            fee: listingFee,
            creationTime: block.timestamp,
            escrow: Escrow({
                amount: 0,
                fee: 0,
                lockedTime: 0,
                isReleased: false
            }),
            expiryTime: expiryTime
        }));

        emit ListingCreated(listings.length - 1, msg.sender, price, title);
        return listings.length - 1;
    }

    // New: Check if listing is expired
    function isExpired(uint256 listingId) public view returns (bool) {
        require(listingId < listings.length, "Invalid listing ID");
        Listing storage listing = listings[listingId];
        return block.timestamp > listing.expiryTime && 
               listing.status == Status.Listed; // Only Listed items can expire
    }

    // New: Allow seller to relist an expired listing
    function relist(uint256 listingId) public {
        require(listingId < listings.length, "Invalid listing ID");
        Listing storage listing = listings[listingId];
        require(msg.sender == listing.seller, "Only seller can relist");
        require(isExpired(listingId), "Listing is not expired");
        
        listing.expiryTime = block.timestamp + listingDuration;
        listing.status = Status.Listed;
        listing.fee = (listing.price * feeBps) / 10000; // Recalculate fee with current rate
        
        emit ListingRelisted(listingId);
    }


    function initiateBuy(uint256 listingId) public {
        require(listingId < listings.length, "Invalid listing ID");
        Listing storage listing = listings[listingId];
        require(listing.status == Status.Listed, "Listing not available");
        require(!isExpired(listingId), "Listing has expired");  // New check
        require(msg.sender != listing.seller, "Seller cannot buy own listing");

        uint256 totalAmount = listing.price + listing.fee;
        require(usdcToken.transferFrom(msg.sender, address(this), totalAmount), "Insufficient balance");

        listing.escrow = Escrow({
            amount: listing.price,
            fee: listing.fee,
            lockedTime: block.timestamp,
            isReleased: false
        });

        listing.buyer = msg.sender;
        listing.status = Status.BuyerPaid;

        emit BuyerSet(listingId, msg.sender);
        emit StatusUpdated(listingId, Status.BuyerPaid);
        emit EscrowFundsLocked(listingId, listing.price, listing.fee);
    }

    function confirmTransaction(uint256 listingId) public {
        require(listingId < listings.length, "Invalid listing ID");
        Listing storage listing = listings[listingId];
        require(msg.sender == listing.buyer, "Only buyer can confirm");
        require(!listing.escrow.isReleased && listing.status == Status.BuyerPaid,
        "Transaction already completed or invalid status");

        // Release escrow and collect fee
        listing.escrow.isReleased = true;
        collectedFees += listing.escrow.fee;

        // Transfer funds to seller
        require(usdcToken.transfer(listing.seller, listing.escrow.amount), "Transfer to seller failed");

        listing.status = Status.Finalized;
        emit StatusUpdated(listingId, Status.Finalized);
        emit FundsReleased(listingId, listing.seller, listing.escrow.amount);
    }

    function requestEscrowRelease(uint256 listingId) public {
        require(listingId < listings.length, "Invalid listing ID");
        Listing storage listing = listings[listingId];
        require(msg.sender == listing.seller, "Only seller can request release");
        require(!listing.escrow.isReleased, "Funds already released");
        require(listing.status == Status.BuyerPaid, "Invalid listing status");
        require(block.timestamp >= listing.escrow.lockedTime + ESCROW_LOCK_PERIOD, "Lock period not ended");

        // Release escrow after lock period
        listing.escrow.isReleased = true;
        collectedFees += listing.escrow.fee;

        require(usdcToken.transfer(listing.seller, listing.escrow.amount), "Transfer to seller failed");

        listing.status = Status.Finalized;
        emit StatusUpdated(listingId, Status.Finalized);
        emit FundsReleased(listingId, listing.seller, listing.escrow.amount);
    }

    function handleDispute(uint256 listingId, bool refundBuyer) public onlyRole(DISPUTE_HANDLER_ROLE) {
        require(listingId < listings.length, "Invalid listing ID");
        Listing storage listing = listings[listingId];
        require(!listing.escrow.isReleased, "Funds already released");
        
        listing.escrow.isReleased = true;
        
        if (refundBuyer) {
            require(usdcToken.transfer(listing.buyer, listing.escrow.amount + listing.escrow.fee), "Refund failed");
            listing.status = Status.Listed;
            listing.buyer = address(0);
        } else {
            require(usdcToken.transfer(listing.seller, listing.escrow.amount), "Transfer to seller failed");
            collectedFees += listing.escrow.fee;
            listing.status = Status.Finalized;
        }
        
        emit DisputeResolved(listingId, msg.sender, refundBuyer);
        emit StatusUpdated(listingId, listing.status);
    }

    function getEscrowInfo(uint256 listingId) public view returns (Escrow memory) {
        require(listingId < listings.length, "Invalid listing ID");
        return listings[listingId].escrow;
    }

    // Rest of the contract remains unchanged
    function setFee(uint256 _feeBps) public onlyRole(FEE_ADMIN_ROLE) {
        feeBps = _feeBps;
        emit FeeSet(_feeBps);
    }

    function getFee() public view returns (uint256) {
        return feeBps;
    }

    function viewCollectedFee() public view returns (uint256) {
        return collectedFees;
    }

    function withdrawFee() public onlyRole(FEE_ADMIN_ROLE) {
        uint256 amount = collectedFees;
        collectedFees = 0;
        require(usdcToken.transfer(msg.sender, amount), "Fee withdrawal failed");
        emit FeeWithdrawn(amount, msg.sender);
    }

    function getAllListings() public view returns (Listing[] memory) {
        return listings;
    }

    function getListing(uint256 listingId) public view returns (Listing memory) {
        require(listingId < listings.length, "Listing does not exist");
        Listing memory listing = listings[listingId];
        
        // Auto-update status if expired (view only, doesn't modify state)
        if (isExpired(listingId)) {
            listing.status = Status.Expired;
        }
        
        return listing;
    }

    function getListingCount() public view returns (uint256) {
        return listings.length;
    }
}