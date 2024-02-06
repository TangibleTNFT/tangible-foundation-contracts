// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

import {BytesLib} from "@layerzerolabs/contracts/libraries/BytesLib.sol";
import {OFTUpgradeable} from "@layerzerolabs/contracts-upgradeable/token/oft/v1/OFTUpgradeable.sol";
import {IOFTSubscriber} from "@layerzerolabs/contracts-upgradeable/token/oft/interfaces/IOFTSubscriber.sol";

import {RebaseTokenMath} from "../libraries/RebaseTokenMath.sol";
import {CrossChainRebaseTokenUpgradeable} from "./CrossChainRebaseTokenUpgradeable.sol";
import {RebaseTokenUpgradeable} from "./RebaseTokenUpgradeable.sol";

/**
 * @title LayerZeroRebaseTokenUpgradeable
 * @author Caesar LaVey
 * @notice This contract extends the functionality of `CrossChainRebaseTokenUpgradeable` and implements
 * `OFTUpgradeable`. It is designed to support cross-chain rebase token transfers and operations in a LayerZero network.
 *
 * @dev The contract introduces a new struct, `Message`, to encapsulate the information required for cross-chain
 * transfers. This includes shares, the rebase index, and the rebase nonce.
 *
 * The contract overrides various functions like `totalSupply`, `balanceOf`, and `_update` to utilize the base
 * functionalities from `RebaseTokenUpgradeable`.
 *
 * It also implements specific functions like `_debitFrom` and `_creditTo` to handle LayerZero specific operations.
 */
abstract contract LayerZeroRebaseTokenUpgradeable is CrossChainRebaseTokenUpgradeable, OFTUpgradeable {
    using BytesLib for bytes;
    using RebaseTokenMath for uint256;

    struct Message {
        uint256 shares;
        uint256 rebaseIndex;
        uint256 nonce;
    }

    error CannotBridgeWhenOptedOut(address account);

    /**
     * @param endpoint The endpoint for Layer Zero operations.
     * @custom:oz-upgrades-unsafe-allow constructor
     */
    constructor(address endpoint) OFTUpgradeable(endpoint) {}

    /**
     * @notice Initializes the LayerZeroRebaseTokenUpgradeable contract.
     * @dev This function is intended to be called once during the contract's deployment. It chains initialization logic
     * from `__LayerZeroRebaseToken_init_unchained`, `__CrossChainRebaseToken_init_unchained`, and `__OFT_init`.
     *
     * @param initialOwner The initial owner of the token contract.
     * @param name The name of the token.
     * @param symbol The symbol of the token.
     */
    function __LayerZeroRebaseToken_init(address initialOwner, string memory name, string memory symbol)
        internal
        onlyInitializing
    {
        __LayerZeroRebaseToken_init_unchained();
        __CrossChainRebaseToken_init_unchained();
        __OFT_init(initialOwner, name, symbol);
    }

    function __LayerZeroRebaseToken_init_unchained() internal onlyInitializing {}

    function balanceOf(address account)
        public
        view
        override(IERC20, ERC20Upgradeable, RebaseTokenUpgradeable)
        returns (uint256)
    {
        return RebaseTokenUpgradeable.balanceOf(account);
    }

    function totalSupply() public view override(IERC20, ERC20Upgradeable, RebaseTokenUpgradeable) returns (uint256) {
        return RebaseTokenUpgradeable.totalSupply();
    }

    function _update(address from, address to, uint256 amount)
        internal
        virtual
        override(ERC20Upgradeable, RebaseTokenUpgradeable)
    {
        RebaseTokenUpgradeable._update(from, to, amount);
    }

    /**
     * @notice Debits a specified amount of tokens from an account.
     * @dev This function performs a series of checks and operations to debit tokens from an account. If the account
     * has not opted out of rebasing, it calculates the share equivalent of the specified amount and updates the
     * internal state accordingly. If the operation occurs on the main chain, the tokens are moved to the contract's
     * address. Otherwise, the tokens are burned.
     *
     * @param from The address from which the tokens will be debited.
     * @param amount The amount to debit from the account.
     * @return shares The share equivalent of the debited amount.
     */
    function _debitFrom(address from, uint16, bytes memory, uint256 amount)
        internal
        override
        returns (uint256 shares)
    {
        shares = _transferableShares(amount, from);
        if (from != msg.sender) {
            _spendAllowance(from, msg.sender, amount);
        }
        if (isMainChain) {
            _update(from, address(this), amount);
        } else {
            _update(from, address(0), amount);
        }
    }

    /**
     * @notice Credits a specified number of tokens to an account.
     *
     * @param to The address to which the shares will be credited.
     * @param shares The number of shares to credit to the account.
     * @return amount The token equivalent of the credited shares.
     */
    function _creditTo(uint16, address to, uint256 shares) internal override returns (uint256 amount) {
        amount = shares.toTokens(rebaseIndex());
        if (isMainChain) {
            _update(address(this), to, amount);
        } else {
            _update(address(0), to, amount);
        }
        return amount;
    }

    /**
     * @notice Initiates the sending of tokens to another chain.
     * @dev This function prepares a message containing the shares, rebase index, and nonce. It then uses LayerZero's
     * send functionality to send the tokens to the destination chain. The function checks adapter parameters and emits
     * a `SendToChain` event upon successful execution.
     *
     * @param from The address from which tokens are sent.
     * @param dstChainId The destination chain ID.
     * @param toAddress The address on the destination chain to which tokens will be sent.
     * @param amount The amount of tokens to send.
     * @param refundAddress The address for any refunds.
     * @param zroPaymentAddress The address for ZRO payment.
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
    ) internal override {
        if (optedOut(from)) {
            // tokens cannot be bridged if the account has opted out of rebasing
            revert CannotBridgeWhenOptedOut(from);
        }

        _checkAdapterParams(dstChainId, PT_SEND, adapterParams, NO_EXTRA_GAS);

        Message memory message = Message({
            shares: _debitFrom(from, dstChainId, toAddress, amount),
            rebaseIndex: rebaseIndex(),
            nonce: _rebaseNonce()
        });

        emit SendToChain(dstChainId, from, toAddress, message.shares.toTokens(message.rebaseIndex));

        bytes memory lzPayload = abi.encode(PT_SEND, msg.sender, from, toAddress, message);
        _lzSend(dstChainId, lzPayload, refundAddress, zroPaymentAddress, adapterParams, msg.value);
    }

    /**
     * @notice Acknowledges the receipt of tokens from another chain and credits the correct amount to the recipient's
     * address.
     * @dev Upon receiving a payload, this function decodes it to extract the destination address and the message
     * content, which includes shares, rebase index, and nonce. If the current chain is not the main chain, it updates
     * the rebase index and nonce accordingly. Then, it credits the token shares to the recipient's address and emits a
     * `ReceiveFromChain` event.
     *
     * The function assumes that `_setRebaseIndex` handles the correctness of the rebase index and nonce update.
     *
     * @param srcChainId The source chain ID from which tokens are received.
     * @param srcAddressBytes The address on the source chain from which the message originated.
     * @param payload The payload containing the encoded destination address and message with shares, rebase index, and
     * nonce.
     */
    function _sendAck(uint16 srcChainId, bytes memory srcAddressBytes, uint64, bytes memory payload)
        internal
        override
    {
        (, address initiator, address from, bytes memory toAddressBytes, Message memory message) =
            abi.decode(payload, (uint16, address, address, bytes, Message));

        if (!isMainChain) {
            _setRebaseIndex(message.rebaseIndex, message.nonce);
        }

        address src = srcAddressBytes.toAddress(0);
        address to = toAddressBytes.toAddress(0);
        uint256 amount;

        amount = _creditTo(srcChainId, to, message.shares);

        _tryNotifyReceiver(srcChainId, initiator, from, src, to, amount);

        emit ReceiveFromChain(srcChainId, to, amount);
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
