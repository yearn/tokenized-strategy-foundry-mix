// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

import {AprOracleBase} from "@periphery/AprOracle/AprOracleBase.sol";

interface IStrategy {
    function curveLendVault() external view returns (address);
    function liquidityGauge() external view returns (address);
}

interface ICurveVault {
    function controller() external view returns (address);
    function totalSupply() external view returns (uint256);
}

interface IController {
    function monetary_policy() external view returns (address);
    function total_debt() external view returns (uint256);
}

interface IMonetaryPolicy {
    function future_rate(address, int256, int256) external view returns (uint256);
}

interface ILiquidityGauge {
    function reward_data(address) external view returns (address token, address distributor, uint256 period_finish, uint256 rate, uint256 last_update, uint256 integral);
    function totalSupply() external view returns (uint256);
}

interface IChainlink {
    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80);
}

contract StrategyAprOracle is AprOracleBase {
    address internal constant CRV = 0xD533a949740bb3306d119CC777fa900bA034cd52; //hardcode for now
    address public immutable chainlinkCRVUSDvsUSD;
    address public immutable chainlinkCRVvsUSD;
    uint256 internal constant WAD = 1e18;
    uint256 internal constant secondsInOneYear = 60 * 60 * 24 * 365;

    constructor(address _chainlinkCRVUSDvsUSD, address _chainlinkCRVvsUSD) AprOracleBase("Strategy Apr Oracle Example", msg.sender) {
        chainlinkCRVUSDvsUSD = _chainlinkCRVUSDvsUSD;
        chainlinkCRVvsUSD = _chainlinkCRVvsUSD;
    }

    function aprAfterDebtChange(
        address _strategy,
        int256 _delta
    ) external view override returns (uint256 apr) {
        IStrategy strategy = IStrategy(_strategy);
        ICurveVault curveVault = ICurveVault(strategy.curveLendVault());
        IController controller = IController(curveVault.controller());
        IMonetaryPolicy monetaryPolicy = IMonetaryPolicy(controller.monetary_policy());
        
        uint256 futureRate = monetaryPolicy.future_rate(address(controller),_delta,0);        
        uint256 lendingAPR = futureRate * secondsInOneYear * curveVault.totalSupply() / controller.total_debt();

        // @todo: add APY coming from gauge staking
        // this is the gauge, reward token expected in CRV for now
        // https://etherscan.io/address/0x79D584d2D49eC8CE8Ea379d69364b700bd35874D#code
        // we can use chainlink or redstone oracle for crvusd and crv
        // https://data.chain.link/feeds/ethereum/mainnet/crvusd-usd
        // https://data.chain.link/feeds/ethereum/mainnet/crv-usd
        // https://app.redstone.finance/#/app/token/CRV

        address liquidityGauge = strategy.liquidityGauge();
        (address token, , , uint256 rate, , uint256 integral) = ILiquidityGauge(liquidityGauge).reward_data(CRV);
        //add check for token == CRV?
        //do we need integral?

        uint256 rewardYield;
        uint256 totalSupply = ILiquidityGauge(liquidityGauge).totalSupply();
        if (_delta >= 0) {
            rewardYield = secondsInOneYear * rate * WAD / ( totalSupply + uint256(_delta) );
        } else if (uint256(_delta) < totalSupply) {
            rewardYield = secondsInOneYear * rate * WAD / ( totalSupply - uint256(_delta) );
        } else {
            rewardYield = secondsInOneYear * rate * WAD;
        }
        
        //pricing: reward to CRVUSD
        (, int256 price, , , ) = IChainlink(chainlinkCRVvsUSD).latestRoundData();
        uint256 USDyield = rewardYield * uint256(price) / 1e8; //convert reward to USD
        (, price, , , ) = IChainlink(chainlinkCRVUSDvsUSD).latestRoundData();
        uint256 gaugeAPR = USDyield * WAD / (uint256(price) * 1e10); //convert USD to CRVUSD

        //return total of lending yields + gauge rewards
        return lendingAPR + gaugeAPR;
    }
}
