// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {MockFactory} from "@tokenized-strategy/test/mocks/MockFactory.sol";

contract MockFeesFactory is MockFactory {
    address public governance;

    constructor(uint16 bps, address treasury) MockFactory(bps, treasury) {
        governance = msg.sender;
    }
}
