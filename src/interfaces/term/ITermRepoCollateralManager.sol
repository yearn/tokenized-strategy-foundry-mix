// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

interface ITermRepoCollateralManager {
    function maintenanceCollateralRatios(
        address
    ) external view returns (uint256);

    function numOfAcceptedCollateralTokens() external view returns (uint8);

    function collateralTokens(uint256 index) external view returns (address);
}
