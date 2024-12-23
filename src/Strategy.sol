// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {BaseStrategy, ERC20} from "@tokenized-strategy/BaseStrategy.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {ITermRepoToken} from "./interfaces/term/ITermRepoToken.sol";
import {ITermRepoServicer} from "./interfaces/term/ITermRepoServicer.sol";
import {ITermController} from "./interfaces/term/ITermController.sol";
import {ITermVaultEvents} from "./interfaces/term/ITermVaultEvents.sol";
import {ITermAuctionOfferLocker} from "./interfaces/term/ITermAuctionOfferLocker.sol";
import {ITermDiscountRateAdapter} from "./interfaces/term/ITermDiscountRateAdapter.sol";
import {ITermAuction} from "./interfaces/term/ITermAuction.sol";
import {RepoTokenList, RepoTokenListData} from "./RepoTokenList.sol";
import {TermAuctionList, TermAuctionListData, PendingOffer} from "./TermAuctionList.sol";
import {RepoTokenUtils} from "./RepoTokenUtils.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

// Import interfaces for many popular DeFi projects, or add your own!
//import "../interfaces/<protocol>/<Interface>.sol";

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

contract Strategy is BaseStrategy, Pausable, AccessControl {
    using SafeERC20 for IERC20;
    using RepoTokenList for RepoTokenListData;
    using TermAuctionList for TermAuctionListData;

    /**
     * @notice Constructor to initialize the Strategy contract
     * @param _asset The address of the asset
     * @param _yearnVault The address of the Yearn vault
     * @param _discountRateAdapter The address of the discount rate adapter
     * @param _eventEmitter The address of the event emitter
     * @param _governorAddress The address of the governor
     * @param _termController The address of the term controller
     * @param _repoTokenConcentrationLimit The concentration limit for repoTokens
     * @param _timeToMaturityThreshold The time to maturity threshold
     * @param _requiredReserveRatio The required reserve ratio
     * @param _discountRateMarkup The discount rate markup
     */
    struct StrategyParams {
        address _asset;
        address _yearnVault;
        address _discountRateAdapter;
        address _eventEmitter;
        address _governorAddress;
        address _termController;
        uint256 _repoTokenConcentrationLimit;
        uint256 _timeToMaturityThreshold;
        uint256 _requiredReserveRatio;
        uint256 _discountRateMarkup;
    }

    struct StrategyState {
        address assetVault;
        address eventEmitter;
        address governorAddress;
        ITermController prevTermController;
        ITermController currTermController;
        ITermDiscountRateAdapter discountRateAdapter;
        uint256 timeToMaturityThreshold;
        uint256 requiredReserveRatio;
        uint256 discountRateMarkup;
        uint256 repoTokenConcentrationLimit;
    }

    // Custom errors
    error InvalidTermAuction(address auction);
    error TimeToMaturityAboveThreshold();
    error BalanceBelowRequiredReserveRatio();
    error InsufficientLiquidBalance(uint256 have, uint256 want);
    error RepoTokenConcentrationTooHigh(address repoToken);
    error RepoTokenBlacklisted(address repoToken);
    error DepositPaused();
    error AuctionNotOpen();
    error ZeroPurchaseTokenAmount();
    error OfferNotFound();

    bytes32 internal constant GOVERNOR_ROLE = keccak256("GOVERNOR_ROLE");

    // Immutable state variables
    ITermVaultEvents internal immutable TERM_VAULT_EVENT_EMITTER;
    uint256 internal immutable PURCHASE_TOKEN_PRECISION;
    IERC4626 internal immutable YEARN_VAULT;

    /// @notice State variables
    bool internal depositLock;
    address internal pendingGovernor;

    RepoTokenListData internal repoTokenListData;
    TermAuctionListData internal termAuctionListData;
    string internal tokenSymbol;

    StrategyState public strategyState;
    mapping(address => bool) public repoTokenBlacklist;

    modifier notBlacklisted(address repoToken) {
        if (repoTokenBlacklist[repoToken]) {
            revert RepoTokenBlacklisted(repoToken);
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                    MANAGEMENT FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Pause the contract
     */
    function pauseDeposit() external onlyRole(GOVERNOR_ROLE) {
        depositLock = true;
        TERM_VAULT_EVENT_EMITTER.emitDepositPaused();
    }

    /**
     * @notice Unpause the contract
     */
    function unpauseDeposit() external onlyRole(GOVERNOR_ROLE) {
        depositLock = false;
        TERM_VAULT_EVENT_EMITTER.emitDepositUnpaused();
    }

    /**
     * @notice Pause the contract
     */
    function pauseStrategy() external onlyRole(GOVERNOR_ROLE) {
        _pause();
        depositLock = true;
        //TERM_VAULT_EVENT_EMITTER.emitStrategyPaused();
    }

    /**
     * @notice Unpause the contract
     */
    function unpauseStrategy() external onlyRole(GOVERNOR_ROLE) {
        _unpause();
        depositLock = false;
        //TERM_VAULT_EVENT_EMITTER.emitStrategyUnpaused();
    }

    function setPendingGovernor(
        address newGovernor
    ) external onlyRole(GOVERNOR_ROLE) {
        require(newGovernor != address(0));
        pendingGovernor = newGovernor;
    }

    function acceptGovernor() external {
        require(msg.sender == pendingGovernor, "!pendingGovernor");
        _revokeRole(GOVERNOR_ROLE, strategyState.governorAddress);
        _grantRole(GOVERNOR_ROLE, pendingGovernor);
        strategyState.governorAddress = pendingGovernor;
        TERM_VAULT_EVENT_EMITTER.emitNewGovernor(pendingGovernor);
        pendingGovernor = address(0);
    }

    /**
     * @notice Set the term controller
     * @param newTermControllerAddr The address of the new term controller
     */
    function setTermController(
        address newTermControllerAddr
    ) external onlyRole(GOVERNOR_ROLE) {
        require(newTermControllerAddr != address(0));
        require(
            ITermController(newTermControllerAddr)
                .getProtocolReserveAddress() != address(0)
        );
        address currentIteration = repoTokenListData.head;
        while (currentIteration != address(0)) {
            if (!_isTermDeployed(currentIteration)) {
                revert RepoTokenList.InvalidRepoToken(currentIteration);
            }
            currentIteration = repoTokenListData.nodes[currentIteration].next;
        }
        address current = address(strategyState.currTermController);
        TERM_VAULT_EVENT_EMITTER.emitTermControllerUpdated(
            current,
            newTermControllerAddr
        );
        strategyState.prevTermController = ITermController(current);
        strategyState.currTermController = ITermController(
            newTermControllerAddr
        );
    }

    /**
     * @notice Set the discount rate adapter used to price repoTokens
     * @param newAdapter The address of the new discount rate adapter
     */
    function setDiscountRateAdapter(
        address newAdapter
    ) external onlyRole(GOVERNOR_ROLE) {
        ITermDiscountRateAdapter newDiscountRateAdapter = ITermDiscountRateAdapter(
                newAdapter
            );
        require(
            address(newDiscountRateAdapter.currTermController()) != address(0)
        );
        TERM_VAULT_EVENT_EMITTER.emitDiscountRateAdapterUpdated(
            address(strategyState.discountRateAdapter),
            newAdapter
        );
        strategyState.discountRateAdapter = newDiscountRateAdapter;
    }

    /**
     * @notice Set the weighted time to maturity cap
     * @param newTimeToMaturityThreshold The new weighted time to maturity cap
     */
    function setTimeToMaturityThreshold(
        uint256 newTimeToMaturityThreshold
    ) external onlyRole(GOVERNOR_ROLE) {
        TERM_VAULT_EVENT_EMITTER.emitTimeToMaturityThresholdUpdated(
            strategyState.timeToMaturityThreshold,
            newTimeToMaturityThreshold
        );
        strategyState.timeToMaturityThreshold = newTimeToMaturityThreshold;
    }

    /**
     * @notice Set the required reserve ratio
     * @dev This function can only be called by management
     * @param newRequiredReserveRatio The new required reserve ratio (in 1e18 precision)
     */
    function setRequiredReserveRatio(
        uint256 newRequiredReserveRatio
    ) external onlyRole(GOVERNOR_ROLE) {
        TERM_VAULT_EVENT_EMITTER.emitRequiredReserveRatioUpdated(
            strategyState.requiredReserveRatio,
            newRequiredReserveRatio
        );
        strategyState.requiredReserveRatio = newRequiredReserveRatio;
    }

    /**
     * @notice Set the repoToken concentration limit
     * @param newRepoTokenConcentrationLimit The new repoToken concentration limit
     */
    function setRepoTokenConcentrationLimit(
        uint256 newRepoTokenConcentrationLimit
    ) external onlyRole(GOVERNOR_ROLE) {
        TERM_VAULT_EVENT_EMITTER.emitRepoTokenConcentrationLimitUpdated(
            strategyState.repoTokenConcentrationLimit,
            newRepoTokenConcentrationLimit
        );
        strategyState
            .repoTokenConcentrationLimit = newRepoTokenConcentrationLimit;
    }

    /**
     * @notice Set the markup that the vault will receive in excess of the oracle rate
     * @param newDiscountRateMarkup The new auction rate markup
     */
    function setDiscountRateMarkup(
        uint256 newDiscountRateMarkup
    ) external onlyRole(GOVERNOR_ROLE) {
        TERM_VAULT_EVENT_EMITTER.emitDiscountRateMarkupUpdated(
            strategyState.discountRateMarkup,
            newDiscountRateMarkup
        );
        strategyState.discountRateMarkup = newDiscountRateMarkup;
    }
    /**
     * @notice Set the collateral token parameters
     * @param tokenAddr The address of the collateral token to be accepted
     * @param minCollateralRatio The minimum collateral ratio accepted by the strategy
     */
    function setCollateralTokenParams(
        address tokenAddr,
        uint256 minCollateralRatio
    ) external onlyRole(GOVERNOR_ROLE) {
        TERM_VAULT_EVENT_EMITTER.emitMinCollateralRatioUpdated(
            tokenAddr,
            minCollateralRatio
        );
        repoTokenListData.collateralTokenParams[tokenAddr] = minCollateralRatio;
    }

    function setRepoTokenBlacklist(
        address repoToken,
        bool blacklisted
    ) external onlyRole(GOVERNOR_ROLE) {
        TERM_VAULT_EVENT_EMITTER.emitRepoTokenBlacklistUpdated(
            repoToken,
            blacklisted
        );
        repoTokenBlacklist[repoToken] = blacklisted;
    }

    /*//////////////////////////////////////////////////////////////
                    VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function symbol() external view returns (string memory) {
        return tokenSymbol;
    }

    /**
     * @notice Calculates the total value of all assets managed by the strategy
     * @return The total asset value in the purchase token precision
     *
     * @dev This function aggregates the total liquid balance, the present value of all repoTokens,
     * and the present value of all pending offers to calculate the total asset value.
     */
    function totalAssetValue() external view returns (uint256) {
        return _totalAssetValue(_totalLiquidBalance());
    }

    /**
     * @notice Get the total liquid balance of the assets managed by the strategy
     * @return The total liquid balance in the purchase token precision
     *
     * @dev This function aggregates the balance of the underlying asset held directly by the strategy
     * and the balance of the asset held in the Yearn Vault to calculate the total liquid balance.
     */
    function totalLiquidBalance() external view returns (uint256) {
        return _totalLiquidBalance();
    }

    /**
     * @notice Calculate the liquid reserve ratio
     * @param liquidBalance The current liquid balance of the strategy
     * @return The liquid reserve ratio in 1e18 precision
     *
     * @dev This function calculates the ratio of liquid balance to total asset value.
     * It returns 0 if the total asset value is 0 to avoid division by zero.
     */
    function _liquidReserveRatio(
        uint256 liquidBalance
    ) internal view returns (uint256) {
        uint256 assetValue = _totalAssetValue(liquidBalance);
        if (assetValue == 0) return 0;
        return (liquidBalance * 1e18) / assetValue;
    }

    /**
     * @notice Get the current liquid reserve ratio of the strategy
     * @return The current liquid reserve ratio in 1e18 precision
     *
     * @dev This function calculates the liquid reserve ratio based on the current
     * total liquid balance of the strategy.
     */
    function liquidReserveRatio() external view returns (uint256) {
        return _liquidReserveRatio(_totalLiquidBalance());
    }

    /**
     * @notice Returns an array of addresses representing the repoTokens currently held by the strategy
     * @return address[] An array of addresses of the repoTokens held by the strategy
     *
     * @dev This function calls the `holdings` function from the `RepoTokenList` library to get the list
     * of repoTokens currently held in the `RepoTokenListData` structure.
     */
    function repoTokenHoldings() external view returns (address[] memory) {
        return repoTokenListData.holdings();
    }

    /**
     * @notice Get an array of pending offers submitted into Term auctions
     * @return bytes32[] An array of `bytes32` values representing the IDs of the pending offers
     *
     * @dev This function calls the `pendingOffers` function from the `TermAuctionList` library to get the list
     * of pending offers currently submitted into Term auctions from the `TermAuctionListData` structure.
     */
    function pendingOffers() external view returns (bytes32[] memory) {
        return termAuctionListData.pendingOffers();
    }

    /**
     * @notice Calculate the concentration ratio of a specific repoToken in the strategy
     * @param repoToken The address of the repoToken to calculate the concentration for
     * @return The concentration ratio of the repoToken in the strategy (in 1e18 precision)
     *
     * @dev This function computes the current concentration ratio of a specific repoToken
     * in the strategy's portfolio. It reverts if the repoToken address is zero. The calculation
     * is based on the current total asset value and does not consider any additional purchases
     * or removals of the repoToken.
     */
    function getRepoTokenConcentrationRatio(
        address repoToken
    ) external view returns (uint256) {
        if (repoToken == address(0)) {
            revert RepoTokenList.InvalidRepoToken(address(0));
        }
        return
            _getRepoTokenConcentrationRatio(
                repoToken,
                0,
                _totalAssetValue(_totalLiquidBalance()),
                0
            );
    }

    /**
     * @notice Simulates the weighted time to maturity for a specified repoToken and amount, including the impact on the entire strategy's holdings
     * @param repoToken The address of the repoToken to be simulated
     * @param amount The amount of the repoToken to be simulated
     * @return simulatedWeightedMaturity The simulated weighted time to maturity for the entire strategy
     * @return simulatedRepoTokenConcentrationRatio The concentration ratio of the repoToken in the strategy (in 1e18 precision)
     * @return simulatedLiquidityRatio The simulated liquidity ratio after the transaction
     *
     * @dev This function simulates the effects of a potential transaction on the strategy's key metrics.
     * It calculates the new weighted time to maturity and liquidity ratio, considering the specified
     * repoToken and amount. For existing repoTokens, use address(0) as the repoToken parameter.
     * The function performs various checks and calculations, including:
     * - Validating the repoToken (if not address(0))
     * - Calculating the present value of the transaction
     * - Estimating the impact on the strategy's liquid balance
     * - Computing the new weighted maturity and liquidity ratio
     */
    function simulateTransaction(
        address repoToken,
        uint256 amount
    )
        external
        view
        returns (
            uint256 simulatedWeightedMaturity,
            uint256 simulatedRepoTokenConcentrationRatio,
            uint256 simulatedLiquidityRatio
        )
    {
        // do not validate if we are simulating with existing repoTokens
        uint256 liquidBalance = _totalLiquidBalance();
        uint256 repoTokenAmountInBaseAssetPrecision;
        uint256 proceeds;
        if (repoToken != address(0)) {
            if (!_isTermDeployed(repoToken)) {
                revert RepoTokenList.InvalidRepoToken(repoToken);
            }

            (
                bool isRepoTokenValid,
                uint256 redemptionTimestamp
            ) = repoTokenListData.validateRepoToken(
                    ITermRepoToken(repoToken),
                    address(asset)
                );

            if (!isRepoTokenValid) {
                revert RepoTokenList.InvalidRepoToken(repoToken);
            }

            uint256 discountRate = strategyState
                .discountRateAdapter
                .getDiscountRate(repoToken);
            uint256 repoRedemptionHaircut = strategyState
                .discountRateAdapter
                .repoRedemptionHaircut(repoToken);
            repoTokenAmountInBaseAssetPrecision = RepoTokenUtils
                .getNormalizedRepoTokenAmount(
                    repoToken,
                    amount,
                    PURCHASE_TOKEN_PRECISION,
                    repoRedemptionHaircut
                );
            proceeds = RepoTokenUtils.calculatePresentValue(
                repoTokenAmountInBaseAssetPrecision,
                PURCHASE_TOKEN_PRECISION,
                redemptionTimestamp,
                discountRate + strategyState.discountRateMarkup
            );
        }

        simulatedWeightedMaturity = _calculateWeightedMaturity(
            repoToken,
            amount,
            liquidBalance - proceeds
        );

        if (repoToken != address(0)) {
            simulatedRepoTokenConcentrationRatio = _getRepoTokenConcentrationRatio(
                repoToken,
                repoTokenAmountInBaseAssetPrecision,
                _totalAssetValue(liquidBalance),
                proceeds
            );
        }

        uint256 assetValue = _totalAssetValue(liquidBalance);

        if (assetValue == 0) {
            simulatedLiquidityRatio = 0;
        } else {
            simulatedLiquidityRatio =
                ((liquidBalance - proceeds) * 10 ** 18) /
                assetValue;
        }
    }

    /**
     * @notice Calculates the present value of a specified repoToken based on its discount rate, redemption timestamp, and amount
     * @param repoToken The address of the repoToken
     * @param discountRate The discount rate to be used in the present value calculation
     * @param amount The amount of the repoToken to be discounted
     * @return uint256 The present value of the specified repoToken and amount
     *
     * @dev This function retrieves the redemption timestamp, calculates the repoToken precision,
     * normalizes the repoToken amount to base asset precision, and calculates the present value
     * using the provided discount rate and redemption timestamp.
     */
    function calculateRepoTokenPresentValue(
        address repoToken,
        uint256 discountRate,
        uint256 amount
    ) public view returns (uint256) {
        (uint256 redemptionTimestamp, , , ) = ITermRepoToken(repoToken)
            .config();
        uint256 repoTokenAmountInBaseAssetPrecision = RepoTokenUtils
            .getNormalizedRepoTokenAmount(
                repoToken,
                amount,
                PURCHASE_TOKEN_PRECISION,
                strategyState.discountRateAdapter.repoRedemptionHaircut(
                    repoToken
                )
            );
        return
            RepoTokenUtils.calculatePresentValue(
                repoTokenAmountInBaseAssetPrecision,
                PURCHASE_TOKEN_PRECISION,
                redemptionTimestamp,
                discountRate
            );
    }

    /**
     * @notice Calculates the present value of a specified repoToken held by the strategy
     * @param repoToken The address of the repoToken to value
     * @return uint256 The present value of the specified repoToken
     *
     * @dev This function calculates the present value of the specified repoToken from both
     * the `repoTokenListData` and `termAuctionListData` structures, then sums these values
     * to provide a comprehensive valuation.
     */
    function getRepoTokenHoldingValue(
        address repoToken
    ) public view returns (uint256) {
        uint256 repoTokenHoldingPV;
        if (repoTokenListData.discountRates[repoToken] != 0) {
            address tokenTermController;
            if (strategyState.currTermController.isTermDeployed(repoToken)) {
                tokenTermController = address(strategyState.currTermController);
            } else if (
                strategyState.prevTermController.isTermDeployed(repoToken)
            ) {
                tokenTermController = address(strategyState.prevTermController);
            }
            repoTokenHoldingPV = calculateRepoTokenPresentValue(
                repoToken,
                strategyState.discountRateAdapter.getDiscountRate(
                    tokenTermController,
                    repoToken
                ),
                ITermRepoToken(repoToken).balanceOf(address(this))
            );
        }
        return
            repoTokenHoldingPV +
            termAuctionListData.getPresentValue(
                repoTokenListData,
                strategyState.discountRateAdapter,
                PURCHASE_TOKEN_PRECISION,
                repoToken
            );
    }

    /*//////////////////////////////////////////////////////////////
                    INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Withdraw assets from the Yearn vault
     * @param amount The amount to withdraw
     */
    function _withdrawAsset(uint256 amount) private {
        YEARN_VAULT.withdraw(amount, address(this), address(this));
    }

    /**
     * @dev Retrieves the asset balance from the Yearn Vault
     * @return The balance of assets in the purchase token precision
     */
    function _assetBalance() private view returns (uint256) {
        return
            YEARN_VAULT.convertToAssets(YEARN_VAULT.balanceOf(address(this)));
    }

    /**
     * @notice Calculates the total liquid balance of the assets managed by the strategy
     * @return uint256 The total liquid balance of the assets
     *
     * @dev This function aggregates the balance of the underlying asset held directly by the strategy
     * and the balance of the asset held in the Yearn Vault to calculate the total liquid balance.
     */
    function _totalLiquidBalance() private view returns (uint256) {
        uint256 underlyingBalance = IERC20(asset).balanceOf(address(this));
        return _assetBalance() + underlyingBalance;
    }

    /**
     * @notice Calculates the total value of all assets managed by the strategy (internal function)
     * @return totalValue The total value of all assets
     *
     * @dev This function aggregates the total liquid balance, the present value of all repoTokens,
     * and the present value of all pending offers to calculate the total asset value.
     */
    function _totalAssetValue(
        uint256 liquidBalance
    ) internal view returns (uint256 totalValue) {
        return
            liquidBalance +
            repoTokenListData.getPresentValue(
                strategyState.discountRateAdapter,
                PURCHASE_TOKEN_PRECISION
            ) +
            termAuctionListData.getPresentValue(
                repoTokenListData,
                strategyState.discountRateAdapter,
                PURCHASE_TOKEN_PRECISION,
                address(0)
            );
    }

    /**
     * @notice Calculates the concentration ratio of a specific repoToken in the strategy
     * @param repoToken The address of the repoToken to calculate the concentration for
     * @param repoTokenAmountInBaseAssetPrecision The amount of the repoToken in base asset precision to be added
     * @param assetValue The current total asset value of the strategy
     * @param liquidBalanceToRemove The amount of liquid balance to be removed from the strategy
     * @return The concentration ratio of the repoToken in the strategy (in 1e18 precision)
     *
     * @dev This function computes the concentration ratio of a specific repoToken, considering both
     * existing holdings and a potential new addition. It adjusts the total asset value, normalizes
     * values to 1e18 precision, and handles the case where total asset value might be zero.
     */
    function _getRepoTokenConcentrationRatio(
        address repoToken,
        uint256 repoTokenAmountInBaseAssetPrecision,
        uint256 assetValue,
        uint256 liquidBalanceToRemove
    ) private view returns (uint256) {
        // Retrieve the current value of the repoToken held by the strategy and add the new repoToken amount
        uint256 repoTokenValue = getRepoTokenHoldingValue(repoToken) +
            repoTokenAmountInBaseAssetPrecision;

        // Retrieve the total asset value of the strategy and adjust it for the new repoToken amount and liquid balance to be removed
        uint256 adjustedTotalAssetValue = assetValue +
            repoTokenAmountInBaseAssetPrecision -
            liquidBalanceToRemove;

        // Normalize the repoToken value and total asset value to 1e18 precision
        repoTokenValue = (repoTokenValue * 1e18) / PURCHASE_TOKEN_PRECISION;
        adjustedTotalAssetValue =
            (adjustedTotalAssetValue * 1e18) /
            PURCHASE_TOKEN_PRECISION;

        // Calculate the repoToken concentration
        return
            adjustedTotalAssetValue == 0
                ? 0
                : (repoTokenValue * 1e18) / adjustedTotalAssetValue;
    }

    /**
     * @notice Validate the concentration of a repoToken against the strategy's limit
     * @param repoToken The address of the repoToken to validate
     * @param repoTokenAmountInBaseAssetPrecision The amount of the repoToken in base asset precision
     * @param assetValue The current total asset value of the strategy
     * @param liquidBalanceToRemove The amount of liquid balance to be removed from the strategy
     *
     * @dev This function calculates the concentration ratio of the specified repoToken
     * and compares it against the predefined concentration limit. It reverts with a
     * RepoTokenConcentrationTooHigh error if the concentration exceeds the limit.
     */
    function _validateRepoTokenConcentration(
        address repoToken,
        uint256 repoTokenAmountInBaseAssetPrecision,
        uint256 assetValue,
        uint256 liquidBalanceToRemove
    ) private view {
        uint256 repoTokenConcentration = _getRepoTokenConcentrationRatio(
            repoToken,
            repoTokenAmountInBaseAssetPrecision,
            assetValue,
            liquidBalanceToRemove
        );

        // Check if the repoToken concentration exceeds the predefined limit
        if (
            repoTokenConcentration > strategyState.repoTokenConcentrationLimit
        ) {
            revert RepoTokenConcentrationTooHigh(repoToken);
        }
    }

    /**
     * @notice Calculates the weighted time to maturity for the strategy's holdings, including the impact of a specified repoToken and amount
     * @param repoToken The address of the repoToken (optional)
     * @param repoTokenAmount The amount of the repoToken to be included in the calculation
     * @param liquidBalance The liquid balance of the strategy
     * @return uint256 The weighted time to maturity in seconds for the entire strategy, including the specified repoToken and amount
     *
     * @dev This function aggregates the cumulative weighted time to maturity and the cumulative amount of both existing repoTokens
     * and offers, then calculates the weighted time to maturity for the entire strategy. It considers both repoTokens and auction offers.
     * The `repoToken` and `repoTokenAmount` parameters are optional and provide flexibility to adjust the calculations to include
     * the provided repoToken amount. If `repoToken` is set to `address(0)` or `repoTokenAmount` is `0`, the function calculates
     * the cumulative data without specific token adjustments.
     */
    function _calculateWeightedMaturity(
        address repoToken,
        uint256 repoTokenAmount,
        uint256 liquidBalance
    ) private view returns (uint256) {
        // Initialize cumulative weighted time to maturity and cumulative amount
        uint256 cumulativeWeightedTimeToMaturity; // in seconds
        uint256 cumulativeAmount; // in purchase token precision

        // Get cumulative data from repoToken list
        (
            uint256 cumulativeRepoTokenWeightedTimeToMaturity,
            uint256 cumulativeRepoTokenAmount,
            bool foundInRepoTokenList
        ) = repoTokenListData.getCumulativeRepoTokenData(
                strategyState.discountRateAdapter,
                repoToken,
                repoTokenAmount,
                PURCHASE_TOKEN_PRECISION
            );

        // Accumulate repoToken data
        cumulativeWeightedTimeToMaturity += cumulativeRepoTokenWeightedTimeToMaturity;
        cumulativeAmount += cumulativeRepoTokenAmount;

        (
            uint256 cumulativeOfferWeightedTimeToMaturity,
            uint256 cumulativeOfferAmount,
            bool foundInOfferList
        ) = termAuctionListData.getCumulativeOfferData(
                repoTokenListData,
                strategyState.discountRateAdapter,
                repoToken,
                repoTokenAmount,
                PURCHASE_TOKEN_PRECISION
            );

        // Accumulate offer data
        cumulativeWeightedTimeToMaturity += cumulativeOfferWeightedTimeToMaturity;
        cumulativeAmount += cumulativeOfferAmount;

        if (
            !foundInRepoTokenList &&
            !foundInOfferList &&
            repoToken != address(0)
        ) {
            uint256 repoRedemptionHaircut = strategyState
                .discountRateAdapter
                .repoRedemptionHaircut(repoToken);
            uint256 repoTokenAmountInBaseAssetPrecision = RepoTokenUtils
                .getNormalizedRepoTokenAmount(
                    repoToken,
                    repoTokenAmount,
                    PURCHASE_TOKEN_PRECISION,
                    repoRedemptionHaircut
                );

            cumulativeAmount += repoTokenAmountInBaseAssetPrecision;
            cumulativeWeightedTimeToMaturity += RepoTokenList
                .getRepoTokenWeightedTimeToMaturity(
                    repoToken,
                    repoTokenAmountInBaseAssetPrecision
                );
        }

        // Avoid division by zero
        if (cumulativeAmount == 0 && liquidBalance == 0) {
            return 0;
        }

        // Calculate and return weighted time to maturity
        // time * purchaseTokenPrecision / purchaseTokenPrecision
        return
            cumulativeWeightedTimeToMaturity /
            (cumulativeAmount + liquidBalance);
    }

    /**
     * @notice Checks if a term contract is marked as deployed in either the current or previous term controller
     * @param termContract The address of the term contract to check
     * @return bool True if the term contract is deployed, false otherwise
     *
     * @dev This function first checks the current term controller, then the previous one if necessary.
     * It handles cases where either controller might be unset (address(0)).
     */
    function _isTermDeployed(address termContract) private view returns (bool) {
        ITermController currTermController = strategyState.currTermController;
        ITermController prevTermController = strategyState.prevTermController;
        if (
            address(currTermController) != address(0) &&
            currTermController.isTermDeployed(termContract)
        ) {
            return true;
        }
        if (
            address(prevTermController) != address(0) &&
            prevTermController.isTermDeployed(termContract)
        ) {
            return true;
        }
        return false;
    }

    /**
     * @notice Rebalances the strategy's assets by sweeping assets and redeeming matured repoTokens
     * @param liquidAmountRequired The amount of liquid assets required to be maintained by the strategy
     *
     * @dev This function removes completed auction offers, redeems matured repoTokens, and adjusts the underlying
     * balance to maintain the required liquidity. It ensures that the strategy has sufficient liquid assets while
     * optimizing asset allocation.
     */
    function _redeemRepoTokens(uint256 liquidAmountRequired) private {
        // Remove completed auction offers
        termAuctionListData.removeCompleted(
            repoTokenListData,
            strategyState.discountRateAdapter,
            address(asset)
        );

        // Remove and redeem matured repoTokens
        repoTokenListData.removeAndRedeemMaturedTokens();

        uint256 liquidity = IERC20(asset).balanceOf(address(this));

        // Deposit excess underlying balance into Yearn Vault
        if (liquidity > liquidAmountRequired) {
            unchecked {
                YEARN_VAULT.deposit(
                    liquidity - liquidAmountRequired,
                    address(this)
                );
            }
            // Withdraw shortfall from Yearn Vault to meet required liquidity
        } else if (liquidity < liquidAmountRequired) {
            unchecked {
                _withdrawAsset(liquidAmountRequired - liquidity);
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                    STRATEGIST FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Validates a term auction and repo token, and retrieves the associated offer locker
     * @param termAuction The term auction contract to validate
     * @param repoToken The repo token address to validate
     * @return ITermAuctionOfferLocker The offer locker associated with the validated term auction
     *
     * @dev This function performs several validation steps: verifying term auction and repo token deployment,
     * matching repo token to auction's term repo ID, validating repo token against strategy requirements,
     * and ensuring the auction is open. It reverts with specific error messages on validation failures.
     */
    function _validateAndGetOfferLocker(
        ITermAuction termAuction,
        address repoToken
    ) private view returns (ITermAuctionOfferLocker) {
        // Verify that the term auction and repo token are valid and deployed by term
        if (!_isTermDeployed(address(termAuction))) {
            revert InvalidTermAuction(address(termAuction));
        }
        if (!_isTermDeployed(repoToken)) {
            revert RepoTokenList.InvalidRepoToken(repoToken);
        }

        if (
            termAuction.termRepoId() != ITermRepoToken(repoToken).termRepoId()
        ) {
            revert RepoTokenList.InvalidRepoToken(repoToken);
        }

        // Validate purchase token, min collateral ratio and insert the repoToken if necessary
        (bool isValid, ) = repoTokenListData.validateRepoToken(
            ITermRepoToken(repoToken),
            address(asset)
        );

        if (!isValid) {
            revert RepoTokenList.InvalidRepoToken(repoToken);
        }

        // Prepare and submit the offer
        ITermAuctionOfferLocker offerLocker = ITermAuctionOfferLocker(
            termAuction.termAuctionOfferLocker()
        );
        if (
            block.timestamp <= offerLocker.auctionStartTime() ||
            block.timestamp >= offerLocker.revealTime()
        ) {
            revert AuctionNotOpen();
        }

        return offerLocker;
    }

    /**
     * @notice Submits an offer into a term auction for a specified repoToken
     * @param termAuction The address of the term auction
     * @param repoToken The address of the repoToken
     * @param idHash The hash of the offer ID
     * @param offerPriceHash The hash of the offer price
     * @param purchaseTokenAmount The amount of purchase tokens being offered
     * @return offerIds An array of offer IDs for the submitted offers
     *
     * @dev This function validates the underlying repoToken, checks concentration limits, ensures the auction is open,
     * and rebalances liquidity to support the offer submission. It handles both new offers and edits to existing offers.
     */
    function submitAuctionOffer(
        ITermAuction termAuction,
        address repoToken,
        bytes32 idHash,
        bytes32 offerPriceHash,
        uint256 purchaseTokenAmount
    )
        external
        whenNotPaused
        notBlacklisted(repoToken)
        onlyManagement
        returns (bytes32[] memory offerIds)
    {
        if (purchaseTokenAmount == 0) {
            revert ZeroPurchaseTokenAmount();
        }

        ITermAuctionOfferLocker offerLocker = _validateAndGetOfferLocker(
            termAuction,
            repoToken
        );

        // Sweep assets, redeem matured repoTokens and ensure liquid balances up to date
        _redeemRepoTokens(0);

        uint256 newOfferAmount = purchaseTokenAmount;
        uint256 currentOfferAmount = termAuctionListData
            .offers[idHash]
            .offerAmount;

        // Submit the offer and lock it in the auction
        ITermAuctionOfferLocker.TermAuctionOfferSubmission memory offer;
        offer.id = idHash;
        offer.offeror = address(this);
        offer.offerPriceHash = offerPriceHash;
        offer.amount = purchaseTokenAmount;
        offer.purchaseToken = address(asset);

        // InsufficientLiquidBalance checked inside _submitOffer
        offerIds = _submitOffer(
            termAuction,
            offerLocker,
            offer,
            repoToken,
            newOfferAmount,
            currentOfferAmount
        );

        // Retrieve the total liquid balance
        uint256 liquidBalance = _totalLiquidBalance();
        uint256 totalAssetValue = _totalAssetValue(liquidBalance);
        require(totalAssetValue > 0);
        uint256 liquidReserveRatio = (liquidBalance * 1e18) / totalAssetValue; // NOTE: we require totalAssetValue > 0 above

        // Check that new offer does not violate reserve ratio constraint
        if (liquidReserveRatio < strategyState.requiredReserveRatio) {
            revert BalanceBelowRequiredReserveRatio();
        }

        // Calculate the resulting weighted time to maturity
        // Passing in 0 adjustment because offer and balance already updated
        uint256 resultingWeightedTimeToMaturity = _calculateWeightedMaturity(
            address(0),
            0,
            liquidBalance
        );

        // Check if the resulting weighted time to maturity exceeds the threshold
        if (
            resultingWeightedTimeToMaturity >
            strategyState.timeToMaturityThreshold
        ) {
            revert TimeToMaturityAboveThreshold();
        }

        // Passing in 0 amount and 0 liquid balance adjustment because offer and balance already updated
        _validateRepoTokenConcentration(repoToken, 0, totalAssetValue, 0);
    }

    /**
     * @dev Submits an offer to a term auction and locks it using the offer locker.
     * @param auction The term auction contract
     * @param offerLocker The offer locker contract
     * @param offer The offer details
     * @param repoToken The address of the repoToken
     * @param newOfferAmount The amount of the new offer
     * @param currentOfferAmount The amount of the current offer, if it exists
     * @return offerIds An array of offer IDs for the submitted offers
     */
    function _submitOffer(
        ITermAuction auction,
        ITermAuctionOfferLocker offerLocker,
        ITermAuctionOfferLocker.TermAuctionOfferSubmission memory offer,
        address repoToken,
        uint256 newOfferAmount,
        uint256 currentOfferAmount
    ) private returns (bytes32[] memory offerIds) {
        // Retrieve the repo servicer contract
        ITermRepoServicer repoServicer = ITermRepoServicer(
            offerLocker.termRepoServicer()
        );

        // Prepare the offer submission details
        ITermAuctionOfferLocker.TermAuctionOfferSubmission[]
            memory offerSubmissions = new ITermAuctionOfferLocker.TermAuctionOfferSubmission[](
                1
            );
        offerSubmissions[0] = offer;

        // Handle additional asset withdrawal if the new offer amount is greater than the current amount
        if (newOfferAmount > currentOfferAmount) {
            uint256 offerDebit;
            unchecked {
                // checked above
                offerDebit = newOfferAmount - currentOfferAmount;
            }

            uint256 liquidBalance = _totalLiquidBalance();
            if (liquidBalance < offerDebit) {
                revert InsufficientLiquidBalance(liquidBalance, offerDebit);
            }

            _withdrawAsset(offerDebit);
            IERC20(asset).safeApprove(
                address(repoServicer.termRepoLocker()),
                offerDebit
            );
        }

        // Submit the offer and get the offer IDs
        offerIds = offerLocker.lockOffers(offerSubmissions);

        if (offerIds.length == 0) {
            revert OfferNotFound();
        }

        // Update the pending offers list
        if (currentOfferAmount == 0) {
            // new offer
            termAuctionListData.insertPending(
                offerIds[0],
                PendingOffer({
                    repoToken: repoToken,
                    offerAmount: offer.amount,
                    termAuction: auction,
                    offerLocker: offerLocker
                })
            );
        } else {
            // Edit offer, overwrite existing
            PendingOffer storage pendingOffer = termAuctionListData.offers[
                offerIds[0]
            ];
            pendingOffer.offerAmount = offer.amount;
        }

        if (newOfferAmount < currentOfferAmount) {
            YEARN_VAULT.deposit(
                IERC20(asset).balanceOf(address(this)),
                address(this)
            );
        }
    }

    /**
     * @dev Removes specified offers from a term auction and performs related cleanup.
     * @param termAuction The address of the term auction from which offers will be deleted.
     * @param offerIds An array of offer IDs to be deleted.
     */
    function deleteAuctionOffers(
        address termAuction,
        bytes32[] calldata offerIds
    ) external onlyManagement {
        // Validate if the term auction is deployed by term
        if (!_isTermDeployed(termAuction)) {
            revert InvalidTermAuction(termAuction);
        }

        // Retrieve the auction and offer locker contracts
        ITermAuction auction = ITermAuction(termAuction);
        ITermAuctionOfferLocker offerLocker = ITermAuctionOfferLocker(
            auction.termAuctionOfferLocker()
        );

        // Unlock the specified offers
        offerLocker.unlockOffers(offerIds);

        // Update the term auction list data and remove completed offers
        termAuctionListData.removeCompleted(
            repoTokenListData,
            strategyState.discountRateAdapter,
            address(asset)
        );

        // Sweep any remaining assets and redeem repoTokens
        _redeemRepoTokens(0);
    }

    /**
     * @notice Required for post-processing after auction clos
     */
    function auctionClosed() external {
        _redeemRepoTokens(0);
    }

    /*//////////////////////////////////////////////////////////////
                    PUBLIC FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Allows the sale of a specified amount of a repoToken in exchange for assets.
     * @param repoToken The address of the repoToken to be sold.
     * @param repoTokenAmount The amount of the repoToken to be sold.
     */
    function sellRepoToken(
        address repoToken,
        uint256 repoTokenAmount
    ) external whenNotPaused notBlacklisted(repoToken) {
        // Ensure the amount of repoTokens to sell is greater than zero
        require(repoTokenAmount > 0);

        // Make sure repo token is valid and deployed by Term
        if (!_isTermDeployed(repoToken)) {
            revert RepoTokenList.InvalidRepoToken(repoToken);
        }

        // Validate and insert the repoToken into the list, retrieve auction rate and redemption timestamp
        (bool isRepoTokenValid, uint256 redemptionTimestamp) = repoTokenListData
            .validateAndInsertRepoToken(
                ITermRepoToken(repoToken),
                strategyState.discountRateAdapter,
                address(asset)
            );

        if (!isRepoTokenValid) {
            revert RepoTokenList.InvalidRepoToken(repoToken);
        }

        // Sweep assets and redeem repoTokens, if needed
        _redeemRepoTokens(0);

        // Retrieve total asset value and liquid balance and ensure they are greater than zero
        uint256 liquidBalance = _totalLiquidBalance();
        require(liquidBalance > 0);
        uint256 totalAssetValue = _totalAssetValue(liquidBalance);
        require(totalAssetValue > 0);

        uint256 discountRate = strategyState
            .discountRateAdapter
            .getDiscountRate(repoToken);

        // Calculate the repoToken amount in base asset precision
        uint256 repoTokenAmountInBaseAssetPrecision = RepoTokenUtils
            .getNormalizedRepoTokenAmount(
                repoToken,
                repoTokenAmount,
                PURCHASE_TOKEN_PRECISION,
                strategyState.discountRateAdapter.repoRedemptionHaircut(
                    repoToken
                )
            );

        // Calculate the proceeds from selling the repoToken
        uint256 proceeds = RepoTokenUtils.calculatePresentValue(
            repoTokenAmountInBaseAssetPrecision,
            PURCHASE_TOKEN_PRECISION,
            redemptionTimestamp,
            discountRate + strategyState.discountRateMarkup
        );

        // Ensure the liquid balance is sufficient to cover the proceeds
        if (liquidBalance < proceeds) {
            revert InsufficientLiquidBalance(liquidBalance, proceeds);
        }

        // Calculate resulting time to maturity after the sale and ensure it doesn't exceed the threshold
        uint256 resultingTimeToMaturity = _calculateWeightedMaturity(
            repoToken,
            repoTokenAmount,
            liquidBalance - proceeds
        );
        if (resultingTimeToMaturity > strategyState.timeToMaturityThreshold) {
            revert TimeToMaturityAboveThreshold();
        }

        // Ensure the remaining liquid balance is above the liquidity threshold
        uint256 newLiquidReserveRatio = ((liquidBalance - proceeds) * 1e18) /
            totalAssetValue; // NOTE: we require totalAssetValue > 0 above
        if (newLiquidReserveRatio < strategyState.requiredReserveRatio) {
            revert BalanceBelowRequiredReserveRatio();
        }

        // Validate resulting repoToken concentration to ensure it meets requirements
        _validateRepoTokenConcentration(
            repoToken,
            repoTokenAmountInBaseAssetPrecision,
            totalAssetValue,
            proceeds
        );

        // withdraw from underlying vault
        _withdrawAsset(proceeds);

        // Transfer repoTokens from the sender to the contract
        IERC20(repoToken).safeTransferFrom(
            msg.sender,
            address(this),
            repoTokenAmount
        );

        // Transfer the proceeds in assets to the sender
        IERC20(asset).safeTransfer(msg.sender, proceeds);
    }

    /**
     * @notice Constructor to initialize the Strategy contract
     * @param _name The name of the strategy
    
     */
    constructor(
        string memory _name,
        string memory _symbol,
        StrategyParams memory _params
    ) BaseStrategy(_params._asset, _name) {
        YEARN_VAULT = IERC4626(_params._yearnVault);
        TERM_VAULT_EVENT_EMITTER = ITermVaultEvents(_params._eventEmitter);
        PURCHASE_TOKEN_PRECISION = 10 ** ERC20(asset).decimals();

        IERC20(_params._asset).safeApprove(
            _params._yearnVault,
            type(uint256).max
        );
        tokenSymbol = _symbol;

        strategyState = StrategyState({
            assetVault: address(YEARN_VAULT),
            eventEmitter: address(TERM_VAULT_EVENT_EMITTER),
            governorAddress: _params._governorAddress,
            prevTermController: ITermController(address(0)),
            currTermController: ITermController(_params._termController),
            discountRateAdapter: ITermDiscountRateAdapter(
                _params._discountRateAdapter
            ),
            timeToMaturityThreshold: _params._timeToMaturityThreshold,
            requiredReserveRatio: _params._requiredReserveRatio,
            discountRateMarkup: _params._discountRateMarkup,
            repoTokenConcentrationLimit: _params._repoTokenConcentrationLimit
        });

        _grantRole(GOVERNOR_ROLE, _params._governorAddress);
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
    function _deployFunds(uint256 _amount) internal override whenNotPaused {
        if (depositLock) {
            revert DepositPaused();
        }

        _redeemRepoTokens(0);
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
    function _freeFunds(uint256 _amount) internal override whenNotPaused {
        _redeemRepoTokens(_amount);
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
        whenNotPaused
        returns (uint256 _totalAssets)
    {
        _redeemRepoTokens(0);
        return _totalAssetValue(_totalLiquidBalance());
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
     * @return . The available amount that can be withdrawn in terms of `asset`
     */
    function availableWithdrawLimit(
        address /*_owner*/
    ) public view override returns (uint256) {
        return _totalLiquidBalance();
    }

    /**
     * @dev Optional function for strategist to override that can
     *  be called in between reports.
     *
     * If '_tend' is used tendTrigger() will also need to be overridden.
     *
     * This call can only be called by a permissioned role so may be
     * through protected relays.
     *
     * This can be used to harvest and compound rewards, deposit idle funds,
     * perform needed position maintenance or anything else that doesn't need
     * a full report for.
     *
     *   EX: A strategy that can not deposit funds without getting
     *       sandwiched can use the tend when a certain threshold
     *       of idle to totalAssets has been reached.
     *
     * This will have no effect on PPS of the strategy till report() is called.
     *
     * @param _totalIdle The current amount of idle funds that are available to deploy.
     *
    function _tend(uint256 _totalIdle) internal override {}
    */

    /**
     * @dev Optional trigger to override if tend() will be used by the strategy.
     * This must be implemented if the strategy hopes to invoke _tend().
     *
     * @return . Should return true if tend() should be called by keeper or false if not.
     *
    function _tendTrigger() internal view override returns (bool) {}
    */

    /**
     * @dev Optional function for a strategist to override that will
     * allow management to manually withdraw deployed funds from the
     * yield source if a strategy is shutdown.
     *
     * This should attempt to free `_amount`, noting that `_amount` may
     * be more than is currently deployed.
     *
     * NOTE: This will not realize any profits or losses. A separate
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
        EX:
            _amount = min(_amount, aToken.balanceOf(address(this)));
            _freeFunds(_amount);
    }
    */
}
