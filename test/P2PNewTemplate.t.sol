// // SPDX-License-Identifier: UNLICENSED
// pragma solidity ^0.8.13;

// import {Test, console} from "forge-std/Test.sol";
// import {P2PExchange} from "../src/P2P.sol";
// import {MockUSDC} from "./MockUSDC.sol";

// contract P2PExchangeTest is Test {
//     P2PExchange public p2p;
//     MockUSDC public usdc;
//     address seller;
//     address buyer;
//     address unrelatedUser;
//     address disputeHandler;
//     address feeAdmin;

//     event ListingCreated(uint256 listingId, address indexed seller, uint256 price, string title);
//     event StatusUpdated(uint256 listingId, P2PExchange.Status newStatus);
//     event BuyerSet(uint256 listingId, address indexed buyer);
//     event FundsReleased(uint256 listingId, address indexed seller, uint256 amount);
//     event ListingExpired(uint256 listingId);
//     event ListingRelisted(uint256 listingId);

//     function setUp() public {
//         usdc = new MockUSDC();
//         disputeHandler = address(400000);
//         feeAdmin = address(500000);
//         p2p = new P2PExchange(address(usdc), disputeHandler, feeAdmin);
//         seller = address(100);
//         buyer = address(200);
//         unrelatedUser = address(300);

//         // Initial balance setup
//         vm.deal(seller, 100 ether);
//         vm.deal(buyer, 100 ether);
//         vm.deal(unrelatedUser, 100 ether);
//     }

//     // Helper functions
//     function prepFunding(address addr, uint256 amount) private {
//         vm.startPrank(addr);
//         usdc.mint(addr, amount);
//         usdc.approve(address(p2p), amount);
//         vm.stopPrank();
//     }

//     // Constructor Tests
//     function test_Constructor() public {
//         // Test invalid constructor params
//         vm.expectRevert("Invalid USDC token address");
//         new P2PExchange(address(0), disputeHandler, feeAdmin);

//         vm.expectRevert("Invalid dispute handler address");
//         new P2PExchange(address(usdc), address(0), feeAdmin);

//         vm.expectRevert("Invalid fee admin address");
//         new P2PExchange(address(usdc), disputeHandler, address(0));

//         // Test duplicate address prevention
//         vm.expectRevert("Dispute handler and fee admin must be different");
//         new P2PExchange(address(usdc), disputeHandler, disputeHandler);
//     }

//     // Listing Creation Tests
//     function test_CreateListingValidation() public {
//         vm.expectRevert("Price must be greater than 0");
//         p2p.createListing(0, "test");

//         vm.expectRevert("Title cannot be empty");
//         p2p.createListing(1 ether, "");

//         // Test successful creation
//         uint256 listingId = p2p.createListing(1 ether, "Valid Listing");
//         P2PExchange.Listing memory listing = p2p.getListing(listingId);
//         assertEq(listing.price, 1 ether);
//         assertEq(listing.title, "Valid Listing");
//     }

//     // Expiry Tests
//     function test_ListingExpiry() public {
//         uint256 listingId = p2p.createListing(1 ether, "Test Listing");
        
//         // Should not be expired initially
//         assertFalse(p2p.isExpired(listingId));

//         // Move time forward past expiry
//         vm.warp(block.timestamp + 31 days);
//         assertTrue(p2p.isExpired(listingId));

//         // Test getListing shows expired status
//         P2PExchange.Listing memory listing = p2p.getListing(listingId);
//         assertEq(uint256(listing.status), uint256(P2PExchange.Status.Expired));
//     }

//     // Relist Tests
//     function test_RelistValidation() public {
//         vm.prank(seller);
//         uint256 listingId = p2p.createListing(1 ether, "Test Listing");

//         // Should fail if not expired
//         vm.expectRevert("Listing is not expired");
//         vm.prank(seller);
//         p2p.relist(listingId);

//         // Move time forward to expire listing
//         vm.warp(block.timestamp + 31 days);

//         // Should fail if not seller
//         vm.expectRevert("Only seller can relist");
//         vm.prank(buyer);
//         p2p.relist(listingId);

//         // Should succeed for seller
//         vm.prank(seller);
//         p2p.relist(listingId);
        
//         P2PExchange.Listing memory listing = p2p.getListing(listingId);
//         assertEq(uint256(listing.status), uint256(P2PExchange.Status.Listed));
//         assertTrue(listing.expiryTime > block.timestamp);
//     }

//     // Buy Flow Tests
//     function test_BuyFlowWithFees() public {
//         // Set fee to 2.5%
//         vm.prank(feeAdmin);
//         p2p.setFee(250);

//         vm.prank(seller);
//         uint256 listingId = p2p.createListing(1 ether, "Test");
//         P2PExchange.Listing memory listing = p2p.getListing(listingId);
        
//         uint256 totalAmount = listing.price + listing.fee;
//         prepFunding(buyer, totalAmount);

//         // Test buy
//         vm.prank(buyer);
//         p2p.initiateBuy(listingId);

//         // Verify escrow
//         P2PExchange.Escrow memory escrow = p2p.getEscrowInfo(listingId);
//         assertEq(escrow.amount, 1 ether);
//         assertEq(escrow.fee, 0.025 ether);
//         assertFalse(escrow.isReleased);
//     }

//     // Escrow Tests
//     function test_EscrowReleaseMechanisms() public {
//         vm.prank(seller);
//         uint256 listingId = p2p.createListing(1 ether, "Test");
        
//         prepFunding(buyer, 1 ether);
        
//         vm.prank(buyer);
//         p2p.initiateBuy(listingId);

//         // Test normal confirmation
//         uint256 sellerBalanceBefore = usdc.balanceOf(seller);
//         vm.prank(buyer);
//         p2p.confirmTransaction(listingId);
//         assertEq(usdc.balanceOf(seller), sellerBalanceBefore + 1 ether);

//         // Test dispute handler
//         listingId = p2p.createListing(1 ether, "Test 2");
//         prepFunding(buyer, 1 ether);
//         vm.prank(buyer);
//         p2p.initiateBuy(listingId);

//         vm.prank(disputeHandler);
//         p2p.handleDispute(listingId, true); // Refund to buyer
        
//         P2PExchange.Listing memory listing = p2p.getListing(listingId);
//         assertEq(uint256(listing.status), uint256(P2PExchange.Status.Listed));
//         assertEq(listing.buyer, address(0));
//     }

//     // Time-based Release Tests
//     function test_TimeBasedRelease() public {
//         vm.prank(seller);
//         uint256 listingId = p2p.createListing(1 ether, "Test");
        
//         prepFunding(buyer, 1 ether);
        
//         vm.prank(buyer);
//         p2p.initiateBuy(listingId);

//         // Should fail before lock period
//         vm.expectRevert("Lock period not ended");
//         vm.prank(seller);
//         p2p.requestEscrowRelease(listingId);

//         // Move time forward
//         vm.warp(block.timestamp + 8 days);

//         // Should succeed after lock period
//         vm.prank(seller);
//         p2p.requestEscrowRelease(listingId);

//         P2PExchange.Listing memory listing = p2p.getListing(listingId);
//         assertEq(uint256(listing.status), uint256(P2PExchange.Status.Finalized));
//     }

//     // Fee Management Tests
//     function test_FeeManagement() public {
//         vm.startPrank(feeAdmin);
        
//         // Set fee to 5%
//         p2p.setFee(500);
//         assertEq(p2p.getFee(), 500);

//         vm.stopPrank();

//         // Create and complete a transaction
//         vm.prank(seller);
//         uint256 listingId = p2p.createListing(1 ether, "Test");
        
//         prepFunding(buyer, 1.05 ether); // Price + 5% fee
        
//         vm.prank(buyer);
//         p2p.initiateBuy(listingId);
        
//         vm.prank(buyer);
//         p2p.confirmTransaction(listingId);

//         // Check collected fees
//         assertEq(p2p.viewCollectedFee(), 0.05 ether);

//         // Withdraw fees
//         uint256 feeAdminBalanceBefore = usdc.balanceOf(feeAdmin);
//         vm.prank(feeAdmin);
//         p2p.withdrawFee();
//         assertEq(usdc.balanceOf(feeAdmin), feeAdminBalanceBefore + 0.05 ether);
//         assertEq(p2p.viewCollectedFee(), 0);
//     }

//     // Event Tests
//     function test_EventEmission() public {
//         vm.prank(seller);
        
//         vm.expectEmit(true, true, false, true);
//         emit ListingCreated(0, seller, 1 ether, "Test Event");
//         uint256 listingId = p2p.createListing(1 ether, "Test Event");

//         prepFunding(buyer, 1 ether);
        
//         vm.prank(buyer);
//         vm.expectEmit(true, true, false, true);
//         emit BuyerSet(listingId, buyer);
//         p2p.initiateBuy(listingId);

//         vm.prank(buyer);
//         vm.expectEmit(true, true, false, true);
//         emit FundsReleased(listingId, seller, 1 ether);
//         p2p.confirmTransaction(listingId);
//     }

//         function test_EdgeCases() public {

//         uint256 maxPrice = p2p.MAX_PRICE();
//         uint256 attemptPrice = maxPrice + 1;
    
//         console.log("Max Price:", maxPrice);
//         console.log("Attempt Price:", attemptPrice);
        
//         // Test price limits
//         vm.expectRevert("Price exceeds maximum allowed");
//         p2p.createListing(maxPrice + 1, "Too Expensive");
        

//         // Test with maximum allowed price
//         uint256 listingId = p2p.createListing(p2p.MAX_PRICE(), "Max Allowed Price");
//         P2PExchange.Listing memory listing = p2p.getListing(listingId);
//         assertEq(listing.price, p2p.MAX_PRICE());

//         // Test with very long title
//         string memory longTitle = new string(201); // Exceed 200 char limit
//         vm.expectRevert("Title too long");
//         p2p.createListing(1 ether, longTitle);

//         // Test with maximum allowed title length
//         string memory maxTitle = new string(200);
//         listingId = p2p.createListing(1 ether, maxTitle);
//         listing = p2p.getListing(listingId);
//         assertEq(listing.title, maxTitle);

//         // // Test fee overflow protection
//         // vm.prank(feeAdmin);
//         // p2p.setFee(10000); // Set fee to 100%
//         // vm.expectRevert("Fee calculation overflow");
//         // p2p.createListing(maxPrice, "Fee Overflow Test");

//         // // Test normal price with high fee
//         // listingId = p2p.createListing(1 ether, "High Fee Test");
//         // listing = p2p.getListing(listingId);
//         // assertEq(listing.fee, 1 ether); // Fee should be equal to price at 100%

//         // // Test multiple relists
//         // vm.warp(block.timestamp + 31 days);
//         // vm.expectRevert("Only seller can relist");
//         // p2p.relist(listingId);

//         // vm.prank(listing.seller);
//         // p2p.relist(listingId);
        
//         // vm.warp(block.timestamp + 31 days);
//         // vm.prank(listing.seller);
//         // p2p.relist(listingId);

//         // Verify listing still works after multiple relists
//         prepFunding(buyer, 2 ether); // Price + 100% fee
//         vm.prank(buyer);
//         p2p.initiateBuy(listingId);

//         // Test edge cases for escrow
//         vm.prank(buyer);
//         p2p.confirmTransaction(listingId);
        
//         // // Try to confirm again
//         // vm.expectRevert("Funds already released");
//         // vm.prank(buyer);
//         // p2p.confirmTransaction(listingId);
//     }

//     // Add new test for price and fee calculations
//     function test_PriceAndFeeCalculations() public {
//         vm.startPrank(feeAdmin);
        
//         // Test various fee percentages
//         uint256[] memory fees = new uint256[](4);
//         fees[0] = 100;   // 1%
//         fees[1] = 500;   // 5%
//         fees[2] = 1000;  // 10%
//         fees[3] = 10000; // 100%

//         for(uint256 i = 0; i < fees.length; i++) {
//             p2p.setFee(fees[i]);
//             uint256 listingId = p2p.createListing(1 ether, "Fee Test");
//             P2PExchange.Listing memory listing = p2p.getListing(listingId);
            
//             uint256 expectedFee = (1 ether * fees[i]) / 10000;
//             assertEq(listing.fee, expectedFee);
//         }

//         // Test with very small prices
//         p2p.setFee(100); // 1%
//         uint256 listingId = p2p.createListing(100, "Small Price");
//         P2PExchange.Listing memory listing = p2p.getListing(listingId);
//         assertEq(listing.fee, 1); // 1% of 100

//         vm.stopPrank();
//     }
// }