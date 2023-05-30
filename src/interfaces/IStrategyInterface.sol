// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

import {IStrategy} from "@tokenized-strategy/interfaces/IStrategy.sol";

interface IStrategyInterface is IStrategy {
    //TODO: Add your specific implementation interface in here.
    function morpho() external view returns (address);

    function lens() external view returns (address);

    function aToken() external view returns (address);

    function underlyingBalance()
        external
        view
        returns (
            uint256 balanceInP2P,
            uint256 balanceOnPool,
            uint256 totalBalance
        );
}
