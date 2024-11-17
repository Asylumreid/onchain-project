// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {P2PExchange} from "../src/P2P.sol";

// Mock USDC Contract
contract MockUSDC {
    string public name = "Mock USDC";
    string public symbol = "USDC";
    uint8 public decimals = 18;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function mint(address to, uint256 amount) public {
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    function transfer(address to, uint256 amount) public returns (bool) {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function approve(address spender, uint256 amount) public returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public returns (bool) {
        require(balanceOf[from] >= amount, "Insufficient balance");
        require(allowance[from][msg.sender] >= amount, "Allowance exceeded");
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        allowance[from][msg.sender] -= amount;
        emit Transfer(from, to, amount);
        return true;
    }
}

contract P2PExchangeTest is Test {
    P2PExchange public p2p;
    MockUSDC public usdc;

    address seller = address(0x1);
    address buyer = address(0x2);

    function setUp() public {
        // Deploy MockUSDC and P2PExchange contracts
        usdc = new MockUSDC();
        p2p = new P2PExchange(address(usdc));

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

        // Buyer marks the item as received and confirms the transaction
        vm.startPrank(buyer);
        p2p.updateStatus(listingId, P2PExchange.Status.Received);
        p2p.confirmTransaction(listingId);
        vm.stopPrank();

        // Seller withdraws the funds
        vm.startPrank(seller);
        p2p.withdrawFunds(listingId);
        vm.stopPrank();

        // Verify the seller's USDC balance
        assertEq(usdc.balanceOf(seller), price);
    }
}
