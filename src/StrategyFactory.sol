// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "octant-v2-core/src/dragons/DragonTokenizedStrategy.sol";
import "forge-std/console2.sol";
import {Strategy, ERC20} from "./Strategy.sol";
import {IStrategyInterface} from "./interfaces/IStrategyInterface.sol";

contract StrategyFactory {
    error InvalidStrategyId();

    event NewStrategy(address indexed strategy, uint256 indexed strategyId);

    /// @notice Track the deployments. strategyId => strategy address
    mapping(uint256 => address) public deployments;

    address public strategyImplementation;
    address public dragonTokenizedStrategyImplementation;
    uint256 public strategyId;

    constructor() {
        strategyId = 0;
        strategyImplementation = address(new Strategy());
        dragonTokenizedStrategyImplementation = address(new DragonTokenizedStrategy());
    }

    /**
     * @notice Deploy a new Strategy
     * @param initializeParams The encoded parameters to initialize the strategy with
     * @return address The address of the newly deployed strategy
     */
    function newStrategy(bytes memory initializeParams) external virtual returns (address) {
        ERC1967Proxy _newStrategy = new ERC1967Proxy(
            strategyImplementation,
            abi.encodeWithSelector(Strategy(payable(address(0))).setUp.selector, initializeParams)
        );

        uint256 currentId = strategyId;
        deployments[currentId] = address(_newStrategy);

        emit NewStrategy(address(_newStrategy), currentId);

        unchecked {
            strategyId = currentId + 1;
        }

        return address(_newStrategy);
    }

    /**
     * @notice Retrieve a deployed strategy address by ID
     * @param _strategyId The ID of the strategy to look up
     * @return address The strategy contract address
     */
    function getStrategy(uint256 _strategyId) external view returns (address) {
        address strategy = deployments[_strategyId];
        if (strategy == address(0)) revert InvalidStrategyId();
        return strategy;
    }
}
