// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

import {AprOracleBase} from "@periphery/AprOracle/AprOracleBase.sol";
import {IMorpho} from "../interfaces/morpho/IMorpho.sol";
import {ILens} from "../interfaces/morpho/ILens.sol";
import {IStrategyInterface} from "../interfaces/IStrategyInterface.sol";
import "../interfaces/aave/ILendingPool.sol";
import "../interfaces/aave/IProtocolDataProvider.sol";
import "../interfaces/aave/IReserveInterestRateStrategy.sol";

import "@morpho-dao/morpho-utils/math/PercentageMath.sol";
import "@morpho-dao/morpho-utils/math/WadRayMath.sol";
import "@morpho-dao/morpho-utils/math/Math.sol";

contract StrategyAprOracle is AprOracleBase {
    ILendingPool internal constant POOL =
        ILendingPool(0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9);
    IProtocolDataProvider internal constant AAVE_DATA_PROIVDER =
        IProtocolDataProvider(0x057835Ad21a177dbdd3090bB1CAE03EaCF78Fc6d);

    constructor() AprOracleBase("Morpho Aave v2 Apr Oracle") {}

    /**
     * @notice Will return the expected Apr of a strategy post a debt change.
     * @dev _delta is a signed integer so that it can also repersent a debt
     * decrease.
     *
     * This should return the annual expected return at the current timestamp
     * repersented as 1e18.
     *
     *      ie. 10% == 1e17
     *
     * _delta will be == 0 to get the current apr.
     *
     * This will potentially be called during non-view functions so gas
     * effeciency should be taken into account.
     *
     * @param _strategy The token to get the apr for.
     * @param _delta The difference in debt.
     * @return apr The expected apr for the strategy repersented as 1e18.
     */
    function aprAfterDebtChange(
        address _strategy,
        int256 _delta
    ) external view override returns (uint256 apr) {
        IStrategyInterface strategy = IStrategyInterface(_strategy);
        address aToken = strategy.aToken();
        if (_delta == 0) {
            apr = ILens(strategy.lens()).getCurrentUserSupplyRatePerYear(
                aToken,
                _strategy
            );
        } else if (_delta > 0) {
            (apr, , , ) = ILens(strategy.lens()).getNextUserSupplyRatePerYear(
                aToken,
                _strategy,
                uint256(_delta)
            );
        } else {
            apr = aprAfterLiquidityWithdraw(strategy, aToken, uint256(-_delta));
        }
        apr = apr / 1e9; // scale down from wad to ray
    }

    struct PoolData {
        uint256 withdrawnFromPool;
        uint256 borrowedFromPool;
        uint256 poolSupplyRate;
        uint256 variableBorrowRate;
        uint256 p2pSupplyRate;
    }

    function aprAfterLiquidityWithdraw(
        IStrategyInterface _strategy,
        address _aToken,
        uint256 _amount
    ) internal view returns (uint256 apr) {
        IMorpho morpho = IMorpho(_strategy.morpho());
        ILens lens = ILens(_strategy.lens());

        ILens.Indexes memory indexes = lens.getIndexes(_aToken);
        IMorpho.Market memory market = morpho.market(_aToken);
        IMorpho.Delta memory delta = morpho.deltas(_aToken);
        IMorpho.SupplyBalance memory supplyBalance = morpho.supplyBalanceInOf(
            _aToken,
            address(_strategy)
        );

        /// Pool withdraw ///

        // Withdraw supply on pool.
        PoolData memory poolData;
        // uint256 withdrawnFromPool;
        if (supplyBalance.onPool > 0) {
            poolData.withdrawnFromPool += Math.min(
                WadRayMath.rayMul(
                    supplyBalance.onPool,
                    indexes.poolSupplyIndex
                ),
                _amount
            );

            supplyBalance.onPool -= WadRayMath.rayDiv(
                poolData.withdrawnFromPool,
                indexes.poolSupplyIndex
            );
            _amount -= poolData.withdrawnFromPool;
        }

        // Reduce the peer-to-peer supply delta.
        if (delta.p2pSupplyDelta > 0) {
            uint256 matchedDelta = Math.min(
                WadRayMath.rayMul(
                    delta.p2pSupplyDelta,
                    indexes.poolSupplyIndex
                ),
                _amount
            );

            supplyBalance.inP2P -= WadRayMath.rayDiv(
                matchedDelta,
                indexes.p2pSupplyIndex
            );
            delta.p2pSupplyDelta -= Math.min(
                delta.p2pSupplyDelta,
                WadRayMath.rayDiv(matchedDelta, indexes.poolSupplyIndex)
            );
            poolData.withdrawnFromPool += matchedDelta;
            _amount -= matchedDelta;
        }

        /// Transfer withdraw ///

        // Promote pool suppliers.
        if (_amount > 0 && supplyBalance.inP2P > 0 && !market.isP2PDisabled) {
            address firstPoolSupplier = morpho.getHead(
                _aToken,
                IMorpho.PositionType.SUPPLIERS_ON_POOL
            );
            uint256 firstPoolSupplierBalance = morpho
                .supplyBalanceInOf(_aToken, firstPoolSupplier)
                .onPool;

            if (firstPoolSupplierBalance > 0) {
                uint256 matchedP2P = Math.min(
                    WadRayMath.rayMul(
                        firstPoolSupplierBalance,
                        indexes.poolSupplyIndex
                    ),
                    _amount
                );

                supplyBalance.inP2P -= WadRayMath.rayDiv(
                    matchedP2P,
                    indexes.p2pSupplyIndex
                );
                poolData.withdrawnFromPool += matchedP2P;
                _amount -= matchedP2P;
            }
        }

        /// Breaking withdraw ///

        // Demote peer-to-peer borrowers.
        poolData.borrowedFromPool = Math.min(
            WadRayMath.rayMul(supplyBalance.inP2P, indexes.p2pSupplyIndex),
            _amount
        );
        if (poolData.borrowedFromPool > 0) {
            delta.p2pSupplyAmount -= Math.min(
                delta.p2pSupplyAmount,
                WadRayMath.rayDiv(
                    poolData.borrowedFromPool,
                    indexes.p2pSupplyIndex
                )
            );
        }

        (poolData.poolSupplyRate, poolData.variableBorrowRate) = getAaveRates(
            0,
            poolData.borrowedFromPool,
            0,
            poolData.withdrawnFromPool,
            _strategy.asset()
        );

        poolData.p2pSupplyRate = computeP2PSupplyRatePerYear(
            P2PRateComputeParams({
                poolSupplyRatePerYear: poolData.poolSupplyRate,
                poolBorrowRatePerYear: poolData.variableBorrowRate,
                poolIndex: indexes.poolSupplyIndex,
                p2pIndex: indexes.p2pSupplyIndex,
                p2pDelta: delta.p2pSupplyDelta,
                p2pAmount: delta.p2pSupplyAmount,
                p2pIndexCursor: market.p2pIndexCursor,
                reserveFactor: market.reserveFactor
            })
        );

        (apr, ) = getWeightedRate(
            poolData.p2pSupplyRate,
            poolData.poolSupplyRate,
            WadRayMath.rayMul(supplyBalance.inP2P, indexes.p2pSupplyIndex),
            WadRayMath.rayMul(supplyBalance.onPool, indexes.poolSupplyIndex)
        );
    }

    // ---------------------- RATES CALCULATIONS ----------------------

    /// @notice Computes and returns the underlying pool rates on AAVE.
    /// @param _supplied The amount hypothetically supplied.
    /// @param _borrowed The amount hypothetically borrowed.
    /// @param _repaid The amount hypothetically repaid.
    /// @param _withdrawn The amount hypothetically withdrawn.
    /// @return supplyRate The market's pool supply rate per year (in ray).
    /// @return variableBorrowRate The market's pool borrow rate per year (in ray).
    function getAaveRates(
        uint256 _supplied,
        uint256 _borrowed,
        uint256 _repaid,
        uint256 _withdrawn,
        address _asset
    ) private view returns (uint256 supplyRate, uint256 variableBorrowRate) {
        ILendingPool.ReserveData memory reserve = POOL.getReserveData(_asset);
        PoolRatesVars memory vars;
        (
            vars.availableLiquidity,
            vars.totalStableDebt,
            vars.totalVariableDebt,
            ,
            ,
            ,
            vars.avgStableBorrowRate,
            ,
            ,

        ) = AAVE_DATA_PROIVDER.getReserveData(_asset);
        (, , , , vars.reserveFactor, , , , , ) = AAVE_DATA_PROIVDER
            .getReserveConfigurationData(_asset);

        (supplyRate, , variableBorrowRate) = IReserveInterestRateStrategy(
            reserve.interestRateStrategyAddress
        ).calculateInterestRates(
                _asset,
                vars.availableLiquidity +
                    _supplied +
                    _repaid -
                    _borrowed -
                    _withdrawn, // repaidToPool is added to avaiable liquidity by aave impl, see: https://github.com/aave/protocol-v2/blob/0829f97c5463f22087cecbcb26e8ebe558592c16/contracts/protocol/lendingpool/LendingPool.sol#L277
                vars.totalStableDebt,
                vars.totalVariableDebt + _borrowed - _repaid,
                vars.avgStableBorrowRate,
                vars.reserveFactor
            );
    }

    /// @dev Returns the rate experienced based on a given pool & peer-to-peer distribution.
    /// @param _p2pRate The peer-to-peer rate (in a unit common to `_poolRate` & `weightedRate`).
    /// @param _poolRate The pool rate (in a unit common to `_p2pRate` & `weightedRate`).
    /// @param _balanceInP2P The amount of balance matched peer-to-peer (in a unit common to `_balanceOnPool`).
    /// @param _balanceOnPool The amount of balance supplied on pool (in a unit common to `_balanceInP2P`).
    /// @return weightedRate The rate experienced by the given distribution (in a unit common to `_p2pRate` & `_poolRate`).
    /// @return totalBalance The sum of peer-to-peer & pool balances.
    function getWeightedRate(
        uint256 _p2pRate,
        uint256 _poolRate,
        uint256 _balanceInP2P,
        uint256 _balanceOnPool
    ) internal pure returns (uint256 weightedRate, uint256 totalBalance) {
        totalBalance = _balanceInP2P + _balanceOnPool;
        if (totalBalance == 0) return (weightedRate, totalBalance);

        if (_balanceInP2P > 0)
            weightedRate = WadRayMath.rayMul(
                _p2pRate,
                WadRayMath.rayDiv(_balanceInP2P, totalBalance)
            );
        if (_balanceOnPool > 0)
            weightedRate =
                weightedRate +
                WadRayMath.rayMul(
                    _poolRate,
                    WadRayMath.rayDiv(_balanceOnPool, totalBalance)
                );
    }

    struct PoolRatesVars {
        uint256 availableLiquidity;
        uint256 totalStableDebt;
        uint256 totalVariableDebt;
        uint256 avgStableBorrowRate;
        uint256 reserveFactor;
    }

    struct P2PRateComputeParams {
        uint256 poolSupplyRatePerYear; // The pool supply rate per year (in ray).
        uint256 poolBorrowRatePerYear; // The pool borrow rate per year (in ray).
        uint256 poolIndex; // The last stored pool index (in ray).
        uint256 p2pIndex; // The last stored peer-to-peer index (in ray).
        uint256 p2pDelta; // The peer-to-peer delta for the given market (in pool unit).
        uint256 p2pAmount; // The peer-to-peer amount for the given market (in peer-to-peer unit).
        uint256 p2pIndexCursor; // The index cursor of the given market (in bps).
        uint256 reserveFactor; // The reserve factor of the given market (in bps).
    }

    /// @notice Computes and returns the peer-to-peer supply rate per year of a market given its parameters.
    /// @param _params The computation parameters.
    /// @return p2pSupplyRate The peer-to-peer supply rate per year (in ray).
    function computeP2PSupplyRatePerYear(
        P2PRateComputeParams memory _params
    ) internal pure returns (uint256 p2pSupplyRate) {
        if (_params.poolSupplyRatePerYear > _params.poolBorrowRatePerYear) {
            p2pSupplyRate = _params.poolBorrowRatePerYear; // The p2pSupplyRate is set to the poolBorrowRatePerYear because there is no rate spread.
        } else {
            p2pSupplyRate = PercentageMath.weightedAvg(
                _params.poolSupplyRatePerYear,
                _params.poolBorrowRatePerYear,
                _params.p2pIndexCursor
            );

            p2pSupplyRate =
                p2pSupplyRate -
                PercentageMath.percentMul(
                    (p2pSupplyRate - _params.poolSupplyRatePerYear),
                    _params.reserveFactor
                );
        }

        if (_params.p2pDelta > 0 && _params.p2pAmount > 0) {
            uint256 shareOfTheDelta = Math.min(
                WadRayMath.rayDiv(
                    WadRayMath.rayMul(_params.p2pDelta, _params.poolIndex),
                    WadRayMath.rayMul(_params.p2pAmount, _params.p2pIndex)
                ), // Using ray division of an amount in underlying decimals by an amount in underlying decimals yields a value in ray.
                WadRayMath.RAY // To avoid shareOfTheDelta > 1 with rounding errors.
            ); // In ray.

            p2pSupplyRate =
                WadRayMath.rayMul(
                    p2pSupplyRate,
                    WadRayMath.RAY - shareOfTheDelta
                ) +
                WadRayMath.rayMul(
                    _params.poolSupplyRatePerYear,
                    shareOfTheDelta
                );
        }
    }
}
