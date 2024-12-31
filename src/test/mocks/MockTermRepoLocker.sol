// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract MockTermRepoLocker {
    IERC20 internal purchaseToken;

    constructor(address _purchaseToken) {
        purchaseToken = IERC20(_purchaseToken);
    }

    function lockPurchaseTokens(address from, uint256 amount) external {
        purchaseToken.transferFrom(from, address(this), amount);
    }

    function releasePurchaseTokens(address to, uint256 amount) external {
        purchaseToken.transfer(to, amount);
    }
}
