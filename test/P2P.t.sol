// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {P2PExchange} from "../src/P2P.sol";
import {MockUSDC} from "./MockUSDC.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";


/// @title P2PExchangeTest
/// @dev Test contract for P2P Exchange implementation
contract P2PExchangeTest is Test {
    P2PExchange public p2p;
    MockUSDC public usdc;
    address seller;
    address buyer;
    address disputeHandler;
    address feeAdmin;

    event ListingCreated(uint256 listingId, address indexed seller, uint256 price, string title);
    event StatusUpdated(uint256 listingId, P2PExchange.Status newStatus);
    event BuyerSet(uint256 listingId, address indexed buyer);
    event FundsReleased(uint256 listingId, address indexed seller, uint256 amount);
    event ListingExpired(uint256 listingId);
    event ListingRelisted(uint256 listingId);
    event FeeSet(uint256 feeBps);
    event FeeWithdrawn(uint256 amount, address indexed admin);
    event DisputeResolved(uint256 listingId, address indexed handler, bool refundedToBuyer);
    event EscrowFundsLocked(uint256 listingId, uint256 amount, uint256 fee);

    // Test setup to initialise contract and test addresses
    function setUp() public {
        usdc = new MockUSDC();
        disputeHandler = address(400000);
        feeAdmin = address(500000);
        p2p = new P2PExchange(address(usdc), disputeHandler, feeAdmin);
        seller = address(100);
        buyer = address(200);
        

        vm.deal(seller, 100 ether);
        vm.deal(buyer, 100 ether);
    }

    // Helper to setup USDC funding for test addresses
    function prepFunding(address addr, uint256 amount) internal {
        vm.startPrank(addr);
        usdc.mint(addr, amount);
        usdc.approve(address(p2p), amount);
        vm.stopPrank();
    }

    // Verifies non-admin cannot set fees
    function test_WhenTheCallerIsNotAnAdmin() external {
        vm.expectRevert();
        vm.prank(address(1));
        p2p.setFee(100);
    }

    // Setup modifier for contract initialization tests
    modifier whenInitializingContract() {
        vm.deal(address(this), 1 ether); // Ensure testing contract has some ETH
        _;
    }

    // Tests contract deployment with zero USDC address
    function test_RevertWhen_USDCAddressIsZero() external whenInitializingContract {
        vm.expectRevert("Invalid USDC token address");
        new P2PExchange(address(0), disputeHandler, feeAdmin);
    }

    // Tests contract deployment with zero dispute handler
    function test_RevertWhen_DisputeHandlerIsZero() external whenInitializingContract {
        vm.expectRevert("Invalid dispute handler address");
        new P2PExchange(address(usdc), address(0), feeAdmin);
    }

    // Tests contract deployment with zero fee admin
    function test_RevertWhen_FeeAdminIsZero() external whenInitializingContract {
        vm.expectRevert("Invalid fee admin address");
        new P2PExchange(address(usdc), disputeHandler, address(0));
    }

    // Tests contract deployment with duplicate dispute handler and fee admin
    function test_RevertWhen_DisputeHandlerEqualsFeeAdmin() external whenInitializingContract {
        vm.expectRevert("Dispute handler and fee admin must be different");
        new P2PExchange(address(usdc), disputeHandler, disputeHandler);
    }

    // Tests contract deployment with USDC address same as dispute handler
    function test_RevertWhen_USDCEqualsDisputeHandler() external whenInitializingContract {
        vm.expectRevert("USDC token and dispute handler must be different");
        new P2PExchange(address(usdc), address(usdc), feeAdmin);
    }

    // Tests contract deployment with USDC address same as fee admin
    function test_RevertWhen_USDCEqualsFeeAdmin() external whenInitializingContract {
        vm.expectRevert("USDC token and fee admin must be different");
        new P2PExchange(address(usdc), disputeHandler, address(usdc));
    }

    // Modifier for token operation tests
    modifier whenHandlingTokenOperations() {
        _;
    }

    // Tests token transfer with insufficient balance
    function test_RevertWhen_BalanceInsufficient() external whenHandlingTokenOperations {
        usdc.mint(address(this), 1 ether);
        vm.expectRevert("Insufficient balance");
        usdc.transfer(address(1), 2 ether);
    }

    // Tests token transfer with insufficient allowance
    function test_RevertWhen_AllowanceInsufficient() external whenHandlingTokenOperations {
        address from = address(1);
        usdc.mint(from, 2 ether);
        vm.prank(from);
        usdc.approve(address(this), 1 ether);
        vm.expectRevert("Allowance exceeded");
        usdc.transferFrom(from, address(2), 2 ether);
    }

    // Modifier for authenticated calls
    modifier whenTheCallerIsAuthorized() {
        _;
    }

    // Modifier for listing creation tests
    modifier givenCreatingAListing() {
        vm.startPrank(seller);
        _;
        vm.stopPrank();
    }

    // Tests listing creation with zero price
    function test_RevertWhen_ThePriceIsZero() external whenTheCallerIsAuthorized givenCreatingAListing {
        vm.expectRevert("Price must be greater than 0");
        p2p.createListing(0, "Test");
    }

    // Tests listing creation with price exceeding maximum
    function test_RevertWhen_ThePriceExceedsMaximum() external whenTheCallerIsAuthorized givenCreatingAListing {
        uint256 maxPrice = p2p.MAX_PRICE();
        vm.expectRevert("Price exceeds maximum allowed");
        p2p.createListing( maxPrice + 1, "Test");
    }

    // Tests listing creation with empty title
    function test_RevertWhen_TheTitleIsBlank() external whenTheCallerIsAuthorized givenCreatingAListing {
        vm.expectRevert("Title cannot be empty");
        p2p.createListing(1 ether, "");
    }

    // Tests listing creation with title exceeding length limit
    function test_RevertWhen_TheTitleExceedsLength() external whenTheCallerIsAuthorized givenCreatingAListing {
        string memory longTitle = new string(201);
        vm.expectRevert("Title too long");
        p2p.createListing(1 ether, longTitle);
    }

    // Tests fee calculation overflow during listing creation
    function test_RevertWhen_TheFeeCalculationOverflows() external whenTheCallerIsAuthorized {
        vm.startPrank(feeAdmin);
        p2p.setFee(10001); // 100% in basis points
        vm.stopPrank();

        vm.expectRevert("Fee calculation overflow");
        vm.prank(seller);
        p2p.createListing(1 ether, "Test Item");
    }

    // Tests successful listing creation
    function test_WhenCreationParametersAreValid() external whenTheCallerIsAuthorized givenCreatingAListing {
        uint256 listingId = p2p.createListing(1 ether, "Valid Listing");
        P2PExchange.Listing memory listing = p2p.getListing(listingId);
        assertEq(listing.seller, seller);
        assertEq(listing.price, 1 ether);
        assertEq(listing.title, "Valid Listing");
        assertEq(uint256(listing.status), uint256(P2PExchange.Status.Listed));
    }

    // Modifier for buy initiation tests
    modifier givenInitiatingABuy() {
        vm.prank(seller);
        uint256 listingId = p2p.createListing(1 ether, "Test");
        _;
    }

    // Tests buying expired listing
    function test_RevertWhen_TheListingHasTimedOut() external whenTheCallerIsAuthorized givenInitiatingABuy {
        vm.warp(block.timestamp + 31 days);
        vm.prank(buyer);
        vm.expectRevert("Listing has expired");
        p2p.initiateBuy(0);
    }

    // Tests buying with invalid listing status
    function test_RevertWhen_TheListingStatusIsInvalid() external whenTheCallerIsAuthorized givenInitiatingABuy {
        prepFunding(buyer, 1 ether);
        vm.startPrank(buyer);
        p2p.initiateBuy(0);
        vm.expectRevert("Invalid listing status");
        p2p.initiateBuy(0);
        vm.stopPrank();
    }

    // Tests seller attempting to buy own listing
    function test_RevertWhen_TheBuyerMatchesSeller() external whenTheCallerIsAuthorized givenInitiatingABuy {
        vm.prank(seller);
        vm.expectRevert("Seller cannot buy own listing");
        p2p.initiateBuy(0);
    }

    // Tests buying with insufficient payment
    function test_RevertWhen_ThePaymentFails() external whenTheCallerIsAuthorized givenInitiatingABuy {
        vm.prank(buyer);
        vm.expectRevert("Insufficient balance");
        p2p.initiateBuy(0);
    }

    // Tests successful purchase initiation
    function test_WhenPurchaseParametersAreValid() external whenTheCallerIsAuthorized givenInitiatingABuy {
        prepFunding(buyer, 1 ether);
        vm.prank(buyer);
        p2p.initiateBuy(0);
        P2PExchange.Listing memory listing = p2p.getListing(0);
        assertEq(listing.buyer, buyer);
        assertEq(uint256(listing.status), uint256(P2PExchange.Status.BuyerPaid));
    }

    // Modifier for transaction confirmation tests
    modifier givenConfirmingATransaction() {
        vm.prank(seller);
        uint256 listingId = p2p.createListing(1 ether, "Test");
        prepFunding(buyer, 1 ether);
        vm.prank(buyer);
        p2p.initiateBuy(listingId);
        _;
    }

    // Tests confirmation by non-buyer address
    function test_RevertWhen_ConfirmerIsNotBuyer() external whenTheCallerIsAuthorized givenConfirmingATransaction {
        vm.prank(seller);
        vm.expectRevert("Only buyer can call");
        p2p.confirmTransaction(0);
    }

    // Tests confirmation with invalid transaction state
    function test_RevertWhen_TransactionStateInvalid() external whenTheCallerIsAuthorized givenConfirmingATransaction {
        vm.prank(buyer);
        p2p.confirmTransaction(0);
        vm.prank(buyer);
        vm.expectRevert("Invalid listing status");
        p2p.confirmTransaction(0);
    }

    // Tests confirmation of already released escrow
    function test_RevertWhen_EscrowAlreadyReleased() external whenTheCallerIsAuthorized givenConfirmingATransaction {
        vm.prank(buyer);
        p2p.confirmTransaction(0);
        vm.prank(buyer);
        vm.expectRevert("Invalid listing status");
        p2p.confirmTransaction(0);
    }

    // Tests confirmation with failed transfer
    function test_RevertWhen_ConfirmationTransferFails()
        external
        whenTheCallerIsAuthorized
        givenConfirmingATransaction
    {
    vm.mockCall(
            address(usdc),
            abi.encodeWithSelector(IERC20.transfer.selector),
            abi.encode(false)
        );
        
        vm.prank(buyer);
        vm.expectRevert("Transfer to seller failed");
        p2p.confirmTransaction(0);
    }

    // Tests successful transaction confirmation
    function test_WhenConfirmationParametersValid() external whenTheCallerIsAuthorized givenConfirmingATransaction {
        uint256 sellerBalanceBefore = usdc.balanceOf(seller);
        vm.prank(buyer);
        p2p.confirmTransaction(0);
        assertEq(usdc.balanceOf(seller), sellerBalanceBefore + 1 ether);
    }

    // Modifier for escrow release tests
    modifier givenRequestingEscrowRelease() {
        vm.prank(seller);
        uint256 listingId = p2p.createListing(1 ether, "Test");
        prepFunding(buyer, 1 ether);
        vm.prank(buyer);
        p2p.initiateBuy(listingId);
        _;
    }

    // Tests escrow release by non-seller
    function test_RevertWhen_RequesterIsNotSeller() external whenTheCallerIsAuthorized givenRequestingEscrowRelease {
        vm.prank(buyer);
        vm.expectRevert("Only seller can call");
        p2p.requestEscrowRelease(0);
    }

    // Tests early escrow release request
    function test_RevertWhen_EscrowPeriodIncomplete() external whenTheCallerIsAuthorized givenRequestingEscrowRelease {
        vm.prank(seller);
        vm.expectRevert("Lock period not ended");
        p2p.requestEscrowRelease(0);
    }

    // Tests release of already released escrow
    function test_RevertWhen_EscrowStateInvalid() external whenTheCallerIsAuthorized givenRequestingEscrowRelease {
        vm.warp(block.timestamp + 8 days);
        vm.prank(seller);
        p2p.requestEscrowRelease(0);
        vm.prank(seller);
        vm.expectRevert("Funds already released");
        p2p.requestEscrowRelease(0);
    }

    // Tests escrow release with failed transfer
    function test_RevertWhen_ReleaseTransferFails() external whenTheCallerIsAuthorized givenRequestingEscrowRelease {
        vm.warp(block.timestamp + 8 days);
        vm.mockCall(
            address(usdc),
            abi.encodeWithSelector(IERC20.transfer.selector),
            abi.encode(false)
        );
        
        vm.prank(seller);
        vm.expectRevert("Transfer to seller failed");
        p2p.requestEscrowRelease(0);
    }

    // Tests successful escrow release
    function test_WhenReleaseParametersValid() external whenTheCallerIsAuthorized givenRequestingEscrowRelease {
        vm.warp(block.timestamp + 8 days);
        uint256 sellerBalanceBefore = usdc.balanceOf(seller);
        vm.prank(seller);
        p2p.requestEscrowRelease(0);
        assertEq(usdc.balanceOf(seller), sellerBalanceBefore + 1 ether);
    }

    // Modifier for dispute handling tests
    modifier givenHandlingADispute() {
        vm.prank(seller);
        uint256 listingId = p2p.createListing(1 ether, "Test");
        prepFunding(buyer, 1 ether);
        vm.prank(buyer);
        p2p.initiateBuy(listingId);
        _;
    }

    // Tests dispute handling by unauthorized address
    function test_RevertWhen_HandlerLacksPermission() external whenTheCallerIsAuthorized givenHandlingADispute {
        vm.prank(address(1));
        vm.expectRevert();
        p2p.handleDispute(0, true);
    }

    // Tests dispute handling after funds released
    function test_RevertWhen_EscrowFundsGone() external whenTheCallerIsAuthorized givenHandlingADispute {
        vm.prank(buyer);
        p2p.confirmTransaction(0);
        vm.prank(disputeHandler);
        vm.expectRevert("Funds already released");
        p2p.handleDispute(0, true);
    }

    // Tests failed buyer refund in dispute
    function test_RevertWhen_BuyerRefundFails() external whenTheCallerIsAuthorized givenHandlingADispute {
        vm.mockCall(
        address(usdc),
        abi.encodeWithSelector(IERC20.transfer.selector),
        abi.encode(false)
        );
        
        vm.prank(disputeHandler);
        vm.expectRevert("Refund failed");
        p2p.handleDispute(0, true);
    }

    // Tests successful dispute resolution for buyer
    function test_WhenResolvingForBuyer() external whenTheCallerIsAuthorized givenHandlingADispute {
        uint256 buyerBalanceBefore = usdc.balanceOf(buyer);
        vm.prank(disputeHandler);
        p2p.handleDispute(0, true);
        assertEq(usdc.balanceOf(buyer), buyerBalanceBefore + 1 ether);
    }

    // Tests successful dispute resolution for seller
    function test_WhenResolvingForSeller() external whenTheCallerIsAuthorized givenHandlingADispute {
        uint256 sellerBalanceBefore = usdc.balanceOf(seller);
        vm.prank(disputeHandler);
        p2p.handleDispute(0, false);
        
        assertEq(usdc.balanceOf(seller), sellerBalanceBefore + 1 ether);
    }

    // Modifier for fee management tests
    modifier givenManagingFees() {
        _;
    }

    // Modifier for fee rate setting tests
    modifier whenSettingFeeRate() {
        _;
    }

    // Tests fee setting by unauthorized address
    function test_RevertWhen_SetterUnauthorized()
        external
        whenTheCallerIsAuthorized
        givenManagingFees
        whenSettingFeeRate
    {
        vm.prank(address(1));
        vm.expectRevert();
        p2p.setFee(100);
    }

    // Tests successful fee rate setting
    function test_WhenSetterAuthorized() external whenTheCallerIsAuthorized givenManagingFees whenSettingFeeRate {
        vm.prank(feeAdmin);
        p2p.setFee(250); // 2.5%
        assertEq(p2p.getFee(), 250);
    }

    // Tests fee collection verification
    function test_WhenCheckingCollectedFees() external whenTheCallerIsAuthorized givenManagingFees {
        assertEq(p2p.viewCollectedFee(), 0);
        vm.prank(feeAdmin);
        p2p.setFee(250); // 2.5%
        
        vm.prank(seller);
        p2p.createListing(1 ether, "Test");
        prepFunding(buyer, 1.025 ether);
        vm.prank(buyer);
        p2p.initiateBuy(0);
        vm.prank(buyer);
        p2p.confirmTransaction(0);
        
        assertEq(p2p.viewCollectedFee(), 0.025 ether);
    }

    // Modifier for fee withdrawal tests
    modifier whenWithdrawingCollectedFees() {
        _;
    }

    // Tests fee withdrawal by unauthorized address
    function test_RevertWhen_WithdrawerUnauthorized()
        external
        whenTheCallerIsAuthorized
        givenManagingFees
        whenWithdrawingCollectedFees
    {
        vm.prank(address(1));
        vm.expectRevert();
        p2p.withdrawFee();
    }

    // Tests fee withdrawal with no collected fees
    function test_RevertWhen_NoFeesCollected()
        external
        whenTheCallerIsAuthorized
        givenManagingFees
        whenWithdrawingCollectedFees
    {
        vm.prank(feeAdmin);
        vm.expectRevert("No fees to withdraw");
        p2p.withdrawFee();
    }

    // Tests successful fee withdrawal
    function test_WhenWithdrawerAuthorized()
        external
        whenTheCallerIsAuthorized
        givenManagingFees
        whenWithdrawingCollectedFees
    {
        vm.prank(feeAdmin);
        p2p.setFee(250); // 2.5% fee

        vm.prank(seller);
        p2p.createListing(1 ether, "Test");
        prepFunding(buyer, 1.025 ether); // Price + 2.5% fee
        vm.prank(buyer);
        p2p.initiateBuy(0);
        vm.prank(buyer);
        p2p.confirmTransaction(0);

        // Test fee withdrawal
        uint256 feeAdminBalanceBefore = usdc.balanceOf(feeAdmin);
        vm.prank(feeAdmin);
        p2p.withdrawFee();
        assertEq(usdc.balanceOf(feeAdmin), feeAdminBalanceBefore + 0.025 ether);
    }

    // Modifier for listing expiry tests
    modifier givenManagingExpiry() {
        vm.prank(seller);
        p2p.createListing(1 ether, "Test");
        _;
    }

    // Modifier for timeout status check tests
    modifier whenCheckingTimeoutStatus() {
        _;
    }

    // Tests expired listing check
    function test_WhenPastDeadline() external whenTheCallerIsAuthorized givenManagingExpiry whenCheckingTimeoutStatus {
        vm.warp(block.timestamp + 31 days);
        assertTrue(p2p.isExpired(0));
    }

    // Tests non-expired listing check
    function test_WhenWithinDeadline()
        external
        whenTheCallerIsAuthorized
        givenManagingExpiry
        whenCheckingTimeoutStatus
    {
        assertFalse(p2p.isExpired(0));
    }

    // Modifier for listing relist tests
    modifier whenAttemptingRelist() {
        vm.warp(block.timestamp + 31 days);
        _;
    }

    // Tests relisting by non-owner
    function test_RevertWhen_RelisterNotOwner()
        external
        whenTheCallerIsAuthorized
        givenManagingExpiry
        whenAttemptingRelist
    {
        vm.prank(buyer);
        vm.expectRevert("Only seller can call");
        p2p.relist(0);
    }

    // Tests relisting active listing
    function test_RevertWhen_ListingStillActive()
        external
        whenTheCallerIsAuthorized
        givenManagingExpiry
        whenAttemptingRelist
    {
        vm.warp(block.timestamp - 31 days); // Make listing active
        vm.prank(seller);
        vm.expectRevert("Listing is not expired");
        p2p.relist(0);
    }

    // Tests successful relisting of expired listing
    function test_WhenRelistParametersValid()
        external
        whenTheCallerIsAuthorized
        givenManagingExpiry
        whenAttemptingRelist
    {
        vm.prank(seller);
        p2p.relist(0);
        
        P2PExchange.Listing memory listing = p2p.getListing(0);
        assertTrue(listing.expiryTime > block.timestamp);
        assertEq(uint256(listing.status), uint256(P2PExchange.Status.Listed));
    }

    // Modifier for listing data retrieval tests
    modifier givenFetchingData() {
        vm.prank(seller);
        uint256 listingId = p2p.createListing(1 ether, "Test");
        _;
    }

    // Modifier for listing count verification tests
    modifier whenCheckingListingCount() {
        _;
    }

    // Tests initial listing count for new contract
    function test_WhenNoListingsExist() external whenTheCallerIsAuthorized givenFetchingData whenCheckingListingCount {
        P2PExchange newP2P = new P2PExchange(address(usdc), disputeHandler, feeAdmin);
        assertEq(newP2P.getListingCount(), 0);
    }

    // Tests listing count after multiple listings
    function test_WhenListingsExist() external whenTheCallerIsAuthorized givenFetchingData whenCheckingListingCount {
        uint256 initialCount = p2p.getListingCount();
        vm.startPrank(seller);
        p2p.createListing(1 ether, "Test 1");
        p2p.createListing(1 ether, "Test 2");
        vm.stopPrank();
        assertEq(p2p.getListingCount(), initialCount + 2);
    }

    // Modifier for listing retrieval tests
    modifier whenRetrievingListing() {
        _;
    }

    // Tests retrieval of non-existent listing
    function test_RevertWhen_ListingDoesNotExist()  
        external 
        whenTheCallerIsAuthorized 
        givenFetchingData 
        whenRetrievingListing 
    {
        vm.expectRevert("Invalid listing ID");
        p2p.getListing(999);
    }

    // Tests various operations with invalid listing ID
    function test_RevertWhen_ListingIdInvalid()
        external
        whenTheCallerIsAuthorized
        givenFetchingData
        whenRetrievingListing
    {
        vm.expectRevert("Invalid listing ID");
        p2p.initiateBuy(999);

        vm.expectRevert("Invalid listing ID");
        p2p.confirmTransaction(999);

        vm.expectRevert("Invalid listing ID");
        p2p.requestEscrowRelease(999);

        vm.expectRevert("Invalid listing ID");
        p2p.isExpired(999);

        vm.expectRevert("Invalid listing ID");
        p2p.getEscrowInfo(999);
    }

    // Tests retrieval of valid listing data
    function test_WhenListingIdValid() external whenTheCallerIsAuthorized givenFetchingData whenRetrievingListing {
        P2PExchange.Listing memory listing = p2p.getListing(0);
        assertEq(listing.seller, seller);
        assertEq(listing.price, 1 ether);
        assertEq(listing.title, "Test");
    }

    // Tests retrieval of all listings
    function test_WhenRetrievingAllListings() external whenTheCallerIsAuthorized givenFetchingData {
        P2PExchange.Listing[] memory listings = p2p.getAllListings();
        assertEq(listings.length, 1);
    }

    // Modifier for escrow information retrieval tests
    modifier whenRetrievingEscrowDetails() {
        _;
    }

    // Tests retrieval of escrow info with invalid ID
    function test_RevertWhen_EscrowIdInvalid()
        external
        whenTheCallerIsAuthorized
        givenFetchingData
        whenRetrievingEscrowDetails
    {
        vm.expectRevert("Invalid listing ID");
        p2p.getEscrowInfo(999);
    }

    // Tests retrieval of valid escrow information
    function test_WhenEscrowIdValid()
        external
        whenTheCallerIsAuthorized
        givenFetchingData
        whenRetrievingEscrowDetails
    {
        P2PExchange.Escrow memory escrow = p2p.getEscrowInfo(0);
        assertEq(escrow.amount, 0);
        assertEq(escrow.fee, 0);
        assertEq(escrow.isReleased, false);
    }

    // ++++++ Fuzz Test ++++++
    // Tests listing creation with random price and title
    function testFuzz_CreateListing(uint256 price, string memory title) public {
        // Set up constraints for price
        vm.assume(price > 0); // Price must be positive
        vm.assume(price <= p2p.MAX_PRICE()); // Price must not exceed MAX_PRICE

        // Set up constraints for title
        vm.assume(bytes(title).length > 0); // Title must not be empty
        vm.assume(bytes(title).length <= 200); // Title must not exceed 200 chars

        // Set up constraints for fee calculation
        uint256 potentialFee = (price * p2p.getFee()) / 10000;
        vm.assume(potentialFee <= price); // Prevent fee calculation overflow

        vm.startPrank(seller);

        uint256 listingId = p2p.createListing(price, title);
        P2PExchange.Listing memory listing = p2p.getListing(listingId);

        // Assertions
        assertEq(listing.seller, seller);
        assertEq(listing.price, price);
        assertEq(listing.title, title);
        assertEq(uint(listing.status), uint(P2PExchange.Status.Listed));

        // Additional assertions for new fields
        assertEq(listing.fee, potentialFee);
        assertTrue(listing.creationTime > 0);
        assertTrue(listing.expiryTime == listing.creationTime + p2p.listingDuration());
        assertFalse(listing.escrow.isReleased);

        vm.stopPrank();
    }

    // Tests initiating a buy for a valid listing
    function testFuzz_InitiateBuy(uint256 price, string memory title, uint256 buyerBalance) public {
        // Set up constraints for price and title
        vm.assume(price > 0); // Price must be positive
        vm.assume(price <= p2p.MAX_PRICE()); // Price must not exceed MAX_PRICE
        vm.assume(bytes(title).length > 0); // Title must not be empty
        vm.assume(bytes(title).length <= 200); // Title must not exceed 200 chars

        // Set up constraints for fee calculation
        uint256 potentialFee = (price * p2p.getFee()) / 10000;
        vm.assume(potentialFee <= price); // Prevent fee calculation overflow

        // Set up constraints for buyer balance
        vm.assume(buyerBalance >= price + potentialFee); // Buyer must have sufficient balance

        // Create a new listing
        vm.startPrank(seller);
        uint256 listingId = p2p.createListing(price, title);
        vm.stopPrank();

        // Initiate a buy for the listing
        vm.startPrank(buyer);

        // Mint and approve USDC tokens for the buyer
        usdc.mint(buyer, price + potentialFee);
        usdc.approve(address(p2p), price + potentialFee);

        p2p.initiateBuy(listingId);

        // Assertions
        P2PExchange.Listing memory listing = p2p.getListing(listingId);
        assertEq(listing.buyer, buyer);
        assertEq(uint(listing.status), uint(P2PExchange.Status.BuyerPaid));
        assertEq(usdc.balanceOf(address(p2p)), price + potentialFee);

        vm.stopPrank();
    }
    
}
