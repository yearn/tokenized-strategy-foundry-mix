pragma solidity ^0.8.18;

import "forge-std/console2.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import {MockTermRepoToken} from "./mocks/MockTermRepoToken.sol";
import {MockTermAuction} from "./mocks/MockTermAuction.sol";
import {MockUSDC} from "./mocks/MockUSDC.sol";
import {Setup, ERC20, IStrategyInterface} from "./utils/Setup.sol";
import {Strategy} from "../Strategy.sol";

contract TestUSDCSubmitOffer is Setup {
    uint256 internal constant TEST_REPO_TOKEN_RATE = 0.05e18;

    MockUSDC internal mockUSDC;
    ERC20Mock internal mockCollateral;
    MockTermRepoToken internal repoToken1Week;
    MockTermAuction internal repoToken1WeekAuction;
    Strategy internal termStrategy;
    StrategySnapshot internal initialState;

    function setUp() public override {
        mockUSDC = new MockUSDC();
        mockCollateral = new ERC20Mock();

        _setUp(ERC20(address(mockUSDC)));

        repoToken1Week = new MockTermRepoToken(
            bytes32("test repo token 1"),
            address(mockUSDC),
            address(mockCollateral),
            1e18,
            1 weeks
        );
        termController.setOracleRate(
            MockTermRepoToken(repoToken1Week).termRepoId(),
            TEST_REPO_TOKEN_RATE
        );

        termStrategy = Strategy(address(strategy));

        repoToken1WeekAuction = new MockTermAuction(repoToken1Week);

        vm.startPrank(governor);
        termStrategy.setCollateralTokenParams(address(mockCollateral), 0.5e18);
        termStrategy.setTimeToMaturityThreshold(3 weeks);
        termStrategy.setRepoTokenConcentrationLimit(1e18);
        termStrategy.setRequiredReserveRatio(0);
        termStrategy.setDiscountRateMarkup(0);
        vm.stopPrank();

        // start with some initial funds
        mockUSDC.mint(address(strategy), 100e6);

        initialState.totalAssetValue = termStrategy.totalAssetValue();
        initialState.totalLiquidBalance = termStrategy.totalLiquidBalance();
    }

    function _submitOffer(
        bytes32 idHash,
        uint256 offerAmount
    ) private returns (bytes32) {
        // test: only management can submit offers
        vm.expectRevert("!management");
        bytes32[] memory offerIds = termStrategy.submitAuctionOffer(
            repoToken1WeekAuction,
            address(repoToken1Week),
            idHash,
            bytes32("test price"),
            offerAmount
        );

        vm.prank(management);
        offerIds = termStrategy.submitAuctionOffer(
            repoToken1WeekAuction,
            address(repoToken1Week),
            idHash,
            bytes32("test price"),
            offerAmount
        );

        assertEq(offerIds.length, 1);

        return offerIds[0];
    }

    function testSubmitOffer() public {
        _submitOffer(bytes32("offer id hash 1"), 1e6);

        assertEq(
            termStrategy.totalLiquidBalance(),
            initialState.totalLiquidBalance - 1e6
        );
        // test: totalAssetValue = total liquid balance + pending offer amount
        assertEq(
            termStrategy.totalAssetValue(),
            termStrategy.totalLiquidBalance() + 1e6
        );
    }

    function testEditOffer() public {
        bytes32 idHash1 = bytes32("offer id hash 1");
        bytes32 offerId1 = _submitOffer(idHash1, 1e6);

        // TODO: fuzz this
        uint256 offerAmount = 4e6;

        vm.prank(management);
        bytes32[] memory offerIds = termStrategy.submitAuctionOffer(
            repoToken1WeekAuction,
            address(repoToken1Week),
            offerId1,
            bytes32("test price"),
            offerAmount
        );

        assertEq(
            termStrategy.totalLiquidBalance(),
            initialState.totalLiquidBalance - offerAmount
        );
        // test: totalAssetValue = total liquid balance + pending offer amount
        assertEq(
            termStrategy.totalAssetValue(),
            termStrategy.totalLiquidBalance() + offerAmount
        );
    }

    function testEditOfferWithConcentrationLimit() public {
        bytes32 idHash1 = bytes32("offer id hash 1");

        vm.prank(governor);
        termStrategy.setRepoTokenConcentrationLimit(0.5e18);

        // 50% concentration
        bytes32 offerId1 = _submitOffer(idHash1, 50e6);

        // 60% concentration should fail (> 50%)
        vm.expectRevert(
            abi.encodeWithSelector(
                Strategy.RepoTokenConcentrationTooHigh.selector,
                address(repoToken1Week)
            )
        );
        vm.prank(management);
        bytes32[] memory offerIds = termStrategy.submitAuctionOffer(
            repoToken1WeekAuction,
            address(repoToken1Week),
            offerId1,
            bytes32("test price"),
            60e6
        );

        // 40% concentration should pass
        vm.prank(management);
        offerIds = termStrategy.submitAuctionOffer(
            repoToken1WeekAuction,
            address(repoToken1Week),
            offerId1,
            bytes32("test price"),
            40e6
        );
    }

    function testDeleteOffers() public {
        bytes32 offerId1 = _submitOffer(bytes32("offer id hash 1"), 1e6);

        bytes32[] memory offerIds = new bytes32[](1);

        offerIds[0] = offerId1;

        vm.expectRevert("!management");
        termStrategy.deleteAuctionOffers(
            address(repoToken1WeekAuction),
            offerIds
        );

        vm.prank(management);
        termStrategy.deleteAuctionOffers(
            address(repoToken1WeekAuction),
            offerIds
        );

        assertEq(
            termStrategy.totalLiquidBalance(),
            initialState.totalLiquidBalance
        );
        assertEq(
            termStrategy.totalAssetValue(),
            termStrategy.totalLiquidBalance()
        );
    }

    uint256 public constant THREESIXTY_DAYCOUNT_SECONDS = 360 days;
    uint256 public constant RATE_PRECISION = 1e18;

    function _getRepoTokenAmountGivenPurchaseTokenAmount(
        uint256 purchaseTokenAmount,
        MockTermRepoToken termRepoToken,
        uint256 discountRate
    ) private view returns (uint256) {
        (uint256 redemptionTimestamp, address purchaseToken, , ) = termRepoToken
            .config();

        uint256 purchaseTokenPrecision = 10 ** ERC20(purchaseToken).decimals();
        uint256 repoTokenPrecision = 10 **
            ERC20(address(termRepoToken)).decimals();

        uint256 timeLeftToMaturityDayFraction = ((redemptionTimestamp -
            block.timestamp) * purchaseTokenPrecision) /
            THREESIXTY_DAYCOUNT_SECONDS;

        // purchaseTokenAmount * (1 + r * days / 360) = repoTokenAmountInBaseAssetPrecision
        uint256 repoTokenAmountInBaseAssetPrecision = (purchaseTokenAmount *
            (purchaseTokenPrecision +
                ((discountRate * timeLeftToMaturityDayFraction) /
                    RATE_PRECISION))) / purchaseTokenPrecision;

        return
            (repoTokenAmountInBaseAssetPrecision * repoTokenPrecision) /
            purchaseTokenPrecision;
    }

    function testCompleteAuctionSuccessFull() public {
        bytes32 offerId1 = _submitOffer(bytes32("offer id hash 1"), 1e6);
        uint256 fillAmount = 1e6;

        bytes32[] memory offerIds = new bytes32[](1);
        offerIds[0] = offerId1;
        uint256[] memory fillAmounts = new uint256[](1);
        fillAmounts[0] = fillAmount;
        uint256[] memory repoTokenAmounts = new uint256[](1);
        repoTokenAmounts[0] = _getRepoTokenAmountGivenPurchaseTokenAmount(
            fillAmount,
            repoToken1Week,
            TEST_REPO_TOKEN_RATE
        );

        repoToken1WeekAuction.auctionSuccess(
            offerIds,
            fillAmounts,
            repoTokenAmounts
        );

        //console2.log("repoTokenAmounts[0]", repoTokenAmounts[0]);

        // test: asset value should equal to initial asset value (liquid + pending offers)
        assertEq(termStrategy.totalAssetValue(), initialState.totalAssetValue);

        address[] memory holdings = termStrategy.repoTokenHoldings();

        // test: 0 holding because auctionClosed not yet called
        assertEq(holdings.length, 0);

        termStrategy.auctionClosed();

        // test: asset value should equal to initial asset value (liquid + repo tokens)
        assertEq(termStrategy.totalAssetValue(), initialState.totalAssetValue);

        holdings = termStrategy.repoTokenHoldings();

        // test: check repo token holdings
        assertEq(holdings.length, 1);
        assertEq(holdings[0], address(repoToken1Week));

        bytes32[] memory offers = termStrategy.pendingOffers();

        assertEq(offers.length, 0);
    }

    function testCompleteAuctionSuccessPartial() public {
        bytes32 offerId1 = _submitOffer(bytes32("offer id 1"), 1e6);
        uint256 fillAmount = 0.5e6;

        bytes32[] memory offerIds = new bytes32[](1);
        offerIds[0] = offerId1;
        uint256[] memory fillAmounts = new uint256[](1);

        // test: 50% filled
        fillAmounts[0] = fillAmount;
        uint256[] memory repoTokenAmounts = new uint256[](1);
        repoTokenAmounts[0] = _getRepoTokenAmountGivenPurchaseTokenAmount(
            fillAmount,
            repoToken1Week,
            TEST_REPO_TOKEN_RATE
        );

        repoToken1WeekAuction.auctionSuccess(
            offerIds,
            fillAmounts,
            repoTokenAmounts
        );

        // test: asset value should equal to initial asset value (liquid + pending offers)
        assertEq(termStrategy.totalAssetValue(), initialState.totalAssetValue);

        address[] memory holdings = termStrategy.repoTokenHoldings();

        // test: 0 holding because auctionClosed not yet called
        assertEq(holdings.length, 0);

        termStrategy.auctionClosed();

        // test: asset value should equal to initial asset value (liquid + repo tokens)
        assertEq(termStrategy.totalAssetValue(), initialState.totalAssetValue);

        holdings = termStrategy.repoTokenHoldings();

        // test: check repo token holdings
        assertEq(holdings.length, 1);
        assertEq(holdings[0], address(repoToken1Week));

        bytes32[] memory offers = termStrategy.pendingOffers();

        assertEq(offers.length, 0);
    }

    function testAuctionCancelForWithdrawal() public {
        bytes32 offerId1 = _submitOffer(bytes32("offer id hash 1"), 1e6);

        repoToken1WeekAuction.auctionCancelForWithdrawal();

        // test: check value before calling complete auction
        termStrategy.auctionClosed();

        bytes32[] memory offers = termStrategy.pendingOffers();

        assertEq(offers.length, 0);
    }

    function testMultipleOffers() public {
        bytes32 offerId1 = _submitOffer(bytes32("offer id hash 1"), 1e6);
        bytes32 offerId2 = _submitOffer(bytes32("offer id hash 2"), 5e6);

        assertEq(
            termStrategy.totalLiquidBalance(),
            initialState.totalLiquidBalance - 6e6
        );
        // test: totalAssetValue = total liquid balance + pending offer amount
        assertEq(
            termStrategy.totalAssetValue(),
            termStrategy.totalLiquidBalance() + 6e6
        );

        bytes32[] memory offers = termStrategy.pendingOffers();

        assertEq(offers.length, 2);
        assertEq(offers[0], offerId1);
        assertEq(offers[1], offerId2);
    }

    function testMultipleOffersFillAndNoFill() public {
        uint256 offer1Amount = 1e6;
        uint256 offer2Amount = 5e6;
        bytes32 offerId1 = _submitOffer(
            bytes32("offer id hash 1"),
            offer1Amount
        );
        bytes32 offerId2 = _submitOffer(
            bytes32("offer id hash 2"),
            offer2Amount
        );

        bytes32[] memory offerIds = new bytes32[](2);
        offerIds[0] = offerId1;
        offerIds[1] = offerId2;
        uint256[] memory fillAmounts = new uint256[](2);

        // test: offer 1 filled, offer 2 not filled
        fillAmounts[0] = offer1Amount;
        fillAmounts[1] = 0;
        uint256[] memory repoTokenAmounts = new uint256[](2);
        repoTokenAmounts[0] = _getRepoTokenAmountGivenPurchaseTokenAmount(
            offer1Amount,
            repoToken1Week,
            TEST_REPO_TOKEN_RATE
        );
        repoTokenAmounts[1] = 0;

        repoToken1WeekAuction.auctionSuccess(
            offerIds,
            fillAmounts,
            repoTokenAmounts
        );

        // test: asset value should equal to initial asset value (liquid + pending offers)
        assertEq(termStrategy.totalAssetValue(), initialState.totalAssetValue);
    }

    function testEditOfferTotalGreaterThanCurrentLiquidity() public {
        bytes32 idHash1 = bytes32("offer id hash 1");
        bytes32 offerId1 = _submitOffer(idHash1, 50e6);

        assertEq(termStrategy.totalLiquidBalance(), 50e6);

        _submitOffer(offerId1, 100e6);

        assertEq(termStrategy.totalLiquidBalance(), 0);
    }

    function testEditOfferTotalLessThanCurrentLiquidity() public {
        bytes32 idHash1 = bytes32("offer id hash 1");
        bytes32 offerId1 = _submitOffer(idHash1, 100e6);

        assertEq(termStrategy.totalLiquidBalance(), 0);

        _submitOffer(offerId1, 50e6);

        assertEq(termStrategy.totalLiquidBalance(), 50e6);
    }
}
