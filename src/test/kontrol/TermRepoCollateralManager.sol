pragma solidity 0.8.23;

import "forge-std/Test.sol";
import "kontrol-cheatcodes/KontrolCheats.sol";

import "src/interfaces/term/ITermRepoCollateralManager.sol";

contract TermRepoCollateralManager is ITermRepoCollateralManager, Test, KontrolCheats {
    mapping(address => uint256) _maintenanceCollateralRatios;
    address[] _collateralTokens;

    function initializeSymbolic() public {
        kevm.symbolicStorage(address(this));

        // For simplicity, choose an arbitrary number of collateral tokens
        vm.assume(_collateralTokens.length == 3);

        for (uint256 i = 0; i < _collateralTokens.length; ++i) {
            // Generate an arbitrary concrete address for each token
            address currentToken = address(
                uint160(uint256(keccak256(abi.encodePacked("collateral", i))))
            );

            _collateralTokens[i] = currentToken;
            _maintenanceCollateralRatios[currentToken] = freshUInt256();
        }
    }

    function maintenanceCollateralRatios(
        address collateralToken
    ) external view returns (uint256) {
        return _maintenanceCollateralRatios[collateralToken];
    }

    function numOfAcceptedCollateralTokens() external view returns (uint8) {
        return uint8(_collateralTokens.length);
    }

    function collateralTokens(uint256 index) external view returns (address) {
        return _collateralTokens[index];
    }
}
