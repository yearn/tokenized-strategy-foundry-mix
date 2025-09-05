// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

library ProtocolTypes {
    enum Side {
        Lend,
        Borrow
    }
}

struct GetOrderEstimationFromFVParams {
    bytes32 ccy;
    uint256 maturity;
    address user;
    ProtocolTypes.Side side;
    uint256 amountInFV;
    uint256 additionalDepositAmount;
    bool ignoreBorrowedAmount;
}

interface ILendingMarketController {
    function getMaturities(
        bytes32 _ccy
    ) external view returns (uint256[] memory);
    function getOrderBookIds(
        bytes32 _ccy
    ) external view returns (uint256[] memory);
    function getLendingMarket(bytes32 _ccy) external view returns (address);
    function getOrderBookId(
        bytes32 _ccy,
        uint256 _maturity
    ) external view returns (uint8);
    function getPosition(
        bytes32 _ccy,
        uint256 _maturity,
        address _user
    ) external view returns (int256 presentValue, int256 futureValue);
    function getCurrentMinDebtUnitPrice(
        bytes32 _ccy,
        uint256 _maturity
    ) external view returns (uint256);
    //   function getOrderEstimation(
    //     GetOrderEstimationParams calldata params
    //   )
    //     external
    //     view
    //     returns (
    //       uint256 lastUnitPrice,
    //       uint256 filledAmount,
    //       uint256 filledAmountInFV,
    //       uint256 orderFeeInFV,
    //       uint256 placedAmount,
    //       uint256 coverage,
    //       bool isInsufficientDepositAmount
    //     );
    function getOrderEstimationFromFV(
        GetOrderEstimationFromFVParams calldata _params
    )
        external
        view
        returns (
            uint256 lastUnitPrice,
            uint256 filledAmount,
            uint256 filledAmountInFV,
            uint256 orderFeeInFV,
            uint256 coverage,
            bool isInsufficientDepositAmount
        );

    function executeOrder(
        bytes32 _ccy,
        uint256 _maturity,
        ProtocolTypes.Side _side,
        uint256 _amount,
        uint256 _unitPrice
    ) external returns (bool);

    function cancelOrder(
        bytes32 _ccy,
        uint256 _maturity,
        uint48 _orderId
    ) external returns (bool);

    function unwindPosition(
        bytes32 ccy,
        uint256 maturity
    ) external returns (bool);

    function unwindPositionWithCap(
        bytes32 ccy,
        uint256 maturity,
        uint256 maxFutureValue
    )
        external
        returns (
            uint256 filledAmount,
            uint256 filledAmountInFV,
            uint256 feeInFV
        );
}

interface ILendingMarket {
    function getLendOrderIds(
        uint8 orderBookId,
        address user
    )
        external
        view
        returns (
            uint48[] memory activeOrderIds,
            uint48[] memory inActiveOrderIds
        );

    function getOrder(
        uint8 orderBookId,
        uint48 orderId
    )
        external
        view
        returns (
            ProtocolTypes.Side side,
            uint256 unitPrice,
            uint256 maturity,
            address maker,
            uint256 amount,
            uint256 timestamp,
            bool isPreOrder
        );
    function getOrderFeeRate() external view returns (uint256);
    function isOpened(uint8 orderBookId) external view returns (bool);
    function isPreOrderPeriod(uint8 orderBookId) external view returns (bool);
    function isItayosePeriod(uint8 orderBookId) external view returns (bool);
    function getMarketUnitPrice(
        uint8 orderBookId
    ) external view returns (uint256);
}

interface ITokenVault {
    function deposit(bytes32 _ccy, uint256 _amount) external;
    function withdraw(bytes32 _ccy, uint256 _amount) external;
    function getTokenAddress(bytes32 _ccy) external view returns (address);
    function getDepositAmount(
        address _user,
        bytes32 _ccy
    ) external view returns (uint256);
}
