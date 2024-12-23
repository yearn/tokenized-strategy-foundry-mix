pragma solidity 0.8.23;

import "src/interfaces/term/ITermDiscountRateAdapter.sol";

import "src/test/kontrol/Constants.sol";
import "src/test/kontrol/KontrolTest.sol";

contract TermDiscountRateAdapter is ITermDiscountRateAdapter, KontrolTest {
    mapping(address => uint256) _repoRedemptionHaircut;
    mapping(address => uint256) _discountRate;

    function initializeSymbolic() public {
        kevm.symbolicStorage(address(this));
    }

    function initializeSymbolicParamsFor(address repoToken) public {
        uint256 repoRedemptionhaircut = freshUInt256();
        vm.assume(repoRedemptionhaircut <= 1e18);
        _repoRedemptionHaircut[repoToken] = repoRedemptionhaircut;

        uint256 discountRate = freshUInt256();
        vm.assume(discountRate < ETH_UPPER_BOUND);
        _discountRate[repoToken] = discountRate;
    }

    function repoRedemptionHaircut(
        address repoToken
    ) external view returns (uint256) {
        return _repoRedemptionHaircut[repoToken];
    }

    function getDiscountRate(
        address termController,
        address repoToken
    ) external view returns (uint256) {
        return _discountRate[repoToken];
    }

    function getDiscountRate(
        address repoToken
    ) external view returns (uint256) {
        return _discountRate[repoToken];
    }

    function currTermController() external view returns (ITermController) {
        return ITermController(kevm.freshAddress());
    }
}
