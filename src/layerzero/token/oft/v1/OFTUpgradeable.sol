// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20, ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import {IOFT} from "@layerzerolabs/contracts/token/oft/v1/interfaces/IOFT.sol";

import {OFTCoreUpgradeable} from "./OFTCoreUpgradeable.sol";

/**
 * @title OFTUpgradeable
 * @dev This contract is an upgradable implementation of LayerZero's Omnichain Fungible Tokens (OFT) standard.
 * It inherits the core functionalities from OFTCoreUpgradeable and extends it by adding ERC-20 token functionalities.
 * This contract is designed to allow the token to be transacted across different blockchains in a seamless manner.
 *
 * Key methods include `_debitFrom` and `_creditTo`, which are overridden to handle the actual token transactions.
 * This contract is also compatible with the ERC-165 standard for contract introspection.
 */
contract OFTUpgradeable is OFTCoreUpgradeable, ERC20Upgradeable, IOFT {
    /**
     * @param endpoint The address of the LayerZero endpoint.
     * @custom:oz-upgrades-unsafe-allow constructor
     */
    constructor(address endpoint) OFTCoreUpgradeable(endpoint) {}

    /**
     * @dev Initializes the OFT token with a given name and symbol.
     * It sets the state within this contract and also initializes the inherited ERC20 token with the given name and
     * symbol.
     * This function should only be called during the contract initialization phase.
     *
     * @param initialOwner The address of the initial owner.
     * @param name The name of the token.
     * @param symbol The symbol of the token.
     */
    function __OFT_init(address initialOwner, string memory name, string memory symbol) internal onlyInitializing {
        __OFT_init_unchained();
        __OFTCore_init(initialOwner);
        __ERC20_init(name, symbol);
    }

    function __OFT_init_unchained() internal onlyInitializing {}

    /**
     * @dev Implements the ERC165 standard for contract introspection.
     * Extends the functionality to include the interface IDs of IOFT and IERC20, alongside the inherited interfaces.
     *
     * @param interfaceId The interface identifier, as specified in ERC-165.
     * @return `true` if the contract implements the interface represented by `interfaceId`, otherwise `false`.
     */
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(OFTCoreUpgradeable, IERC165)
        returns (bool)
    {
        return interfaceId == type(IOFT).interfaceId || interfaceId == type(IERC20).interfaceId
            || super.supportsInterface(interfaceId);
    }

    /**
     * @dev Retrieves the address of the OFT token, which is the address of this contract.
     * This function is part of the IOFT interface.
     *
     * @return The address of this OFT token contract.
     */
    function token() public view virtual override returns (address) {
        return address(this);
    }

    /**
     * @dev Returns the total circulating supply of OFT tokens.
     * In this implementation, it's equivalent to the total supply as managed by the ERC20 standard.
     * This function is part of the IOFT interface.
     *
     * @return The total circulating supply of OFT tokens.
     */
    function circulatingSupply() public view virtual override returns (uint256) {
        return totalSupply();
    }

    /**
     * @dev Handles the token debit operation when sending tokens to another chain.
     * Burns the specified amount of tokens from the sender's account.
     *
     * @param from The address of the token holder.
     * @param amount The amount of tokens to be debited (burned).
     * @return The actual amount of tokens that were debited.
     */
    function _debitFrom(address from, uint16, bytes memory, uint256 amount)
        internal
        virtual
        override
        returns (uint256)
    {
        address spender = _msgSender();
        if (from != spender) _spendAllowance(from, spender, amount);
        _burn(from, amount);
        return amount;
    }

    /**
     * @dev Handles the token credit operation when receiving tokens from another chain.
     * Mints the specified amount of tokens to the recipient's account.
     *
     * @param toAddress The address of the recipient.
     * @param amount The amount of tokens to be credited (minted).
     * @return The actual amount of tokens that were credited.
     */
    function _creditTo(uint16, address toAddress, uint256 amount) internal virtual override returns (uint256) {
        _mint(toAddress, amount);
        return amount;
    }
}
