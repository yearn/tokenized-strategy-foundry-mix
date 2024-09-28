pragma solidity 0.8.23;

import "forge-std/Test.sol";
import "kontrol-cheatcodes/KontrolCheats.sol";

import "src/interfaces/term/ITermDiscountRateAdapter.sol";

import "src/test/kontrol/Constants.sol";

contract TermDiscountRateAdapter is ITermDiscountRateAdapter, Test, KontrolCheats {
    mapping(address => uint256) _repoRedemptionHaircut;
    mapping(address => uint256) _discountRate;

    function initializeSymbolic() public {
        kevm.symbolicStorage(address(this));
    }

    function initializeSymbolicFor(address repoToken) public {
        uint256 repoRedemptionHaircut = freshUInt256();
        vm.assume(repoRedemptionHaircut <= 1e18);
        _repoRedemptionHaircut[repoToken] = repoRedemptionHaircut;

        uint256 discountRate = freshUInt256();
        vm.assume(discountRate < ETH_UPPER_BOUND);
        _discountRate[repoToken] = discountRate;
    }

    function repoRedemptionHaircut(address repoToken) external view returns (uint256) {
        return _repoRedemptionHaircut[repoToken];
    }

    function getDiscountRate(address repoToken) external view returns (uint256) {
        return _discountRate[repoToken];
    }

    function TERM_CONTROLLER() external view returns (ITermController) {
        return ITermController(kevm.freshAddress());
    }
}
