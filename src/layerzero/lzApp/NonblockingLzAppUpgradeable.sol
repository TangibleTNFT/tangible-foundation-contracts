// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ExcessivelySafeCall} from "@layerzerolabs/contracts/libraries/ExcessivelySafeCall.sol";

import {LzAppUpgradeable} from "./LzAppUpgradeable.sol";

/**
 * @title Nonblocking LayerZero Application
 * @dev This contract extends LzAppUpgradeable and modifies its behavior to be non-blocking. Failed messages are caught
 * and stored for future retries, ensuring that the message channel remains unblocked. This contract serves as an
 * abstract base class and should be extended by specific implementations.
 *
 * Note: If the `srcAddress` is not configured properly, it will still block the message pathway from (`srcChainId`,
 * `srcAddress`).
 */
abstract contract NonblockingLzAppUpgradeable is LzAppUpgradeable {
    using ExcessivelySafeCall for address;

    event MessageFailed(uint16 srcChainId, bytes srcAddress, uint64 nonce, bytes payload, bytes reason);
    event RetryMessageSuccess(uint16 srcChainId, bytes srcAddress, uint64 nonce, bytes32 payloadHash);

    /// @custom:storage-location erc7201:layerzero.storage.NonblockingLzApp
    struct NonblockingLzAppStorage {
        mapping(uint16 => mapping(bytes => mapping(uint64 => bytes32))) failedMessages;
    }

    // keccak256(abi.encode(uint256(keccak256("layerzero.storage.NonblockingLzApp")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant NonblockingLzAppStorageLocation =
        0xe5a86fa43fa85f564c84895bd4f80ec5c29d03a57a0c1f7cb91d2cc05b4d8600;

    function _getNonblockingLzAppStorage() private pure returns (NonblockingLzAppStorage storage $) {
        // slither-disable-next-line assembly
        assembly {
            $.slot := NonblockingLzAppStorageLocation
        }
    }

    /**
     * @param endpoint The address of the LayerZero endpoint contract.
     * @custom:oz-upgrades-unsafe-allow constructor
     */
    constructor(address endpoint) LzAppUpgradeable(endpoint) {}

    /**
     * @dev Initializes the contract, setting the initial owner and endpoint addresses.
     * Also chains the initialization process with the base `LzAppUpgradeable` contract.
     *
     * Requirements:
     * - Can only be called during contract initialization.
     *
     * @param initialOwner The address that will initially own the contract.
     */
    function __NonblockingLzApp_init(address initialOwner) internal onlyInitializing {
        __NonblockingLzApp_init_unchained();
        __LzApp_init(initialOwner);
    }

    function __NonblockingLzApp_init_unchained() internal onlyInitializing {}

    /**
     * @dev Retrieves the hash of the payload of a failed message for a given source chain, source address, and nonce.
     *
     * @param srcChainId The ID of the source chain where the message originated.
     * @param srcAddress The address on the source chain where the message originated.
     * @param nonce The nonce of the failed message.
     * @return payloadHash The hash of the payload of the failed message.
     */
    function failedMessages(uint16 srcChainId, bytes calldata srcAddress, uint64 nonce)
        external
        view
        returns (bytes32 payloadHash)
    {
        NonblockingLzAppStorage storage $ = _getNonblockingLzAppStorage();
        return $.failedMessages[srcChainId][srcAddress][nonce];
    }

    /**
     * @dev Internal function that receives LayerZero messages and attempts to process them in a non-blocking manner.
     * If processing fails, the message is stored for future retries.
     *
     * @param srcChainId The ID of the source chain where the message originated.
     * @param srcAddress The address on the source chain where the message originated.
     * @param nonce The nonce of the message.
     * @param payload The payload of the message.
     */
    function _blockingLzReceive(uint16 srcChainId, bytes memory srcAddress, uint64 nonce, bytes memory payload)
        internal
        virtual
        override
    {
        (bool success, bytes memory reason) = address(this).excessivelySafeCall(
            gasleft(),
            150,
            abi.encodeWithSelector(this.nonblockingLzReceive.selector, srcChainId, srcAddress, nonce, payload)
        );
        // try-catch all errors/exceptions
        if (!success) {
            _storeFailedMessage(srcChainId, srcAddress, nonce, payload, reason);
        }
    }

    /**
     * @dev Internal function to store the details of a failed message for future retries.
     *
     * @param srcChainId The ID of the source chain where the message originated.
     * @param srcAddress The address on the source chain where the message originated.
     * @param nonce The nonce of the failed message.
     * @param payload The payload of the failed message.
     * @param reason The reason for the message's failure.
     */
    function _storeFailedMessage(
        uint16 srcChainId,
        bytes memory srcAddress,
        uint64 nonce,
        bytes memory payload,
        bytes memory reason
    ) internal virtual {
        NonblockingLzAppStorage storage $ = _getNonblockingLzAppStorage();
        $.failedMessages[srcChainId][srcAddress][nonce] = keccak256(payload);
        emit MessageFailed(srcChainId, srcAddress, nonce, payload, reason);
    }

    /**
     * @dev Public wrapper function for handling incoming LayerZero messages in a non-blocking manner.
     * It internally calls the `_nonblockingLzReceive` function, which should be overridden in derived contracts.
     *
     * Requirements:
     * - The caller must be the contract itself.
     *
     * @param srcChainId The ID of the source chain where the message originated.
     * @param srcAddress The address on the source chain where the message originated.
     * @param nonce The nonce of the message.
     * @param payload The payload of the message.
     */
    function nonblockingLzReceive(uint16 srcChainId, bytes calldata srcAddress, uint64 nonce, bytes calldata payload)
        public
        virtual
    {
        // only internal transaction
        require(_msgSender() == address(this), "NonblockingLzApp: caller must be LzApp");
        _nonblockingLzReceive(srcChainId, srcAddress, nonce, payload);
    }

    /**
     * @dev Internal function that should be overridden in derived contracts to implement the logic
     * for processing incoming LayerZero messages in a non-blocking manner.
     *
     * @param srcChainId The ID of the source chain where the message originated.
     * @param srcAddress The address on the source chain where the message originated.
     * @param nonce The nonce of the message.
     * @param payload The payload of the message.
     */
    function _nonblockingLzReceive(uint16 srcChainId, bytes memory srcAddress, uint64 nonce, bytes memory payload)
        internal
        virtual;

    /**
     * @dev Allows for the manual retry of a previously failed message.
     *
     * Requirements:
     * - There must be a stored failed message matching the provided parameters.
     * - The payload hash must match the stored failed message.
     *
     * @param srcChainId The ID of the source chain where the failed message originated.
     * @param srcAddress The address on the source chain where the failed message originated.
     * @param nonce The nonce of the failed message.
     * @param payload The payload of the failed message.
     */
    function retryMessage(uint16 srcChainId, bytes calldata srcAddress, uint64 nonce, bytes calldata payload)
        public
        payable
        virtual
    {
        NonblockingLzAppStorage storage $ = _getNonblockingLzAppStorage();
        mapping(uint64 => bytes32) storage _failedMessages = $.failedMessages[srcChainId][srcAddress];

        // get the payload hash value
        bytes32 payloadHash = _failedMessages[nonce];

        // assert there is message to retry
        require(payloadHash != bytes32(0), "NonblockingLzApp: no stored message");
        require(keccak256(payload) == payloadHash, "NonblockingLzApp: invalid payload");

        // clear the stored message
        payloadHash = bytes32(0);

        // execute the message. revert if it fails again
        _nonblockingLzReceive(srcChainId, srcAddress, nonce, payload);
        emit RetryMessageSuccess(srcChainId, srcAddress, nonce, payloadHash);
    }
}
