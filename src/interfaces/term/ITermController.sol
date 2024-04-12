// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

interface ITermController {
    function isTermDeployed(address contractAddress) external view returns (bool);
}
