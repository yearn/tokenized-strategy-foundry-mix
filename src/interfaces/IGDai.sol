// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

interface IGDai is IERC4626 {
  function withdrawEpochsTimelock() external view returns (uint256);
  function makeWithdrawRequest(uint256 shares, address owner) external;
  function cancelWithdrawRequest(uint256 shares, address owner, uint256 unlockEpoch) external;
  function withdrawRequests(address owner, uint256 unlockEpoch) external view returns (uint256);
  function currentEpoch() external view returns (uint256);
  function currentEpochStart() external view returns (uint256);
  function convertToAssets(uint256 shares) external view returns (uint256);
  function distributeReward(uint assets) external;
  function collateralizationP() external view returns (uint);
  function currentEpochPositiveOpenPnl() external view returns (uint);
  function availableAssets() external view returns (uint);
  function updateAccPnlPerTokenUsed(uint prevPositiveOpenPnl, uint newPositiveOpenPnl) external returns (uint);
}
