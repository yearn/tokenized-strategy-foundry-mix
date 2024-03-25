// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

import {BaseStrategy, ERC20} from "@tokenized-strategy/BaseStrategy.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {UniswapV3Swapper} from "@periphery/swappers/UniswapV3Swapper.sol";
import {TradeFactorySwapper} from "@periphery/swappers/TradeFactorySwapper.sol";
import {AuctionSwapper, Auction} from "@periphery/swappers/AuctionSwapper.sol";

interface ICurveLendVault {
    function asset() external view returns (address);
    function deposit(uint256) external returns (uint256);
    function withdraw(uint256) external;
    function redeem(uint256) external;
    function maxWithdraw(address) external view returns (uint256);
    function convertToShares(uint256) external view returns (uint256);
    function convertToAssets(uint256) external view returns (uint256);
    }

interface ILiquidityGauge {
    function deposit(uint256) external;
    function withdraw(uint256) external;
    function claim_rewards() external;
}

contract CurveLender is BaseStrategy, UniswapV3Swapper, TradeFactorySwapper, AuctionSwapper {
    using SafeERC20 for ERC20;

    ICurveLendVault public immutable curveLendVault;
    ILiquidityGauge public immutable liquidityGauge;
    address internal immutable GOV; //yearn governance

    // If rewards should be sold through TradeFactory.
    bool public useTradeFactory;

    // If rewards should be sold through Auctions.
    bool public useAuction;

    mapping(address => uint256) public minAmountToSellMapping;

    constructor(
        address _asset,
        address _curveLendVault,
        address _liquidityGauge,
        address _base,
        uint24 _feeBaseToAsset,
        address _GOV,
        string memory _name
    ) BaseStrategy(_asset, _name) {
        curveLendVault = ICurveLendVault(_curveLendVault);
        require(curveLendVault.asset() == _asset, "wrong asset");
        liquidityGauge = ILiquidityGauge(_liquidityGauge);
        base = _base;
        GOV = _GOV;

        asset.safeApprove(address(curveLendVault), type(uint256).max);
        ERC20(address(curveLendVault)).safeApprove(address(liquidityGauge), type(uint256).max);

        // Set uni swapper values
        minAmountToSell = 0; // We will use the minAmountToSell mapping instead.
        _setUniFees(_base, _asset, _feeBaseToAsset);
    }

    function _deployFunds(uint256 _amount) internal override {
        liquidityGauge.deposit(curveLendVault.deposit(_amount)); // deposit & stake
    }

    function _freeFunds(uint256 _amount) internal override {
        uint256 shares = curveLendVault.convertToShares(_amount);
        liquidityGauge.withdraw(shares); // unstake from gauge
        curveLendVault.redeem(shares); // redeem
    }

    function _harvestAndReport()
        internal
        override
        returns (uint256 _totalAssets)
    {
        if (!TokenizedStrategy.isShutdown()) {
            _claimAndSellRewards();

            uint256 assetBalance = asset.balanceOf(address(this));
            if (assetBalance > 0) {
                _deployFunds(assetBalance);
            }
        }

        _totalAssets = asset.balanceOf(address(this)); //@todo: fix
    }

    function _claimRewards() internal override {
        // @todo: need to add gauge claim logic
        liquidityGauge.claim_rewards();
    }

    function _claimAndSellRewards() internal {
        _claimRewards();

        // If both tradeFactory and Auction are not being used, we sell rewards here:
        if (!useTradeFactory && !useAuction) {
            //rewards --> asset
            address[] memory _rewardTokens = rewardTokens();
            uint256 rewardsLength = _rewardTokens.length;
            if (rewardsLength > 0) {
                address currentReward;
                uint256 rewardBalance;
                for (uint256 i; i < rewardsLength; ++i) {
                    currentReward = _rewardTokens[i];
                    rewardBalance = ERC20(currentReward).balanceOf(address(this));
                    if (rewardBalance > minAmountToSellMapping[currentReward]) {
                        _swapFrom(currentReward, address(asset), rewardBalance, 0);
                    }
                }
            }
        }
    }

    function availableWithdrawLimit(
        address _owner
    ) public view override returns (uint256) {
            return curveLendVault.maxWithdraw(address(this));
    }

    /**
     * @notice Set wether to use the trade factory contract address.
     * @param _useTradeFactory wether to use the trade factory or not.
     */
    function setUseTradeFactory(bool _useTradeFactory) external onlyManagement {
        require(tradeFactory() != address(0));
        useTradeFactory = _useTradeFactory;
    }

    /**
     * @notice Remove all the permissions of the tradeFactory and set its address to zero.
     */
    function removeTradeFactory() external onlyManagement {
        require(tradeFactory() != address(0));
        _removeTradeFactoryPermissions();
        useTradeFactory = false;
    }

    /**
     * @notice Add a reward address that will be sold to autocompound the LP.
     * @param _rewardToken address of the reward token to be sold.
     * @param _feeRewardTokenToBase automatic swapping fee tier between rewardToken and base (0.01% = 100, 0.05% = 500, 0.3% = 3000, 1% = 10000).
     */
    function addReward(address _rewardToken, uint24 _feeRewardTokenToBase) external onlyManagement {
        _setUniFees(_rewardToken, base, _feeRewardTokenToBase);
        _addToken(_rewardToken, address(asset));
    }

    /**
     * @notice Remove a reward token to stop it being autocompounded to the LP.
     * @param _rewardToken address of the reward token to be removed.
     */
    function removeReward(address _rewardToken) external onlyManagement {
        _removeToken(_rewardToken, address(asset));
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

    ///////////// DUTCH AUCTION FUNCTIONS \\\\\\\\\\\\\\\\\\
    function setAuction(address _auction) external onlyEmergencyAuthorized {
        if (_auction != address(0)) {
            address want = Auction(_auction).want();
            require(want == address(asset), "wrong want");
        }
        auction = _auction;
    }

    function _auctionKicked(address _token) internal virtual override returns (uint256 _kicked) {
        require(_token != address(asset), "asset");
        _kicked = super._auctionKicked(_token);
        require(_kicked >= minAmountToSellMapping[_token], "< minAmount");
    }

    /**
     * @notice Set if tokens should be sold through the dutch auction contract.
     */
    function setUseAuction(bool _useAuction) external onlyManagement {
        useAuction = _useAuction;
    }

    /*//////////////////////////////////////////////////////////////
                EMERGENCY & GOVERNANCE:
    //////////////////////////////////////////////////////////////*/

    function _emergencyWithdraw(uint256 _amount) internal override {
        _freeFunds(_amount);
    }

    /**
     * @notice Set the trade factory contract address.
     * @dev For disabling set address(0).
     * @param _tradeFactory The address of the trade factory contract.
     * @param _useTradeFactory Wether or not to enable the tradeFactory.
     */
    function setTradeFactory(address _tradeFactory, bool _useTradeFactory) external onlyGovernance {
        _setTradeFactory(_tradeFactory, address(asset));
        useTradeFactory = _useTradeFactory;
    }

    /// @notice Sweep of non-asset ERC20 tokens to governance (onlyGovernance)
    /// @param _token The ERC20 token to sweep
    function sweep(address _token) external onlyGovernance {
        require(_token != address(asset), "!asset");
        ERC20(_token).safeTransfer(GOV, ERC20(_token).balanceOf(address(this)));
    }

    modifier onlyGovernance() {
        require(msg.sender == GOV, "!gov");
        _;
    }
}
