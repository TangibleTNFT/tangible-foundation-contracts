// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import {ILayerZeroReceiver} from "@layerzerolabs/contracts/lzApp/interfaces/ILayerZeroReceiver.sol";
import {ILayerZeroUserApplicationConfig} from
    "@layerzerolabs/contracts/lzApp/interfaces/ILayerZeroUserApplicationConfig.sol";
import {ILayerZeroEndpoint} from "@layerzerolabs/contracts/lzApp/interfaces/ILayerZeroEndpoint.sol";
import {BytesLib} from "@layerzerolabs/contracts/libraries/BytesLib.sol";

/**
 * @title LzAppUpgradeable
 * @dev This is a generic implementation of LzReceiver, designed for LayerZero cross-chain communication.
 *
 * The contract inherits from `OwnableUpgradeable` and implements `ILayerZeroReceiver` and
 * `ILayerZeroUserApplicationConfig` interfaces. It provides functionality for setting and managing trusted remote
 * chains and their corresponding paths, configuring minimum destination gas, payload size limitations, and more.
 *
 * The contract uses a custom storage location `LzAppStorage`, which includes various mappings and state variables such
 * as `trustedRemoteLookup`, `minDstGasLookup`, and `payloadSizeLimitLookup`.
 *
 * Events:
 * - `SetPrecrime(address)`: Emitted when the precrime address is set.
 * - `SetTrustedRemote(uint16, bytes)`: Emitted when a trusted remote chain is set with its path.
 * - `SetTrustedRemoteAddress(uint16, bytes)`: Emitted when a trusted remote chain is set with its address.
 * - `SetMinDstGas(uint16, uint16, uint256)`: Emitted when minimum destination gas is set for a chain and packet type.
 *
 * Initialization:
 * The contract should be initialized by calling `__LzApp_init` function.
 *
 * Permissions:
 * Most administrative tasks require the sender to be the contract's owner.
 *
 * Note:
 * The contract includes the Checks-Effects-Interactions pattern and optimizes for gas-efficiency wherever applicable.
 */
abstract contract LzAppUpgradeable is OwnableUpgradeable, ILayerZeroReceiver, ILayerZeroUserApplicationConfig {
    using BytesLib for bytes;

    // ua can not send payload larger than this by default, but it can be changed by the ua owner
    uint256 public constant DEFAULT_PAYLOAD_SIZE_LIMIT = 10_000;

    event SetPrecrime(address precrime);
    event SetTrustedRemote(uint16 _remoteChainId, bytes _path);
    event SetTrustedRemoteAddress(uint16 _remoteChainId, bytes _remoteAddress);
    event SetMinDstGas(uint16 _dstChainId, uint16 _type, uint256 _minDstGas);

    /// @custom:storage-location erc7201:layerzero.storage.LzApp
    struct LzAppStorage {
        mapping(uint16 => bytes) trustedRemoteLookup;
        mapping(uint16 => mapping(uint16 => uint256)) minDstGasLookup;
        mapping(uint16 => uint256) payloadSizeLimitLookup;
        address precrime;
    }

    // keccak256(abi.encode(uint256(keccak256("layerzero.storage.LzApp")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant LzAppStorageLocation = 0x111388274dd962a0529050efb131321f60015c2ab1a99387d94540f430037b00;

    function _getLzAppStorage() private pure returns (LzAppStorage storage $) {
        // slither-disable-next-line assembly
        assembly {
            $.slot := LzAppStorageLocation
        }
    }

    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    ILayerZeroEndpoint public immutable lzEndpoint;

    /**
     * @param endpoint Address of the LayerZero endpoint contract.
     * @custom:oz-upgrades-unsafe-allow constructor
     */
    constructor(address endpoint) {
        lzEndpoint = ILayerZeroEndpoint(endpoint);
    }

    /**
     * @dev Initializes the contract with the given `initialOwner`.
     *
     * Requirements:
     * - The function should only be called during the initialization process.
     *
     * @param initialOwner Address of the initial owner of the contract.
     */
    function __LzApp_init(address initialOwner) internal onlyInitializing {
        __LzApp_init_unchained();
        __Ownable_init(initialOwner);
    }

    function __LzApp_init_unchained() internal onlyInitializing {}

    /**
     * @dev Returns the trusted path for a given remote chain ID.
     *
     * @param remoteChainId The ID of the remote chain to query for a trusted path.
     * @return path Bytes representation of the trusted path for the specified remote chain ID.
     */
    function trustedRemoteLookup(uint16 remoteChainId) external view returns (bytes memory path) {
        LzAppStorage storage $ = _getLzAppStorage();
        path = $.trustedRemoteLookup[remoteChainId];
    }

    /**
     * @dev Returns the minimum gas required for a given destination chain ID and packet type.
     *
     * @param dstChainId The ID of the destination chain to query for a minimum gas limit.
     * @param packetType The type of packet for which the minimum gas limit is to be fetched.
     * @return minGas The minimum gas limit required for the specified destination chain ID and packet type.
     */
    function minDstGasLookup(uint16 dstChainId, uint16 packetType) external view returns (uint256 minGas) {
        LzAppStorage storage $ = _getLzAppStorage();
        minGas = $.minDstGasLookup[dstChainId][packetType];
    }

    /**
     * @dev Returns the payload size limit for a given destination chain ID.
     *
     * @param dstChainId The ID of the destination chain to query for a payload size limit.
     * @return size The maximum allowable payload size in bytes for the specified destination chain ID.
     */
    function payloadSizeLimitLookup(uint16 dstChainId) external view returns (uint256 size) {
        LzAppStorage storage $ = _getLzAppStorage();
        size = $.payloadSizeLimitLookup[dstChainId];
    }

    /**
     * @dev Returns the address of the precrime contract.
     *
     * @return _precrime The address of the precrime contract.
     */
    function precrime() external view returns (address _precrime) {
        LzAppStorage storage $ = _getLzAppStorage();
        _precrime = $.precrime;
    }

    /**
     * @dev Handles incoming LayerZero messages from a source chain.
     * This function must be called by the LayerZero endpoint and validates the source of the message.
     *
     * Requirements:
     * - Caller must be the LayerZero endpoint.
     * - Source address must be a trusted remote address.
     *
     * @param srcChainId The ID of the source chain from which the message is sent.
     * @param srcAddress The address on the source chain that is sending the message.
     * @param nonce A unique identifier for the message.
     * @param payload The actual data payload of the message.
     */
    function lzReceive(uint16 srcChainId, bytes calldata srcAddress, uint64 nonce, bytes calldata payload)
        public
        virtual
        override
    {
        LzAppStorage storage $ = _getLzAppStorage();

        // lzReceive must be called by the endpoint for security
        require(_msgSender() == address(lzEndpoint), "LzApp: invalid endpoint caller");

        bytes memory trustedRemote = $.trustedRemoteLookup[srcChainId];
        // if will still block the message pathway from (srcChainId, srcAddress). should not receive message from
        // untrusted remote.
        require(
            srcAddress.length == trustedRemote.length && trustedRemote.length != 0
                && keccak256(srcAddress) == keccak256(trustedRemote),
            "LzApp: invalid source sending contract"
        );

        _blockingLzReceive(srcChainId, srcAddress, nonce, payload);
    }

    /**
     * @dev Internal function that handles incoming LayerZero messages in a blocking manner.
     * This is an abstract function and should be implemented by derived contracts.
     *
     * @param srcChainId The ID of the source chain from which the message is sent.
     * @param srcAddress The address on the source chain that is sending the message.
     * @param nonce A unique identifier for the message.
     * @param payload The actual data payload of the message.
     */
    function _blockingLzReceive(uint16 srcChainId, bytes memory srcAddress, uint64 nonce, bytes memory payload)
        internal
        virtual;

    /**
     * @dev Internal function to send a LayerZero message to a destination chain.
     * It performs a series of validations before sending the message.
     *
     * Requirements:
     * - Destination chain must be a trusted remote.
     * - Payload size must be within the configured limit.
     *
     * @param dstChainId The ID of the destination chain.
     * @param payload The actual data payload to be sent.
     * @param refundAddress The address to which any refunds should be sent.
     * @param zroPaymentAddress The address for the ZRO token payment.
     * @param adapterParams Additional parameters required for the adapter.
     * @param nativeFee The native fee to be sent along with the message.
     */
    function _lzSend(
        uint16 dstChainId,
        bytes memory payload,
        address payable refundAddress,
        address zroPaymentAddress,
        bytes memory adapterParams,
        uint256 nativeFee
    ) internal virtual {
        LzAppStorage storage $ = _getLzAppStorage();
        bytes memory trustedRemote = $.trustedRemoteLookup[dstChainId];
        require(trustedRemote.length != 0, "LzApp: destination chain is not a trusted source");
        _checkPayloadSize(dstChainId, payload.length);
        lzEndpoint.send{value: nativeFee}(
            dstChainId, trustedRemote, payload, refundAddress, zroPaymentAddress, adapterParams
        );
    }

    /**
     * @dev Internal function to validate if the provided gas limit meets the minimum requirement for a given packet
     * type and destination chain.
     *
     * Requirements:
     * - The minimum destination gas limit must be set for the given packet type and destination chain.
     * - Provided gas limit should be greater than or equal to the sum of the minimum gas limit and any extra gas.
     *
     * @param dstChainId The ID of the destination chain.
     * @param packetType The type of the packet being sent.
     * @param adapterParams Additional parameters required for the adapter.
     * @param extraGas Extra gas to be added to the minimum required gas.
     */
    function _checkGasLimit(uint16 dstChainId, uint16 packetType, bytes memory adapterParams, uint256 extraGas)
        internal
        view
        virtual
    {
        LzAppStorage storage $ = _getLzAppStorage();
        uint256 providedGasLimit = _getGasLimit(adapterParams);
        uint256 minGasLimit = $.minDstGasLookup[dstChainId][packetType];
        require(minGasLimit != 0, "LzApp: minGasLimit not set");
        require(providedGasLimit >= minGasLimit + extraGas, "LzApp: gas limit is too low");
    }

    /**
     * @dev Internal function to extract the gas limit from the adapter parameters.
     *
     * Requirements:
     * - The `adapterParams` must be at least 34 bytes long to contain the gas limit.
     *
     * @param _adapterParams The adapter parameters from which the gas limit is to be extracted.
     * @return gasLimit The extracted gas limit.
     */
    function _getGasLimit(bytes memory _adapterParams) internal pure virtual returns (uint256 gasLimit) {
        require(_adapterParams.length >= 34, "LzApp: invalid adapterParams");
        // slither-disable-next-line assembly
        assembly {
            gasLimit := mload(add(_adapterParams, 34))
        }
    }

    /**
     * @dev Internal function to validate the size of the payload against the configured limit for a given destination
     * chain.
     *
     * Requirements:
     * - Payload size must be less than or equal to the configured size limit for the given destination chain.
     *
     * @param _dstChainId The ID of the destination chain.
     * @param _payloadSize The size of the payload in bytes.
     */
    function _checkPayloadSize(uint16 _dstChainId, uint256 _payloadSize) internal view virtual {
        LzAppStorage storage $ = _getLzAppStorage();
        uint256 payloadSizeLimit = $.payloadSizeLimitLookup[_dstChainId];
        if (payloadSizeLimit == 0) {
            // use default if not set
            payloadSizeLimit = DEFAULT_PAYLOAD_SIZE_LIMIT;
        }
        require(_payloadSize <= payloadSizeLimit, "LzApp: payload size is too large");
    }

    /**
     * @dev Retrieves the configuration of the LayerZero user application for a given version, chain ID, and config
     * type.
     *
     * @param version The version for which the configuration is to be fetched.
     * @param chainId The ID of the chain for which the configuration is needed.
     * @param configType The type of the configuration to be retrieved.
     * @return The bytes representation of the configuration.
     */
    function getConfig(uint16 version, uint16 chainId, address, uint256 configType)
        external
        view
        returns (bytes memory)
    {
        return lzEndpoint.getConfig(version, chainId, address(this), configType);
    }

    /**
     * @dev Sets the configuration of the LayerZero user application for a given version, chain ID, and config type.
     *
     * Requirements:
     * - Only the owner can set the configuration.
     *
     * @param version The version for which the configuration is to be set.
     * @param chainId The ID of the chain for which the configuration is being set.
     * @param configType The type of the configuration to be set.
     * @param config The actual configuration data in bytes format.
     */
    function setConfig(uint16 version, uint16 chainId, uint256 configType, bytes calldata config)
        external
        override
        onlyOwner
    {
        lzEndpoint.setConfig(version, chainId, configType, config);
    }

    /**
     * @dev Sets the version to be used for sending LayerZero messages.
     *
     * Requirements:
     * - Only the owner can set the send version.
     *
     * @param version The version to be set for sending messages.
     */
    function setSendVersion(uint16 version) external override onlyOwner {
        lzEndpoint.setSendVersion(version);
    }

    /**
     * @dev Sets the version to be used for receiving LayerZero messages.
     *
     * Requirements:
     * - Only the owner can set the receive version.
     *
     * @param version The version to be set for receiving messages.
     */
    function setReceiveVersion(uint16 version) external override onlyOwner {
        lzEndpoint.setReceiveVersion(version);
    }

    /**
     * @dev Resumes the reception of LayerZero messages from a specific source chain and address.
     *
     * Requirements:
     * - Only the owner can force the resumption of message reception.
     *
     * @param srcChainId The ID of the source chain from which message reception is to be resumed.
     * @param srcAddress The address on the source chain for which message reception is to be resumed.
     */
    function forceResumeReceive(uint16 srcChainId, bytes calldata srcAddress) external override onlyOwner {
        lzEndpoint.forceResumeReceive(srcChainId, srcAddress);
    }

    /**
     * @dev Sets the trusted path for cross-chain communication with a specified remote chain.
     *
     * Requirements:
     * - Only the owner can set the trusted path.
     *
     * @param remoteChainId The ID of the remote chain for which the trusted path is being set.
     * @param path The trusted path encoded as bytes.
     */
    function setTrustedRemote(uint16 remoteChainId, bytes calldata path) external onlyOwner {
        LzAppStorage storage $ = _getLzAppStorage();
        $.trustedRemoteLookup[remoteChainId] = path;
        emit SetTrustedRemote(remoteChainId, path);
    }

    /**
     * @dev Sets the trusted remote address for cross-chain communication with a specified remote chain.
     * The function also automatically appends the contract's own address to the path.
     *
     * Requirements:
     * - Only the owner can set the trusted remote address.
     *
     * @param remoteChainId The ID of the remote chain for which the trusted address is being set.
     * @param remoteAddress The trusted remote address encoded as bytes.
     */
    function setTrustedRemoteAddress(uint16 remoteChainId, bytes calldata remoteAddress) external onlyOwner {
        LzAppStorage storage $ = _getLzAppStorage();
        $.trustedRemoteLookup[remoteChainId] = abi.encodePacked(remoteAddress, address(this));
        emit SetTrustedRemoteAddress(remoteChainId, remoteAddress);
    }

    /**
     * @dev Retrieves the trusted remote address for a given remote chain.
     *
     * Requirements:
     * - A trusted path record must exist for the specified remote chain.
     *
     * @param remoteChainId The ID of the remote chain for which the trusted address is needed.
     * @return The trusted remote address encoded as bytes.
     */
    function getTrustedRemoteAddress(uint16 remoteChainId) external view returns (bytes memory) {
        LzAppStorage storage $ = _getLzAppStorage();
        bytes memory path = $.trustedRemoteLookup[remoteChainId];
        require(path.length != 0, "LzApp: no trusted path record");
        return path.slice(0, path.length - 20); // the last 20 bytes should be address(this)
    }

    /**
     * @dev Sets the "Precrime" address, which could be an address for handling fraudulent activities or other specific
     * behaviors.
     *
     * Requirements:
     * - Only the owner can set the Precrime address.
     *
     * @param _precrime The address to be set as Precrime.
     */
    function setPrecrime(address _precrime) external onlyOwner {
        LzAppStorage storage $ = _getLzAppStorage();
        $.precrime = _precrime;
        emit SetPrecrime(_precrime);
    }

    /**
     * @dev Sets the minimum required gas for a specific packet type and destination chain.
     *
     * Requirements:
     * - Only the owner can set the minimum destination gas.
     *
     * @param dstChainId The ID of the destination chain for which the minimum gas is being set.
     * @param packetType The type of the packet for which the minimum gas is being set.
     * @param minGas The minimum required gas in units.
     */
    function setMinDstGas(uint16 dstChainId, uint16 packetType, uint256 minGas) external onlyOwner {
        LzAppStorage storage $ = _getLzAppStorage();
        $.minDstGasLookup[dstChainId][packetType] = minGas;
        emit SetMinDstGas(dstChainId, packetType, minGas);
    }

    /**
     * @dev Sets the payload size limit for a specific destination chain.
     *
     * Requirements:
     * - Only the owner can set the payload size limit.
     *
     * @param dstChainId The ID of the destination chain for which the payload size limit is being set.
     * @param size The size limit in bytes.
     */
    function setPayloadSizeLimit(uint16 dstChainId, uint256 size) external onlyOwner {
        LzAppStorage storage $ = _getLzAppStorage();
        $.payloadSizeLimitLookup[dstChainId] = size;
    }

    /**
     * @dev Checks whether a given source chain and address are trusted for receiving LayerZero messages.
     *
     * @param srcChainId The ID of the source chain to be checked.
     * @param srcAddress The address on the source chain to be verified.
     * @return A boolean indicating whether the source chain and address are trusted.
     */
    function isTrustedRemote(uint16 srcChainId, bytes calldata srcAddress) external view returns (bool) {
        LzAppStorage storage $ = _getLzAppStorage();
        bytes memory trustedSource = $.trustedRemoteLookup[srcChainId];
        return keccak256(trustedSource) == keccak256(srcAddress);
    }
}
