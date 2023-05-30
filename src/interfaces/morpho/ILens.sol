// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

interface ILens {
    struct Indexes {
        uint256 p2pSupplyIndex; // The peer-to-peer supply index (in ray), used to multiply the scaled peer-to-peer supply balance and get the peer-to-peer supply balance (in underlying).
        uint256 p2pBorrowIndex; // The peer-to-peer borrow index (in ray), used to multiply the scaled peer-to-peer borrow balance and get the peer-to-peer borrow balance (in underlying).
        uint256 poolSupplyIndex; // The pool supply index (in ray), used to multiply the scaled pool supply balance and get the pool supply balance (in underlying).
        uint256 poolBorrowIndex; // The pool borrow index (in ray), used to multiply the scaled pool borrow balance and get the pool borrow balance (in underlying).
    }

    function getIndexes(
        address _poolToken
    ) external view returns (Indexes memory indexes);

    function getMainMarketData(
        address _poolTokenAddress
    )
        external
        view
        returns (
            uint256 avgSupplyRatePerBlock,
            uint256 avgBorrowRatePerBlock,
            uint256 p2pSupplyAmount,
            uint256 p2pBorrowAmount,
            uint256 poolSupplyAmount,
            uint256 poolBorrowAmount
        );

    // only for Aave, Compound has different order of return values
    function getCurrentSupplyBalanceInOf(
        address _poolTokenAddress,
        address _user
    )
        external
        view
        returns (
            uint256 balanceInP2P,
            uint256 balanceOnPool,
            uint256 totalBalance
        );

    // only for Aave
    function getNextUserSupplyRatePerYear(
        address _poolTokenAddress,
        address _user,
        uint256 _amount
    )
        external
        view
        returns (
            uint256 nextSupplyRatePerYear,
            uint256 balanceInP2P,
            uint256 balanceOnPool,
            uint256 totalBalance
        );

    // only for Aave
    function getCurrentUserSupplyRatePerYear(
        address _poolTokenAddress,
        address _user
    ) external view returns (uint256 supplyRatePerYear);
}
