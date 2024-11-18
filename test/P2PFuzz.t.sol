// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {P2PExchange} from "../src/P2P.sol";
import {MockUSDC} from "./MockUSDC.sol";

contract P2PFuzzTest is Test {
    P2PExchange public p2p;
    MockUSDC public usdc;

    address seller = address(0x1);
    address disputeHandler = address(0x3);
    address feeAdmin = address(0x4);

    function setUp() public {
        // Deploy MockUSDC and P2PExchange contracts
        usdc = new MockUSDC();
        p2p = new P2PExchange(address(usdc), disputeHandler, feeAdmin);
    }

    /// @dev Fuzz test for creating a listing with random price and title
    function testFuzz_CreateListing(uint256 price, string memory title) public {
        // Set up constraints
        vm.assume(price > 0); // Ensure the price is positive
        vm.assume(bytes(title).length > 0); // Ensure the title is not empty

        vm.startPrank(seller);

        uint256 listingId = p2p.createListing(price, title);
        P2PExchange.Listing memory listing = p2p.getListing(listingId);

        assertEq(listing.seller, seller);
        assertEq(listing.price, price);
        assertEq(listing.title, title);
        assertEq(uint(listing.status), uint(P2PExchange.Status.Listed));

        vm.stopPrank();
    }

    /// @dev Fuzz test for initiating a buy with random allowance and price
    function testFuzz_InitiateBuy(uint256 allowance, uint256 price) public {
        // Set up constraints
        vm.assume(allowance >= price && price > 0); // Ensure sufficient allowance and positive price

        // Seller creates a listing
        vm.startPrank(seller);
        uint256 listingId = p2p.createListing(price, "Fuzz Test Item");
        vm.stopPrank();

        // Buyer gets allowance and USDC balance
        address buyer = address(0x2);
        usdc.mint(buyer, allowance);
        vm.startPrank(buyer);
        usdc.approve(address(p2p), allowance);

        // Buyer initiates the purchase
        p2p.initiateBuy(listingId);

        P2PExchange.Listing memory listing = p2p.getListing(listingId);
        assertEq(listing.buyer, buyer);
        assertEq(uint(listing.status), uint(P2PExchange.Status.BuyerPaid));

        vm.stopPrank();
    }
}