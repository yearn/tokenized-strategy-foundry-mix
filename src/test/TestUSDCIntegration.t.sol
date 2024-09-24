pragma solidity ^0.8.18;

import "forge-std/console2.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import {MockTermRepoToken} from "./mocks/MockTermRepoToken.sol";
import {MockTermAuction} from "./mocks/MockTermAuction.sol";
import {MockUSDC} from "./mocks/MockUSDC.sol";
import {Setup, ERC20, IStrategyInterface} from "./utils/Setup.sol";
import {Strategy} from "../Strategy.sol";

contract TestUSDCIntegration is Setup {
    uint256 internal constant TEST_REPO_TOKEN_RATE = 0.05e18;
    uint256 public constant THREESIXTY_DAYCOUNT_SECONDS = 360 days;
    uint256 public constant RATE_PRECISION = 1e18;

    MockUSDC internal mockUSDC;
    ERC20Mock internal mockCollateral; 
    MockTermRepoToken internal repoToken1Week;
    MockTermRepoToken internal repoToken1Month;
    MockTermAuction internal repoToken1WeekAuction;
    MockTermAuction internal repoToken1MonthAuction;
    Strategy internal termStrategy;
    StrategySnapshot internal initialState;

    function setUp() public override {
        mockUSDC = new MockUSDC();
        mockCollateral = new ERC20Mock();

        _setUp(ERC20(address(mockUSDC)));

        repoToken1Week = new MockTermRepoToken(
            bytes32("test repo token 1"), address(mockUSDC), address(mockCollateral), 1e18, 1 weeks
        );        
        repoToken1Month = new MockTermRepoToken(
            bytes32("test repo token 2"), address(mockUSDC), address(mockCollateral), 1e18, 4 weeks
        );    
        termController.setOracleRate(MockTermRepoToken(repoToken1Week).termRepoId(), TEST_REPO_TOKEN_RATE);
        termController.setOracleRate(MockTermRepoToken(repoToken1Month).termRepoId(), TEST_REPO_TOKEN_RATE);


        termStrategy = Strategy(address(strategy));

        repoToken1WeekAuction = new MockTermAuction(repoToken1Week);
        repoToken1MonthAuction = new MockTermAuction(repoToken1Month);

        vm.startPrank(management);
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

    function _submitOffer(bytes32 idHash, uint256 offerAmount, MockTermAuction auction, MockTermRepoToken repoToken) private returns (bytes32) { 
        // test: only management can submit offers
        vm.expectRevert("!management");
        bytes32[] memory offerIds = termStrategy.submitAuctionOffer(
            auction, address(repoToken), idHash, bytes32("test price"), offerAmount
        );        

        vm.prank(management);
        offerIds = termStrategy.submitAuctionOffer(
            auction, address(repoToken), idHash, bytes32("test price"), offerAmount
        );        

        assertEq(offerIds.length, 1);

        return offerIds[0];
    }

    function testSellRepoTokenSubmitOfferAndCloseAuction() public {       
        address testUser = vm.addr(0x11111);  
        mockUSDC.mint(testUser, 1e18);
        repoToken1Month.mint(testUser, 1000e18);

        vm.startPrank(testUser);
        mockUSDC.approve(address(mockYearnVault), type(uint256).max);
        mockYearnVault.deposit(1e18, testUser);
        repoToken1Month.approve(address(strategy), type(uint256).max);
        termStrategy.sellRepoToken(address(repoToken1Month), 1e6);
        mockYearnVault.withdraw(1e18, testUser, testUser);
        vm.stopPrank();

        address[] memory holdings = termStrategy.repoTokenHoldings();

        assertEq(holdings.length, 1);


        bytes32 offerId1 = _submitOffer(bytes32("offer id hash 1"), 1e6, repoToken1WeekAuction, repoToken1Week);
        bytes32[] memory offerIds = new bytes32[](1);
        offerIds[0] = offerId1;
        uint256[] memory fillAmounts = new uint256[](1);
        fillAmounts[0] = 1e6;
        uint256[] memory repoTokenAmounts = new uint256[](1);
        repoTokenAmounts[0] = _getRepoTokenAmountGivenPurchaseTokenAmount(
            1e6, repoToken1Week, TEST_REPO_TOKEN_RATE
        );


        repoToken1WeekAuction.auctionSuccess(offerIds, fillAmounts, repoTokenAmounts);

        holdings = termStrategy.repoTokenHoldings();

        // test: 1 holding because auctionClosed not yet called
        assertEq(holdings.length, 1);

        termStrategy.auctionClosed();
        holdings = termStrategy.repoTokenHoldings();
        assertEq(holdings.length, 2);
        (uint256 holdings0Maturity, , ,) = MockTermRepoToken(holdings[0]).config();
        (uint256 holdings1Maturity, , ,) = MockTermRepoToken(holdings[1]).config();
        assertTrue(holdings0Maturity <= holdings1Maturity);
        bytes32[] memory offers = termStrategy.pendingOffers();        

        assertEq(offers.length, 0);

        assertEq(termStrategy.totalLiquidBalance(), initialState.totalLiquidBalance - 1e6);
        // test: totalAssetValue = total liquid balance + pending offer amount
        assertEq(termStrategy.totalAssetValue(), termStrategy.totalLiquidBalance() + 1e6);
    }

    function testSubmittingOffersToMultipleAuctions() public {       
        address testUser = vm.addr(0x11111);  
        mockUSDC.mint(testUser, 1e18);
        repoToken1Month.mint(testUser, 1000e18);

        vm.startPrank(testUser);
        mockUSDC.approve(address(mockYearnVault), type(uint256).max);
        mockYearnVault.deposit(1e18, testUser);
        repoToken1Month.approve(address(strategy), type(uint256).max);
        termStrategy.sellRepoToken(address(repoToken1Month), 1e6);
        mockYearnVault.withdraw(1e18, testUser, testUser);
        vm.stopPrank();

        bytes32 offerId1 = _submitOffer(bytes32("offer id hash 1"), 1e6, repoToken1WeekAuction, repoToken1Week);

        bytes32 offerId2 = _submitOffer(bytes32("offer id hash 2"), 1e6, repoToken1MonthAuction, repoToken1Month);

        bytes32[] memory offers = termStrategy.pendingOffers();

        assertEq(offers.length, 2);

        assertTrue(offers[0] == offerId1 ? address(repoToken1WeekAuction) <= address(repoToken1MonthAuction) : address(repoToken1MonthAuction) <= address(repoToken1WeekAuction));
    }

    function _getRepoTokenAmountGivenPurchaseTokenAmount(
        uint256 purchaseTokenAmount,
        MockTermRepoToken termRepoToken,
        uint256 discountRate
    ) private view returns (uint256) {
        (uint256 redemptionTimestamp, address purchaseToken, ,) = termRepoToken.config();

        uint256 purchaseTokenPrecision = 10**ERC20(purchaseToken).decimals();
        uint256 repoTokenPrecision = 10**ERC20(address(termRepoToken)).decimals();

        uint256 timeLeftToMaturityDayFraction = 
            ((redemptionTimestamp - block.timestamp) * purchaseTokenPrecision) / THREESIXTY_DAYCOUNT_SECONDS;

        // purchaseTokenAmount * (1 + r * days / 360) = repoTokenAmountInBaseAssetPrecision
        uint256 repoTokenAmountInBaseAssetPrecision = 
            purchaseTokenAmount * (purchaseTokenPrecision + (discountRate * timeLeftToMaturityDayFraction / RATE_PRECISION)) / purchaseTokenPrecision;

        return repoTokenAmountInBaseAssetPrecision * repoTokenPrecision / purchaseTokenPrecision;
    }

}
