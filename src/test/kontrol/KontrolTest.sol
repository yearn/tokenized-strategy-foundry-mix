pragma solidity 0.8.23;

import "forge-std/Vm.sol";
import "forge-std/Test.sol";
import "kontrol-cheatcodes/KontrolCheats.sol";

contract KontrolTest is Test, KontrolCheats {
    // Note: there are lemmas dependent on `ethUpperBound`
    uint256 constant ethMaxWidth = 96;
    uint256 constant ethUpperBound = 2 ** ethMaxWidth;
    // Note: 2 ** 35 takes us to year 3058
    uint256 constant timeUpperBound = 2 ** 35;

    function infoAssert(bool condition, string memory message) external {
        if (!condition) {
            revert(message);
        }
    }

    enum Mode {
        Assume,
        Try,
        Assert
    }

    function _establish(Mode mode, bool condition) internal pure returns (bool) {
        if (mode == Mode.Assume) {
            vm.assume(condition);
            return true;
        } else if (mode == Mode.Try) {
            return condition;
        } else {
            assert(condition);
            return true;
        }
    }

    function _loadUInt256(address contractAddress, uint256 slot) internal view returns (uint256) {
        return uint256(vm.load(contractAddress, bytes32(slot)));
    }

    function _loadAddress(address contractAddress, uint256 slot) internal view returns (address) {
        return address(uint160(uint256(vm.load(contractAddress, bytes32(slot)))));
    }

    function _storeBytes32(address contractAddress, uint256 slot, bytes32 value) internal {
        vm.store(contractAddress, bytes32(slot), value);
    }

    function _storeUInt256(address contractAddress, uint256 slot, uint256 value) internal {
        vm.store(contractAddress, bytes32(slot), bytes32(value));
    }

    function _storeAddress(address contractAddress, uint256 slot, address value) internal {
        vm.store(contractAddress, bytes32(slot), bytes32(uint256(uint160(value))));
    }

    function _assumeNoOverflow(uint256 augend, uint256 addend) internal {
        unchecked {
            vm.assume(augend < augend + addend);
        }
    }
}
