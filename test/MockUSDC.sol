// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

/// @title MockUSDC Contract
/// @notice A simple mock implementation of a USDC-like ERC20 token for testing purposes
/// @dev This contract mimics basic ERC20 functionality including minting, transfers, and approvals
contract MockUSDC {

    // Token metadata
    string public name = "Mock USDC";
    string public symbol = "USDC";
    uint8 public decimals = 18;

    // Mappings to track balances and allowances
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    // Events for logging token actions
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);


    /// @notice Mints new tokens to the specified address
    /// @param to Address to receive the minted tokens
    /// @param amount Amount of tokens to mint
    /// @dev Increases the balance of the specified address without reducing any other balance
    function mint(address to, uint256 amount) public {
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    /// @notice Transfers tokens to another address
    /// @param to Address to receive the tokens
    /// @param amount Amount of tokens to transfer
    /// @return success Boolean indicating whether the transfer succeeded
    /// @dev Requires the sender to have sufficient balance and it updates balances accordingly
    function transfer(address to, uint256 amount) public returns (bool) {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    /// @notice Approves a spender to transfer tokens on behalf of the caller
    /// @param spender Address allowed to spend the tokens
    /// @param amount Amount of tokens to approve
    /// @return success Boolean indicating whether the approval succeeded
    /// @dev Sets the allowance for the spender to the specified amount
    function approve(address spender, uint256 amount) public returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    /// @notice Transfers tokens from one address to another using an allowance
    /// @param from Address from which tokens will be deducted
    /// @param to Address to receive the tokens
    /// @param amount Amount of tokens to transfer
    /// @return success Boolean indicating whether the transfer succeeded
    /// @dev Requires the sender to have an allowance for the from address and updates balances and allowances
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
