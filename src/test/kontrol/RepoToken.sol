pragma solidity 0.8.23;

import "forge-std/Test.sol";
import "kontrol-cheatcodes/KontrolCheats.sol";

import "src/interfaces/term/ITermRepoServicer.sol";
import "src/interfaces/term/ITermRepoToken.sol";

import "src/test/kontrol/Constants.sol";
import "src/test/kontrol/TermRepoServicer.sol";

contract RepoToken is ITermRepoToken, Test, KontrolCheats {
    mapping(address => uint256) _balance;
    uint256 _redemptionTimestamp;
    uint256 _redemptionValue;
    TermRepoServicer _termRepoServicer;

    function initializeSymbolic() public {
        kevm.symbolicStorage(address(this));

        uint256 senderBalance = freshUInt256();
        vm.assume(senderBalance < ETH_UPPER_BOUND);
        _balance[msg.sender] = senderBalance;

        _redemptionTimestamp = freshUInt256();
        vm.assume(_redemptionTimestamp < TIME_UPPER_BOUND);

        _redemptionValue = freshUInt256();
        vm.assume(_redemptionValue < ETH_UPPER_BOUND);

        _termRepoServicer = new TermRepoServicer();
        _termRepoServicer.initializeSymbolic(address(this));
    }

    function decimals() public view virtual returns (uint8) {
        return 18;
    }

    function balanceOf(address account) public view virtual returns (uint256) {
        return _balance[account];
    }

    function redemptionValue() external view returns (uint256) {
        return _redemptionValue;
    }

    function config() external view returns (
        uint256 redemptionTimestamp,
        address purchaseToken,
        address termRepoServicer,
        address termRepoCollateralManager
    ) {
        redemptionTimestamp = _redemptionTimestamp;
        purchaseToken = kevm.freshAddress();
        termRepoServicer = address(_termRepoServicer);
        termRepoCollateralManager = kevm.freshAddress();
    }

    function termRepoId() external view returns (bytes32) {
        return bytes32(freshUInt256());
    }

    function allowance(address owner, address spender) external view returns (uint256) {
        return freshUInt256();
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        kevm.symbolicStorage(address(this));
        return kevm.freshBool() > 0;
    }

    function totalSupply() external view returns (uint256) {
        return freshUInt256();
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        kevm.symbolicStorage(address(this));
        return kevm.freshBool() > 0;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        kevm.symbolicStorage(address(this));
        return kevm.freshBool() > 0;
    }
}
