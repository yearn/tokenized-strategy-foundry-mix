// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

interface IGDaiOpenPnlFeed {
  function nextEpochValuesRequestCount() external view returns (uint256);
}
