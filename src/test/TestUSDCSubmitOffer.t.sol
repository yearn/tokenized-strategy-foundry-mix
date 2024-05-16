pragma solidity ^0.8.18;

import "forge-std/console.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import {MockTermRepoToken} from "./mocks/MockTermRepoToken.sol";
import {MockTermAuction} from "./mocks/MockTermAuction.sol";
import {MockUSDC} from "./mocks/MockUSDC.sol";
import {Setup, ERC20, IStrategyInterface} from "./utils/Setup.sol";
import {Strategy} from "../Strategy.sol";

contract TestUSDCSubmitOffer is Setup {

    MockUSDC internal mockUSDC;
    ERC20Mock internal mockCollateral; 
    MockTermRepoToken internal repoToken1Week;

    function setUp() public override {
        mockUSDC = new MockUSDC();
        mockCollateral = new ERC20Mock();

        _setUp(ERC20(address(mockUSDC)));

        repoToken1Week = new MockTermRepoToken(
            bytes32("test repo token 1"), address(mockUSDC), address(mockCollateral), 1e18, 1 weeks
        );        
    }

    function testSubmitOffer() public {
        mockUSDC.mint(address(strategy), 100e6);
        
        MockTermAuction mockAuction = new MockTermAuction(repoToken1Week);

        vm.startPrank(management);
        Strategy(address(strategy)).setCollateralTokenParams(address(mockCollateral), 0.5e18);
        Strategy(address(strategy)).setTimeToMaturityThreshold(3 weeks);
        vm.stopPrank();

        Strategy(address(strategy)).submitAuctionOffer(
            address(mockAuction), address(repoToken1Week), bytes32("offer id 1"), bytes32("test price"), 1e6
        );
    }

    function testEditOffer() public {

    }

    function testCompleteAuction() public {
        
    }
}
