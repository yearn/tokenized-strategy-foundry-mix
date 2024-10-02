pragma solidity 0.8.23;

import "forge-std/Vm.sol";
import "forge-std/Test.sol";
import "kontrol-cheatcodes/KontrolCheats.sol";

contract KontrolTest is Test, KontrolCheats {
    // Note: there are lemmas dependent on `ethUpperBound`
    uint256 constant ethMaxWidth = 96;
    uint256 constant ethUpperBound = 2 ** ethMaxWidth;
    uint256 constant timeUpperBound = 2 ** 40;

    enum Mode {
        Assume,
        Assert
    }

    function _establish(Mode mode, bool condition) internal pure {
        if (mode == Mode.Assume) {
            vm.assume(condition);
        } else {
            assert(condition);
        }
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
}