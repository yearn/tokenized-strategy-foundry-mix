// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {IStrategy} from "octant-v2-core/src/interfaces/IStrategy.sol";

interface IStrategyInterface is IStrategy {
    function setUp(bytes calldata initializeParams) external;
}
