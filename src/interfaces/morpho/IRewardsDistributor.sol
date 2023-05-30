// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

interface IRewardsDistributor {
    /// @notice Claims rewards.
    /// @param _account The address of the claimer.
    /// @param _claimable The overall claimable amount of token rewards.
    /// @param _proof The merkle proof that validates this claim.
    function claim(
        address _account,
        uint256 _claimable,
        bytes32[] calldata _proof
    ) external;
}
