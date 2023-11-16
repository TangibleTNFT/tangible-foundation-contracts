# Tangible Solidity Smart Contract Framework

## Introduction
The Tangible Framework is a Solidity-based smart contract suite designed for creating cross-chain and rebase tokens. Leveraging LayerZero's omnichain interoperability protocol, it offers developers a robust and upgradeable set of tools to deploy tokens that maintain consistent behaviors and states across multiple blockchain networks.

## Features
- **Cross-Chain Token Support**: Utilize `CrossChainToken` and `LzAppUpgradeable` contracts to deploy and manage tokens that can interact across chains.
- **Rebase Token Functionality**: Implement elastic supply tokens with `RebaseTokenUpgradeable` and `RebaseTokenMath` library, allowing for automated supply adjustments.
- **Omnichain Fungible Tokens (OFT)**: Integrate with the OFT standard using `OFTUpgradeable`, enabling tokens to be transacted seamlessly across different blockchains.
- **Advanced Cross-Chain Rebase Tokens**: `CrossChainRebaseTokenUpgradeable` and `LayerZeroRebaseTokenUpgradeable` combine the rebase functionality with cross-chain capabilities, providing a sophisticated mechanism for rebase tokens in a multi-chain environment.
- **Upgradeability**: All key contracts are upgradeable, ensuring your token logic can evolve over time without sacrificing state or continuity.

## Getting Started
### Prerequisites
- Solidity ^0.8.20
- [Foundry](https://github.com/foundry-rs/foundry) for smart contract development and testing

### Installation
Clone the repository:
```bash
git clone https://github.com/TangibleTNFT/tangible-foundation-contracts
cd tangible-foundation-contracts
forge install
```

## Contract Architecture
### Cross-Chain Communication
- `LzAppUpgradeable.sol`: Base contract for LayerZero applications, handling message sending and receiving across chains.

### Rebase Tokens
- `RebaseTokenUpgradeable.sol`: Upgradeable base contract for implementing rebase tokens with elastic supply.
- `RebaseTokenMath.sol`: Library providing mathematical functions to facilitate rebase token calculations.

### Advanced Cross-Chain Rebase Tokens
- `CrossChainRebaseTokenUpgradeable.sol`: Enhances `RebaseTokenUpgradeable` with nonce-based cross-chain functionalities, ensuring the integrity of rebase operations across chains.
- `LayerZeroRebaseTokenUpgradeable.sol`: Builds upon `CrossChainRebaseTokenUpgradeable` to provide specialized cross-chain rebase token operations within the LayerZero network, handling complex message passing and state synchronization.

### OFT Standard Implementation
- `OFTUpgradeable.sol`: Implements the LayerZero OFT standard, facilitating seamless fungible token transactions across multiple chains.

## Dependencies
This framework uses the following external libraries:
- OpenZeppelin Contracts for secure standard implementations.
- LayerZero Labs Contracts for cross-chain communication.

## Development
Setup your development environment with Foundry and write your interaction scripts. Test your contracts thoroughly using Foundry's test environment.

## License
This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Support
For support, please open an issue in the GitHub repository or contact the development team.

## Acknowledgments
- LayerZero Labs for the cross-chain communication protocols.
- OpenZeppelin for the secure contract standards.
- Omniscia for the security audit of the contracts.
