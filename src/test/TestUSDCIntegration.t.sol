pragma solidity ^0.8.18;

import "forge-std/console2.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import {MockTermAuctionOfferLocker} from "./mocks/MockTermAuctionOfferLocker.sol";
import {MockTermRepoToken} from "./mocks/MockTermRepoToken.sol";
import {MockTermAuction} from "./mocks/MockTermAuction.sol";
import {MockUSDC} from "./mocks/MockUSDC.sol";
import {Setup, ERC20, IStrategyInterface} from "./utils/Setup.sol";
import {Strategy} from "../Strategy.sol";

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {TermDiscountRateAdapter} from "../TermDiscountRateAdapter.sol";
import {RepoTokenList} from "../RepoTokenList.sol";
import "../TermAuctionList.sol";


contract TestUSDCIntegration is Setup {
    uint256 internal constant TEST_REPO_TOKEN_RATE = 0.05e18;
    uint256 public constant THREESIXTY_DAYCOUNT_SECONDS = 360 days;
    uint256 public constant RATE_PRECISION = 1e18;

    MockUSDC internal mockUSDC;
    ERC20Mock internal mockCollateral; 
    MockTermRepoToken internal repoToken1Week;
    MockTermRepoToken internal repoToken1Month;
    MockTermRepoToken internal repoToken1Year;
    MockTermRepoToken internal repoTokenMatured;
    MockTermAuction internal repoToken1WeekAuction;
    MockTermAuction internal repoToken1MonthAuction;
    MockTermAuction internal repoToken1YearAuction;
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
        repoToken1Year = new MockTermRepoToken(
            bytes32("test repo token 4"), address(mockUSDC), address(mockCollateral), 1e18, 48 weeks
        ); 
        repoTokenMatured = new MockTermRepoToken(
            bytes32("test repo token 3"), address(mockUSDC), address(mockCollateral), 1e18, block.timestamp - 1
        );

        termController.setOracleRate(MockTermRepoToken(repoToken1Week).termRepoId(), TEST_REPO_TOKEN_RATE);
        termController.setOracleRate(MockTermRepoToken(repoToken1Month).termRepoId(), TEST_REPO_TOKEN_RATE);


        termStrategy = Strategy(address(strategy));

        repoToken1WeekAuction = new MockTermAuction(repoToken1Week);
        repoToken1MonthAuction = new MockTermAuction(repoToken1Month);
        repoToken1YearAuction = new MockTermAuction(repoToken1Year);

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

        _submitOffer(bytes32("offer id hash 4"), 1e6, repoToken1YearAuction, repoToken1Year);

        _submitOffer(bytes32("offer id hash 1"), 1e6, repoToken1WeekAuction, repoToken1Week);

        _submitOffer(bytes32("offer id hash 2"), 1e6, repoToken1MonthAuction, repoToken1Month);

        bytes32[] memory offers = termStrategy.pendingOffers();

        bool isSorted = true;

        bytes32 offer1;
        bytes32 offer2;
        address termAuction1;
        address termAuction2;

        for (uint256 i = 0; i < offers.length - 1; i++) {
            bytes32 offerSlot1 = keccak256(abi.encode(offers[i], 7));
            bytes32 offerSlot2 = keccak256(abi.encode(offers[i+1], 7));
            offer1 = vm.load(address(termStrategy), offerSlot1);
            offer2 = vm.load(address(termStrategy), offerSlot2);
            termAuction1 = address(uint160(uint256(offer1) >> 64));
            termAuction2 = address(uint160(uint256(offer2) >> 64));

            if (termAuction1 > termAuction2) {
                isSorted=false;
                break;
            }
        }
        assertTrue(isSorted);
    }

    function testRemovingMaturedTokensWithRedemptionAttempt() public {       
        address testUser = vm.addr(0x11111);  
        mockUSDC.mint(testUser, 1e18);
        repoToken1Month.mint(testUser, 1000e18);

        vm.startPrank(testUser);
        mockUSDC.approve(address(mockYearnVault), type(uint256).max);
        mockYearnVault.deposit(1e18, testUser);
        repoToken1Month.approve(address(strategy), type(uint256).max);
        termStrategy.sellRepoToken(address(repoToken1Month), 1e6);
        vm.stopPrank();

        address[] memory holdings = termStrategy.repoTokenHoldings();
        assertEq(holdings.length, 1);


        vm.warp(block.timestamp + 5 weeks);
        termStrategy.auctionClosed();

        holdings = termStrategy.repoTokenHoldings();
        assertEq(holdings.length, 0);
        assertEq(repoToken1Month.balanceOf(address(strategy)), 0);
    }

    function testSimulateTransactionWithNonTermDeployedToken() public {
        address testUser = vm.addr(0x11111);  

        vm.prank(management);
        termController.markNotTermDeployed(address(repoToken1Week));
        vm.stopPrank();

        vm.prank(testUser);  
        vm.expectRevert(abi.encodeWithSelector(RepoTokenList.InvalidRepoToken.selector, address(repoToken1Week)));
        termStrategy.simulateTransaction(address(repoToken1Week), 1e6);
    }

    function testSimulateTransactionWithInvalidToken() public {
        address testUser = vm.addr(0x11111);  

        vm.prank(testUser);  
        vm.expectRevert(abi.encodeWithSelector(RepoTokenList.InvalidRepoToken.selector, address(repoTokenMatured)));
        termStrategy.simulateTransaction(address(repoTokenMatured), 1e6);
    }

    function testSimulateTransactionWithValidToken() public {
        address testUser = vm.addr(0x11111);

        repoToken1Week.mint(testUser, 1000e18);

        termController.setOracleRate(repoToken1Week.termRepoId(), 0.05e6);

        vm.startPrank(testUser);
        repoToken1Week.approve(address(strategy), type(uint256).max);
        termStrategy.sellRepoToken(address(repoToken1Week), 25e18);
        vm.stopPrank();

        uint256 repoTokenSellAmount = 25e18;

        termController.setOracleRate(repoToken1Month.termRepoId(), 0.05e6);

        vm.startPrank(governor);
        termStrategy.setCollateralTokenParams(address(mockCollateral), 0.5e18);
        termStrategy.setTimeToMaturityThreshold(3 weeks);
        vm.stopPrank();

        vm.startPrank(testUser);  
        repoToken1Month.mint(testUser, 1000e18);
        repoToken1Month.approve(address(strategy), type(uint256).max);
        (uint256 simulatedWeightedMaturity, uint256 simulatedRepoTokenConcentrationRatio, uint256 simulatedLiquidityRatio) = termStrategy.simulateTransaction(address(repoToken1Month), repoTokenSellAmount);
        assertApproxEq(simulatedWeightedMaturity, 1.25 weeks, 1);
        assertEq(simulatedRepoTokenConcentrationRatio, 0.25e18);
        assertEq(simulatedLiquidityRatio, 0.5e18);
        vm.stopPrank();
    }

    function testSuccessfulUnlockedOfferFromCancelledAuction() public {
        address testUser = vm.addr(0x11111);

        vm.prank(management);
        termStrategy.submitAuctionOffer(
            repoToken1WeekAuction, address(repoToken1Week), bytes32("offer 1"), bytes32("test price"), 1e6
        ); 

        repoToken1WeekAuction.auctionCancelForWithdrawal();       

        vm.startPrank(testUser);
        repoToken1Month.mint(testUser, 1000e18);
        repoToken1Month.approve(address(strategy), type(uint256).max);
        termStrategy.sellRepoToken(address(repoToken1Month), 1e6);
        bytes32[] memory pendingOffers = termStrategy.pendingOffers();
        assertEq(0, pendingOffers.length);
    }

    function testFailedUnlockedOfferFromCancelledAuction() public {
        address testUser = vm.addr(0x11111);

        vm.prank(management);
        bytes32[] memory offerIds = termStrategy.submitAuctionOffer(
            repoToken1WeekAuction, address(repoToken1Week), bytes32("offer 1"), bytes32("test price"), 1e6
        ); 

        repoToken1WeekAuction.auctionCancelForWithdrawal();       

        vm.startPrank(testUser);
        repoToken1Month.mint(testUser, 1000e18);
        repoToken1Month.approve(address(strategy), type(uint256).max);
        vm.mockCall(repoToken1WeekAuction.termAuctionOfferLocker(), abi.encodeWithSelector(MockTermAuctionOfferLocker.unlockOffers.selector, offerIds), abi.encodeWithSelector(MockTermAuctionOfferLocker.OfferUnlockingFailed.selector));
        termStrategy.sellRepoToken(address(repoToken1Month), 1e6);
        bytes32[] memory pendingOffers = termStrategy.pendingOffers();
        assertEq(1, pendingOffers.length);
    }

    function testRepoTokenBlacklist() public {
        address testUser = vm.addr(0x11111);  
        vm.prank(testUser);
        vm.expectRevert();
        termStrategy.setRepoTokenBlacklist(address(repoToken1Week), true);
        vm.stopPrank();

        vm.prank(governor);
        termStrategy.setRepoTokenBlacklist(address(repoToken1Week), true);
        vm.stopPrank();

        vm.prank(testUser);  
        vm.expectRevert(abi.encodeWithSelector(Strategy.RepoTokenBlacklisted.selector, address(repoToken1Week)));      
        termStrategy.sellRepoToken(address(repoToken1Week), 1e6);
    }

    function testPauses() public {
        address testUser = vm.addr(0x11111);  
        mockUSDC.mint(testUser, 1e18);
        vm.prank(testUser);
        vm.expectRevert();
        termStrategy.pauseDeposit();
        vm.expectRevert();
        termStrategy.unpauseDeposit();
        vm.stopPrank();

        vm.prank(governor);
        termStrategy.pauseDeposit();
        vm.stopPrank();

        vm.prank(testUser);
        mockUSDC.approve(address(termStrategy), 1e6);

        vm.prank(testUser);
        vm.expectRevert(abi.encodeWithSelector(Strategy.DepositPaused.selector));
        IERC4626(address(termStrategy)).deposit(1e6, testUser);
        vm.stopPrank();

        vm.prank(governor);
        termStrategy.unpauseDeposit();
        vm.stopPrank();

        vm.prank(testUser);
        IERC4626(address(termStrategy)).deposit(1e6, testUser);
        vm.stopPrank();
    }

    function testSetDiscountRateAdapter() public {
        address testUser = vm.addr(0x11111);  

        TermDiscountRateAdapter invalid =  new TermDiscountRateAdapter(address(0), adminWallet);
        TermDiscountRateAdapter valid =  new TermDiscountRateAdapter(address(termController), adminWallet);

        vm.prank(testUser);
        vm.expectRevert();
        termStrategy.setDiscountRateAdapter(address(valid));

        vm.prank(governor);
        vm.expectRevert();
        termStrategy.setDiscountRateAdapter(address(invalid));

        vm.prank(governor);
        termStrategy.setDiscountRateAdapter(address(valid));
        vm.stopPrank();

        (
            address assetVault,
        address eventEmitter,
        address governor,
        ITermController prevTermController,
        ITermController currTermController,
        ITermDiscountRateAdapter discountRateAdapter,
        uint256 timeToMaturityThreshold,
        uint256 requiredReserveRatio,
        uint256 discountRateMarkup,
        uint256 repoTokenConcentrationLimit
        ) = termStrategy.strategyState();


        assertEq(address(valid), address(discountRateAdapter));
    }

    function testSettingNewGovernor() public {
        address testUser = vm.addr(0x11111);  

        TermDiscountRateAdapter invalid =  new TermDiscountRateAdapter(address(0), adminWallet);
        TermDiscountRateAdapter valid =  new TermDiscountRateAdapter(address(termController), adminWallet);

        vm.prank(testUser);
        vm.expectRevert();
        termStrategy.setPendingGovernor(address(testUser));

        vm.prank(governor);
        vm.expectRevert();
        termStrategy.setPendingGovernor(address(0));

        vm.prank(governor);
        termStrategy.setPendingGovernor(address(testUser));
        vm.stopPrank();

        vm.prank(adminWallet);
        vm.expectRevert("!pendingGovernor");
        termStrategy.acceptGovernor();

        vm.startPrank(testUser);
        termStrategy.acceptGovernor();
        vm.stopPrank();

        vm.startPrank(governor);
        vm.expectRevert();
        termStrategy.setDiscountRateAdapter(address(valid));

        vm.startPrank(testUser);
        termStrategy.setDiscountRateAdapter(address(valid));
        vm.stopPrank();

        (
            address assetVault,
        address eventEmitter,
        address governor,
        ITermController prevTermController,
        ITermController currTermController,
        ITermDiscountRateAdapter discountRateAdapter,
        uint256 timeToMaturityThreshold,
        uint256 requiredReserveRatio,
        uint256 discountRateMarkup,
        uint256 repoTokenConcentrationLimit
        ) = termStrategy.strategyState();


        assertEq(address(valid), address(discountRateAdapter));
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
