// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {CrossChainToken} from "./CrossChainToken.sol";
import {RebaseTokenUpgradeable} from "./RebaseTokenUpgradeable.sol";

/**
 * @title CrossChainRebaseTokenUpgradeable
 * @author Caesar LaVey
 * @notice This contract extends the functionality of `RebaseTokenUpgradeable` by enabling cross-chain rebase
 * operations. It also implements the `ICrossChain` interface.
 *
 * @dev The contract introduces a nonce mechanism to facilitate cross-chain interactions. It has a new struct,
 * `CrossChainRebaseTokenStorage`, to manage this additional state.
 *
 * The contract overrides the `_setRebaseIndex` function to add nonce-based verification. It provides a new function
 * `_setRebaseIndex(uint256 index, uint256 nonce)` to be used in place of the original `_setRebaseIndex` function.
 *
 * It also includes functions for nonce management and verification.
 */
abstract contract CrossChainRebaseTokenUpgradeable is RebaseTokenUpgradeable, CrossChainToken {
    /// @custom:storage-location erc7201:tangible.storage.CrossChainRebaseToken
    struct CrossChainRebaseTokenStorage {
        uint256 nonce;
    }

    // keccak256(abi.encode(uint256(keccak256("tangible.storage.CrossChainRebaseToken")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant CrossChainRebaseTokenStorageLocation =
        0xdc2fee72b887a559c0d0f7379919bb4c097013a85e230aa333d867a22945b500;

    function _getCrossChainRebaseTokenStorage() private pure returns (CrossChainRebaseTokenStorage storage $) {
        // slither-disable-next-line assembly
        assembly {
            $.slot := CrossChainRebaseTokenStorageLocation
        }
    }

    /**
     * @notice Initializes the CrossChainRebaseTokenUpgradeable contract.
     * @dev This function should only be called once during the contract deployment. It internally calls
     * `__CrossChainRebaseToken_init_unchained` for any further initializations and `__RebaseToken_init` to initialize
     * the inherited RebaseTokenUpgradeable contract.
     *
     * @param name The name of the token.
     * @param symbol The symbol of the token.
     */
    function __CrossChainRebaseToken_init(string memory name, string memory symbol) internal onlyInitializing {
        __CrossChainRebaseToken_init_unchained();
        __RebaseToken_init(name, symbol);
    }

    function __CrossChainRebaseToken_init_unchained() internal onlyInitializing {}

    /**
     * @notice Retrieves the current rebase nonce.
     * @dev The function fetches the current nonce from the `CrossChainRebaseTokenStorage` struct. The nonce is used in
     * cross-chain rebase operations to ensure the correct sequence of operations.
     *
     * @return nonce The current rebase nonce.
     */
    function _rebaseNonce() internal view returns (uint256 nonce) {
        CrossChainRebaseTokenStorage storage $ = _getCrossChainRebaseTokenStorage();
        nonce = $.nonce;
    }

    function _setRebaseIndex(uint256) internal pure override {
        revert("use: _setRebaseIndex(uint256 index, uint256 nonce)");
    }

    /**
     * @notice Sets a new rebase index if the provided nonce is valid and updates the rebase nonce if it's different
     * from the current nonce.
     * @dev This function checks that the provided nonce is greater than or equal to the current stored nonce before
     * setting the new rebase index. If the nonce is greater than the stored nonce, the stored nonce is updated to the
     * new value. It relies on `_setRebaseIndex` from the `RebaseTokenUpgradeable` contract to change the rebase index.
     * If the provided nonce is less than the current nonce, no changes occur.
     *
     * @param index The new rebase index to set.
     * @param nonce The rebase nonce for this operation, which must be greater than or equal to the current nonce.
     */
    function _setRebaseIndex(uint256 index, uint256 nonce) internal virtual {
        CrossChainRebaseTokenStorage storage $ = _getCrossChainRebaseTokenStorage();
        uint256 rebaseNonce = $.nonce;
        if (nonce >= rebaseNonce) {
            RebaseTokenUpgradeable._setRebaseIndex(index);
            if (nonce != rebaseNonce) {
                $.nonce = nonce;
            }
        }
    }
}
