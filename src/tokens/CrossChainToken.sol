// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IOFTSubscriber} from "@layerzerolabs/contracts-upgradeable/token/oft/interfaces/IOFTSubscriber.sol";

abstract contract CrossChainToken {
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    bool public immutable isMainChain;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(uint256 mainChainId) {
        isMainChain = mainChainId == block.chainid;
    }

    /**
     * @dev Attempts to notify the receiver of the credited amount.
     * Inline assembly is used to call the `notifyCredit` function on the receiver in order to prevent LayerZero's
     * ExcessivelySafeCall library from tagging the transaction as failed when this call fails.
     *
     * @param srcChainId The ID of the source chain where the message originated.
     * @param initiator The address of the initiator on the source chain.
     * @param sender The address on the source chain from which the tokens were sent.
     * @param receiver The address of the receiver who received tokens.
     * @param amount The amount of tokens credited.
     */
    function _tryNotifyReceiver(
        uint16 srcChainId,
        address initiator,
        address sender,
        address,
        address receiver,
        uint256 amount
    ) internal returns (bool success) {
        bytes memory data =
            abi.encodeCall(IOFTSubscriber.notifyCredit, (srcChainId, initiator, sender, address(this), amount));
        assembly {
            success :=
                call(
                    gas(), // gas remaining
                    receiver, // destination address
                    0, // no ether
                    add(data, 32), // input buffer (starts after the first 32 bytes in the `data` array)
                    mload(data), // input length (loaded from the first 32 bytes in the `data` array)
                    0, // output buffer
                    0 // output length
                )
        }
    }
}
