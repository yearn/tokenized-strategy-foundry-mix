// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import "forge-std/console2.sol";
import {ExtendedTest} from "./ExtendedTest.sol";

import {Strategy, ERC20} from "../../Strategy.sol";
import {TermDiscountRateAdapter} from "../../TermDiscountRateAdapter.sol";
import {IStrategyInterface} from "../../interfaces/IStrategyInterface.sol";

// Inherit the events so they can be checked if desired.
import {IEvents} from "@tokenized-strategy/interfaces/IEvents.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ERC4626Mock} from "@openzeppelin/contracts/mocks/ERC4626Mock.sol";

import {TokenizedStrategy} from "@tokenized-strategy/TokenizedStrategy.sol";
import {MockFeesFactory} from "../mocks/MockFeesFactory.sol";
import {TermVaultEventEmitter} from "../../TermVaultEventEmitter.sol";
import {MockTermAuction} from "../mocks/MockTermAuction.sol";
import {MockUSDC} from "../mocks/MockUSDC.sol";

import {MockTermAuctionOfferLocker} from "../mocks/MockTermAuctionOfferLocker.sol";
import {MockTermController} from "../mocks/MockTermController.sol";
import {MockTermRepoCollateralManager} from "../mocks/MockTermRepoCollateralManager.sol";
import {MockTermRepoServicer} from "../mocks/MockTermRepoServicer.sol";
import {MockTermRepoToken} from "../mocks/MockTermRepoToken.sol";

contract Setup is ExtendedTest, IEvents {
    struct StrategySnapshot {
        uint256 totalAssetValue;
        uint256 totalLiquidBalance;
    }

    // Contract instances that we will use repeatedly.
    ERC20 public asset;
    IStrategyInterface public strategy;

    mapping(string => address) public tokenAddrs;

    // Addresses for different roles we will use repeatedly.
    address public user = address(10);
    address public keeper = address(4);
    address public management = address(1);
    address public governor = address(2);
    address public performanceFeeRecipient = address(3);
    address public adminWallet = address(111);
    address public devopsWallet = address(222);

    // Integer variables that will be used repeatedly.
    uint256 public decimals;
    uint256 public MAX_BPS = 10_000;

    // Fuzz from $0.01 of 1e6 stable coins up to 1 trillion of a 1e18 coin
    uint256 public maxFuzzAmount = 1e30;
    uint256 public minFuzzAmount = 10_000;

    // Default profit max unlock time is set for 10 days
    uint256 public profitMaxUnlockTime = 10 days;

    MockFeesFactory internal mockFactory;

    // Term finance mocks
    MockTermController internal termController;
    TermDiscountRateAdapter internal discountRateAdapter;
    TermVaultEventEmitter internal termVaultEventEmitterImpl;
    TermVaultEventEmitter internal termVaultEventEmitter;
    ERC4626Mock internal mockYearnVault;
    TokenizedStrategy internal tokenizedStrategy;

    function setUp() public virtual {
        _setTokenAddrs();
        ERC20 mockUSDC = new MockUSDC();

        _setUp(ERC20(ERC20(address(mockUSDC))));
    }

    function _setUp(ERC20 _underlying) internal {
        // Set asset
        asset = _underlying;

        // Set decimals
        decimals = asset.decimals();

        mockFactory = new MockFeesFactory(0, adminWallet);

        // Factory from mainnet, tokenized strategy needs to be hardcoded to 0xBB51273D6c746910C7C06fe718f30c936170feD0
        tokenizedStrategy = new TokenizedStrategy(address(mockFactory));
        vm.etch(
            0xBB51273D6c746910C7C06fe718f30c936170feD0,
            address(tokenizedStrategy).code
        );

        termController = new MockTermController();
        discountRateAdapter = new TermDiscountRateAdapter(
            address(termController),
            adminWallet
        );
        termVaultEventEmitterImpl = new TermVaultEventEmitter();
        termVaultEventEmitter = TermVaultEventEmitter(
            address(new ERC1967Proxy(address(termVaultEventEmitterImpl), ""))
        );
        mockYearnVault = new ERC4626Mock(address(asset));

        termVaultEventEmitter.initialize(adminWallet, devopsWallet);

        // Deploy strategy and set variables
        strategy = IStrategyInterface(setUpStrategy());

        //        factory = strategy.FACTORY();

        // label all the used addresses for traces
        vm.label(keeper, "keeper");
        vm.label(address(mockFactory), "mockFactory");
        vm.label(address(asset), "asset");
        vm.label(management, "management");
        vm.label(governor, "governor");
        vm.label(address(strategy), "strategy");
        vm.label(performanceFeeRecipient, "performanceFeeRecipient");
    }

    function setUpStrategy() public returns (address) {
        // we save the strategy as a IStrategyInterface to give it the needed interface
        IStrategyInterface _strategy = constructStrategy(
            address(asset),
            address(mockYearnVault),
            address(discountRateAdapter),
            address(termVaultEventEmitter),
            governor,
            address(termController)
        );
        vm.prank(adminWallet);
        termVaultEventEmitter.pairVaultContract(address(_strategy));

        // set keeper
        _strategy.setKeeper(keeper);
        // set treasury
        _strategy.setPerformanceFeeRecipient(performanceFeeRecipient);
        // set management of the strategy
        _strategy.setPendingManagement(management);

        vm.prank(management);
        _strategy.acceptManagement();

        vm.prank(governor);
        _strategy.setTermController(address(termController));

        return address(_strategy);
    }

    function constructStrategy(
        address asset,
        address mockYearnVault,
        address discountRateAdapter,
        address termVaultEventEmitter,
        address governor,
        address termController
    ) internal returns (IStrategyInterface) {
        Strategy.StrategyParams memory params = Strategy.StrategyParams(
            asset,
            mockYearnVault,
            discountRateAdapter,
            termVaultEventEmitter,
            governor,
            termController,
            0.1e18,
            45 days,
            0.2e18,
            0.005e18
        );
        Strategy strat = new Strategy("Tokenized Strategy", "tS", params);

        return IStrategyInterface(address(strat));
    }

    function depositIntoStrategy(
        IStrategyInterface _strategy,
        address _user,
        uint256 _amount
    ) public {
        vm.prank(_user);
        asset.approve(address(_strategy), _amount);

        vm.prank(_user);
        _strategy.deposit(_amount, _user);
    }

    function mintAndDepositIntoStrategy(
        IStrategyInterface _strategy,
        address _user,
        uint256 _amount
    ) public {
        airdrop(asset, _user, _amount);
        depositIntoStrategy(_strategy, _user, _amount);
    }

    // For checking the amounts in the strategy
    function checkStrategyTotals(
        IStrategyInterface _strategy,
        uint256 _totalAssets,
        uint256 _totalDebt,
        uint256 _totalIdle
    ) public {
        uint256 _assets = _strategy.totalAssets();
        uint256 _balance = ERC20(_strategy.asset()).balanceOf(
            address(_strategy)
        );
        uint256 _idle = _balance > _assets ? _assets : _balance;
        uint256 _debt = _assets - _idle;
        assertEq(_assets, _totalAssets, "!totalAssets");
        assertEq(_debt, _totalDebt, "!totalDebt");
        assertEq(_idle, _totalIdle, "!totalIdle");
        assertEq(_totalAssets, _totalDebt + _totalIdle, "!Added");
    }

    function airdrop(ERC20 _asset, address _to, uint256 _amount) public {
        uint256 balanceBefore = _asset.balanceOf(_to);
        deal(address(_asset), _to, balanceBefore + _amount);
    }

    function setFees(uint16 _protocolFee, uint16 _performanceFee) public {
        address gov = mockFactory.governance();

        // Need to make sure there is a protocol fee recipient to set the fee.
        vm.prank(gov);
        mockFactory.setRecipient(gov);

        vm.prank(gov);
        mockFactory.setFee(_protocolFee);

        vm.prank(management);
        strategy.setPerformanceFee(_performanceFee);
    }

    function _setTokenAddrs() internal {
        tokenAddrs["WBTC"] = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
        tokenAddrs["YFI"] = 0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e;
        tokenAddrs["WETH"] = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        tokenAddrs["LINK"] = 0x514910771AF9Ca656af840dff83E8264EcF986CA;
        tokenAddrs["USDT"] = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
        tokenAddrs["DAI"] = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
        tokenAddrs["USDC"] = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    }
}
