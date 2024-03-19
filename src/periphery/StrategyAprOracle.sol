// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

import {AprOracleBase} from "@periphery/AprOracle/AprOracleBase.sol";

interface IStrategy {
    function curveLendVault() external view returns (address);
}

interface ICurveVault {
    function controller() external view returns (address);
    function totalSupply() external view returns (uint256);
}

interface IController {
    function monetary_policy() external view returns (address);
}

interface IMonetaryPolicy {
    function future_rate(address, int256, int256) external view returns (uint256);
}

contract StrategyAprOracle is AprOracleBase {
    constructor() AprOracleBase("Strategy Apr Oracle Example", msg.sender) {}

    function aprAfterDebtChange(
        address _strategy,
        int256 _delta
    ) external view override returns (uint256) {
        IStrategy strategy = IStrategy(_strategy);
        ICurveVault curveVault = ICurveVault(strategy.curveLendVault());
        IController controller = IController(curveVault.controller());
        IMonetaryPolicy monetaryPolicy = IMonetaryPolicy(controller.monetary_policy());
        uint256 secondsInOneYear = 60 * 60 * 24 * 365;
        uint256 totalSupply = curveVault.totalSupply();
        uint256 totalDebt = controller.total_debt();
        uint256 futureRate = monetaryPolicy.future_rate(address(controller),_delta,0)
        
        // @todo: add APY coming from gauge staking
        // this is the gauge, reward token expected in CRV for now
        // https://etherscan.io/address/0x79D584d2D49eC8CE8Ea379d69364b700bd35874D#code
        // we can use chainlink or redstone oracle for crvusd and crv
        // https://data.chain.link/feeds/ethereum/mainnet/crvusd-usd
        // https://data.chain.link/feeds/ethereum/mainnet/crv-usd
        // https://app.redstone.finance/#/app/token/CRV

        return futureRate * secondsInOneYear * totalSupply / totalDebt;
    }
}
