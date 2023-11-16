// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

import {RebaseTokenMath} from "../libraries/RebaseTokenMath.sol";

/**
 * @title RebaseTokenUpgradeable
 * @author Caesar LaVey
 * @notice This is an upgradeable ERC20 token contract that introduces a rebase mechanism and allows accounts to opt out
 * of rebasing. The contract uses an index-based approach to implement rebasing, allowing for more gas-efficient
 * calculations.
 *
 * @dev The contract inherits from OpenZeppelin's ERC20Upgradeable and utilizes the RebaseTokenMath library for its
 * arithmetic operations. It introduces a new struct "RebaseTokenStorage" to manage its state. The state variables
 * include `rebaseIndex`, which is the current index value for rebasing, and `totalShares`, which is the total number of
 * index-based shares in circulation.
 *
 * The contract makes use of low-level Solidity features like assembly for optimized storage handling. It adheres to the
 * Checks-Effects-Interactions design pattern where applicable and emits events for significant state changes.
 */
abstract contract RebaseTokenUpgradeable is ERC20Upgradeable {
    using RebaseTokenMath for uint256;

    /// @custom:storage-location erc7201:tangible.storage.RebaseToken
    struct RebaseTokenStorage {
        uint256 rebaseIndex;
        uint256 totalShares;
        mapping(address => uint256) shares;
        mapping(address => bool) optOut;
    }

    // keccak256(abi.encode(uint256(keccak256("tangible.storage.RebaseToken")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant RebaseTokenStorageLocation =
        0x8a0c9d8ec1d9f8b365393c36404b40a33f47675e34246a2e186fbefd5ecd3b00;

    function _getRebaseTokenStorage() private pure returns (RebaseTokenStorage storage $) {
        // slither-disable-next-line assembly
        assembly {
            $.slot := RebaseTokenStorageLocation
        }
    }

    event RebaseIndexUpdated(address updatedBy, uint256 index);
    event RebaseEnabled(address indexed account);
    event RebaseDisabled(address indexed account);

    error AmountExceedsBalance(address account, uint256 balance, uint256 amount);
    error RebaseOverflow();

    /**
     * @notice Initializes the RebaseTokenUpgradeable contract.
     * @dev This function should only be called once during the contract deployment. It internally calls
     * `__RebaseToken_init_unchained` for any further initializations and `__ERC20_init` to initialize the inherited
     * ERC20 contract.
     *
     * @param name The name of the token.
     * @param symbol The symbol of the token.
     */
    function __RebaseToken_init(string memory name, string memory symbol) internal onlyInitializing {
        __RebaseToken_init_unchained();
        __ERC20_init(name, symbol);
    }

    function __RebaseToken_init_unchained() internal onlyInitializing {}

    /**
     * @notice Enables or disables rebasing for a specific account.
     * @dev This function updates the `optOut` mapping for the `account` based on the `disable` flag. It also adjusts
     * the shares and token balances accordingly if the account has a non-zero balance. This function emits either a
     * `RebaseEnabled` or `RebaseDisabled` event.
     *
     * @param account The address of the account for which rebasing is to be enabled or disabled.
     * @param disable A boolean flag indicating whether to disable (true) or enable (false) rebasing for the account.
     */
    function _disableRebase(address account, bool disable) internal {
        RebaseTokenStorage storage $ = _getRebaseTokenStorage();
        if ($.optOut[account] != disable) {
            uint256 balance = balanceOf(account);
            if (balance != 0) {
                if (disable) {
                    RebaseTokenUpgradeable._update(account, address(0), balance);
                } else {
                    ERC20Upgradeable._update(account, address(0), balance);
                }
            }
            $.optOut[account] = disable;
            if (balance != 0) {
                if (disable) {
                    ERC20Upgradeable._update(address(0), account, balance);
                } else {
                    RebaseTokenUpgradeable._update(address(0), account, balance);
                }
            }
            if (disable) emit RebaseDisabled(account);
            else emit RebaseEnabled(account);
        }
    }

    /**
     * @notice Checks if rebasing is disabled for a specific account.
     * @dev This function fetches the `optOut` status from the contract's storage for the specified `account`.
     *
     * @param account The address of the account to check.
     * @return disabled A boolean indicating whether rebasing is disabled (true) or enabled (false) for the account.
     */
    function _isRebaseDisabled(address account) internal view returns (bool disabled) {
        RebaseTokenStorage storage $ = _getRebaseTokenStorage();
        disabled = $.optOut[account];
    }

    /**
     * @notice Returns the current rebase index of the token.
     * @dev This function fetches the `rebaseIndex` from the contract's storage and returns it. The returned index is
     * used in various calculations related to token rebasing.
     *
     * @return index The current rebase index.
     */
    function rebaseIndex() public view returns (uint256 index) {
        RebaseTokenStorage storage $ = _getRebaseTokenStorage();
        index = $.rebaseIndex;
    }

    /**
     * @notice Returns the balance of a specific account, adjusted for the current rebase index.
     * @dev This function fetches the `shares` and `rebaseIndex` from the contract's storage for the specified account.
     * It then calculates the balance in tokens by converting these shares to their equivalent token amount using the
     * current rebase index.
     *
     * @param account The address of the account whose balance is to be fetched.
     * @return balance The balance of the specified account in tokens.
     */
    function balanceOf(address account) public view virtual override returns (uint256 balance) {
        RebaseTokenStorage storage $ = _getRebaseTokenStorage();
        if ($.optOut[account]) {
            balance = ERC20Upgradeable.balanceOf(account);
        } else {
            balance = $.shares[account].toTokens($.rebaseIndex);
        }
    }

    /**
     * @notice Returns the total supply of the token, taking into account the current rebase index.
     * @dev This function fetches the `totalShares` and `rebaseIndex` from the contract's storage. It then calculates
     * the total supply of tokens by converting these shares to their equivalent token amount using the current rebase
     * index.
     *
     * @return supply The total supply of tokens.
     */
    function totalSupply() public view virtual override returns (uint256 supply) {
        RebaseTokenStorage storage $ = _getRebaseTokenStorage();
        supply = $.totalShares.toTokens($.rebaseIndex) + ERC20Upgradeable.totalSupply();
    }

    /**
     * @notice Sets a new rebase index for the token.
     * @dev This function updates the `rebaseIndex` state variable if the new index differs from the current one. It
     * also performs a check for any potential overflow conditions that could occur with the new index. Emits a
     * `RebaseIndexUpdated` event upon successful update.
     *
     * @param index The new rebase index to set.
     */
    function _setRebaseIndex(uint256 index) internal virtual {
        RebaseTokenStorage storage $ = _getRebaseTokenStorage();
        if ($.rebaseIndex != index) {
            $.rebaseIndex = index;
            _checkRebaseOverflow($.totalShares, index);
            emit RebaseIndexUpdated(msg.sender, index);
        }
    }

    /**
     * @notice Calculates the number of transferable shares for a given amount and account.
     * @dev This function fetches the current rebase index and the shares held by the `from` address. It then converts
     * these shares to the equivalent token balance. If the `amount` to be transferred exceeds this balance, the
     * function reverts with an `AmountExceedsBalance` error. Otherwise, it calculates the number of shares equivalent
     * to the `amount` to be transferred.
     *
     * @param amount The amount of tokens to be transferred.
     * @param from The address from which the tokens are to be transferred.
     * @return shares The number of shares equivalent to the `amount` to be transferred.
     */
    function _transferableShares(uint256 amount, address from) internal view returns (uint256 shares) {
        RebaseTokenStorage storage $ = _getRebaseTokenStorage();
        shares = $.shares[from];
        uint256 index = $.rebaseIndex;
        uint256 balance = shares.toTokens(index);
        if (amount > balance) {
            revert AmountExceedsBalance(from, balance, amount);
        }
        if (amount < balance) {
            shares = amount.toShares(index);
        }
    }

    /**
     * @notice Updates the state of the contract during token transfers, mints, or burns.
     * @dev This function adjusts the `totalShares` and individual `shares` of `from` and `to` addresses based on their
     * rebasing status (`optOut`). When both parties have opted out of rebasing, the standard ERC20 `_update` is called
     * instead. It performs overflow and underflow checks where necessary and delegates to the parent function when
     * opt-out applies.
     *
     * @param from The address from which tokens are transferred or burned. Address(0) implies minting.
     * @param to The address to which tokens are transferred or minted. Address(0) implies burning.
     * @param amount The amount of tokens to be transferred.
     */
    function _update(address from, address to, uint256 amount) internal virtual override {
        RebaseTokenStorage storage $ = _getRebaseTokenStorage();
        bool optOutFrom = $.optOut[from];
        bool optOutTo = $.optOut[to];
        if (optOutFrom && optOutTo) {
            ERC20Upgradeable._update(from, to, amount);
            return;
        }
        uint256 index = $.rebaseIndex;
        uint256 shares = amount.toShares($.rebaseIndex);
        if (from == address(0)) {
            if (!optOutTo) {
                uint256 totalShares = $.totalShares + shares; // Overflow check required
                _checkRebaseOverflow(totalShares, index);
                $.totalShares = totalShares;
            }
        } else {
            if (optOutFrom) {
                ERC20Upgradeable._update(from, address(0), amount);
            } else {
                shares = _transferableShares(amount, from);
                unchecked {
                    // Underflow not possible: `shares <= $.shares[from] <= totalShares`.
                    $.shares[from] -= shares;
                }
            }
        }

        if (to == address(0)) {
            if (!optOutFrom) {
                unchecked {
                    // Underflow not possible: `shares <= $.totalShares` or `shares <= $.shares[from] <= $.totalShares`.
                    $.totalShares -= shares;
                }
                emit Transfer(from, address(0), shares.toTokens(index));
            }
        } else {
            if (optOutTo) {
                // At this point we know that `from` has not opted out.
                ERC20Upgradeable._update(address(0), to, amount);
            } else {
                unchecked {
                    // Overflow not possible: `$.shares[to] + shares` is at most `$.totalShares`, which we know fits
                    // into a `uint256`.
                    $.shares[to] += shares;
                }
                emit Transfer(optOutFrom ? address(0) : from, to, shares.toTokens(index));
            }
        }
    }

    /**
     * @notice Checks for potential overflow conditions in token-to-share calculations.
     * @dev This function uses an `assert` statement to ensure that converting shares to tokens using the provided
     * `index` will not result in an overflow. It leverages the `toTokens` function from the `RebaseTokenMath` library
     * to perform this check.
     *
     * @param shares The number of shares involved in the operation.
     * @param index The current rebase index.
     */
    function _checkRebaseOverflow(uint256 shares, uint256 index) private view {
        // Using an unchecked block to avoid overflow checks, as overflow will be handled explicitly.
        uint256 _elasticSupply = shares.toTokens(index);
        unchecked {
            if (_elasticSupply + ERC20Upgradeable.totalSupply() < _elasticSupply) {
                revert RebaseOverflow();
            }
        }
    }
}
