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
     * @param initiator Address of the initiator on the source chain.
     * @param sender The address on the source chain from which the tokens were sent.
     * @param token Address of the credited token.
     * @param amount Amount of tokens credited.
     */
    function notifyCredit(uint16 srcChainId, address initiator, address sender, address token, uint256 amount)
        external;
}
