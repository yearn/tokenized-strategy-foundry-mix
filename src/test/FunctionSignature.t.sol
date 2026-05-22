// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/console2.sol";
import {Setup, ERC20, IStrategyInterface} from "./utils/Setup.sol";

contract FunctionSignatureTest is Setup {
    function setUp() public virtual override {
        super.setUp();
    }

    // This test should not be overridden and checks that
    // no function signature collisions occurred from the custom functions.
    // Does not check functions that are strategy dependant and will be checked in other tests
    function test_functionCollisions() public {
        uint256 wad = 1e18;
        vm.expectRevert("initialized");
        strategy.initialize(address(asset), "name", management, performanceFeeRecipient, keeper);

        // Check view functions
        assertEq(strategy.convertToAssets(wad), wad, "convert to assets");
        assertEq(strategy.convertToShares(wad), wad, "convert to shares");
        assertEq(strategy.previewDeposit(wad), wad, "preview deposit");
        assertEq(strategy.previewMint(wad), wad, "preview mint");
        assertEq(strategy.previewWithdraw(wad), wad, "preview withdraw");
        assertEq(strategy.previewRedeem(wad), wad, "preview redeem");
        assertEq(strategy.totalAssets(), 0, "total assets");
        assertEq(strategy.totalSupply(), 0, "total supply");
        assertEq(strategy.unlockedShares(), 0, "unlocked shares");
        assertEq(strategy.asset(), address(asset), "asset");
        assertEq(strategy.apiVersion(), "3.0.4", "api");
        assertEq(strategy.MAX_FEE(), 5_000, "max fee");
        assertEq(strategy.fullProfitUnlockDate(), 0, "unlock date");
        assertEq(strategy.profitUnlockingRate(), 0, "unlock rate");
        assertGt(strategy.lastReport(), 0, "last report");
        assertEq(strategy.pricePerShare(), 10 ** asset.decimals(), "pps");
        assertTrue(!strategy.isShutdown());
        assertEq(strategy.symbol(), string(abi.encodePacked("ys", asset.symbol())), "symbol");
        assertEq(strategy.decimals(), asset.decimals(), "decimals");

        // Assure modifiers are working
        vm.startPrank(user);
        vm.expectRevert("!management");
        strategy.setPendingManagement(user);
        vm.expectRevert("!pending");
        strategy.acceptManagement();
        vm.expectRevert("!management");
        strategy.setKeeper(user);
        vm.expectRevert("!management");
        strategy.setEmergencyAdmin(user);
        vm.expectRevert("!management");
        strategy.setPerformanceFee(uint16(2_000));
        vm.expectRevert("!management");
        strategy.setPerformanceFeeRecipient(user);
        vm.expectRevert("!management");
        strategy.setProfitMaxUnlockTime(1);
        vm.stopPrank();

        // Assure checks are being used
        vm.startPrank(strategy.management());
        vm.expectRevert("Cannot be self");
        strategy.setPerformanceFeeRecipient(address(strategy));
        vm.expectRevert("too long");
        strategy.setProfitMaxUnlockTime(type(uint256).max);
        vm.stopPrank();

        // Mint some shares to the user
        airdrop(ERC20(address(strategy)), user, wad);
        assertEq(strategy.balanceOf(address(user)), wad, "balance");
        vm.prank(user);
        strategy.transfer(keeper, wad);
        assertEq(strategy.balanceOf(user), 0, "second balance");
        assertEq(strategy.balanceOf(keeper), wad, "keeper balance");
        assertEq(strategy.allowance(keeper, user), 0, "allowance");
        vm.prank(keeper);
        assertTrue(strategy.approve(user, wad), "approval");
        assertEq(strategy.allowance(keeper, user), wad, "second allowance");
        vm.prank(user);
        assertTrue(strategy.transferFrom(keeper, user, wad), "transfer from");
        assertEq(strategy.balanceOf(user), wad, "second balance");
        assertEq(strategy.balanceOf(keeper), 0, "keeper balance");
    }
}
