// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

interface IGDai is IERC4626 {
  function makeWithdrawReqeust(uint256 shares, address owner) external;
  function cancelWithdrawRequest(uint256 shares, address owner, uint256 unlockEpoch) external;
  function withdrawRequests(address owner, uint256 unlockEpoch) external view returns (uint256);
}
