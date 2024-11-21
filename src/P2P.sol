// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title P2P Exchange Contract
/// @notice Implements a secure P2P marketplace with escrow functionality
/// @dev Utilizes AccessControl for role-based permissions and ReentrancyGuard to prevent reentrancy attacks
contract P2PExchange is AccessControl, ReentrancyGuard {
    // Enum representing the possible statuses of a listing
    enum Status { Listed, BuyerPaid, Finalized, Dispute, Expired }
    
    // Structure for escrow details associated with a listing
    struct Escrow {
        uint256 amount;
        uint256 fee;
        uint256 lockedTime;
        bool isReleased;
    }
    
    // Structure for a P2P listing
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

    // Roles for access control
    bytes32 public constant DISPUTE_HANDLER_ROLE = keccak256("DISPUTE_HANDLER_ROLE");
    bytes32 public constant FEE_ADMIN_ROLE = keccak256("FEE_ADMIN_ROLE");

    IERC20 public immutable usdcToken;
    Listing[] public listings;
    uint256 private feeBps;
    uint256 private collectedFees;
    uint256 public constant ESCROW_LOCK_PERIOD = 7 days;
    uint256 public constant listingDuration = 30 days; 
    uint256 public constant MAX_PRICE = 100000 ether;

    // Events for tracking actions within the contract
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

    // Modifiers for enforcing specific conditions

    // Checks if the listing ID exists
    modifier validListing(uint256 listingId) {
        require(listingId < listings.length, "Invalid listing ID");
        _;
    }

    // Ensures only the buyer of the listing can call the function
    modifier onlyBuyer(uint256 listingId) {
        require(msg.sender == listings[listingId].buyer, "Only buyer can call");
        _;
    }

    // Ensures only the seller of the listing can call the function
    modifier onlySeller(uint256 listingId) {
        require(msg.sender == listings[listingId].seller, "Only seller can call");
        _;
    }

    // Verifies that the listing hasn't passed its expiry time
    modifier notExpired(uint256 listingId) {
        require(!isExpired(listingId), "Listing has expired");
        _;
    }

    // Checks if the listing is in the expected status
    modifier inStatus(uint256 listingId, Status requiredStatus) {
        Listing storage listing = listings[listingId];
        require(listing.status == requiredStatus, "Invalid listing status");
        _;
    }

    // Verifies that the escrow funds haven't been released yet
    modifier escrowNotReleased(uint256 listingId) {
        require(!listings[listingId].escrow.isReleased, "Funds already released");
        _;
    }

    /// @notice Contract constructor
    /// @param _usdcToken Address of the USDC token
    /// @param disputeHandler Address of the dispute handler
    /// @param feeAdmin Address of the fee administrator
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

    /// @notice Creates a new listing
    /// @param price Price of the listing
    /// @param title Title of the listing
    /// @return listingId ID of the newly created listing
    function createListing(uint256 price, string memory title) public nonReentrant returns (uint256) {
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

    /// @notice Checks if a listing has expired
    /// @param listingId ID of the listing to check
    /// @return True if the listing has expired, false otherwise
    function isExpired(uint256 listingId) public view validListing(listingId) returns (bool) {
        Listing storage listing = listings[listingId];
        return block.timestamp > listing.expiryTime && 
               listing.status == Status.Listed; // Only Listed items can expire
    }

    /// @notice Allows a seller to relist an expired listing
    /// @param listingId ID of the listing to relist
    /// @dev Resets the expiry time and recalculates the fee for the listing
    function relist(uint256 listingId) public nonReentrant validListing(listingId) onlySeller(listingId) {
        Listing storage listing = listings[listingId];
        require(isExpired(listingId), "Listing is not expired");
        
        // Reset expiry time and status
        listing.expiryTime = block.timestamp + listingDuration;
        listing.status = Status.Listed;

        // Recalculate fee based on the current fee rate
        listing.fee = (listing.price * feeBps) / 10000; // Recalculate fee with current rate
        
        emit ListingRelisted(listingId);
    }

    /// @notice Allows a buyer to initiate a purchase on a listed item
    /// @param listingId ID of the listing to buy
    /// @dev Transfers the total amount (price + fee) to the contract and locks funds in escrow
    function initiateBuy(uint256 listingId) 
        public 
        nonReentrant 
        validListing(listingId) 
        notExpired(listingId)
        inStatus(listingId, Status.Listed) 
    {
        Listing storage listing = listings[listingId];
        require(msg.sender != listing.seller, "Seller cannot buy own listing");

        uint256 totalAmount = listing.price + listing.fee;

        // Lock funds in escrow
        listing.escrow = Escrow({
            amount: listing.price,
            fee: listing.fee,
            lockedTime: block.timestamp,
            isReleased: false
        });

        // Update buyer and status
        listing.buyer = msg.sender;
        listing.status = Status.BuyerPaid;

        require(usdcToken.transferFrom(msg.sender, address(this), totalAmount), "Insufficient balance");

        emit BuyerSet(listingId, msg.sender);
        emit StatusUpdated(listingId, Status.BuyerPaid);
        emit EscrowFundsLocked(listingId, listing.price, listing.fee);
    }

    /// @notice Allows a buyer to confirm the transaction and release funds to the seller
    /// @param listingId ID of the listing being finalized
    /// @dev Transfers the escrow amount to the seller and updates the status to Finalized
    function confirmTransaction(uint256 listingId) 
        public
        nonReentrant 
        validListing(listingId) 
        onlyBuyer(listingId) 
        inStatus(listingId, Status.BuyerPaid)
        escrowNotReleased(listingId)
    {
        Listing storage listing = listings[listingId];

        // Mark escrow as released
        listing.escrow.isReleased = true;
        listing.status = Status.Finalized;

        // Transfer funds to seller
        uint256 amountToTransfer = listing.escrow.amount;
        uint256 feeCollected = listing.escrow.fee;
        collectedFees += feeCollected;

        require(usdcToken.transfer(listing.seller, amountToTransfer), "Transfer to seller failed");
        
        emit StatusUpdated(listingId, Status.Finalized);
        emit FundsReleased(listingId, listing.seller, amountToTransfer);
    }

    /// @notice Allows a seller to request escrow release after the lock period if buyer forgets to confirm after some time, however if seller tries to exploit this - buyer can dispute 
    /// @param listingId ID of the listing for which funds are being requested
    /// @dev Only callable after the escrow lock period has elapsed
    function requestEscrowRelease(uint256 listingId) 
        public
        nonReentrant 
        validListing(listingId) 
        onlySeller(listingId)
        escrowNotReleased(listingId) 
        inStatus(listingId, Status.BuyerPaid)
    {
        Listing storage listing = listings[listingId];
        require(block.timestamp >= listing.escrow.lockedTime + ESCROW_LOCK_PERIOD, "Lock period not ended");

        // Mark escrow as released
        listing.escrow.isReleased = true;
        listing.status = Status.Finalized;

        // Transfer funds to seller
        uint256 amountToTransfer = listing.escrow.amount;
        uint256 feeCollected = listing.escrow.fee;
        collectedFees += feeCollected;

        require(usdcToken.transfer(listing.seller, amountToTransfer), "Transfer to seller failed");

        
        emit StatusUpdated(listingId, Status.Finalized);
        emit FundsReleased(listingId, listing.seller, listing.escrow.amount);
    }

    /// @notice Handles disputes and resolves the escrow funds
    /// @param listingId ID of the listing under dispute
    /// @param refundBuyer Boolean indicating whether funds should be refunded to the buyer
    /// @dev Only callable by an account with the DISPUTE_HANDLER_ROLE
    function handleDispute(uint256 listingId, bool refundBuyer)
        public 
        nonReentrant 
        onlyRole(DISPUTE_HANDLER_ROLE) 
        validListing(listingId)
        escrowNotReleased(listingId)
    {
        Listing storage listing = listings[listingId];
        
        address buyerAddress = listing.buyer;
        uint256 amountToTransfer = listing.escrow.amount;
        uint256 feeAmount = listing.escrow.fee;
        
        // Mark escrow as released
        listing.escrow.isReleased = true;
        
        if (refundBuyer) {
            listing.status = Status.Listed;
            listing.buyer = address(0);
            require(usdcToken.transfer(buyerAddress, amountToTransfer + feeAmount), "Refund failed");
        } else {
            listing.status = Status.Finalized;
            collectedFees += feeAmount;
            require(usdcToken.transfer(listing.seller, amountToTransfer), "Transfer to seller failed");
        }
        
        emit DisputeResolved(listingId, msg.sender, refundBuyer);
        emit StatusUpdated(listingId, listing.status);
    }

    /// @notice Retrieves information about a specific escrow
    /// @param listingId ID of the listing
    /// @return Escrow details for the given listing
    function getEscrowInfo(uint256 listingId) public view validListing(listingId) returns (Escrow memory) {
        return listings[listingId].escrow;
    }

    /// @notice Updates the fee in basis points (bps)
    /// @param _feeBps New fee in bps
    /// @dev Only callable by an account with the FEE_ADMIN_ROLE
    function setFee(uint256 _feeBps) public onlyRole(FEE_ADMIN_ROLE) {
        feeBps = _feeBps;
        emit FeeSet(_feeBps);
    }

    /// @notice Retrieves the current fee in basis points
    /// @return Current fee in bps
    function getFee() public view returns (uint256) {
        return feeBps;
    }

    /// @notice Retrieves the total fees collected by the contract
    /// @return The total amount of fees collected in the contract
    function viewCollectedFee() public view returns (uint256) {
        return collectedFees;
    }

    /// @notice Withdraws collected fees to the fee admin
    /// @dev Transfers the collected fees to the caller
    function withdrawFee() public nonReentrant onlyRole(FEE_ADMIN_ROLE) {
        uint256 amount = collectedFees;
        require(amount > 0, "No fees to withdraw");
        collectedFees = 0;
        require(usdcToken.transfer(msg.sender, amount), "Fee withdrawal failed");
        emit FeeWithdrawn(amount, msg.sender);
    }

    /// @notice Retrieves all listings
    /// @return Array of all listings
    function getAllListings() public view returns (Listing[] memory) {
        return listings;
    }

    /// @notice Retrieves a specific listing by ID
    /// @param listingId ID of the listing to retrieve
    /// @return Listing details
    function getListing(uint256 listingId) public view validListing(listingId) returns (Listing memory) {
        Listing memory listing = listings[listingId];
        
        if (isExpired(listingId)) {
            listing.status = Status.Expired;
        }
        
        return listing;
    }

    /// @notice Retrieves the total number of listings
    /// @return Number of listings
    function getListingCount() public view returns (uint256) {
        return listings.length;
    }
}