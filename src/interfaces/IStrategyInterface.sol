// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

import {IStrategy} from "@tokenized-strategy/interfaces/IStrategy.sol";
import {IGDai} from "./IGDai.sol";

interface IStrategyInterface is IStrategy {
  function GDAI() external view returns (IGDai);
}
