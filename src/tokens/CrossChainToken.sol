// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

abstract contract CrossChainToken {
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    bool public immutable isMainChain;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(uint256 mainChainId) {
        isMainChain = mainChainId == block.chainid;
    }
}
