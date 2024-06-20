// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ITermRepoToken} from "../../interfaces/term/ITermRepoToken.sol";
import {ITermRepoServicer} from "../../interfaces/term/ITermRepoServicer.sol";
import {ITermRepoCollateralManager} from "../../interfaces/term/ITermRepoCollateralManager.sol";
import {MockTermRepoServicer} from "./MockTermRepoServicer.sol";
import {MockTermRepoCollateralManager} from "./MockTermRepoCollateralManager.sol";

contract MockTermRepoToken is ERC20, ITermRepoToken {
    struct RepoTokenContext {
        uint256 redemptionTimestamp;
        address purchaseToken;
        ITermRepoServicer termRepoServicer;
        ITermRepoCollateralManager termRepoCollateralManager;
    }

    bytes32 public termRepoId;
    RepoTokenContext internal repoTokenContext;

    constructor(
        bytes32 _termRepoId,
        address _purchaseToken,
        address _collateral,
        uint256 _maintenanceRatio,
        uint256 _redemptionTimestamp
    ) ERC20("MockRepo", "MockRepo") {
        termRepoId = _termRepoId;
        repoTokenContext.redemptionTimestamp = _redemptionTimestamp;
        repoTokenContext.purchaseToken = _purchaseToken;
        repoTokenContext.termRepoServicer = new MockTermRepoServicer(ITermRepoToken(address(this)), _purchaseToken);
        repoTokenContext.termRepoCollateralManager = new MockTermRepoCollateralManager(
            ITermRepoToken(address(this)), _collateral, _maintenanceRatio
        );
    }

    function redemptionValue() external view returns (uint256) {
        return 1e18;
    }

    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }

    function burn(address account, uint256 amount) external {
        _burn(account, amount);
    }

    function mockServicer() external returns (MockTermRepoServicer) {
        return MockTermRepoServicer(address(repoTokenContext.termRepoServicer));
    }
    
    function config()
        external
        view
        returns (
            uint256 redemptionTimestamp,
            address purchaseToken,
            address termRepoServicer,
            address termRepoCollateralManager
        )
    {
        return (
            repoTokenContext.redemptionTimestamp,
            repoTokenContext.purchaseToken,
            address(repoTokenContext.termRepoServicer),
            address(repoTokenContext.termRepoCollateralManager)
        );
    }
}
