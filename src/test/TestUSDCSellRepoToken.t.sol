pragma solidity ^0.8.18;

import "forge-std/console.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import {MockTermRepoToken} from "./mocks/MockTermRepoToken.sol";
import {MockUSDC} from "./mocks/MockUSDC.sol";
import {Setup, ERC20, IStrategyInterface} from "./utils/Setup.sol";
import {Strategy} from "../Strategy.sol";

contract TestUSDCSellRepoToken is Setup {

    MockUSDC internal mockUSDC;
    ERC20Mock internal mockCollateral; 
    MockTermRepoToken internal repoToken1Week;
    MockTermRepoToken internal repoToken2Week;
    MockTermRepoToken internal repoToken4Week;

    function setUp() public override {
        mockUSDC = new MockUSDC();
        mockCollateral = new ERC20Mock();

        _setUp(ERC20(address(mockUSDC)));

        repoToken1Week = new MockTermRepoToken(
            bytes32("test repo token 1"), address(mockUSDC), address(mockCollateral), 1e18, 1 weeks
        );
        repoToken2Week = new MockTermRepoToken(
            bytes32("test repo token 2"), address(mockUSDC), address(mockCollateral), 1e18, 2 weeks
        );
        repoToken4Week = new MockTermRepoToken(
            bytes32("test repo token 3"), address(mockUSDC), address(mockCollateral), 1e18, 4 weeks
        );
    }

    function testSellSingleRepoToken() public {
        mockUSDC.mint(address(strategy), 100e6);

        address testUser = vm.addr(0x11111);

        repoToken1Week.mint(testUser, 1000e18);

        vm.prank(testUser);
        repoToken1Week.approve(address(strategy), type(uint256).max);

        termController.setOracleRate(repoToken1Week.termRepoId(), 1.05e18);

        vm.startPrank(management);
        Strategy(address(strategy)).setCollateralTokenParams(address(mockCollateral), 0.5e18);
        Strategy(address(strategy)).setTimeToMaturityThreshold(3 weeks);
        vm.stopPrank();

        vm.prank(testUser);
        Strategy(address(strategy)).sellRepoToken(address(repoToken1Week), 1e18);

        uint256 weightedTimeToMaturity = Strategy(address(strategy)).simulateWeightedTimeToMaturity(address(0), 0);

        console.log("weightedTimeToMat", weightedTimeToMaturity);
    }

    // 
    function testSellMultipleRepoTokens() public {

    }

    function testSellMultipleRepoTokensMultipleUsers() public {

    }

    function testSetGovernanceParameters() public {
        
    }

    function testRepoTokenValidationFailures() public {

    }

    function testAboveMaturityThresholdFailure() public {

    }

    function testBelowLiquidityThresholdFailure() public {

    }
}
