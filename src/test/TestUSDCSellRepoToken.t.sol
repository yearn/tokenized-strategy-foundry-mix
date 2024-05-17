pragma solidity ^0.8.18;

import "forge-std/console.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import {MockTermRepoToken} from "./mocks/MockTermRepoToken.sol";
import {MockTermController} from "./mocks/MockTermController.sol";
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
        // start with some initial funds
        mockUSDC.mint(address(strategy), 100e6);

        initialState.totalAssetValue = termStrategy.totalAssetValue();
        initialState.totalLiquidBalance = termStrategy.totalLiquidBalance();
    }

    function testSellSingleRepoToken() public {
        // TODO: fuzz this
        uint256 repoTokenSellAmount = 1e18;

        address testUser = vm.addr(0x11111);

        repoToken1Week.mint(testUser, 1000e18);

        vm.prank(testUser);
        repoToken1Week.approve(address(strategy), type(uint256).max);

        termController.setOracleRate(repoToken1Week.termRepoId(), 1.05e18);

        vm.startPrank(management);
        termStrategy.setCollateralTokenParams(address(mockCollateral), 0.5e18);
        termStrategy.setTimeToMaturityThreshold(3 weeks);
        vm.stopPrank();

        vm.prank(testUser);
        termStrategy.sellRepoToken(address(repoToken1Week), repoTokenSellAmount);

        uint256 expectedProceeds = termStrategy.calculateRepoTokenPresentValue(address(repoToken1Week), repoTokenSellAmount);

        assertEq(mockUSDC.balanceOf(testUser), expectedProceeds);
        assertEq(termStrategy.totalLiquidBalance(), initialState.totalLiquidBalance - expectedProceeds);
        assertEq(termStrategy.totalAssetValue(), initialState.totalAssetValue);

        uint256 weightedTimeToMaturity = termStrategy.simulateWeightedTimeToMaturity(address(0), 0);

        (uint256 redemptionTimestamp, , ,) = ITermRepoToken(repoToken1Week).config();

        uint256 repoTokenBalanceInBaseAssetPrecision = 
            (ITermRepoToken(repoToken1Week).redemptionValue() * repoTokenSellAmount * 1e6) / (1e18 * 1e18);
        uint256 cumulativeWeightedTimeToMaturity = 
            (redemptionTimestamp - block.timestamp) * repoTokenBalanceInBaseAssetPrecision;
        uint256 expectedWeightedTimeToMaturity = 
            cumulativeWeightedTimeToMaturity / (repoTokenBalanceInBaseAssetPrecision + termStrategy.totalLiquidBalance());

        console.log("repoTokenBalanceInBaseAssetPrecision", repoTokenBalanceInBaseAssetPrecision);
        console.log("cumulativeWeightedTimeToMaturity", cumulativeWeightedTimeToMaturity);
        console.log("totalLiquidBalance", termStrategy.totalLiquidBalance());
        console.log("redemptionTimestamp", redemptionTimestamp);
        console.log("weightedTimeToMat", weightedTimeToMaturity);

        assertEq(weightedTimeToMaturity, expectedWeightedTimeToMaturity);
    }

    // 
    function testSellMultipleRepoTokens() public {

    }

    function testSellMultipleRepoTokensMultipleUsers() public {

    }

    function testSetGovernanceParameters() public {
        MockTermController newController = new MockTermController();

        vm.expectRevert("!management");
        termStrategy.setTermController(address(newController));

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
        mockUSDC.mint(address(strategy), 100e6);

        address testUser = vm.addr(0x11111);

        repoToken1Week.mint(testUser, 1000e18);
        repoTokenMatured.mint(testUser, 1000e18);

        // test: token has no auction clearing rate
        vm.expectRevert(abi.encodeWithSelector(RepoTokenList.InvalidRepoToken.selector, address(repoToken1Week)));
        vm.prank(testUser);
        termStrategy.sellRepoToken(address(repoToken1Week), 1e18);           

        termController.setOracleRate(repoToken1Week.termRepoId(), 1.05e18);     
        termController.setOracleRate(repoTokenMatured.termRepoId(), 1.05e18);     

        // test: min collaterl ratio not set
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

    }

    function testBelowLiquidityThresholdFailure() public {

    }
}
