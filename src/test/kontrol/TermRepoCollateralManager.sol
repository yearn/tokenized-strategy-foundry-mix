pragma solidity 0.8.23;

import "forge-std/Test.sol";
import "kontrol-cheatcodes/KontrolCheats.sol";

import "src/interfaces/term/ITermRepoCollateralManager.sol";

contract TermRepoCollateralManager is ITermRepoCollateralManager, Test, KontrolCheats {
    mapping(address => uint256) _maintenanceCollateralRatios;
    uint8 _numOfAcceptedCollateralTokens;
    address[] _collateralTokens;

    function initializeSymbolic() public {
        kevm.symbolicStorage(address(this));

        _numOfAcceptedCollateralTokens = freshUInt8();

        for (uint256 i = 0; i < _numOfAcceptedCollateralTokens; ++i) {
            address currentToken = kevm.freshAddress();
            _collateralTokens.push(currentToken);
            _maintenanceCollateralRatios[currentToken] = freshUInt256();
        }
    }

    function maintenanceCollateralRatios(
        address collateralToken
    ) external view returns (uint256) {
        return _maintenanceCollateralRatios[collateralToken];
    }

    function numOfAcceptedCollateralTokens() external view returns (uint8) {
        return _numOfAcceptedCollateralTokens;
    }

    function collateralTokens(uint256 index) external view returns (address) {
        return _collateralTokens[index];
    }
}
