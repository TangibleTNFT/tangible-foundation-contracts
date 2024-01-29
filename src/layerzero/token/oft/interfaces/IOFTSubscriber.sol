// SPDX-License-Identifier: MIT

pragma solidity >=0.5.0;

/**
 * @dev Interface of the OFT subscriber
 */
interface IOFTSubscriber {
    /**
     * @notice Notifies the contract about a token credit from a source chain.
     * @dev This function allows external systems to inform the contract about credited tokens.
     * @param srcChainId Chain ID of the source chain.
     * @param token Address of the credited token.
     * @param src Address of the sender on the source chain.
     * @param amount Amount of tokens credited.
     */
    function notifyCredit(uint16 srcChainId, address token, address src, uint256 amount) external;
}
