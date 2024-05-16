// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

import {ITermRepoServicer} from "../../interfaces/term/ITermRepoServicer.sol";
import {ITermRepoToken} from "../../interfaces/term/ITermRepoToken.sol";
import {MockTermRepoLocker} from "./MockTermRepoLocker.sol";

contract MockTermRepoServicer is ITermRepoServicer {
    ITermRepoToken internal repoToken;
    MockTermRepoLocker internal repoLocker;

    constructor(ITermRepoToken _repoToken, address purchaseToken) {
        repoToken = _repoToken;
        repoLocker = new MockTermRepoLocker(purchaseToken);
    }

    function redeemTermRepoTokens(
        address redeemer,
        uint256 amountToRedeem
    ) external {

    }
    
    function termRepoToken() external view returns (address) {
        return address(repoToken);
    }

    function termRepoLocker() external view returns (address) {
        return address(repoLocker);
    }

    function purchaseToken() external view returns (address) {
        (, address purchaseToken, ,) = repoToken.config();
        return purchaseToken;
    }
}
