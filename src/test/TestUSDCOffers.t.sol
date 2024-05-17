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
    Strategy internal termStrategy;
    MockTermAuction internal mockAuction;
    StrategySnapshot internal initialState;

    function setUp() public override {
        mockUSDC = new MockUSDC();
        mockCollateral = new ERC20Mock();

        _setUp(ERC20(address(mockUSDC)));

        repoToken1Week = new MockTermRepoToken(
            bytes32("test repo token 1"), address(mockUSDC), address(mockCollateral), 1e18, 1 weeks
        );        

        termStrategy = Strategy(address(strategy));
        // start with some initial funds
        mockUSDC.mint(address(strategy), 100e6);

        initialState.totalAssetValue = termStrategy.totalAssetValue();
        initialState.totalLiquidBalance = termStrategy.totalLiquidBalance();
    }

    function testSubmitOffer() public {       
        // TODO: fuzz this
        uint256 offerAmount = 1e6;
 
        mockAuction = new MockTermAuction(repoToken1Week);

        vm.startPrank(management);
        termStrategy.setCollateralTokenParams(address(mockCollateral), 0.5e18);
        termStrategy.setTimeToMaturityThreshold(3 weeks);
        vm.stopPrank();

        // test: only management can submit offers
        vm.expectRevert("!management");
        bytes32[] memory offerIds = termStrategy.submitAuctionOffer(
            address(mockAuction), address(repoToken1Week), bytes32("offer id 1"), bytes32("test price"), offerAmount
        );        

        vm.prank(management);
        offerIds = termStrategy.submitAuctionOffer(
            address(mockAuction), address(repoToken1Week), bytes32("offer id 1"), bytes32("test price"), offerAmount
        );        

        assertEq(offerIds.length, 1);
        assertEq(offerIds[0], bytes32("offer id 1"));
        assertEq(termStrategy.totalLiquidBalance(), initialState.totalLiquidBalance - offerAmount);
        // test: totalAssetValue = total liquid balance + pending offer amount
        assertEq(termStrategy.totalAssetValue(), termStrategy.totalLiquidBalance() + offerAmount);
    }

    function testEditOffer() public {
        testSubmitOffer();

        // TODO: fuzz this
        uint256 offerAmount = 4e6;

        vm.prank(management);
        bytes32[] memory offerIds = termStrategy.submitAuctionOffer(
            address(mockAuction), address(repoToken1Week), bytes32("offer id 1"), bytes32("test price"), offerAmount
        );        

        assertEq(termStrategy.totalLiquidBalance(), initialState.totalLiquidBalance - offerAmount);
        // test: totalAssetValue = total liquid balance + pending offer amount
        assertEq(termStrategy.totalAssetValue(), termStrategy.totalLiquidBalance() + offerAmount);
    }

    function testDeleteOffers() public {
        testSubmitOffer();

        bytes32[] memory offerIds = new bytes32[](1);

        offerIds[0] = bytes32("offer id 1");

        vm.expectRevert("!management");
        termStrategy.deleteAuctionOffers(address(mockAuction), offerIds);

        vm.prank(management);
        termStrategy.deleteAuctionOffers(address(mockAuction), offerIds);

        assertEq(termStrategy.totalLiquidBalance(), initialState.totalLiquidBalance);
        assertEq(termStrategy.totalAssetValue(), termStrategy.totalLiquidBalance());
    }

    function testCompleteAuction() public {
        
    }

    function testMultipleOffers() public {

    }
}
