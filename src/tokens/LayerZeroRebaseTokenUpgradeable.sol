// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

import {BytesLib} from "@layerzerolabs/contracts/libraries/BytesLib.sol";
import {OFTUpgradeable} from "@layerzerolabs/contracts-upgradeable/token/oft/v1/OFTUpgradeable.sol";

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
     * @dev This function performs a series of checks and operations to debit tokens from an account. It calculates the
     * share equivalent of the specified amount and updates the internal state accordingly. If the operation occurs on
     * the main chain, the tokens are moved to the contract's address. Otherwise, the tokens are burned.
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
     * @notice Credits a specified number of shares to an account.
     * @dev This function converts the specified shares to their token equivalent using the current rebase index. It
     * then updates the internal state to reflect the credit operation. If the operation occurs on the main chain, the
     * tokens are moved from the contract's address to the target account. Otherwise, new tokens are minted to the
     * target account.
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
        _checkAdapterParams(dstChainId, PT_SEND, adapterParams, NO_EXTRA_GAS);

        Message memory message = Message({
            shares: _debitFrom(from, dstChainId, toAddress, amount),
            rebaseIndex: rebaseIndex(),
            nonce: _rebaseNonce()
        });

        emit SendToChain(dstChainId, from, toAddress, message.shares.toTokens(message.rebaseIndex));

        bytes memory lzPayload = abi.encode(PT_SEND, toAddress, message);
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
     * @param payload The payload containing the encoded destination address and message with shares, rebase index, and
     * nonce.
     */
    function _sendAck(uint16 srcChainId, bytes memory, uint64, bytes memory payload) internal override {
        (, bytes memory toAddressBytes, Message memory message) = abi.decode(payload, (uint16, bytes, Message));

        if (!isMainChain) {
            _setRebaseIndex(message.rebaseIndex, message.nonce);
        }

        address to = toAddressBytes.toAddress(0);
        uint256 amount = _creditTo(srcChainId, to, message.shares);

        emit ReceiveFromChain(srcChainId, to, amount);
    }
}
