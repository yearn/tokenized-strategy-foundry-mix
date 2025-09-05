// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {BaseStrategy, ERC20} from "@tokenized-strategy/BaseStrategy.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ILendingMarketController, ILendingMarket, ITokenVault, ProtocolTypes, GetOrderEstimationFromFVParams} from "./interfaces/ISecuredFinance.sol";

/**
 * The `TokenizedStrategy` variable can be used to retrieve the strategies
 * specific storage data your contract.
 *
 *       i.e. uint256 totalAssets = TokenizedStrategy.totalAssets()
 *
 * This can not be used for write functions. Any TokenizedStrategy
 * variables that need to be updated post deployment will need to
 * come from an external call from the strategies specific `management`.
 */

// NOTE: To implement permissioned functions you can use the onlyManagement, onlyEmergencyAuthorized and onlyKeepers modifiers

contract Strategy is BaseStrategy {
    using SafeERC20 for ERC20;

    ILendingMarketController public immutable lendingMarketController;
    ITokenVault public immutable tokenVault;
    bytes32 public immutable currency;
    ILendingMarket public immutable lendingMarket;
    // Minimum amount for triggering the tend function
    uint256 public immutable minTendAmount;

    uint256 private constant SECONDS_PER_YEAR = 365 days;
    uint256 private constant BASIS_POINTS = 10000;
    uint256 private constant MIN_APR = 700; // 7% in basis points
    uint256 private constant MAX_PRICE = 9975;

    uint256 public maturityExclusionPeriod;
    mapping(uint256 => uint256) public lastMarketUnitPrices; // Mapping to store last market unit prices for each maturity

    struct OrderBook {
        uint8 id;
        uint256 maturity;
    }

    constructor(
        address _asset,
        string memory _name,
        address _lendingMarketController,
        address _tokenVault,
        bytes32 _currency,
        uint256 _minTendAmount
    ) BaseStrategy(_asset, _name) {
        lendingMarketController = ILendingMarketController(
            _lendingMarketController
        );
        tokenVault = ITokenVault(_tokenVault);

        require(
            tokenVault.getTokenAddress(_currency) == _asset,
            "Token address mismatch"
        );

        lendingMarket = ILendingMarket(
            ILendingMarketController(_lendingMarketController).getLendingMarket(
                _currency
            )
        );

        require(
            address(lendingMarket) != address(0),
            "Lending market not found for currency"
        );

        currency = _currency;
        minTendAmount = _minTendAmount;
        maturityExclusionPeriod = 1 weeks;
    }

    function setMaturityExclusionPeriod(
        uint256 _maturityExclusionPeriod
    ) external onlyManagement {
        maturityExclusionPeriod = _maturityExclusionPeriod;
    }

    /*//////////////////////////////////////////////////////////////
                NEEDED TO BE OVERRIDDEN BY STRATEGIST
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Can deploy up to '_amount' of 'asset' in the yield source.
     *
     * This function is called at the end of a {deposit} or {mint}
     * call. Meaning that unless a whitelist is implemented it will
     * be entirely permissionless and thus can be sandwiched or otherwise
     * manipulated.
     *
     * @param _amount The amount of 'asset' that the strategy can attempt
     * to deposit in the yield source.
     */
    function _deployFunds(uint256 _amount) internal override {
        // First deposit funds to TokenVault if there are new funds
        if (_amount > 0) {
            asset.safeApprove(address(tokenVault), _amount);
            tokenVault.deposit(currency, _amount);
        }

        uint256 depositAmount = tokenVault.getDepositAmount(
            address(this),
            currency
        );

        (
            OrderBook memory firstOrderBooks,
            OrderBook memory secondOrderBook
        ) = _getTargetOrderBooks();

        if (firstOrderBooks.id == 0) return; // No available maturities

        uint256 firstAmount;
        uint256 secondAmount;

        if (depositAmount > 0) {
            if (secondOrderBook.id == 0) {
                // Only use first maturity if no first maturity
                firstAmount = depositAmount;
            } else {
                // Split 40% to first, 60% to second
                firstAmount = (depositAmount * 4) / 10;
                secondAmount = depositAmount - firstAmount;
            }
        }

        // Always call rebalancing for both maturities (even with 0 new amount)
        _deployToMaturityWithRebalance(firstOrderBooks, firstAmount);

        if (secondOrderBook.id != 0) {
            _deployToMaturityWithRebalance(secondOrderBook, secondAmount);
        }
    }

    /**
     * @dev Should attempt to free the '_amount' of 'asset'.
     *
     * NOTE: The amount of 'asset' that is already loose has already
     * been accounted for.
     *
     * This function is called during {withdraw} and {redeem} calls.
     * Meaning that unless a whitelist is implemented it will be
     * entirely permissionless and thus can be sandwiched or otherwise
     * manipulated.
     *
     * Should not rely on asset.balanceOf(address(this)) calls other than
     * for diff accounting purposes.
     *
     * Any difference between `_amount` and what is actually freed will be
     * counted as a loss and passed on to the withdrawer. This means
     * care should be taken in times of illiquidity. It may be better to revert
     * if withdraws are simply illiquid so not to realize incorrect losses.
     *
     * @param _amount, The amount of 'asset' to be freed.
     */
    function _freeFunds(uint256 _amount) internal override {
        if (_amount == 0) return;

        uint256 freed = tokenVault.getDepositAmount(address(this), currency);
        uint256 loss = 0;
        OrderBook[] memory orderBooks = _getOrderBooks();

        // Cancel orders starting from the longest maturity to preserve short-term positions
        for (uint256 i = orderBooks.length; i > 0 && freed < _amount; i--) {
            OrderBook memory orderBook = orderBooks[i - 1];

            // Cancel orders for this maturity until we have enough funds
            uint256 maturityFreed = _cancelOrdersForAmountNeeded(
                orderBook,
                _amount - freed
            );
            freed += maturityFreed;
        }

        // If the amount freed is less than requested, unwind positions
        if (freed < _amount) {
            for (uint256 i = 0; i < orderBooks.length && freed < _amount; i++) {
                OrderBook memory orderBook = orderBooks[i];

                // Calculate how much more we need to free
                uint256 remainingAmount = _amount - freed;
                // Get the current position value before unwinding
                uint256 futureValue = _getPositionInFV(orderBook.maturity);

                if (futureValue == 0) {
                    continue;
                }

                // Calculate how much we need to unwind to free the remaining amount
                uint256 remainingAmountInFV = (remainingAmount * BASIS_POINTS) /
                    lastMarketUnitPrices[orderBook.maturity];

                // Unwind position with cap to avoid excessive losses and get the filled amount in future value
                (
                    uint256 filledAmount,
                    uint256 filledAmountInFV,

                ) = lendingMarketController.unwindPositionWithCap(
                        currency,
                        orderBook.maturity,
                        remainingAmountInFV
                    );

                uint256 freedAmount = (filledAmountInFV * remainingAmount) /
                    remainingAmountInFV;

                loss += freedAmount - filledAmount;
                freed += freedAmount;

                // If we have freed enough, break
                if (freed >= _amount + loss) {
                    break;
                }
            }
        }

        require(freed >= _amount + loss, "Not enough funds freed");

        // Withdraw the freed funds from TokenVault
        tokenVault.withdraw(currency, freed - loss);
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
    function _harvestAndReport()
        internal
        override
        returns (uint256 _totalAssets)
    {
        // Calculate total assets including:
        // 1. Assets deposited in TokenVault (includes both free and locked in orders)
        // 2. Assets locked in existing orders (if any)
        // 3. Assets locked in positions (if any)

        uint256 vaultAssets = tokenVault.getDepositAmount(
            address(this),
            currency
        );
        uint256 lockedAssets = 0;

        OrderBook[] memory orderBooks = _getOrderBooks();

        for (uint256 i = 0; i < orderBooks.length; i++) {
            OrderBook memory orderBook = orderBooks[i];

            // Get existing orders for this maturity
            (uint256 totalExistingAmount, ) = _getActiveOrders(orderBook.id);

            uint256 positionInPV = _getPositionInPV(orderBook.maturity);

            if (positionInPV > 0) {
                // Store the last market unit price for this maturity that was used for present value calculations
                lastMarketUnitPrices[orderBook.maturity] = lendingMarket
                    .getMarketUnitPrice(orderBook.id);
            }

            lockedAssets += totalExistingAmount + positionInPV;
        }

        // Note: vaultAssets includes both free funds and funds locked in orders
        // No need to add deployedAssets separately as they are already counted in vaultAssets
        _totalAssets = vaultAssets + lockedAssets;
    }

    /*//////////////////////////////////////////////////////////////
                    OPTIONAL TO OVERRIDE BY STRATEGIST
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Gets the max amount of `asset` that can be withdrawn.
     * @dev Defaults to an unlimited amount for any address. But can
     * be overridden by strategists.
     *
     * This function will be called before any withdraw or redeem to enforce
     * any limits desired by the strategist. This can be used for illiquid
     * or sandwichable strategies.
     *
     *   EX:
     *       return asset.balanceOf(yieldSource);
     *
     * This does not need to take into account the `_owner`'s share balance
     * or conversion rates from shares to assets.
     *
     * @param . The address that is withdrawing from the strategy.
     * @return _totalAmount The available amount that can be withdrawn in terms of `asset`
     */
    function availableWithdrawLimit(
        address /*_owner*/
    ) public view override returns (uint256 _totalAmount) {
        _totalAmount =
            asset.balanceOf(address(this)) +
            tokenVault.getDepositAmount(address(this), currency);

        OrderBook[2] memory orderBooks;
        (orderBooks[0], orderBooks[1]) = _getTargetOrderBooks();

        for (uint256 i = 0; i < orderBooks.length; i++) {
            OrderBook memory orderBook = orderBooks[i];
            (
                uint256 totalExistingAmount,
                uint256 totalExistingAmountInFV
            ) = _getActiveOrders(orderBook.id);

            uint256 futureValue = _getPositionInFV(orderBook.maturity);

            if (futureValue == 0) {
                _totalAmount += totalExistingAmount;
                continue;
            }

            (
                ,
                uint256 filledAmount,
                ,
                ,
                ,
                bool isInsufficientDepositAmount
            ) = lendingMarketController.getOrderEstimationFromFV(
                    GetOrderEstimationFromFVParams({
                        ccy: currency,
                        maturity: orderBook.maturity,
                        user: address(this),
                        side: ProtocolTypes.Side.Borrow,
                        amountInFV: futureValue + totalExistingAmountInFV,
                        additionalDepositAmount: 0,
                        ignoreBorrowedAmount: true
                    })
                );

            require(
                !isInsufficientDepositAmount,
                "Insufficient deposit amount"
            );

            if (filledAmount == 0) {
                _totalAmount += totalExistingAmount;
                continue;
            }

            // Get order fee amount
            uint256 orderFeeRate = lendingMarket.getOrderFeeRate();
            uint256 extraOrderFeeAmount = calculateOrderFeeAmount(
                orderBook.maturity,
                totalExistingAmount,
                orderFeeRate
            );

            // In an actual withdraw, the placed orders will be cancelled before unwinding
            // and the funds will be returned to TokenVault.
            // However, this estimation is triggered without cancelling orders
            // so the filled amount is the amount that would be freed including the placed orders.
            // Therefore, we need to adjust the total amount to account for the order fee.
            _totalAmount += filledAmount + extraOrderFeeAmount;
        }
    }

    // /**
    //  * @notice Gets the max amount of `asset` that an address can deposit.
    //  * @dev Defaults to an unlimited amount for any address. But can
    //  * be overridden by strategists.
    //  *
    //  * This function will be called before any deposit or mints to enforce
    //  * any limits desired by the strategist. This can be used for either a
    //  * traditional deposit limit or for implementing a whitelist etc.
    //  *
    //  *   EX:
    //  *      if(isAllowed[_owner]) return super.availableDepositLimit(_owner);
    //  *
    //  * This does not need to take into account any conversion rates
    //  * from shares to assets. But should know that any non max uint256
    //  * amounts may be converted to shares. So it is recommended to keep
    //  * custom amounts low enough as not to cause overflow when multiplied
    //  * by `totalSupply`.
    //  *
    //  * @param . The address that is depositing into the strategy.
    //  * @return . The available amount the `_owner` can deposit in terms of `asset`
    //  *
    //  */
    // function availableDepositLimit(
    //     address _owner
    // ) public view override returns (uint256) {
    //     TODO: If desired Implement deposit limit logic and any needed state variables .

    //     EX:
    //         uint256 totalAssets = TokenizedStrategy.totalAssets();
    //         return totalAssets >= depositLimit ? 0 : depositLimit - totalAssets;
    // }

    function _tend(uint256 _totalIdle) internal override {
        _deployFunds(_totalIdle);
    }

    function _tendTrigger() internal view override returns (bool) {
        uint256 idleAssets = asset.balanceOf(address(this));

        if (idleAssets >= minTendAmount) {
            // If there are more than minTendAmount idle, we should tend
            return true;
        }

        uint256 depositAmount = tokenVault.getDepositAmount(
            address(this),
            currency
        );

        if (depositAmount != 0) {
            // If there are idle funds in TokenVault, we need to rebalance
            return true;
        }

        // Check if there are orders that need rebalancing
        OrderBook[2] memory orderBooks;
        // Get target order books for rebalancing
        (orderBooks[0], orderBooks[1]) = _getTargetOrderBooks();

        for (uint256 i = 0; i < orderBooks.length; i++) {
            OrderBook memory orderBook = orderBooks[i];

            // Skip if no valid order book
            if (orderBook.id == 0) {
                continue;
            }

            // Get existing orders for this maturity
            uint48[] memory orderIds = _getActiveOrderIds(orderBook.id);

            // Check if rebalancing is needed using the efficient version
            if (_needsRebalancing(orderBook, orderIds)) {
                return true;
            }
        }

        return false;
    }

    function _emergencyWithdraw(uint256 _amount) internal override {
        OrderBook[] memory orderBooks = _getOrderBooks();

        // First, unwind all positions
        for (uint256 i = 0; i < orderBooks.length; i++) {
            OrderBook memory orderBook = orderBooks[i];
            uint256 futureValue = _getPositionInFV(orderBook.maturity);

            if (futureValue != 0) {
                lendingMarketController.unwindPosition(
                    currency,
                    orderBook.maturity
                );
            }
        }

        // Then, cancel all orders
        for (uint256 i = 0; i < orderBooks.length; i++) {
            OrderBook memory orderBook = orderBooks[i];
            uint48[] memory orderIds = _getActiveOrderIds(orderBook.id);

            if (orderIds.length > 0) {
                _cancelOrdersByIds(orderBook.id, orderIds);
            }
        }

        // Withdraw all remaining funds from TokenVault
        uint256 vaultBalance = tokenVault.getDepositAmount(
            address(this),
            currency
        );

        if (vaultBalance == 0) {
            return;
        }

        uint256 withdrawAmount = _amount > vaultBalance
            ? vaultBalance
            : _amount;

        tokenVault.withdraw(currency, withdrawAmount);
    }

    /*//////////////////////////////////////////////////////////////
                        HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _getOrderBookId(
        uint256 maturity
    ) internal view returns (uint8 orderBookId) {
        orderBookId = lendingMarketController.getOrderBookId(
            currency,
            maturity
        );
        require(orderBookId != 0, "No order book for this maturity");
    }

    function _getTargetOrderBooks()
        internal
        view
        returns (
            OrderBook memory firstOrderBook,
            OrderBook memory secondOrderBook
        )
    {
        uint256[] memory maturities = lendingMarketController.getMaturities(
            currency
        );

        uint256 validCount = 0;
        for (uint256 i = 0; i < maturities.length; i++) {
            uint8 orderBookId = _getOrderBookId(maturities[i]);
            OrderBook memory orderBook = OrderBook({
                id: orderBookId,
                maturity: maturities[i]
            });

            if (_isValidMaturity(orderBook)) {
                if (validCount == 0) {
                    firstOrderBook = orderBook;
                } else if (validCount == 1) {
                    secondOrderBook = orderBook;
                    break;
                }
                validCount++;
            }
        }
    }

    function _getOrderBooks()
        internal
        view
        returns (OrderBook[] memory orderBooks)
    {
        uint256[] memory maturities = lendingMarketController.getMaturities(
            currency
        );
        orderBooks = new OrderBook[](maturities.length);

        for (uint256 i = 0; i < maturities.length; i++) {
            uint8 orderBookId = _getOrderBookId(maturities[i]);
            orderBooks[i] = OrderBook({
                id: orderBookId,
                maturity: maturities[i]
            });
        }
    }

    function _isValidMaturity(
        OrderBook memory orderBook
    ) internal view returns (bool) {
        // Check if maturity is in the future and not too close.
        // If maturity is within the exclusion period, skip it.
        if (orderBook.maturity <= block.timestamp + maturityExclusionPeriod)
            return false;

        return
            lendingMarket.isOpened(orderBook.id) &&
            !lendingMarket.isItayosePeriod(orderBook.id) &&
            !lendingMarket.isPreOrderPeriod(orderBook.id);
    }

    function _calculateOrderPrices(
        OrderBook memory orderBook
    ) internal view returns (uint256[3] memory prices) {
        uint256 marketPrice = lendingMarket.getMarketUnitPrice(orderBook.id);
        uint256 marketAPR = _unitPriceToAPR(marketPrice, orderBook.maturity);

        // Price 1: Market price or 7% minimum
        uint256 baseAPR = marketAPR < MIN_APR ? MIN_APR : marketAPR;
        prices[0] = _aprToUnitPrice(baseAPR, orderBook.maturity);

        // Price 2: Base APR + 0.05%
        prices[1] = _aprToUnitPrice(baseAPR + 5, orderBook.maturity);

        // Price 3: Base APR + 0.1%
        prices[2] = _aprToUnitPrice(baseAPR + 10, orderBook.maturity);
    }

    function _unitPriceToAPR(
        uint256 unitPrice,
        uint256 maturity
    ) internal view returns (uint256) {
        if (unitPrice == 0 || maturity <= block.timestamp) return 0;

        uint256 timeToMaturity = maturity - block.timestamp;
        return
            ((((BASIS_POINTS * BASIS_POINTS) / unitPrice) - BASIS_POINTS) *
                SECONDS_PER_YEAR) / timeToMaturity;
    }

    function _aprToUnitPrice(
        uint256 apr,
        uint256 maturity
    ) internal view returns (uint256) {
        if (maturity <= block.timestamp) return BASIS_POINTS;

        uint256 timeToMaturity = maturity - block.timestamp;
        uint256 rate = ((apr * timeToMaturity) / SECONDS_PER_YEAR) +
            BASIS_POINTS;

        // Ensure rate is greater than BASIS_POINTS to prevent unitPrice > BASIS_POINTS
        if (rate <= BASIS_POINTS) return BASIS_POINTS;

        uint256 unitPrice = (BASIS_POINTS * BASIS_POINTS) / rate;

        // Cap unitPrice to BASIS_POINTS to ensure it never exceeds basis points
        return unitPrice > BASIS_POINTS ? BASIS_POINTS : unitPrice;
    }

    function _createSingleOrder(
        uint256 maturity,
        uint256 amount,
        uint256 unitPrice
    ) internal {
        // No need to approve tokens since they're already in TokenVault
        bool success = lendingMarketController.executeOrder(
            currency,
            maturity,
            ProtocolTypes.Side.Lend,
            amount,
            unitPrice
        );

        require(success, "Order execution failed");
    }

    function _deployToMaturityWithRebalance(
        OrderBook memory orderBook,
        uint256 newAmount
    ) internal {
        uint48[] memory orderIds = _getActiveOrderIds(orderBook.id);

        if (newAmount == 0 && orderIds.length == 0) {
            return; // Nothing to do
        }

        uint256 existingAmount = 0;

        // Check if rebalancing is needed for existing orders
        // if (_needsRebalancing(orderBook, orderIds)) {
        // Cancel existing orders and get the freed amount
        existingAmount = _cancelOrdersByIds(orderBook.id, orderIds);
        // }

        // Combine new funds with rebalanced funds
        uint256 totalAmount = newAmount + existingAmount;

        if (totalAmount > 0) {
            _createOrders(
                orderBook,
                totalAmount,
                existingAmount > 0 ? new uint48[](0) : orderIds
            );
        }
    }

    function _getActiveOrderIds(
        uint8 orderBookId
    ) internal view returns (uint48[] memory activeOrderIds) {
        // Get all active order IDs for this strategy
        (activeOrderIds, ) = lendingMarket.getLendOrderIds(
            orderBookId,
            address(this)
        );
    }

    function _getActiveOrders(
        uint8 orderBookId
    ) internal view returns (uint256 totalAmount, uint256 totalAmountInFV) {
        uint48[] memory orderIds = _getActiveOrderIds(orderBookId);

        for (uint256 i = 0; i < orderIds.length; i++) {
            (, uint256 unitPrice, , , uint256 amount, , ) = lendingMarket
                .getOrder(orderBookId, orderIds[i]);

            totalAmount += amount;
            totalAmountInFV += (amount * BASIS_POINTS) / unitPrice;
        }
    }

    function _needsRebalancing(
        OrderBook memory orderBook,
        uint48[] memory orderIds
    ) internal view returns (bool) {
        if (orderIds.length == 0) return false;

        uint256 marketPrice = lendingMarket.getMarketUnitPrice(orderBook.id);
        uint256 marketAPR = _unitPriceToAPR(marketPrice, orderBook.maturity);

        // Find the lowest price among our orders
        uint256 hightestPrice = 0;
        for (uint256 i = 0; i < orderIds.length; i++) {
            (, uint256 unitPrice, , , uint256 amount, , ) = lendingMarket
                .getOrder(orderBook.id, orderIds[i]);
            if (amount > 0 && unitPrice > hightestPrice) {
                hightestPrice = unitPrice;
            }
        }

        if (hightestPrice == 0) {
            return false;
        }

        if (marketPrice >= hightestPrice && hightestPrice >= MAX_PRICE) {
            return false;
        }

        uint256 lowestAPR = _unitPriceToAPR(hightestPrice, orderBook.maturity);

        // Rebalance if the difference in abs is more than 0.25%
        return
            lowestAPR > marketAPR
                ? (lowestAPR - marketAPR > 25)
                : (marketAPR - lowestAPR > 25);
    }

    function _hasOrderAtPrice(
        OrderBook memory orderBook,
        uint256 unitPrice,
        uint48[] memory orderIds
    ) internal view returns (bool) {
        for (uint256 i = 0; i < orderIds.length; i++) {
            (, uint256 orderUnitPrice, , , uint256 amount, , ) = lendingMarket
                .getOrder(orderBook.id, orderIds[i]);
            if (amount > 0 && orderUnitPrice == unitPrice) {
                return true;
            }
        }
        return false;
    }

    function _createOrders(
        OrderBook memory orderBook,
        uint256 totalAmount,
        uint48[] memory existingOrderIds
    ) internal {
        if (totalAmount == 0) return;

        uint256[3] memory amounts;
        amounts[0] = (totalAmount * 40) / 100; // 40%
        amounts[1] = (totalAmount * 30) / 100; // 30%
        amounts[2] = totalAmount - amounts[0] - amounts[1]; // Remaining amount to avoid rounding errors

        uint256[3] memory unitPrices = _calculateOrderPrices(orderBook);

        // Create orders only if we don't already have orders at these exact prices
        for (uint256 i = 0; i < 3; i++) {
            if (
                amounts[i] > 0 &&
                !_hasOrderAtPrice(orderBook, unitPrices[i], existingOrderIds)
            ) {
                _createSingleOrder(
                    orderBook.maturity,
                    amounts[i],
                    unitPrices[i]
                );
            }
        }
    }

    // Optimized version that cancels specific order IDs
    function _cancelOrdersByIds(
        uint8 orderBookId,
        uint48[] memory orderIds
    ) internal returns (uint256 totalCancelled) {
        for (uint256 i = 0; i < orderIds.length; i++) {
            uint48 orderId = orderIds[i];

            // Get current order details before cancelling
            (, , uint256 maturity, , uint256 amount, , ) = lendingMarket
                .getOrder(orderBookId, orderId);

            if (amount > 0) {
                lendingMarketController.cancelOrder(
                    currency,
                    maturity,
                    orderId
                );
                totalCancelled += amount;
            }
        }
    }

    // Helper function for _freeFunds to cancel orders up to a specific amount
    function _cancelOrdersForAmountNeeded(
        OrderBook memory orderBook,
        uint256 amountNeeded
    ) internal returns (uint256 totalCancelled) {
        if (amountNeeded == 0) return 0;

        uint48[] memory orderIds = _getActiveOrderIds(orderBook.id);

        for (
            uint256 i = 0;
            i < orderIds.length && totalCancelled < amountNeeded;
            i++
        ) {
            uint48 orderId = orderIds[i];

            // Get current order details before cancelling
            (, , , , uint256 amount, , ) = lendingMarket.getOrder(
                orderBook.id,
                orderId
            );
            if (amount > 0) {
                bool success = lendingMarketController.cancelOrder(
                    currency,
                    orderBook.maturity,
                    orderId
                );

                if (success) {
                    // Order cancelled successfully, funds returned to TokenVault
                    totalCancelled += amount;
                }
                // If cancel fails, continue to next order
            }
        }
    }

    function _getPositionInPV(
        uint256 maturity
    ) internal view returns (uint256) {
        (int256 presentValue, ) = lendingMarketController.getPosition(
            currency,
            maturity,
            address(this)
        );

        // require(presentValue >= 0, "Borrowing position not allowed");

        return (uint256(presentValue));
    }

    function _getPositionInFV(
        uint256 maturity
    ) internal view returns (uint256) {
        (, int256 futureValue) = lendingMarketController.getPosition(
            currency,
            maturity,
            address(this)
        );

        // require(futureValue >= 0, "Borrowing position not allowed");

        return uint256(futureValue);
    }

    function calculateOrderFeeAmount(
        uint256 _maturity,
        uint256 _amount,
        uint256 _orderFeeRate
    ) public view returns (uint256 orderFeeAmount) {
        if (block.timestamp >= _maturity) return 0;

        uint256 duration = _maturity - block.timestamp;

        // NOTE: The formula is:
        // actualRate = feeRate * (duration / SECONDS_IN_YEAR)
        // orderFeeAmount = amount * actualRate
        orderFeeAmount =
            (_orderFeeRate * duration * _amount) /
            (SECONDS_PER_YEAR * BASIS_POINTS);
    }
}
