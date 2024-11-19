// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {P2PExchange} from "../src/P2P.sol";
import {MockUSDC} from "./MockUSDC.sol";
import "forge-std/console.sol";




contract P2PExchangeTest is Test {
    P2PExchange public p2p;
    MockUSDC public usdc;

    address seller = address(0x1);
    address buyer = address(0x2);
    address disputeHandler = address(0x3);
    address feeAdmin = address(0x4);
    error AccessControlUnauthorizedAccount(address account, bytes32 role);

    function setUp() public {
        // Deploy MockUSDC and P2PExchange contracts
        usdc = new MockUSDC();
        p2p = new P2PExchange(address(usdc), disputeHandler, feeAdmin);

        // Mint USDC tokens for the buyer
        usdc.mint(buyer, 1000 ether);

        // Buyer approves the P2PExchange contract to spend their USDC
        vm.startPrank(buyer);
        usdc.approve(address(p2p), 1000 ether);
        vm.stopPrank();
    }

    function test_CreateListing() public {
        vm.startPrank(seller);
        uint256 price = 100 ether;
        string memory title = "Sample Item";

        // Create a new listing
        uint256 listingId = p2p.createListing(price, title);

        // Verify the listing details
        P2PExchange.Listing memory listing = p2p.getListing(listingId);
        assertEq(listing.seller, seller);
        assertEq(listing.price, price);
        assertEq(listing.title, title);
        assertEq(uint(listing.status), uint(P2PExchange.Status.Listed));
        vm.stopPrank();
    }

    function test_InitiateBuy() public {
        vm.startPrank(seller);

        // Seller creates a listing
        uint256 price = 100 ether;
        uint256 listingId = p2p.createListing(price, "Item for Sale");
        vm.stopPrank();

        // Buyer initiates the purchase
        vm.startPrank(buyer);
        p2p.initiateBuy(listingId);
        vm.stopPrank();

        // Verify that the listing is updated correctly
        P2PExchange.Listing memory listing = p2p.getListing(listingId);
        assertEq(listing.buyer, buyer);
        assertEq(uint(listing.status), uint(P2PExchange.Status.BuyerPaid));
    }

    // maybe include a escrow first, cause this dont work
   function test_WithdrawFunds() public {
        vm.startPrank(seller);

        // Seller creates a listing
        uint256 price = 100 ether;
        uint256 listingId = p2p.createListing(price, "Item for Sale");
        vm.stopPrank();

        // Buyer initiates the purchase
        vm.startPrank(buyer);
        p2p.initiateBuy(listingId);
        vm.stopPrank();

        // Seller marks the item as shipped
        vm.startPrank(seller);
        p2p.updateStatus(listingId, P2PExchange.Status.Shipped);
        vm.stopPrank();

        // Buyer marks the item as received
        vm.startPrank(buyer);
        p2p.updateStatus(listingId, P2PExchange.Status.Received);
        p2p.confirmReceiptAndReleaseFunds(listingId);
        vm.stopPrank();

        // Verify the seller's USDC balance
        uint256 fee = (price * 10) / 10_000; // 0.1% fee
        uint256 sellerAmount = price - fee;
        assertEq(usdc.balanceOf(seller), sellerAmount);

        // Verify collected fees
        vm.startPrank(feeAdmin);
        assertEq(p2p.viewCollectedFee(), fee);
        vm.stopPrank();
    }

    function test_DisputeResolution_RefundBuyer() public {
        // Fee admin sets platform fee
        vm.startPrank(feeAdmin);
        p2p.setFee(100); // 1%
        vm.stopPrank();

        // Seller creates a listing
        vm.startPrank(seller);
        uint256 price = 100 ether;
        uint256 listingId = p2p.createListing(price, "Item for Sale");
        vm.stopPrank();

        // Buyer initiates purchase
        vm.startPrank(buyer);
        p2p.initiateBuy(listingId);
        vm.stopPrank();

        // Buyer marks the listing as disputed
        vm.startPrank(buyer);
        p2p.markDispute(listingId);
        vm.stopPrank();

        // Dispute handler resolves in favor of the buyer
        vm.startPrank(disputeHandler);

        uint256 fee = (price * 1) / 100;
        uint256 refundAmount = price - fee;

        // Expect the `DisputeResolved` event
        vm.expectEmit(true, true, false, true);
        emit P2PExchange.DisputeResolved(listingId, disputeHandler, fee, true);

        p2p.handleDispute(listingId, true); // Refund buyer
        vm.stopPrank();

        // Verify buyer's balance (original balance minus initial purchase + refund)
        assertEq(usdc.balanceOf(buyer), 1000 ether - price + refundAmount);

        // Verify dispute handler received the fee
        assertEq(usdc.balanceOf(disputeHandler), fee);

        // Verify collected fees in the contract
        vm.startPrank(feeAdmin);
        assertEq(p2p.viewCollectedFee(), fee);
        vm.stopPrank();
    }

    function test_DisputeResolution_PaySeller() public {
        // Fee admin sets platform fee
        vm.startPrank(feeAdmin);
        p2p.setFee(100); // 1%
        vm.stopPrank();

        // Seller creates a listing
        vm.startPrank(seller);
        uint256 price = 100 ether;
        uint256 listingId = p2p.createListing(price, "Item for Sale");
        vm.stopPrank();

        // Buyer initiates purchase
        vm.startPrank(buyer);
        p2p.initiateBuy(listingId);
        vm.stopPrank();

        // Buyer marks the listing as disputed
        vm.startPrank(buyer);
        p2p.markDispute(listingId);
        vm.stopPrank();

        // Dispute handler resolves in favor of the seller
        vm.startPrank(disputeHandler);

        uint256 fee = (price * 1) / 100;
        uint256 sellerAmount = price - fee;

        // Expect the `DisputeResolved` event
        vm.expectEmit(true, true, false, true);
        emit P2PExchange.DisputeResolved(listingId, disputeHandler, fee, false);

        p2p.handleDispute(listingId, false); // Pay seller
        vm.stopPrank();

        // Verify seller's balance is increased
        assertEq(usdc.balanceOf(seller), sellerAmount);

        // Verify dispute handler received the fee
        assertEq(usdc.balanceOf(disputeHandler), fee);
    }

    function test_WithdrawPlatformFee() public {
        // Log roles for debugging
        console.log("Default Admin Role:");
        console.logBytes32(p2p.DEFAULT_ADMIN_ROLE());

        console.log("Fee Admin Role:");
        console.logBytes32(p2p.FEE_ADMIN_ROLE());

        console.log("Contract Deployer:");
        console.logAddress(address(this));

        console.log("Fee Admin Address:");
        console.logAddress(feeAdmin);

        console.log("Is Fee Admin Granted:");
        console.logBool(p2p.hasRole(p2p.FEE_ADMIN_ROLE(), feeAdmin));
        assertTrue(p2p.hasRole(p2p.FEE_ADMIN_ROLE(), feeAdmin), "Fee admin role not assigned");

        // Fee admin sets the platform fee
        vm.startPrank(feeAdmin);
        p2p.setFee(100); // 1%
        vm.stopPrank();

        // Seller creates a listing
        vm.startPrank(seller);
        uint256 price = 100 ether;
        uint256 listingId = p2p.createListing(price, "Item for Sale");
        vm.stopPrank();

        // Buyer initiates the purchase
        vm.startPrank(buyer);
        p2p.initiateBuy(listingId);
        vm.stopPrank();

        // Seller marks the item as shipped
        vm.startPrank(seller);
        p2p.updateStatus(listingId, P2PExchange.Status.Shipped);
        vm.stopPrank();

        // Buyer marks the item as received and confirms the transaction
        vm.startPrank(buyer);
        p2p.updateStatus(listingId, P2PExchange.Status.Received);
        p2p.confirmReceiptAndReleaseFunds(listingId);
        vm.stopPrank();

        // Verify collected fees using feeAdmin
        vm.startPrank(feeAdmin);
        uint256 expectedFee = (price * 1) / 100;
        uint256 collectedFee = p2p.viewCollectedFee();
        assertEq(collectedFee, expectedFee);

        // Fee admin withdraws the collected fee
        p2p.withdrawFee();
        assertEq(usdc.balanceOf(feeAdmin), expectedFee);
        assertEq(p2p.viewCollectedFee(), 0); // Collected fees should now be 0
        vm.stopPrank();
    }


    // Test seller-only access control
    function test_SellerOnlyAccess() public {
        // Anyone can create a listing; no restrictions are applied
        vm.startPrank(buyer);
        uint256 listingId = p2p.createListing(100 ether, "Valid Listing");
        P2PExchange.Listing memory listing = p2p.getListing(listingId);
        assertEq(listing.seller, buyer); // Verify the seller is the caller
        vm.stopPrank();

        // Another address can also create a listing
        vm.startPrank(seller);
        listingId = p2p.createListing(200 ether, "Another Listing");
        listing = p2p.getListing(listingId);
        assertEq(listing.seller, seller); // Verify the seller is the caller
        vm.stopPrank();
    }

    // Test buyer-only access control
    function test_BuyerOnlyAccess() public {
        // Seller creates a listing
        vm.startPrank(seller);
        uint256 listingId = p2p.createListing(100 ether, "Valid Listing");
        vm.stopPrank();

        // Same seller tries to buy the listing, which should fail
        vm.startPrank(seller); // Incorrect role
        vm.expectRevert("Seller cannot be the buyer");
        p2p.initiateBuy(listingId);
        vm.stopPrank();

        // Another user (buyer) purchases the listing
        vm.startPrank(buyer); // Correct role
        p2p.initiateBuy(listingId);
        P2PExchange.Listing memory listing = p2p.getListing(listingId);
        assertEq(listing.buyer, buyer); // Verify the buyer is set correctly
        assertEq(uint(listing.status), uint(P2PExchange.Status.BuyerPaid)); // Verify status is updated
        vm.stopPrank();
    }

    function test_GetFeeAndListings() public {
        vm.startPrank(feeAdmin);
        p2p.setFee(100); // 1%
        vm.stopPrank();

        vm.startPrank(seller);
        uint256 price = 100 ether;
        uint256 listingId1 = p2p.createListing(price, "Item 1");
        uint256 listingId2 = p2p.createListing(price, "Item 2");
        vm.stopPrank();

        uint256 fee = p2p.getFee(); // Remove the price parameter
        assertEq(fee, 100); // Should return feeBps value (100 = 1%)

        uint256 listingCount = p2p.getListingCount();
        assertEq(listingCount, 2);

        P2PExchange.Listing[] memory allListings = p2p.getAllListings();
        assertEq(allListings.length, 2);
        assertEq(allListings[0].title, "Item 1");
        assertEq(allListings[1].title, "Item 2");
    }

    function test_InvalidFeeAdminWithdrawal() public {
        // Start prank with seller (not fee admin)
        vm.startPrank(seller);

        // Expect the `AccessControlUnauthorizedAccount` error with proper parameters
        vm.expectRevert(
            abi.encodeWithSelector(
                AccessControlUnauthorizedAccount.selector,
                seller, // The address attempting the action
                p2p.FEE_ADMIN_ROLE() // The required role
            )
        );
        p2p.withdrawFee(); // Should revert with `AccessControlUnauthorizedAccount`
        vm.stopPrank();
    }

    function test_EscrowDisputeFlow() public {
        vm.startPrank(feeAdmin);
        p2p.setFee(100); // 1%
        vm.stopPrank();

        vm.startPrank(seller);
        uint256 listingId = p2p.createListing(100 ether, "Escrow Item");
        vm.stopPrank();

        vm.startPrank(buyer);
        p2p.initiateBuy(listingId);
        p2p.markDispute(listingId);
        vm.stopPrank();

        vm.startPrank(disputeHandler);
        p2p.handleDispute(listingId, true); // Refund buyer
        vm.stopPrank();

        P2PExchange.Listing memory listing = p2p.getListing(listingId);
        assertEq(uint(listing.status), uint(P2PExchange.Status.Cancelled));
    }
}
