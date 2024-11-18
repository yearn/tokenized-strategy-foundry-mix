import "forge-std/Script.sol";
import "../src/Strategy.sol";

interface TermVaultGovernanceFactory {
    function deploySafe(
        address proposer,
        address strategy,
        address governor,
        uint256 saltNonce
    ) external;
}

contract DeployGovernance is Script {

    function run() external {
        uint256 deployerPK = vm.envUint("PRIVATE_KEY");

        // Set up the RPC URL (optional if you're using the default foundry config)
        string memory rpcUrl = vm.envString("RPC_URL");

        vm.startBroadcast(deployerPK);

        TermVaultGovernanceFactory factory = TermVaultGovernanceFactory(vm.envAddress("GOVERNANCE_FACTORY"));
        address proposer = vm.envAddress("PROPOSER");
        address strategy = vm.envAddress("STRATEGY");
        address governor = vm.envAddress("GOVERNOR");
        uint256 saltNonce = block.number;

        factory.deploySafe(proposer, strategy, governor, saltNonce);

        vm.stopBroadcast();
    }

}