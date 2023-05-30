// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

import {BaseTokenizedStrategy} from "@tokenized-strategy/BaseTokenizedStrategy.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IMorpho} from "./interfaces/morpho/IMorpho.sol";
import {ILens} from "./interfaces/morpho/ILens.sol";
import {IRewardsDistributor} from "./interfaces/morpho/IRewardsDistributor.sol";

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

error MarketPaused();
error InsufficientLiquidity();
error InvalidToken();

contract Strategy is BaseTokenizedStrategy {
    using SafeERC20 for ERC20;

    // reward token, not currently listed
    address internal constant MORPHO_TOKEN =
        0x9994E35Db50125E0DF82e4c2dde62496CE330999;
    // used for claiming reward Morpho token
    address public rewardsDistributor =
        0x3B14E5C73e0A56D607A8688098326fD4b4292135;
    // Max gas used for matching with p2p deals
    uint256 public maxGasForMatching = 100000;
    // TODO: see if it is avaiable in the perifery
    address public tradeFactory = 0xd6a8ae62f4d593DAf72E2D7c9f7bDB89AB069F06;

    // Morpho is a contract to handle interaction with the protocol
    IMorpho public morpho;
    // Lens is a contract to fetch data about Morpho protocol
    ILens public lens;
    // aToken = Morpho Aave Market for want token
    address public aToken;

    /// @notice Emitted when maxGasForMatching is updated.
    /// @param maxGasForMatching The new maxGasForMatching value.
    event SetMaxGasForMatching(uint256 maxGasForMatching);

    /// @notice Emitted when rewardsDistributor is updated.
    /// @param rewardsDistributor The new rewardsDistributor address.
    event SetRewardsDistributor(address rewardsDistributor);

    constructor(
        address _asset,
        string memory _name,
        address _morpho,
        address _lens,
        address _aToken
    ) BaseTokenizedStrategy(_asset, _name) {
        // TODO: see if the makes sense to create strategy as clonable and move this to initialize
        morpho = IMorpho(_morpho);
        lens = ILens(_lens);
        aToken = _aToken;
        IMorpho.Market memory market = morpho.market(aToken);

        if (market.underlyingToken != asset) {
            revert InvalidToken();
        }

        ERC20(asset).approve(_morpho, type(uint256).max);
    }

    /*//////////////////////////////////////////////////////////////
                NEEDED TO BE OVERRIDEN BY STRATEGIST
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Should invest up to '_amount' of 'asset'.
     *
     * This function is called at the end of a {deposit} or {mint}
     * call. Meaning that unless a whitelist is implemented it will
     * be entirely permsionless and thus can be sandwhiched or otherwise
     * manipulated.
     *
     * @param _amount The amount of 'asset' that the strategy should attemppt
     * to deposit in the yield source.
     */
    function _invest(uint256 _amount) internal override {
        IMorpho.MarketPauseStatus memory market = morpho.marketPauseStatus(aToken);
        if (market.isSupplyPaused || market.isWithdrawPaused) {
            revert MarketPaused();
        }

        morpho.supply(
            aToken,
            address(this),
            _amount,
            maxGasForMatching
        );
    }

    /**
     * @dev Will attempt to free the '_amount' of 'asset'.
     *
     * The amount of 'asset' that is already loose has already
     * been accounted for.
     *
     * This function is called {withdraw} and {redeem} calls.
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
        // if the market is paused we cannot withdraw
        IMorpho.MarketPauseStatus memory market = morpho.marketPauseStatus(aToken);
        if (market.isWithdrawPaused) {
            revert MarketPaused();
        }

        if (ERC20(asset).balanceOf(address(aToken)) < _amount) {
            // revert if there is not enough liquidity on aave, don't report loss
            revert InsufficientLiquidity();
        }

        morpho.withdraw(aToken, _amount);
    }

    /**
     * @dev Internal non-view function to harvest all rewards, reinvest
     * and return the accurate amount of funds currently held by the Strategy.
     *
     * This should do any needed harvesting, rewards selling, accrual,
     * reinvesting etc. to get the most accurate view of current assets.
     *
     * All applicable assets including loose assets should be accounted
     * for in this function.
     *
     * Care should be taken when relying on oracles or swap values rather
     * than actual amounts as all Strategy profit/loss accounting will
     * be done based on this returned value.
     *
     * This can still be called post a shutdown, a strategist can check
     * `TokenizedStrategy.isShutdown()` to decide if funds should be reinvested
     * or simply realize any profits/losses.
     *
     * @return _invested A trusted and accurate account for the total
     * amount of 'asset' the strategy currently holds.
     */
    function _totalInvested() internal override returns (uint256 _invested) {
        (, , uint256 totalUnderlying) = underlyingBalance();
        _invested = ERC20(asset).balanceOf(address(this)) + totalUnderlying;
    }

    /**
     * @notice Returns the value deposited in Morpho protocol
     * @return balanceInP2P Amount supplied through Morpho that is matched peer-to-peer
     * @return balanceOnPool Amount supplied through Morpho on the underlying protocol's pool
     * @return totalBalance Equals `balanceOnPool` + `balanceInP2P`
     */
    function underlyingBalance()
        public
        view
        returns (
            uint256 balanceInP2P,
            uint256 balanceOnPool,
            uint256 totalBalance
        )
    {
        (balanceInP2P, balanceOnPool, totalBalance) = lens
            .getCurrentSupplyBalanceInOf(aToken, address(this));
    }

    /*//////////////////////////////////////////////////////////////
                    OPTIONAL TO OVERRIDE BY STRATEGIST
    //////////////////////////////////////////////////////////////*/

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
     */
    function availableWithdrawLimit(
        address //_owner
    ) public view override returns (uint256) {
        IMorpho.MarketPauseStatus memory market = morpho.marketPauseStatus(aToken);
        if (market.isWithdrawPaused) {
            return 0;
        }
        return ERC20(asset).balanceOf(address(aToken));
    }

    /**
     * @notice Gets the max amount of `asset` that can be deposited.
     * @dev Returns 0 if the market is paused.
     * @param . The address that is depositing to the strategy.
    * @return . The avialable amount that can be deposited in terms of `asset`
     */
    function availableDepositLimit(
        address //_owner
    ) public view override returns (uint256) {
        IMorpho.MarketPauseStatus memory market = morpho.marketPauseStatus(aToken);
        if (market.isSupplyPaused || market.isWithdrawPaused) {
            return 0;
        }
        return type(uint256).max;
    }

    /*//////////////////////////////////////////////////////////////
                    CUSTOM MANAGEMENT FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Set the maximum amount of gas to consume to get matched in peer-to-peer.
     * @dev
     *  This value is needed in Morpho supply liquidity calls.
     *  Supplyed liquidity goes to loop with current loans on Morpho
     *  and creates a match for p2p deals. The loop starts from bigger liquidity deals.
     *  The default value set by Morpho is 100000.
     * @param _maxGasForMatching new maximum gas value for P2P matching
     */
    function setMaxGasForMatching(
        uint256 _maxGasForMatching
    ) external onlyManagement {
        maxGasForMatching = _maxGasForMatching;
        emit SetMaxGasForMatching(_maxGasForMatching);
    }

    /**
     * @notice Set new rewards distributor contract
     * @param _rewardsDistributor address of new contract
     */
    function setRewardsDistributor(
        address _rewardsDistributor
    ) external onlyManagement {
        rewardsDistributor = _rewardsDistributor;
        emit SetRewardsDistributor(_rewardsDistributor);
    }

    /**
     * @notice Claims MORPHO rewards. Use Morpho API to get the data: https://api.morpho.xyz/rewards/{address}
     * @dev See stages of Morpho rewards distibution: https://docs.morpho.xyz/usdmorpho/ages-and-epochs
     * @param _account The address of the claimer.
     * @param _claimable The overall claimable amount of token rewards.
     * @param _proof The merkle proof that validates this claim.
     */
    function claimMorphoRewards(
        address _account,
        uint256 _claimable,
        bytes32[] calldata _proof
    ) external onlyManagement {
        require(rewardsDistributor != address(0), "Rewards distributor not set");
        IRewardsDistributor(rewardsDistributor).claim(
            _account,
            _claimable,
            _proof
        );
    }

    /**
     * @notice Transfer MORPHO tokens to a given address
     * @dev MORPHO token was launched as non-transferable with the possibility of
     * allowing the DAO to turn on transferability anytime.
     * @param _receiver The address that will receive the MORPHO token.
     * @param _amount The amount of MORPHO token to transfer.
     */
    function transferMorpho(
        address _receiver,
        uint256 _amount
    ) external onlyManagement {
        ERC20(MORPHO_TOKEN).transfer(_receiver, _amount);
    }
}
