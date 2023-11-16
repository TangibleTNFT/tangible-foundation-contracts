// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC165, ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";

import {IOFTCore} from "@layerzerolabs/contracts/token/oft/v1/interfaces/IOFTCore.sol";
import {BytesLib} from "@layerzerolabs/contracts/libraries/BytesLib.sol";

import {NonblockingLzAppUpgradeable} from "../../../lzApp/NonblockingLzAppUpgradeable.sol";

/**
 * @title OFTCoreUpgradeable
 * @dev This contract extends NonblockingLzAppUpgradeable to provide a core implementation for OFT (On-Chain Forwarding
 * Token). It introduces packet types, custom adapter params, and methods for sending and receiving tokens across
 * chains.
 *
 * This contract is intended to be inherited by other contracts that implement specific token logic.
 *
 * Packet Types:
 * - PT_SEND: Packet type for sending tokens. Value is 0.
 *
 * Custom Adapter Params:
 * - The contract allows for the use of custom adapter parameters which affect the gas usage for cross-chain operations.
 *
 * Storage:
 * - useCustomAdapterParams: A flag to indicate whether to use custom adapter parameters.
 */
abstract contract OFTCoreUpgradeable is NonblockingLzAppUpgradeable, ERC165, IOFTCore {
    using BytesLib for bytes;

    uint256 public constant NO_EXTRA_GAS = 0;

    // packet type
    uint16 public constant PT_SEND = 0;

    /// @custom:storage-location erc7201:layerzero.storage.OFTCore
    struct OFTCoreStorage {
        bool useCustomAdapterParams;
    }

    // keccak256(abi.encode(uint256(keccak256("layerzero.storage.OFTCore")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant OFTCoreStorageLocation = 0x822492242235517548c4a8cf040400e3c0daf5b82af652ed16dce4fa3ae72800;

    function _getOFTCoreStorage() private pure returns (OFTCoreStorage storage $) {
        // slither-disable-next-line assembly
        assembly {
            $.slot := OFTCoreStorageLocation
        }
    }

    /**
     * @param endpoint The address of the LayerZero endpoint.
     * @custom:oz-upgrades-unsafe-allow constructor
     */
    constructor(address endpoint) NonblockingLzAppUpgradeable(endpoint) {}

    /**
     * @dev Initializes the contract state for `OFTCoreUpgradeable`.
     * Calls the initialization functions of parent contracts.
     *
     * @param initialOwner The address of the initial owner.
     */
    function __OFTCore_init(address initialOwner) internal onlyInitializing {
        __OFTCore_init_unchained();
        __NonblockingLzApp_init(initialOwner);
    }

    function __OFTCore_init_unchained() internal onlyInitializing {}

    /**
     * @dev Checks if the contract supports a given interface ID.
     * Overrides the implementation in ERC165 to include support for IOFTCore.
     *
     * @param interfaceId The ID of the interface to check.
     * @return bool `true` if the contract supports the given interface ID, `false` otherwise.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC165, IERC165) returns (bool) {
        return interfaceId == type(IOFTCore).interfaceId || super.supportsInterface(interfaceId);
    }

    /**
     * @dev Estimates the fee required for sending tokens to a different chain.
     * This function is part of the IOFTCore interface.
     *
     * @param dstChainId The ID of the destination chain.
     * @param toAddress The address to which the tokens will be sent on the destination chain.
     * @param amount The amount of tokens to send.
     * @param useZro Flag indicating whether to use ZRO for payment.
     * @param adapterParams Additional parameters for the adapter.
     * @return nativeFee The estimated native chain fee.
     * @return zroFee The estimated ZRO fee.
     */
    function estimateSendFee(
        uint16 dstChainId,
        bytes calldata toAddress,
        uint256 amount,
        bool useZro,
        bytes calldata adapterParams
    ) public view virtual override returns (uint256 nativeFee, uint256 zroFee) {
        // mock the payload for sendFrom()
        bytes memory payload = abi.encode(PT_SEND, toAddress, amount);
        return lzEndpoint.estimateFees(dstChainId, address(this), payload, useZro, adapterParams);
    }

    /**
     * @dev Sends tokens from a given address to a destination address on another chain.
     * This function is part of the IOFTCore interface.
     *
     * @param from The address from which tokens will be sent.
     * @param dstChainId The ID of the destination chain.
     * @param toAddress The address on the destination chain to which tokens will be sent.
     * @param amount The amount of tokens to send.
     * @param refundAddress The address where any excess native fee will be refunded.
     * @param zroPaymentAddress The address used for ZRO payments, if applicable.
     * @param adapterParams Additional parameters for the adapter.
     */
    function sendFrom(
        address from,
        uint16 dstChainId,
        bytes calldata toAddress,
        uint256 amount,
        address payable refundAddress,
        address zroPaymentAddress,
        bytes calldata adapterParams
    ) public payable virtual override {
        _send(from, dstChainId, toAddress, amount, refundAddress, zroPaymentAddress, adapterParams);
    }

    /**
     * @dev Toggles the use of custom adapter parameters.
     * When enabled, the contract will check gas limits based on the provided adapter parameters.
     *
     * @param useCustomAdapterParams Flag indicating whether to use custom adapter parameters.
     */
    function setUseCustomAdapterParams(bool useCustomAdapterParams) public virtual onlyOwner {
        OFTCoreStorage storage $ = _getOFTCoreStorage();
        $.useCustomAdapterParams = useCustomAdapterParams;
        emit SetUseCustomAdapterParams(useCustomAdapterParams);
    }

    /**
     * @dev Handles incoming messages from other chains in a non-blocking fashion.
     * This function overrides the abstract implementation in NonblockingLzAppUpgradeable.
     *
     * @param srcChainId The ID of the source chain.
     * @param srcAddress The address on the source chain from which the message originated.
     * @param nonce A unique identifier for the message.
     * @param payload The actual data sent from the source chain.
     */
    function _nonblockingLzReceive(uint16 srcChainId, bytes memory srcAddress, uint64 nonce, bytes memory payload)
        internal
        virtual
        override
    {
        uint16 packetType;

        // slither-disable-next-line assembly
        assembly {
            packetType := mload(add(payload, 32))
        }

        if (packetType == PT_SEND) {
            _sendAck(srcChainId, srcAddress, nonce, payload);
        } else {
            revert("OFTCore: unknown packet type");
        }
    }

    /**
     * @dev Performs the actual sending of tokens to a destination chain.
     * This internal function is called by the public wrapper `sendFrom`.
     *
     * @param from The address from which tokens are sent.
     * @param dstChainId The ID of the destination chain.
     * @param toAddress The address on the destination chain where tokens will be sent.
     * @param amount The amount of tokens to send.
     * @param refundAddress The address for refunding any excess native fee.
     * @param zroPaymentAddress The address for ZRO payment, if applicable.
     * @param adapterParams Additional parameters for the adapter.
     */
    function _send(
        address from,
        uint16 dstChainId,
        bytes memory toAddress,
        uint256 amount,
        address payable refundAddress,
        address zroPaymentAddress,
        bytes memory adapterParams
    ) internal virtual {
        _checkAdapterParams(dstChainId, PT_SEND, adapterParams, NO_EXTRA_GAS);

        amount = _debitFrom(from, dstChainId, toAddress, amount);

        bytes memory lzPayload = abi.encode(PT_SEND, toAddress, amount);
        _lzSend(dstChainId, lzPayload, refundAddress, zroPaymentAddress, adapterParams, msg.value);

        emit SendToChain(dstChainId, from, toAddress, amount);
    }

    /**
     * @dev Acknowledges the reception of tokens sent from another chain.
     * This function is called internally when a PT_SEND packet type is received.
     *
     * @param srcChainId The ID of the source chain from which the tokens were sent.
     * @param payload The payload containing the details of the sent tokens.
     */
    function _sendAck(uint16 srcChainId, bytes memory, uint64, bytes memory payload) internal virtual {
        (, bytes memory toAddressBytes, uint256 amount) = abi.decode(payload, (uint16, bytes, uint256));

        address to = toAddressBytes.toAddress(0);

        amount = _creditTo(srcChainId, to, amount);
        emit ReceiveFromChain(srcChainId, to, amount);
    }

    /**
     * @dev Validates the adapter parameters for sending tokens.
     * This function can be configured to either enforce a gas limit or to accept custom parameters.
     *
     * @param dstChainId The ID of the destination chain.
     * @param pkType The packet type of the message.
     * @param adapterParams The additional parameters for the adapter.
     * @param extraGas The extra gas that may be needed for execution.
     */
    function _checkAdapterParams(uint16 dstChainId, uint16 pkType, bytes memory adapterParams, uint256 extraGas)
        internal
        virtual
    {
        OFTCoreStorage storage $ = _getOFTCoreStorage();
        if ($.useCustomAdapterParams) {
            _checkGasLimit(dstChainId, pkType, adapterParams, extraGas);
        } else {
            require(adapterParams.length == 0, "OFTCore: _adapterParams must be empty.");
        }
    }

    /**
     * @dev Debits an amount of tokens from the specified address.
     * This is an internal function that should be overridden to handle the actual token transfer logic.
     *
     * @param from The address from which tokens will be debited.
     * @param dstChainId The ID of the destination chain.
     * @param toAddress The encoded destination address on the target chain.
     * @param amount The amount of tokens to debit.
     * @return The final amount of tokens that were debited. This allows for potential adjustments.
     */
    function _debitFrom(address from, uint16 dstChainId, bytes memory toAddress, uint256 amount)
        internal
        virtual
        returns (uint256);

    /**
     * @dev Credits an amount of tokens to a specific address.
     * This is an internal function that should be overridden to handle the actual token crediting logic.
     *
     * @param srcChainId The ID of the source chain from which the tokens were sent.
     * @param toAddress The address to which tokens will be credited.
     * @param amount The amount of tokens to credit.
     * @return The final amount of tokens that were credited. This allows for potential adjustments.
     */
    function _creditTo(uint16 srcChainId, address toAddress, uint256 amount) internal virtual returns (uint256);
}
