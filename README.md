Here's a README for your P2P Exchange project:

```markdown
# P2P Exchange Smart Contract

A decentralized peer-to-peer exchange platform built on Solidity, enabling secure trading with USDC and escrow functionality.

## Deployed Contract
- Sepolia Network: [0x4b7d95a3d10d113ba69e4faf96071d9c426833a0](https://sepolia.basescan.org/address/0x4b7d95a3d10d113ba69e4faf96071d9c426833a0)

## Features

- Create and manage listings with customizable titles and prices
- Secure escrow system for trade protection
- Automated fee collection mechanism
- Dispute resolution system
- Listing expiry and relisting functionality
- USDC integration for stable payments

## Contract Structure

The system consists of the following main components:

- `P2PExchange.sol`: Main contract handling listings and trades
- `MockUSDC.sol`: Test USDC token implementation
- `P2PExchangeTest.sol`: Comprehensive test suite

## Testing

The contract includes extensive testing coverage:

### Unit Tests
- Contract initialization
- Listing management
- Purchase flows
- Escrow handling
- Fee collection
- Dispute resolution
- Access control

### Fuzz Tests
- Random listing creation with varied prices and titles
- Buy initiation with randomized parameters

## Security Features

- Escrow system for secure trading
- Role-based access control
- Input validation
- Transaction timeouts
- Dispute resolution mechanism

## Usage

### Prerequisites
- Foundry
- Solidity ^0.8.13

### Installation
```bash
git clone https://github.com/Asylumreid/onchain-project
cd onchain-project
forge install
```

### Running Tests
```bash
forge test
```

## Functionality Overview

### For Sellers
1. Create listings with title and price
2. Receive funds after successful trades
3. Request escrow release after lock period

### For Buyers
1. Browse available listings
2. Purchase items with USDC
3. Confirm successful transactions

### For Administrators
1. Handle disputes
2. Manage platform fees
3. Withdraw collected fees

## License

UNLICENSED

## Testing Coverage
- Unit tests for all core functionalities
- Fuzz testing for input validation
- Integration tests for complete workflows

## Contributors
Praveen Kumar
```

