// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

interface IMorpho {
    enum PositionType {
        SUPPLIERS_IN_P2P,
        SUPPLIERS_ON_POOL,
        BORROWERS_IN_P2P,
        BORROWERS_ON_POOL
    }

    struct Market {
        address underlyingToken; // The address of the market's underlying token.
        uint16 reserveFactor; // Proportion of the additional interest earned being matched peer-to-peer on Morpho compared to being on the pool. It is sent to the DAO for each market. The default value is 0. In basis point (100% = 10 000).
        uint16 p2pIndexCursor; // Position of the peer-to-peer rate in the pool's spread. Determine the weights of the weighted arithmetic average in the indexes computations ((1 - p2pIndexCursor) * r^S + p2pIndexCursor * r^B) (in basis point).
        bool isCreated; // Whether or not this market is created.
        bool isPaused; // Deprecated.
        bool isPartiallyPaused; // Deprecated.
        bool isP2PDisabled; // Whether the peer-to-peer market is open or not.
    }
    struct MarketPauseStatus {
        bool isSupplyPaused; // Whether the supply is paused or not.
        bool isBorrowPaused; // Whether the borrow is paused or not
        bool isWithdrawPaused; // Whether the withdraw is paused or not. Note that a "withdraw" is still possible using a liquidation (if not paused).
        bool isRepayPaused; // Whether the repay is paused or not. Note that a "repay" is still possible using a liquidation (if not paused).
        bool isLiquidateCollateralPaused; // Whether the liquidation on this market as collateral is paused or not.
        bool isLiquidateBorrowPaused; // Whether the liquidatation on this market as borrow is paused or not.
        bool isDeprecated; // Whether a market is deprecated or not.
    }

    struct SupplyBalance {
        uint256 inP2P; // In peer-to-peer supply scaled unit, a unit that grows in underlying value, to keep track of the interests earned by suppliers in peer-to-peer. Multiply by the peer-to-peer supply index to get the underlying amount.
        uint256 onPool; // In pool supply scaled unit. Multiply by the pool supply index to get the underlying amount.
    }
    struct BorrowBalance {
        uint256 inP2P; // In peer-to-peer borrow scaled unit, a unit that grows in underlying value, to keep track of the interests paid by borrowers in peer-to-peer. Multiply by the peer-to-peer borrow index to get the underlying amount.
        uint256 onPool; // In pool borrow scaled unit, a unit that grows in value, to keep track of the debt increase when borrowers are on Aave. Multiply by the pool borrow index to get the underlying amount.
    }
    struct Delta {
        uint256 p2pSupplyDelta; // Difference between the stored peer-to-peer supply amount and the real peer-to-peer supply amount (in pool supply unit).
        uint256 p2pBorrowDelta; // Difference between the stored peer-to-peer borrow amount and the real peer-to-peer borrow amount (in pool borrow unit).
        uint256 p2pSupplyAmount; // Sum of all stored peer-to-peer supply (in peer-to-peer supply unit).
        uint256 p2pBorrowAmount; // Sum of all stored peer-to-peer borrow (in peer-to-peer borrow unit).
    }

    function supply(
        address _poolTokenAddress,
        address _onBehalf,
        uint256 _amount,
        uint256 _maxGasForMatching
    ) external;

    function withdraw(address _poolTokenAddress, uint256 _amount) external;

    function getHead(
        address _poolToken,
        PositionType _positionType
    ) external view returns (address head);

    function supplyBalanceInOf(
        address,
        address
    ) external view returns (SupplyBalance memory);

    function borrowBalanceInOf(
        address,
        address
    ) external view returns (BorrowBalance memory);

    function deltas(address _poolToken) external view returns (Delta memory);

    function market(address _poolToken) external view returns (Market memory);

    function marketPauseStatus(
        address
    ) external view returns (MarketPauseStatus memory);
}
