pragma solidity ^0.8.18;

import "forge-std/console.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {ITokenizedStrategy} from "@tokenized-strategy/interfaces/ITokenizedStrategy.sol";
import {MockTermRepoToken} from "./mocks/MockTermRepoToken.sol";
import {MockTermController} from "./mocks/MockTermController.sol";
import {MockTermAuction} from "./mocks/MockTermAuction.sol";
import {MockUSDC} from "./mocks/MockUSDC.sol";
import {Setup, ERC20, IStrategyInterface} from "./utils/Setup.sol";
import {ITermRepoToken} from "../interfaces/term/ITermRepoToken.sol";
import {RepoTokenList} from "../RepoTokenList.sol";
import {Strategy} from "../Strategy.sol";

contract TestUSDCSellRepoToken is Setup {

    MockUSDC internal mockUSDC;
    ERC20Mock internal mockCollateral; 
    MockTermRepoToken internal repoToken1Week;
    MockTermRepoToken internal repoToken2Week;
    MockTermRepoToken internal repoToken4Week;
    MockTermRepoToken internal repoTokenMatured;
    Strategy internal termStrategy;
    StrategySnapshot internal initialState;

    function setUp() public override {
        mockUSDC = new MockUSDC();
        mockCollateral = new ERC20Mock();

        _setUp(ERC20(address(mockUSDC)));

        repoToken1Week = new MockTermRepoToken(
            bytes32("test repo token 1"), address(mockUSDC), address(mockCollateral), 1e18, block.timestamp + 1 weeks
        );
        repoToken2Week = new MockTermRepoToken(
            bytes32("test repo token 2"), address(mockUSDC), address(mockCollateral), 1e18, block.timestamp + 2 weeks
        );
        repoToken4Week = new MockTermRepoToken(
            bytes32("test repo token 3"), address(mockUSDC), address(mockCollateral), 1e18, block.timestamp + 4 weeks
        );
        repoTokenMatured = new MockTermRepoToken(
            bytes32("test repo token 4"), address(mockUSDC), address(mockCollateral), 1e18, block.timestamp - 1
        );

        termStrategy = Strategy(address(strategy));

        vm.startPrank(management);
        termStrategy.setCollateralTokenParams(address(mockCollateral), 0.5e18);
        termStrategy.setTimeToMaturityThreshold(10 weeks);
        vm.stopPrank();

    }

    function _initState() private {
        initialState.totalAssetValue = termStrategy.totalAssetValue();
        initialState.totalLiquidBalance = termStrategy.totalLiquidBalance();
    }

    function testSellSingleRepoToken() public {
        // start with some initial funds
        mockUSDC.mint(address(strategy), 100e6);
        _initState();

        // TODO: fuzz this
        uint256 repoTokenSellAmount = 1e18;

        address testUser = vm.addr(0x11111);

        repoToken1Week.mint(testUser, 1000e18);

        vm.prank(testUser);
        repoToken1Week.approve(address(strategy), type(uint256).max);

        termController.setOracleRate(repoToken1Week.termRepoId(), 0.05e18);

        vm.startPrank(management);
        termStrategy.setCollateralTokenParams(address(mockCollateral), 0.5e18);
        termStrategy.setTimeToMaturityThreshold(3 weeks);
        vm.stopPrank();

        vm.prank(testUser);
        termStrategy.sellRepoToken(address(repoToken1Week), repoTokenSellAmount);

        uint256 expectedProceeds = termStrategy.calculateRepoTokenPresentValue(
            address(repoToken1Week), 0.05e18, repoTokenSellAmount
        );

        assertEq(mockUSDC.balanceOf(testUser), expectedProceeds);
        assertEq(termStrategy.totalLiquidBalance(), initialState.totalLiquidBalance - expectedProceeds);
        assertEq(termStrategy.totalAssetValue(), initialState.totalAssetValue);

        uint256 weightedTimeToMaturity = termStrategy.simulateWeightedTimeToMaturity(address(0), 0);

        (uint256 redemptionTimestamp, , ,) = ITermRepoToken(repoToken1Week).config();

        // TODO: validate this math (weighted time to maturity)
        uint256 repoTokenBalanceInBaseAssetPrecision = 
            (ITermRepoToken(repoToken1Week).redemptionValue() * repoTokenSellAmount * 1e6) / (1e18 * 1e18);
        uint256 cumulativeWeightedTimeToMaturity = 
            (redemptionTimestamp - block.timestamp) * repoTokenBalanceInBaseAssetPrecision;
        uint256 expectedWeightedTimeToMaturity = 
            cumulativeWeightedTimeToMaturity / (repoTokenBalanceInBaseAssetPrecision + termStrategy.totalLiquidBalance());

        assertEq(weightedTimeToMaturity, expectedWeightedTimeToMaturity);
    }

    // Test with different precisions
    function testCalculateRepoTokenPresentValue() public {
        //      0.05      0.075     0.1687
        // 7	999028	  998544    996730
        // 14	998059    997092    993482
        // 28	996127    994200	987049

        // 7 days, 0.5 = 999028
        assertEq(termStrategy.calculateRepoTokenPresentValue(address(repoToken1Week), 0.05e18, 1e18), 999028);
        // 7 days, 0.075 = 99854
        assertEq(termStrategy.calculateRepoTokenPresentValue(address(repoToken1Week), 0.075e18, 1e18), 998544);
        // 7 days, 0.1687 = 996730
        assertEq(termStrategy.calculateRepoTokenPresentValue(address(repoToken1Week), 0.1687e18, 1e18), 996730);

        // 14 days, 0.5 = 999028
        assertEq(termStrategy.calculateRepoTokenPresentValue(address(repoToken2Week), 0.05e18, 1e18), 998059);
        // 14 days, 0.075 = 99854
        assertEq(termStrategy.calculateRepoTokenPresentValue(address(repoToken2Week), 0.075e18, 1e18), 997092);
        // 14 days, 0.1687 = 996730
        assertEq(termStrategy.calculateRepoTokenPresentValue(address(repoToken2Week), 0.1687e18, 1e18), 993482);

        // 28 days, 0.5 = 999028
        assertEq(termStrategy.calculateRepoTokenPresentValue(address(repoToken4Week), 0.05e18, 1e18), 996127);
        // 28 days, 0.075 = 99854
        assertEq(termStrategy.calculateRepoTokenPresentValue(address(repoToken4Week), 0.075e18, 1e18), 994200);
        // 28 days, 0.1687 = 996730
        assertEq(termStrategy.calculateRepoTokenPresentValue(address(repoToken4Week), 0.1687e18, 1e18), 987049);
    }

    function _sell1RepoToken(MockTermRepoToken rt1, uint256 amount1) private {
        address[] memory tokens = new address[](1);
        tokens[0] = address(rt1);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount1;

        _sellRepoTokens(tokens, amounts, false, true, "");
    }

    function _sell1RepoTokenNoMint(MockTermRepoToken rt1, uint256 amount1) private {
        address[] memory tokens = new address[](1);
        tokens[0] = address(rt1);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount1;

        _sellRepoTokens(tokens, amounts, false, false, "");
    }

    function _sell1RepoTokenExpectRevert(MockTermRepoToken rt1, uint256 amount1, bytes memory err) private {
        address[] memory tokens = new address[](1);
        tokens[0] = address(rt1);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount1;

        _sellRepoTokens(tokens, amounts, true, true, err);
    }

    function _sell3RepoTokens(
        MockTermRepoToken rt1, 
        uint256 amount1, 
        MockTermRepoToken rt2, 
        uint256 amount2, 
        MockTermRepoToken rt3,
        uint256 amount3
    ) private {
        address[] memory tokens = new address[](3);
        tokens[0] = address(rt1);
        tokens[1] = address(rt2);
        tokens[2] = address(rt3);
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = amount1;
        amounts[1] = amount2;
        amounts[2] = amount3;

        _sellRepoTokens(tokens, amounts, false, true, "");
    }

    function _sell2RepoTokens(
        MockTermRepoToken rt1, 
        uint256 amount1, 
        MockTermRepoToken rt2, 
        uint256 amount2
    ) private {
        address[] memory tokens = new address[](2);
        tokens[0] = address(rt1);
        tokens[1] = address(rt2);
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = amount1;
        amounts[1] = amount2;

        _sellRepoTokens(tokens, amounts, false, true, "");
    }

    function _sell3RepoTokensCheckHoldings() private {
        address[] memory holdings = termStrategy.repoTokenHoldings();

        // 3 repo tokens
        assertEq(holdings.length, 3);

        // sorted by time to maturity
        assertEq(holdings[0], address(repoToken1Week));
        assertEq(holdings[1], address(repoToken2Week));
        assertEq(holdings[2], address(repoToken4Week));
    }

    function _sellRepoTokens(address[] memory tokens, uint256[] memory amounts, bool expectRevert, bool mintUnderlying, bytes memory err) private {
        address testUser = vm.addr(0x11111);

        for (uint256 i; i < tokens.length; i++) {
            address token = tokens[i];
            uint256 amount = amounts[i];

            termController.setOracleRate(MockTermRepoToken(token).termRepoId(), 0.05e18);

            MockTermRepoToken(token).mint(testUser, amount);
            if (mintUnderlying) {
                mockUSDC.mint(
                    address(strategy), 
                    termStrategy.calculateRepoTokenPresentValue(token, 0.05e18, amount)
                );
            }

            vm.startPrank(testUser);
            MockTermRepoToken(token).approve(address(strategy), type(uint256).max);

            if (expectRevert) {
                vm.expectRevert(err);
                termStrategy.sellRepoToken(token, amount);
            } else {
                termStrategy.sellRepoToken(token, amount);
            }
            vm.stopPrank();
        }
    }

    // 7 days (3), 14 days (9), 28 days (3)
    function testSellMultipleRepoTokens_7_14_28_3_9_3() public {
        _sell3RepoTokens(repoToken1Week, 3e18, repoToken2Week, 9e18, repoToken4Week, 3e18);
        _sell3RepoTokensCheckHoldings();
        assertEq(termStrategy.simulateWeightedTimeToMaturity(address(0), 0), 1330560);
    }

    // 14 days (9), 7 days (3), 28 days (3)
    function testSellMultipleRepoTokens_14_7_28_9_3_3() public {
        _sell3RepoTokens(repoToken2Week, 9e18, repoToken1Week, 3e18, repoToken4Week, 3e18);
        _sell3RepoTokensCheckHoldings();
        assertEq(termStrategy.simulateWeightedTimeToMaturity(address(0), 0), 1330560);
    }

    // 28 days (3), 14 days (9), 7 days (3)
    function testSellMultipleRepoTokens_28_14_7_3_9_3() public {
        _sell3RepoTokens(repoToken4Week, 3e18, repoToken2Week, 9e18, repoToken1Week, 3e18);
        _sell3RepoTokensCheckHoldings();
        assertEq(termStrategy.simulateWeightedTimeToMaturity(address(0), 0), 1330560);
    }

    // 28 days (3), 7 days (3), 14 days (9)
    function testSellMultipleRepoTokens_28_7_14_3_3_9() public {
        _sell3RepoTokens(repoToken4Week, 3e18, repoToken1Week, 3e18, repoToken2Week, 9e18);
        _sell3RepoTokensCheckHoldings();
        assertEq(termStrategy.simulateWeightedTimeToMaturity(address(0), 0), 1330560);
    }

    // 7 days (6), 14 days (2), 28 days (8)
    function testSellMultipleRepoTokens_7_14_28_6_2_8() public {
        _sell3RepoTokens(repoToken1Week, 6e18, repoToken2Week, 2e18, repoToken4Week, 8e18);
        _sell3RepoTokensCheckHoldings();
        assertEq(termStrategy.simulateWeightedTimeToMaturity(address(0), 0), 1587600);
    }

    // 7 days (8), 14 days (1), 28 days (3)
    function testSellMultipleRepoTokens_7_14_28_8_1_3() public {
        _sell3RepoTokens(repoToken1Week, 8e18, repoToken2Week, 1e18, repoToken4Week, 3e18);
        _sell3RepoTokensCheckHoldings();
        assertEq(termStrategy.simulateWeightedTimeToMaturity(address(0), 0), 1108800);
    }

    // test: weighted maturity with both repo tokens and pending offers
    function testSellMultipleRepoTokens_7_14_8_1_Offer_28_3() public {
        _sell2RepoTokens(repoToken1Week, 8e18, repoToken2Week, 1e18);

        bytes32 idHash = bytes32("offer id hash 1");

        MockTermAuction repoToken4WeekAuction = new MockTermAuction(repoToken4Week);

        mockUSDC.mint(address(termStrategy), 3e6);

        vm.prank(management);
        termStrategy.submitAuctionOffer(
            address(repoToken4WeekAuction), address(repoToken4Week), idHash, bytes32("test price"), 3e6
        );

        assertEq(termStrategy.simulateWeightedTimeToMaturity(address(0), 0), 1108800);
    }

    function testSetGovernanceParameters() public {
        MockTermController newController = new MockTermController();

        vm.expectRevert("!management");
        termStrategy.setTermController(address(newController));

        vm.expectRevert();
        vm.prank(management);
        termStrategy.setTermController(address(0));

        vm.prank(management);
        termStrategy.setTermController(address(newController));
        assertEq(address(termStrategy.termController()), address(newController));

        vm.expectRevert("!management");
        termStrategy.setTimeToMaturityThreshold(12345);

        vm.prank(management);
        termStrategy.setTimeToMaturityThreshold(12345);
        assertEq(termStrategy.timeToMaturityThreshold(), 12345);

        vm.expectRevert("!management");
        termStrategy.setLiquidityThreshold(12345);

        vm.prank(management);
        termStrategy.setLiquidityThreshold(12345);
        assertEq(termStrategy.liquidityThreshold(), 12345);

        vm.expectRevert("!management");
        termStrategy.setAuctionRateMarkup(12345);

        vm.prank(management);
        termStrategy.setAuctionRateMarkup(12345);
        assertEq(termStrategy.auctionRateMarkup(), 12345);

        vm.expectRevert("!management");
        termStrategy.setCollateralTokenParams(address(mockCollateral), 12345);

        vm.prank(management);
        termStrategy.setCollateralTokenParams(address(mockCollateral), 12345);
        assertEq(termStrategy.auctionRateMarkup(), 12345);
    }

    function testRepoTokenValidationFailures() public {
        // start with some initial funds
        mockUSDC.mint(address(strategy), 100e6);
        _initState();

        address testUser = vm.addr(0x11111);

        repoToken1Week.mint(testUser, 1000e18);
        repoTokenMatured.mint(testUser, 1000e18);

        // test: token has no auction clearing rate
        vm.expectRevert(abi.encodeWithSelector(RepoTokenList.InvalidRepoToken.selector, address(repoToken1Week)));
        vm.prank(testUser);
        termStrategy.sellRepoToken(address(repoToken1Week), 1e18);           

        termController.setOracleRate(repoToken1Week.termRepoId(), 1.05e18);     
        termController.setOracleRate(repoTokenMatured.termRepoId(), 1.05e18);     

        vm.prank(management);
        termStrategy.setCollateralTokenParams(address(mockCollateral), 0);

        // test: min collateral ratio not set
        vm.expectRevert(abi.encodeWithSelector(RepoTokenList.InvalidRepoToken.selector, address(repoToken1Week)));
        vm.prank(testUser);
        termStrategy.sellRepoToken(address(repoToken1Week), 1e18);         

        vm.startPrank(management);
        termStrategy.setCollateralTokenParams(address(mockCollateral), 0.5e18);
        termStrategy.setTimeToMaturityThreshold(3 weeks);
        vm.stopPrank();

        // test: matured repo token  
        vm.expectRevert(abi.encodeWithSelector(RepoTokenList.InvalidRepoToken.selector, address(repoTokenMatured)));
        vm.prank(testUser);
        termStrategy.sellRepoToken(address(repoTokenMatured), 1e18);         
    }

    function testAboveMaturityThresholdFailure() public {
        _sell1RepoToken(repoToken2Week, 2e18);

        uint256 timeToMat = termStrategy.simulateWeightedTimeToMaturity(address(0), 0);

        vm.prank(management);
        termStrategy.setTimeToMaturityThreshold(timeToMat);

        // test: can't sell 4 week repo token because of time to maturity threshold
        _sell1RepoTokenExpectRevert(repoToken4Week, 4e18, abi.encodeWithSelector(Strategy.TimeToMaturityAboveThreshold.selector));

        // test: can still sell 1 week repo token
        _sell1RepoToken(repoToken1Week, 4e18);
    }

    function testRedeemMaturedRepoTokensInternal() public {
        // start with some initial funds
        address testDepositor = vm.addr(0x111111);
        uint256 depositAmount = 1000e6;

        mockUSDC.mint(testDepositor, depositAmount);

        vm.startPrank(testDepositor);
        mockUSDC.approve(address(termStrategy), type(uint256).max);
        IERC4626(address(termStrategy)).deposit(depositAmount, testDepositor);
        vm.stopPrank();

        _sell1RepoTokenNoMint(repoToken2Week, 2e18);

        address[] memory holdings = termStrategy.repoTokenHoldings();

        assertEq(holdings.length, 1);

        vm.warp(block.timestamp + 3 weeks);

        vm.prank(keeper);
        ITokenizedStrategy(address(termStrategy)).report();

        holdings = termStrategy.repoTokenHoldings();

        assertEq(holdings.length, 0);

        vm.startPrank(testDepositor);
        IERC4626(address(termStrategy)).withdraw(
            IERC4626(address(termStrategy)).balanceOf(testDepositor),
            testDepositor,
            testDepositor
        );
        vm.stopPrank();
    }

    function testRedeemMaturedRepoTokensExternal() public {
        // start with some initial funds
        address testDepositor = vm.addr(0x111111);
        uint256 depositAmount = 1000e6;

        mockUSDC.mint(testDepositor, depositAmount);

        vm.startPrank(testDepositor);
        mockUSDC.approve(address(termStrategy), type(uint256).max);
        IERC4626(address(termStrategy)).deposit(depositAmount, testDepositor);
        vm.stopPrank();

        console.log("totalLiquidBalance", termStrategy.totalLiquidBalance());

        _sell1RepoTokenNoMint(repoToken2Week, 2e18);

        address[] memory holdings = termStrategy.repoTokenHoldings();

        assertEq(holdings.length, 1);

        vm.warp(block.timestamp + 3 weeks);

        console.log("totalLiquidBalance", termStrategy.totalLiquidBalance());
        console.log("totalAssetValue", termStrategy.totalAssetValue());

        // external redemption
        repoToken2Week.mockServicer().redeemTermRepoTokens(address(termStrategy), repoToken2Week.balanceOf(address(termStrategy)));

        console.log("totalLiquidBalance", termStrategy.totalLiquidBalance());
        console.log("totalAssetValue", termStrategy.totalAssetValue());

        vm.prank(keeper);
        ITokenizedStrategy(address(termStrategy)).report();

        holdings = termStrategy.repoTokenHoldings();

        assertEq(holdings.length, 0);

        vm.startPrank(testDepositor);
        IERC4626(address(termStrategy)).withdraw(
            IERC4626(address(termStrategy)).balanceOf(testDepositor),
            testDepositor,
            testDepositor
        );
        vm.stopPrank();
    }

    function testRedeemMaturedRepoTokensFailure() public {
        // start with some initial funds
        address testDepositor = vm.addr(0x111111);
        uint256 depositAmount = 1000e6;

        mockUSDC.mint(testDepositor, depositAmount);

        vm.startPrank(testDepositor);
        mockUSDC.approve(address(termStrategy), type(uint256).max);
        IERC4626(address(termStrategy)).deposit(depositAmount, testDepositor);
        vm.stopPrank();

        _sell1RepoTokenNoMint(repoToken2Week, 2e18);

        address[] memory holdings = termStrategy.repoTokenHoldings();

        assertEq(holdings.length, 1);

        vm.warp(block.timestamp + 3 weeks);

        repoToken2Week.mockServicer().setRedemptionFailure(true);

        vm.prank(keeper);
        ITokenizedStrategy(address(termStrategy)).report();

        holdings = termStrategy.repoTokenHoldings();

        // TEST: still has 1 repo token because redemption failure
        assertEq(holdings.length, 1);

        console.log("totalAssetValue", termStrategy.totalAssetValue());
    }
}
