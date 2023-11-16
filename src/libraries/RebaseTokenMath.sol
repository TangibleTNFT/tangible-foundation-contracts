// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @title RebaseTokenMath
 * @author Caesar LaVey
 * @dev A library that provides functions to convert between token amounts and shares in the context of a rebase
 * mechanism.
 *
 * Note: This library assumes that 1 ether is used as the base unit for the rebase index.
 */
library RebaseTokenMath {
    /**
     * @dev Converts a token amount to its equivalent shares using the rebase index.
     * The function uses the formula: shares = (amount * 1 ether) / rebaseIndex
     *
     * @param amount The token amount to be converted.
     * @param rebaseIndex The current rebase index.
     * @return shares The equivalent shares for the given token amount.
     */
    function toShares(uint256 amount, uint256 rebaseIndex) internal pure returns (uint256 shares) {
        shares = Math.mulDiv(amount, 1 ether, rebaseIndex);
    }

    /**
     * @dev Converts shares to their equivalent token amount using the rebase index.
     * The function uses the formula: amount = (shares * rebaseIndex) / 1 ether
     *
     * @param shares The number of shares to be converted.
     * @param rebaseIndex The current rebase index.
     * @return amount The equivalent token amount for the given shares.
     */
    function toTokens(uint256 shares, uint256 rebaseIndex) internal pure returns (uint256 amount) {
        amount = Math.mulDiv(shares, rebaseIndex, 1 ether);
    }
}
