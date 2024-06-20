// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

import {ITermRepoServicer} from "../../interfaces/term/ITermRepoServicer.sol";
import {ITermRepoToken} from "../../interfaces/term/ITermRepoToken.sol";
import {MockTermRepoLocker} from "./MockTermRepoLocker.sol";

interface IMockERC20 {
    function mint(address account, uint256 amount) external;
    function burn(address account, uint256 amount) external;
    function decimals() external view returns (uint256);
}

contract MockTermRepoServicer is ITermRepoServicer {
    ITermRepoToken internal repoToken;
    MockTermRepoLocker internal repoLocker;
    address public purchaseToken;
    bool public redemptionFailure;

    constructor(ITermRepoToken _repoToken, address _purchaseToken) {
        repoToken = _repoToken;
        repoLocker = new MockTermRepoLocker(_purchaseToken);
        purchaseToken = _purchaseToken;
    }

    function setRedemptionFailure(bool hasFailure) external {
        redemptionFailure = hasFailure;
    }

    function redeemTermRepoTokens(
        address redeemer,
        uint256 amountToRedeem
    ) external {
        if (redemptionFailure) revert("redemption failured");
        uint256 amountToRedeemInAssetPrecision = 
            amountToRedeem * (10**IMockERC20(purchaseToken).decimals()) / 
            (10**IMockERC20(address(repoToken)).decimals());
        IMockERC20(purchaseToken).mint(redeemer, amountToRedeemInAssetPrecision);
        IMockERC20(address(repoToken)).burn(redeemer, amountToRedeem);
    }
    
    function termRepoToken() external view returns (address) {
        return address(repoToken);
    }

    function termRepoLocker() external view returns (address) {
        return address(repoLocker);
    }
}
