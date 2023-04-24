-include .env

# deps
update:; forge update
build  :; forge build
size  :; forge build --sizes

# storage inspection
inspect :; forge inspect ${contract} storage-layout --pretty

FORK_URL := ${ETH_RPC_URL} 

# local tests without fork
test  :; forge test -vv --fork-url ${FORK_URL} --etherscan-api-key ${ETHERSCAN_API_KEY}
trace  :; forge test -vvv --fork-url ${FORK_URL} --etherscan-api-key ${ETHERSCAN_API_KEY}
gas  :; forge test --gas-report
test-contract  :; forge test -vv --match-contract $(contract)
test-contract-gas  :; forge test --gas-report --match-contract ${contract}
trace-contract  :; forge test -vvv --match-contract $(contract)
test-test  :; forge test -vv --match-test $(test)
trace-test  :; forge test -vvv --match-test $(test)

clean  :; forge clean
snapshot :; forge snapshot