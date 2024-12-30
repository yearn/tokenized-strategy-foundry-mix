// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

import {Strategy, ERC20} from "./Strategy.sol";
import {IStrategyInterface} from "./interfaces/IStrategyInterface.sol";

contract StrategyFactory {
    error InvalidStrategyId();

    event NewStrategy(address indexed strategy, uint256 indexed strategyId);

    /// @notice Track the deployments. strategyId => strategy address
    mapping(uint256 => address) public deployments;

    uint256 public strategyId;

    constructor() {
        strategyId = 0;
    }

    /**
     * @notice Deploy a new Strategy
     * @param initializeParams The encoded parameters to initialize the strategy with
     * @return address The address of the newly deployed strategy
     */
    function newStrategy(bytes calldata initializeParams) external virtual returns (address) {
        IStrategyInterface _newStrategy = IStrategyInterface(address(new Strategy()));
        _newStrategy.setUp(initializeParams);

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
