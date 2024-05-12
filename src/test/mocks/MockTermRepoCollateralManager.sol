// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

import {ITermRepoCollateralManager} from "../../interfaces/term/ITermRepoCollateralManager.sol";
import {ITermRepoToken} from "../../interfaces/term/ITermRepoToken.sol";

contract MockTermRepoCollateralManager is ITermRepoCollateralManager {
    ITermRepoToken internal repoToken;
    mapping(address => uint256) public maintenanceCollateralRatios;
    address[] internal collateralTokenList;

    constructor(ITermRepoToken _repoToken, address _collateral, uint256 _maintenanceRatio) {
        repoToken = _repoToken;
        addCollateralToken(_collateral, _maintenanceRatio);
    }    

    function addCollateralToken(address _collateral, uint256 _maintenanceRatio) public {
        collateralTokenList.push(_collateral);
        maintenanceCollateralRatios[_collateral] = _maintenanceRatio;
    }

    function numOfAcceptedCollateralTokens() external view returns (uint8) {
        return uint8(collateralTokenList.length);
    }

    function collateralTokens(uint256 index) external view returns (address) {
        return collateralTokenList[index];
    }
}
