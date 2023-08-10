// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

import {BaseTokenizedStrategy} from "@tokenized-strategy/BaseTokenizedStrategy.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IGDai} from "./interfaces/IGDai.sol";
import {IGDaiOpenPnlFeed} from "./interfaces/IGDaiOpenPnlFeed.sol";

// Import interfaces for many popular DeFi projects, or add your own!
//import "../interfaces/<protocol>/<Interface>.sol";

/**
 * The `TokenizedStrategy` variable can be used to retrieve the strategies
 * specifc storage data your contract.
 *
 *       i.e. uint256 totalAssets = TokenizedStrategy.totalAssets()
 *
 * This can not be used for write functions. Any TokenizedStrategy
 * variables that need to be udpated post deployement will need to
 * come from an external call from the strategies specific `management`.
 */

// NOTE: To implement permissioned functions you can use the onlyManagement and onlyKeepers modifiers

contract Strategy is BaseTokenizedStrategy {
    using SafeERC20 for ERC20;

    IGDai public constant GDAI = IGDai(0x91993f2101cc758D0dEB7279d41e880F7dEFe827);
    IGDaiOpenPnlFeed public constant GDAI_PNL_FEED = IGDaiOpenPnlFeed(0x8d687276543b92819F2f2B5C3faad4AD27F4440c);

    address public vault;
    uint256 public depositLimit;

    constructor(
        address _asset,
        string memory _name,
        address _vault,
        uint256 _depositLimit
    ) BaseTokenizedStrategy(_asset, _name) {
        vault = _vault;
        depositLimit = _depositLimit;
        ERC20(_asset).safeApprove(address(GDAI), type(uint256).max);
    }

    /*//////////////////////////////////////////////////////////////
                NEEDED TO BE OVERRIDEN BY STRATEGIST
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Should deploy up to '_amount' of 'asset' in the yield source.
     *
     * This function is called at the end of a {deposit} or {mint}
     * call. Meaning that unless a whitelist is implemented it will
     * be entirely permsionless and thus can be sandwhiched or otherwise
     * manipulated.
     *
     * @param _amount The amount of 'asset' that the strategy should attemppt
     * to deposit in the yield source.
     */
    function _deployFunds(uint256 _amount) internal override {        
        GDAI.deposit(_amount, address(this));
    }

    /**
     * @dev Will attempt to free the '_amount' of 'asset'.
     *
     * The amount of 'asset' that is already loose has already
     * been accounted for.
     *
     * This function is called during {withdraw} and {redeem} calls.
     * Meaning that unless a whitelist is implemented it will be
     * entirely permsionless and thus can be sandwhiched or otherwise
     * manipulated.
     *
     * Should not rely on asset.balanceOf(address(this)) calls other than
     * for diff accounting puroposes.
     *
     * Any difference between `_amount` and what is actually freed will be
     * counted as a loss and passed on to the withdrawer. This means
     * care should be taken in times of illiquidity. It may be better to revert
     * if withdraws are simply illiquid so not to realize incorrect losses.
     *
     * @param _amount, The amount of 'asset' to be freed.
     */
    function _freeFunds(uint256 _amount) internal override {
        GDAI.withdraw(_amount, address(this), address(this));
    }

    /**
     * @dev Internal function to harvest all rewards, redeploy any idle
     * funds and return an accurate accounting of all funds currently
     * held by the Strategy.
     *
     * This should do any needed harvesting, rewards selling, accrual,
     * redepositing etc. to get the most accurate view of current assets.
     *
     * NOTE: All applicable assets including loose assets should be
     * accounted for in this function.
     *
     * Care should be taken when relying on oracles or swap values rather
     * than actual amounts as all Strategy profit/loss accounting will
     * be done based on this returned value.
     *
     * This can still be called post a shutdown, a strategist can check
     * `TokenizedStrategy.isShutdown()` to decide if funds should be
     * redeployed or simply realize any profits/losses.
     *
     * @return _totalAssets A trusted and accurate account for the total
     * amount of 'asset' the strategy currently holds including idle funds.
     */
    function _harvestAndReport() internal view override returns (uint256 _totalAssets) {
        // All we need is a total assets report
        // nothing to harvest or redeploy
        _totalAssets = _balanceAsset() + _balanceUpdateGDAI();        
    }

    function _balanceAsset() internal view returns (uint256) {
        return ERC20(asset).balanceOf(address(this));
    }

    function _balanceUpdateGDAI() internal view returns (uint256) {
        uint256 gDaiShares = GDAI.balanceOf(address(this));
        return GDAI.convertToAssets(gDaiShares);
    }

    /*//////////////////////////////////////////////////////////////
                EXTERNAL:
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns the amount of asset (DAI) the strategy holds.
    function balanceAsset() external view returns (uint256) {
        return _balanceAsset();
    }

    /// @notice Returns the approximate asset (DAI) balance the strategy owns
    function balanceGDAI() external view returns (uint256) {
        return _balanceUpdateGDAI();
    }

    /// @notice nextEpochValuesRequestCount goes greater than zero
    /// when gdai's oracle begins reporting open trader pnl to its vault 
    /// (and thus update the vault's collateralization ratio).
    /// This happens towards the end of each epoch.
    function isRedemptionWindowOpen() external view returns (bool) {
        return GDAI_PNL_FEED.nextEpochValuesRequestCount() == 0;
    }

    /// @notice request a redemption of GDAI `shares`
    function requestGDAIRedemption(uint256 shares) external onlyManagement returns (uint256 unlockEpoch) {
        GDAI.makeWithdrawRequest(shares, address(this));
        unlockEpoch = GDAI.currentEpoch() + GDAI.withdrawEpochsTimelock();
    }

    /// @notice cancel request for GDAI `shares` at epoch `unlockEpoch`
    function cancelGDAIRedemption(uint256 shares, uint256 unlockEpoch) external onlyManagement {
        GDAI.cancelWithdrawRequest(shares, address(this), unlockEpoch);
    }

    /// @notice redeem GDAI `shares`. 
    /// Reverts if current gdai epoch doesn't show enough requested shares to redeem.
    function redeemGDAI(uint256 shares) external onlyManagement {
        GDAI.redeem(shares, address(this), address(this));
    }

    /*//////////////////////////////////////////////////////////////
                    OPTIONAL TO OVERRIDE BY STRATEGIST
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Optional function for strategist to override that can
     *  be called in between reports.
     *
     * If '_tend' is used tendTrigger() will also need to be overridden.
     *
     * This call can only be called by a persionned role so may be
     * through protected relays.
     *
     * This can be used to harvest and compound rewards, deposit idle funds,
     * perform needed poisition maintence or anything else that doesn't need
     * a full report for.
     *
     *   EX: A strategy that can not deposit funds without getting
     *       sandwhiched can use the tend when a certain threshold
     *       of idle to totalAssets has been reached.
     *
     * The TokenizedStrategy contract will do all needed debt and idle updates
     * after this has finished and will have no effect on PPS of the strategy
     * till report() is called.
     *
     * @param _totalIdle The current amount of idle funds that are available to deploy.
     *
    function _tend(uint256 _totalIdle) internal override {}
    */

    /**
     * @notice Returns wether or not tend() should be called by a keeper.
     * @dev Optional trigger to override if tend() will be used by the strategy.
     * This must be implemented if the strategy hopes to invoke _tend().
     *
     * @return . Should return true if tend() should be called by keeper or false if not.
     *
    function tendTrigger() public view override returns (bool) {}
    */

    /**
     * @notice Gets the max amount of `asset` that an adress can deposit.
     * @dev Defaults to an unlimited amount for any address. But can
     * be overriden by strategists.
     *
     * This function will be called before any deposit or mints to enforce
     * any limits desired by the strategist. This can be used for either a
     * traditional deposit limit or for implementing a whitelist etc.
     *
     *   EX:
     *      if(isAllowed[_owner]) return super.availableDepositLimit(_owner);
     *
     * This does not need to take into account any conversion rates
     * from shares to assets. But should know that any non max uint256
     * amounts may be converted to shares. So it is recommended to keep
     * custom amounts low enough as not to cause overflow when multiplied
     * by `totalSupply`.
     *
     * @param . The address that is depositing into the strategy.
     * @return . The avialable amount the `_owner` can deposit in terms of `asset`
     *
    */
    function availableDepositLimit(
        address _owner
    ) public view override returns (uint256) {
        if (_owner != vault) {
            return 0;
        }

        uint256 _depositLimit = depositLimit;

        if (_depositLimit == type(uint256).max) {
            return type(uint256).max;
        }

        uint256 _totalAssets = TokenizedStrategy.totalAssets();
        return _totalAssets >= _depositLimit ? 0 : _depositLimit - _totalAssets;
    }

    /**
     * @notice Gets the max amount of `asset` that can be withdrawn.
     * @dev Defaults to an unlimited amount for any address. But can
     * be overriden by strategists.
     *
     * This function will be called before any withdraw or redeem to enforce
     * any limits desired by the strategist. This can be used for illiquid
     * or sandwhichable strategies. It should never be lower than `totalIdle`.
     *
     *   EX:
     *       return TokenIzedStrategy.totalIdle();
     *
     * This does not need to take into account the `_owner`'s share balance
     * or conversion rates from shares to assets.
     *
     * @param . The address that is withdrawing from the strategy.
     * @return . The avialable amount that can be withdrawn in terms of `asset`
     *
    */
    function availableWithdrawLimit(
        address _owner
    ) public view override returns (uint256) {
        uint256 redeemableShares = GDAI.withdrawRequests(address(this), GDAI.currentEpoch());
        return TokenizedStrategy.totalIdle() + GDAI.convertToAssets(redeemableShares);
    }

    /**
     * @dev Optional function for a strategist to override that will
     * allow management to manually withdraw deployed funds from the
     * yield source if a strategy is shutdown.
     *
     * This should attempt to free `_amount`, noting that `_amount` may
     * be more than is currently deployed.
     *
     * NOTE: This will not realize any profits or losses. A seperate
     * {report} will be needed in order to record any profit/loss. If
     * a report may need to be called after a shutdown it is important
     * to check if the strategy is shutdown during {_harvestAndReport}
     * so that it does not simply re-deploy all funds that had been freed.
     *
     * EX:
     *   if(freeAsset > 0 && !TokenizedStrategy.isShutdown()) {
     *       depositFunds...
     *    }
     *
     * @param _amount The amount of asset to attempt to free.
     *
    function _emergencyWithdraw(uint256 _amount) internal override {
        TODO: If desired implement simple logic to free deployed funds.

        EX:
            _amount = min(_amount, atoken.balanceOf(address(this)));
            lendingPool.withdraw(asset, _amount);
    }

    */
}
