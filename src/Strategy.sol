// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

import {BaseStrategy, ERC20} from "@tokenized-strategy/BaseStrategy.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ICurveLendVault} from "./interfaces/Curve/IVault.sol";

contract CurveLender is BaseStrategy {
    using SafeERC20 for ERC20;
    ICurveLendVault public immutable curveLendVault;

    constructor(
        address _asset,
        string memory _name,
        address _curveLendVault
    ) BaseStrategy(_asset, _name) {
        curveLendVault = ICurveLendVault(_curveLendVault);
        require(curveLendVault.asset() == _asset, "wrong asset");
        asset.safeApprove(address(curveLendVault), type(uint256).max);
    }

    function _deployFunds(uint256 _amount) internal override {
        curveLendVault.deposit(_amount);
    }

    function _freeFunds(uint256 _amount) internal override {
        curveLendVault.withdraw(_amount);
    }

    function _harvestAndReport()
        internal
        override
        returns (uint256 _totalAssets)
    {
        _totalAssets = asset.balanceOf(address(this));
    }

    function availableWithdrawLimit(
        address _owner
    ) public view override returns (uint256) {
            return curveLendVault.maxWithdraw(address(this));
    }

}
