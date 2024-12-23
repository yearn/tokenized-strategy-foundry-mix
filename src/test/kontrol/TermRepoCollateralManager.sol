pragma solidity 0.8.23;

import "src/interfaces/term/ITermRepoCollateralManager.sol";
import "src/test/kontrol/KontrolTest.sol";

contract TermRepoCollateralManager is ITermRepoCollateralManager, KontrolTest {
    mapping(address => uint256) _maintenanceCollateralRatios;
    address[] _collateralTokens;

    uint256 private collateralTokensSlot;

    function collateralTokensDataSlot(
        uint256 i
    ) internal view returns (uint256) {
        return uint256(keccak256(abi.encodePacked(collateralTokensSlot))) + i;
    }

    function initializeSymbolic() public {
        kevm.symbolicStorage(address(this));

        assembly {
            sstore(collateralTokensSlot.slot, _collateralTokens.slot)
        }

        // For simplicity, choose an arbitrary number of collateral tokens: 2
        _storeUInt256(address(this), collateralTokensSlot, 2);

        for (uint256 i = 0; i < _collateralTokens.length; ++i) {
            // Generate an arbitrary concrete address for each token
            // All repoTokens in the list will share the same colllateral tokens
            address currentToken = address(
                uint160(uint256(keccak256(abi.encodePacked("collateral", i))))
            );

            _storeUInt256(
                address(this),
                collateralTokensDataSlot(i),
                uint256(uint160(currentToken))
            );
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
