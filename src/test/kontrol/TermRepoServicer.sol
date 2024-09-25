pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import "kontrol-cheatcodes/KontrolCheats.sol";

import "src/interfaces/term/ITermRepoServicer.sol";

contract TermRepoServicer is ITermRepoServicer, Test, KontrolCheats {
    address _termRepoToken;

    function initializeSymbolic(address termRepoToken) public {
        kevm.symbolicStorage(address(this));
        _termRepoToken = termRepoToken;
    }

    function redeemTermRepoTokens(
        address redeemer,
        uint256 amountToRedeem
    ) external {
        // Function might revert in some cases
        require(kevm.freshBool() != 0);

        kevm.symbolicStorage(address(this));
        kevm.symbolicStorage(_termRepoToken);
    }
    
    function termRepoToken() external view returns (address) {
        return _termRepoToken;
    }

    function termRepoLocker() external view returns (address) {
        return kevm.freshAddress();
    }

    function purchaseToken() external view returns (address) {
        return kevm.freshAddress();
    }
}
