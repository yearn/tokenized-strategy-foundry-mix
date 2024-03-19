// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

import {BaseStrategy, ERC20} from "@tokenized-strategy/BaseStrategy.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
mport {UniswapV3Swapper} from "@periphery/swappers/UniswapV3Swapper.sol";

interface ICurveLendVault {
    function asset() external view returns (address);
    function deposit(uint256) external;
    function withdraw(uint256) external;
    function maxWithdraw(address) external view returns (uint256);
    }

interface ILiquidityGauge {
    function deposit(uint256) external;
    function withdraw(uint256) external;
    function claim_rewards() external;
}

contract CurveLender is BaseStrategy, UniswapV3Swapper {
    using SafeERC20 for ERC20;
    ICurveLendVault public immutable curveLendVault;
    ILiquidityGauge public immutable liquidityGauge;
    address[] public rewards;
    mapping(address => uint256) public minAmountToSellMapping;

    constructor(
        address _asset,
        string memory _name,
        address _curveLendVault,
        address _liquidityGauge,
    ) BaseStrategy(_asset, _name) {
        curveLendVault = ICurveLendVault(_curveLendVault);
        require(curveLendVault.asset() == _asset, "wrong asset");
        liquidityGauge = ILiquidityGauge(_liquidityGauge);
        asset.safeApprove(address(curveLendVault), type(uint256).max);
        curveLendVault.safeApprove(address(gauge), type(uint256).max);

        // Set uni swapper values
        minAmountToSell = 0; // We will use the minAmountToSell mapping instead.
        base = _base;
        router = 0xE592427A0AEce92De3Edee1F18E0157C05861564; //universal uniswapv3 router
        _setUniFees(PENDLE, base, _feePENDLEtoBase);
        _setUniFees(_base, _targetToken, _feeBaseToTargetToken);

    }

    function _deployFunds(uint256 _amount) internal override {
        curveLendVault.deposit(_amount); // deposit
        liquidityGauge.deposit(_amount); // stake to gauge
    }

    function _freeFunds(uint256 _amount) internal override {
        uint256 shares = curveLendVault.convertToShares(_amount);
        liquidityGauge.withdraw(shares); // unstake from gauge
        curveLendVault.withdraw(shares); // withdraw
    }

    // @todo: need to add gauge claim logic
    // liquidityGauge.claim_rewards()

    function _harvestAndReport()
        internal
        override
        returns (uint256 _totalAssets)
    {
        _claimAndSellRewards();
        _totalAssets = asset.balanceOf(address(this)); //@todo: fix
    }

    function availableWithdrawLimit(
        address _owner
    ) public view override returns (uint256) {
            return curveLendVault.maxWithdraw(address(this));
    }


    /**
     * @notice Add a reward address that will be sold to autocompound the LP.
     * @param _rewardToken address of the reward token to be sold.
     * @param _feeRewardTokenToBase fee tier between rewardToken and base (0.01% = 100, 0.05% = 500, 0.3% = 3000, 1% = 10000).
     */
    function addReward(address _rewardToken, uint24 _feeRewardTokenToBase) external onlyManagement {
        _setUniFees(_rewardToken, base, _feeRewardTokenToBase);
        require(_rewardToken != address(asset));
        rewards.push(_rewardToken);
    }

    /**
     * @notice Remove a reward by its index in the reward array to stop it being autocompounded to the LP.
     * @param _rewardIndex index inside the reward array for the reward to remove.
     */
    function removeRewardByIndex(uint256 _rewardIndex) external onlyManagement {
        rewards[_rewardIndex] = rewards[rewards.length - 1];
        rewards.pop();
    }

    /**
     * @notice Set the uni fees for swaps.
     * Any incentivized tokens will need a fee to be set for each
     * reward token that it wishes to swap on reports.
     *
     * @param _token0 The first token of the pair.
     * @param _token1 The second token of the pair.
     * @param _fee The fee to be used for the pair.
     */
    function setUniFees(
        address _token0,
        address _token1,
        uint24 _fee
    ) external onlyManagement {
        _setUniFees(_token0, _token1, _fee);
    }

    /**
     * @notice Set the `minAmountToSellMapping` for a specific `_token`.
     * @dev This can be used by management to adjust wether or not the
     * _claimAndSellRewards() function will attempt to sell a specific
     * reward token. This can be used if liquidity is to low, amounts
     * are to low or any other reason that may cause reverts.
     *
     * @param _token The address of the token to adjust.
     * @param _amount Min required amount to sell.
     */
    function setMinAmountToSellMapping(
        address _token,
        uint256 _amount
    ) external onlyManagement {
        minAmountToSellMapping[_token] = _amount;
    }


}
