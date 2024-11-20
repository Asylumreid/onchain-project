// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {P2PExchange} from "../src/P2P.sol";
import {MockUSDC} from "./MockUSDC.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract WhenGivenWhenTest is Test {
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

    // Helper function
    function prepFunding(address addr, uint256 amount) internal {
        vm.startPrank(addr);
        usdc.mint(addr, amount);
        usdc.approve(address(p2p), amount);
        vm.stopPrank();
    }

    function test_WhenTheCallerIsNotAnAdmin() external {
        vm.expectRevert();
        vm.prank(address(1));
        p2p.setFee(100);
    }

    modifier whenInitializingContract() {
        vm.deal(address(this), 1 ether); // Ensure testing contract has some ETH
        _;
    }

    function test_RevertWhen_USDCAddressIsZero() external whenInitializingContract {
        vm.expectRevert("Invalid USDC token address");
        new P2PExchange(address(0), disputeHandler, feeAdmin);
    }

    function test_RevertWhen_DisputeHandlerIsZero() external whenInitializingContract {
        vm.expectRevert("Invalid dispute handler address");
        new P2PExchange(address(usdc), address(0), feeAdmin);
    }

    function test_RevertWhen_FeeAdminIsZero() external whenInitializingContract {
        vm.expectRevert("Invalid fee admin address");
        new P2PExchange(address(usdc), disputeHandler, address(0));
    }

    function test_RevertWhen_DisputeHandlerEqualsFeeAdmin() external whenInitializingContract {
        vm.expectRevert("Dispute handler and fee admin must be different");
        new P2PExchange(address(usdc), disputeHandler, disputeHandler);
    }

    function test_RevertWhen_USDCEqualsDisputeHandler() external whenInitializingContract {
        vm.expectRevert("USDC token and dispute handler must be different");
        new P2PExchange(address(usdc), address(usdc), feeAdmin);
    }

    function test_RevertWhen_USDCEqualsFeeAdmin() external whenInitializingContract {
        vm.expectRevert("USDC token and fee admin must be different");
        new P2PExchange(address(usdc), disputeHandler, address(usdc));
    }

    modifier whenTheCallerIsAuthorized() {
        _;
    }

    modifier givenCreatingAListing() {
        vm.startPrank(seller);
        _;
        vm.stopPrank();
    }

    function test_RevertWhen_ThePriceIsZero() external whenTheCallerIsAuthorized givenCreatingAListing {
        vm.expectRevert("Price must be greater than 0");
        p2p.createListing(0, "Test");
    }

    function test_RevertWhen_ThePriceExceedsMaximum() external whenTheCallerIsAuthorized givenCreatingAListing {
        uint256 maxPrice = p2p.MAX_PRICE();
        vm.expectRevert("Price exceeds maximum allowed");
        p2p.createListing( maxPrice + 1, "Test");
    }

    function test_RevertWhen_TheTitleIsBlank() external whenTheCallerIsAuthorized givenCreatingAListing {
        vm.expectRevert("Title cannot be empty");
        p2p.createListing(1 ether, "");
    }

    function test_RevertWhen_TheTitleExceedsLength() external whenTheCallerIsAuthorized givenCreatingAListing {
        string memory longTitle = new string(201);
        vm.expectRevert("Title too long");
        p2p.createListing(1 ether, longTitle);
    }

    function test_RevertWhen_TheFeeCalculationOverflows() external whenTheCallerIsAuthorized {
        vm.startPrank(feeAdmin);
        p2p.setFee(10001); // 100% in basis points
        vm.stopPrank();

        vm.expectRevert("Fee calculation overflow");
        vm.prank(seller);
        p2p.createListing(1 ether, "Test Item");
    }

    function test_WhenCreationParametersAreValid() external whenTheCallerIsAuthorized givenCreatingAListing {
        uint256 listingId = p2p.createListing(1 ether, "Valid Listing");
        P2PExchange.Listing memory listing = p2p.getListing(listingId);
        assertEq(listing.seller, seller);
        assertEq(listing.price, 1 ether);
        assertEq(listing.title, "Valid Listing");
        assertEq(uint256(listing.status), uint256(P2PExchange.Status.Listed));
    }

    modifier givenInitiatingABuy() {
        vm.prank(seller);
        uint256 listingId = p2p.createListing(1 ether, "Test");
        _;
    }

    function test_RevertWhen_TheListingHasTimedOut() external whenTheCallerIsAuthorized givenInitiatingABuy {
        vm.warp(block.timestamp + 31 days);
        vm.prank(buyer);
        vm.expectRevert("Listing has expired");
        p2p.initiateBuy(0);
    }

    function test_RevertWhen_TheListingStatusIsInvalid() external whenTheCallerIsAuthorized givenInitiatingABuy {
        prepFunding(buyer, 1 ether);
        vm.startPrank(buyer);
        p2p.initiateBuy(0);
        vm.expectRevert("Listing not available");
        p2p.initiateBuy(0);
        vm.stopPrank();
    }

    function test_RevertWhen_TheBuyerMatchesSeller() external whenTheCallerIsAuthorized givenInitiatingABuy {
        vm.prank(seller);
        vm.expectRevert("Seller cannot buy own listing");
        p2p.initiateBuy(0);
    }

    function test_RevertWhen_ThePaymentFails() external whenTheCallerIsAuthorized givenInitiatingABuy {
        vm.prank(buyer);
        vm.expectRevert("Insufficient balance");
        p2p.initiateBuy(0);
    }

    function test_WhenPurchaseParametersAreValid() external whenTheCallerIsAuthorized givenInitiatingABuy {
        prepFunding(buyer, 1 ether);
        vm.prank(buyer);
        p2p.initiateBuy(0);
        P2PExchange.Listing memory listing = p2p.getListing(0);
        assertEq(listing.buyer, buyer);
        assertEq(uint256(listing.status), uint256(P2PExchange.Status.BuyerPaid));
    }

    modifier givenConfirmingATransaction() {
        vm.prank(seller);
        uint256 listingId = p2p.createListing(1 ether, "Test");
        prepFunding(buyer, 1 ether);
        vm.prank(buyer);
        p2p.initiateBuy(listingId);
        _;
    }

    function test_RevertWhen_ConfirmerIsNotBuyer() external whenTheCallerIsAuthorized givenConfirmingATransaction {
        vm.prank(seller);
        vm.expectRevert("Only buyer can confirm");
        p2p.confirmTransaction(0);
    }

    function test_RevertWhen_TransactionStateInvalid() external whenTheCallerIsAuthorized givenConfirmingATransaction {
        vm.prank(buyer);
        p2p.confirmTransaction(0);
        vm.prank(buyer);
        vm.expectRevert("Transaction already completed or invalid status");
        p2p.confirmTransaction(0);
    }

    function test_RevertWhen_EscrowAlreadyReleased() external whenTheCallerIsAuthorized givenConfirmingATransaction {
        vm.prank(buyer);
        p2p.confirmTransaction(0);
        vm.prank(buyer);
        vm.expectRevert("Transaction already completed or invalid status");
        p2p.confirmTransaction(0);
    }

    function test_RevertWhen_ConfirmationTransferFails()
        external
        whenTheCallerIsAuthorized
        givenConfirmingATransaction
    {
        // Mock USDC transfer to return false
    vm.mockCall(
            address(usdc),
            abi.encodeWithSelector(IERC20.transfer.selector),
            abi.encode(false)
        );
        
        vm.prank(buyer);
        vm.expectRevert("Transfer to seller failed");
        p2p.confirmTransaction(0);
    }

    function test_WhenConfirmationParametersValid() external whenTheCallerIsAuthorized givenConfirmingATransaction {
        uint256 sellerBalanceBefore = usdc.balanceOf(seller);
        vm.prank(buyer);
        p2p.confirmTransaction(0);
        assertEq(usdc.balanceOf(seller), sellerBalanceBefore + 1 ether);
    }

    modifier givenRequestingEscrowRelease() {
        vm.prank(seller);
        uint256 listingId = p2p.createListing(1 ether, "Test");
        prepFunding(buyer, 1 ether);
        vm.prank(buyer);
        p2p.initiateBuy(listingId);
        _;
    }

    function test_RevertWhen_RequesterIsNotSeller() external whenTheCallerIsAuthorized givenRequestingEscrowRelease {
        vm.prank(buyer);
        vm.expectRevert("Only seller can request release");
        p2p.requestEscrowRelease(0);
    }

    function test_RevertWhen_EscrowPeriodIncomplete() external whenTheCallerIsAuthorized givenRequestingEscrowRelease {
        vm.prank(seller);
        vm.expectRevert("Lock period not ended");
        p2p.requestEscrowRelease(0);
    }

    function test_RevertWhen_EscrowStateInvalid() external whenTheCallerIsAuthorized givenRequestingEscrowRelease {
        vm.warp(block.timestamp + 8 days);
        vm.prank(seller);
        p2p.requestEscrowRelease(0);
        vm.prank(seller);
        vm.expectRevert("Funds already released");
        p2p.requestEscrowRelease(0);
    }

    function test_RevertWhen_ReleaseTransferFails() external whenTheCallerIsAuthorized givenRequestingEscrowRelease {
        // it should revert
    }

    function test_WhenReleaseParametersValid() external whenTheCallerIsAuthorized givenRequestingEscrowRelease {
        vm.warp(block.timestamp + 8 days);
        uint256 sellerBalanceBefore = usdc.balanceOf(seller);
        vm.prank(seller);
        p2p.requestEscrowRelease(0);
        assertEq(usdc.balanceOf(seller), sellerBalanceBefore + 1 ether);
    }

    modifier givenHandlingADispute() {
        vm.prank(seller);
        uint256 listingId = p2p.createListing(1 ether, "Test");
        prepFunding(buyer, 1 ether);
        vm.prank(buyer);
        p2p.initiateBuy(listingId);
        _;
    }

    function test_RevertWhen_HandlerLacksPermission() external whenTheCallerIsAuthorized givenHandlingADispute {
        vm.prank(address(1));
        vm.expectRevert();
        p2p.handleDispute(0, true);
    }

    function test_RevertWhen_EscrowFundsGone() external whenTheCallerIsAuthorized givenHandlingADispute {
        vm.prank(buyer);
        p2p.confirmTransaction(0);
        vm.prank(disputeHandler);
        vm.expectRevert("Funds already released");
        p2p.handleDispute(0, true);
    }

    function test_RevertWhen_BuyerRefundFails() external whenTheCallerIsAuthorized givenHandlingADispute {
        // it should revert
    }

    function test_WhenResolvingForBuyer() external whenTheCallerIsAuthorized givenHandlingADispute {
        uint256 buyerBalanceBefore = usdc.balanceOf(buyer);
        vm.prank(disputeHandler);
        p2p.handleDispute(0, true);
        assertEq(usdc.balanceOf(buyer), buyerBalanceBefore + 1 ether);
    }

    function test_WhenResolvingForSeller() external whenTheCallerIsAuthorized givenHandlingADispute {
        uint256 sellerBalanceBefore = usdc.balanceOf(seller);
        vm.prank(disputeHandler);
        p2p.handleDispute(0, false);
        assertEq(usdc.balanceOf(seller), sellerBalanceBefore + 1 ether);
    }

    modifier givenManagingFees() {
        _;
    }

    modifier whenSettingFeeRate() {
        _;
    }

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

    function test_WhenSetterAuthorized() external whenTheCallerIsAuthorized givenManagingFees whenSettingFeeRate {
        vm.prank(feeAdmin);
        p2p.setFee(250); // 2.5%
        assertEq(p2p.getFee(), 250);
    }

    modifier whenWithdrawingCollectedFees() {
        _;
    }

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

    modifier givenManagingExpiry() {
        vm.prank(seller);
        p2p.createListing(1 ether, "Test");
        _;
    }

    modifier whenCheckingTimeoutStatus() {
        _;
    }

    function test_WhenPastDeadline() external whenTheCallerIsAuthorized givenManagingExpiry whenCheckingTimeoutStatus {
        vm.warp(block.timestamp + 31 days);
        assertTrue(p2p.isExpired(0));
    }

    function test_WhenWithinDeadline()
        external
        whenTheCallerIsAuthorized
        givenManagingExpiry
        whenCheckingTimeoutStatus
    {
        assertFalse(p2p.isExpired(0));
    }

    modifier whenAttemptingRelist() {
        vm.warp(block.timestamp + 31 days);
        _;
    }

    function test_RevertWhen_RelisterNotOwner()
        external
        whenTheCallerIsAuthorized
        givenManagingExpiry
        whenAttemptingRelist
    {
        vm.prank(buyer);
        vm.expectRevert("Only seller can relist");
        p2p.relist(0);
    }

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

    modifier givenFetchingData() {
        vm.prank(seller);
        uint256 listingId = p2p.createListing(1 ether, "Test");
        _;
    }

    modifier whenRetrievingListing() {
        _;
    }

    function test_RevertWhen_ListingDoesNotExist()  
        external 
        whenTheCallerIsAuthorized 
        givenFetchingData 
        whenRetrievingListing 
    {
        vm.expectRevert("Listing does not exist");
        p2p.getListing(999);
    }

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

    function test_WhenListingIdValid() external whenTheCallerIsAuthorized givenFetchingData whenRetrievingListing {
        P2PExchange.Listing memory listing = p2p.getListing(0);
        assertEq(listing.seller, seller);
        assertEq(listing.price, 1 ether);
        assertEq(listing.title, "Test");
    }

    function test_WhenRetrievingAllListings() external whenTheCallerIsAuthorized givenFetchingData {
        P2PExchange.Listing[] memory listings = p2p.getAllListings();
        assertEq(listings.length, 1);
    }

    modifier whenRetrievingEscrowDetails() {
        _;
    }

    function test_RevertWhen_EscrowIdInvalid()
        external
        whenTheCallerIsAuthorized
        givenFetchingData
        whenRetrievingEscrowDetails
    {
        vm.expectRevert("Invalid listing ID");
        p2p.getEscrowInfo(999);
    }

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
}
