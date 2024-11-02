// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {P2PExchange} from "../src/P2P.sol";

contract P2PExchangeTest is Test {
    P2PExchange public p2p;

    function setUp() public {
        p2p = new P2PExchange();
    }

    function test_CreateListing() public {
        // Example data for listing
        address seller = address(this);
        uint256 price = 1 ether;
        string memory title = "A sample item";
        
        // Create a listing and get the listingId
        uint256 listingId = p2p.createListing(price, title);

        // Retrieve the listing as a struct
        P2PExchange.Listing memory listing = p2p.getListing(listingId);

        // Validate listing details
        assertEq(listing.seller, seller);
        assertEq(listing.price, price);
        assertEq(listing.title, title);
        assertEq(uint(listing.status), uint(P2PExchange.Status.Listed));
        assertEq(uint(listing.listingType), uint(P2PExchange.ListingType.FixedPrice));
    }

    function test_GetListingCount() public {
        // Create two listings
        p2p.createListing(1 ether, "First item");
        p2p.createListing(2 ether, "Second item");

        // Verify the listing count
        assertEq(p2p.getListingCount(), 2);
    }

    function test_GetAllListings() public {
        // Create two listings
        p2p.createListing(1 ether, "First item");
        p2p.createListing(2 ether, "Second item");

        // Retrieve all listings
        P2PExchange.Listing[] memory allListings = p2p.getAllListings();

        // Verify both listings exist and match
        assertEq(allListings.length, 2);
        assertEq(allListings[0].price, 1 ether);
        assertEq(allListings[0].title, "First item");
        assertEq(allListings[1].price, 2 ether);
        assertEq(allListings[1].title, "Second item");
    }

    function test_InitiateBuy() public {
        // Create a listing
        uint256 price = 1 ether;
        uint256 listingId = p2p.createListing(price, "Item for Sale");

        // Simulate buyer initiating a purchase
        address buyer = address(0x123);
        vm.deal(buyer, price); // Provide buyer with enough balance for testing

        // Execute the purchase from the buyer's perspective
        vm.prank(buyer);
        p2p.initiateBuy{value: price}(listingId);

        // Verify listing details after purchase initiation
        P2PExchange.Listing memory listing = p2p.getListing(listingId);
        assertEq(listing.buyer, buyer);
        assertEq(uint(listing.status), uint(P2PExchange.Status.BuyerPaid));
    }

    function test_ConfirmTransaction() public {
        // Step 1: Create a listing
        uint256 price = 1 ether;
        uint256 listingId = p2p.createListing(price, "Item for Sale");

        // Verify initial status is "Listed"
        P2PExchange.Listing memory listing = p2p.getListing(listingId);
        assertEq(uint(listing.status), uint(P2PExchange.Status.Listed));

        // Step 2: Simulate buyer initiating a purchase
        address buyer = address(0x123);
        vm.deal(buyer, price); // Provide buyer with enough balance for testing

        // Buyer initiates buy
        vm.prank(buyer);
        p2p.initiateBuy{value: price}(listingId);

        // Verify status is "BuyerPaid" after initiateBuy
        listing = p2p.getListing(listingId);
        assertEq(uint(listing.status), uint(P2PExchange.Status.BuyerPaid), "Status should be BuyerPaid after initiateBuy");

        // Step 3: Seller updates status to "Shipped"
        vm.prank(address(this)); // Set caller to seller
        p2p.updateStatus(listingId, P2PExchange.Status.Shipped);

        // Verify status is "Shipped"
        listing = p2p.getListing(listingId);
        assertEq(uint(listing.status), uint(P2PExchange.Status.Shipped), "Status should be Shipped after updateStatus");

        // Step 4: Buyer updates status to "Received"
        vm.prank(buyer); // Set caller to buyer
        p2p.updateStatus(listingId, P2PExchange.Status.Received);

        // Verify status is "Received"
        listing = p2p.getListing(listingId);
        assertEq(uint(listing.status), uint(P2PExchange.Status.Received), "Status should be Received after buyer confirms receipt");

        // Step 5: Test that a non-buyer cannot confirm the transaction
        address nonBuyer = address(0x456);
        vm.expectRevert("Only the buyer can perform this action");
        vm.prank(nonBuyer);
        p2p.confirmTransaction(listingId);

        // Step 6: Buyer confirms the transaction
        vm.prank(buyer);
        p2p.confirmTransaction(listingId);

        // Verify that the listing is marked as Completed
        listing = p2p.getListing(listingId);
        assertEq(uint(listing.status), uint(P2PExchange.Status.Completed), "Status should be Completed after confirmTransaction");
    }
}
