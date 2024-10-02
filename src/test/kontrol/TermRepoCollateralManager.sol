pragma solidity 0.8.23;

import "src/interfaces/term/ITermRepoCollateralManager.sol";
import "src/test/kontrol/KontrolTest.sol";

contract TermRepoCollateralManager is ITermRepoCollateralManager, KontrolTest {
    mapping(address => uint256) _maintenanceCollateralRatios;
    address[] _collateralTokens;

    function collateralTokensDataSlot(uint256 i) public view returns (uint256) {
      return uint256(keccak256(abi.encodePacked(uint256(28)))) + i;
    }

    function initializeSymbolic() public {
        kevm.symbolicStorage(address(this));

        // For simplicity, choose an arbitrary number of collateral tokens: 3
        // _collateralTokens: slot 28
        _storeUInt256(address(this), 28, 3);

        for (uint256 i = 0; i < _collateralTokens.length; ++i) {
            // Generate an arbitrary concrete address for each token
            address currentToken = address(
                uint160(uint256(keccak256(abi.encodePacked("collateral", i))))
            );

            _storeUInt256(address(this), collateralTokensDataSlot(i), uint256(uint160(currentToken)));
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
