// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

import {AprOracleBase} from "@periphery/AprOracle/AprOracleBase.sol";

interface IStrategy {
    function curveLendVault() external view returns (address);
}

interface ICurveVault {
    function controller() external view returns (address);
}

interface IController {
    function monetary_policy() external view returns (address);
}

interface IMonetaryPolicy {
    // @param _for	        address	Controller address
    // @param d_reserves	int256	Change of reserve asset
    // @param d_debt	    int256	Change of debt
    // @return .           borrow rate (uint256)
    // https://docs.curve.fi/lending/contracts/semilog-mp/#future_rate
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
        
        // @todo: add APY coming from gauge staking
        // this is the gauge, reward token expected in CRV for now
        // https://etherscan.io/address/0x79D584d2D49eC8CE8Ea379d69364b700bd35874D#code
        // we can use chainlink or redstone oracle for crvusd and crv
        // https://data.chain.link/feeds/ethereum/mainnet/crvusd-usd
        // https://data.chain.link/feeds/ethereum/mainnet/crv-usd
        // https://app.redstone.finance/#/app/token/CRV

        return monetaryPolicy.future_rate(address(controller),_delta,0);
    }
}
