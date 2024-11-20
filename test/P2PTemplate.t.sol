// // SPDX-License-Identifier: UNLICENSED
// // AN IMPORTANT NOTE TO THE STUDETNS:
// // - This file serve as a way for you to check that your submission is
// //   - formatted correctly
// //   - functions are named correctly
// //     - (appologies a few function names or status names were not well-specified in the lab writeup,
// //        so you may need to rename a few things. Use the search and replace in your editor)
// //   - passes the BASIC set of test cases
// // - IT IS important to note the following:
// //   - This is NOT a comprehensive test (a lot of edge case testing are left out intentionally)
// //   - This is NOT a "good" example for you to copy / reference
// //   - Please write your own tests and avoid copy-pasting these code
// //     (this file doesn't use BTT nor fuzzing, which is intentionally left out so you can
// //      independently complete that as hw)
// // To RE-EMPHASIZE:
// //   - This testing file will NOT receive a good grade during assessment
// //   - Even if you pass all the basic test here, there is NO guarantees that you will receive a good grade
// pragma solidity ^0.8.13;

// import {Test, console} from "forge-std/Test.sol";
// import {P2PExchange} from "../src/P2P.sol";
// import {MockUSDC} from "./MockUSDC.sol";


// contract CounterTest is Test {
//     P2PExchange public p2p;
//     MockUSDC public usdc;
//     address seller;
//     address buyer;
//     address unrelatedUser;
//     address disputeHandler;
//     address feeAdmin;

//     function setUp() public {
//         usdc = new MockUSDC();
//         disputeHandler = address(400000);
//         feeAdmin = address(500000);
//         p2p = new P2PExchange(address(usdc), disputeHandler, feeAdmin);
//         seller = address(100);
//         buyer = address(200);
//         unrelatedUser = address(300);
//     }

//     // Basic tests for view interfaces
//     function test_getAllListings() public {
//         // It should return empty array when no listing
//         P2PExchange.Listing[] memory listings = p2p.getAllListings();
//         assertEq(listings.length, 0);

//         // It should return 1 element array after added listing
//         p2p.createListing(1 ether, "hello");
//         listings = p2p.getAllListings();
//         assertEq(listings.length, 1);
//     }

//     function test_getListing() public {
//         // It should error out if invalid index
//         vm.expectRevert();
//         p2p.getListing(0);


//         // It should return the listing when provided correct index
//         p2p.createListing(2 ether, "hello");
//         P2PExchange.Listing memory lst = p2p.getListing(0);
//         assertEq(uint256(lst.status), uint256(P2PExchange.Status.Listed));
//     }

//     function test_getListingCount() public {
//         // It should return 0 when no listing
//         assertEq(p2p.getListingCount(), 0);

//         // It should return listing count when there is listing
//         p2p.createListing(3 ether, "hello");
//         p2p.createListing(4 ether, "hello2");
//         assertEq(p2p.getListingCount(), 2);
//     }

//     // Basic tests for creation
//     function test_createListing() public {
//         uint256 listingId = p2p.createListing(5 ether, "hello");
//         assertEq(listingId, 0);
//         P2PExchange.Listing memory lst = p2p.getListing(listingId);
//         assertEq(uint256(lst.status), uint256(P2PExchange.Status.Listed));
//     }

//     // Basic tests for initiate buy
//     function test_initiateBuyInsufficientBalance() public {
//         uint256 listingId = p2p.createListing(6 ether, "hello");
//         vm.expectRevert();
//         p2p.initiateBuy(listingId);
//     }

//     function test_initiateBuySuccess() public {
//         vm.prank(seller);
//         uint256 listingId = p2p.createListing(7 ether, "hello");

//         prepFunding(buyer, 7 ether);

//         vm.prank(buyer);
//         p2p.initiateBuy(listingId);

//         P2PExchange.Listing memory lst = p2p.getListing(listingId);
//         assertEq(uint256(lst.status), uint256(P2PExchange.Status.BuyerPaid));
//     }

//     // Basic tests for confirmTransaction
//     function test_confirmTransaction() public {
//         vm.prank(seller);
//         uint256 listingId = p2p.createListing(9 ether, "hello");

//         prepFunding(buyer, 9 ether);

//         vm.prank(buyer);
//         p2p.initiateBuy(listingId);

//         P2PExchange.Listing memory lst = p2p.getListing(listingId);

//         assertEq(uint256(lst.status), uint256(P2PExchange.Status.BuyerPaid));
//         assertEq(lst.buyer, buyer);

//         vm.prank(buyer);
//         p2p.confirmTransaction(listingId);
//         lst = p2p.getListing(listingId);
//         assertEq(uint256(lst.status), uint256(P2PExchange.Status.Finalized));
//     }

//     // Basic tests for handleDispute
//     // Specs:
//     // When seller wins, status should be set to finalized
//     // when buyer wins, listing returns to Listed and refund given to buyer
//     function test_handleDisputeSellerWin() public {
//         uint256 listingId = setupListing();

//         vm.prank(disputeHandler);
//         p2p.handleDispute(listingId, false);

//         P2PExchange.Listing memory lst = p2p.getListing(listingId);
//         assertEq(uint256(lst.status), uint256(P2PExchange.Status.Finalized));
//         assertEq(usdc.balanceOf(seller), 9 ether);
//     }

//     // Basic tests for fee collection
//     function test_setGetFee() public {
//         // Default fee is 0
//         assertEq(p2p.getFee(), 0);

//         // Set fee
//         vm.prank(feeAdmin);
//         p2p.setFee(50);
//         assertEq(p2p.getFee(), 50);

//         // Change fee
//         vm.prank(feeAdmin);
//         p2p.setFee(100);
//         assertEq(p2p.getFee(), 100);

//         // Change to zero should be allowed
//         vm.prank(feeAdmin);
//         p2p.setFee(0);
//         assertEq(p2p.getFee(), 0);

//     }

//     function test_viewCollectedFeeWithFee() public {
//         vm.prank(feeAdmin);
//         p2p.setFee(10);

//         createAndFinishPurchase(5 ether);
//         assertEq(p2p.viewCollectedFee(), 0.005 ether);

//         // Collecting more fees should add up
//         vm.prank(feeAdmin);
//         p2p.setFee(25);
//         createAndFinishPurchase(1 ether);
//         assertEq(p2p.viewCollectedFee(), 0.0075 ether);
//     }

//     function test_withdrawFee() public {
//         vm.prank(feeAdmin);
//         p2p.setFee(10);

//         createAndFinishPurchase(10 ether);
//         assertEq(p2p.viewCollectedFee(), 0.01 ether);

//         vm.prank(feeAdmin);
//         p2p.withdrawFee();
//         assertEq(usdc.balanceOf(feeAdmin), 0.01 ether);
//         assertEq(p2p.viewCollectedFee(), 0);
//     }

//     function prepFunding(address addr, uint256 amount) private {
//         vm.startPrank(addr);
//         usdc.mint(addr, amount);
//         usdc.approve(address(p2p), amount);
//         vm.stopPrank();
//     }

//     function setupListing() private returns (uint256 listingId) {
//         vm.prank(seller);
//         uint256 price = 9 ether;
//         listingId = p2p.createListing(price, "hello");
//         P2PExchange.Listing memory lst = p2p.getListing(listingId);

//         prepFunding(buyer, price + lst.fee);

//         vm.prank(buyer);
//         p2p.initiateBuy(listingId);

//         lst = p2p.getListing(listingId);

//         assertEq(uint256(lst.status), uint256(P2PExchange.Status.BuyerPaid));
//         assertEq(lst.buyer, buyer);
//     }

//     function createAndFinishPurchase(uint256 amount) private returns (P2PExchange.Listing memory lst){
//         vm.prank(seller);
//         uint256 listingId = p2p.createListing(amount, "hello");
//         lst = p2p.getListing(listingId);

//         prepFunding(buyer, amount + lst.fee);

//         vm.prank(buyer);
//         p2p.initiateBuy(listingId);

//         lst = p2p.getListing(listingId);

//         assertEq(uint256(lst.status), uint256(P2PExchange.Status.BuyerPaid));
//         assertEq(lst.buyer, buyer);

//         vm.prank(buyer);
//         p2p.confirmTransaction(listingId);

//         lst = p2p.getListing(listingId);

//         assertEq(uint256(lst.status), uint256(P2PExchange.Status.Finalized));

//         return lst;
//     }
// }

