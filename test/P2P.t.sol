// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {P2PExchange} from "../src/P2P.sol";
import {MockUSDC} from "./MockUSDC.sol";

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
    //maybe be wonky, take a look again later
    function test_RevertWhen_EscrowAlreadyReleased() external whenTheCallerIsAuthorized givenConfirmingATransaction {
        vm.prank(buyer);
        p2p.confirmTransaction(0);
        vm.prank(buyer);
        vm.expectRevert("Transaction already completed or invalid status");
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

    function test_WhenListingIdValid() 
        external 
        whenTheCallerIsAuthorized 
        givenFetchingData 
        whenRetrievingListing 
    {
        P2PExchange.Listing memory listing = p2p.getListing(0);
        assertEq(listing.seller, seller);
        assertEq(listing.price, 1 ether);
        assertEq(listing.title, "Test");
    }

    function test_WhenRetrievingAllListings() 
        external 
        whenTheCallerIsAuthorized 
        givenFetchingData 
    {
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