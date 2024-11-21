#!/usr/bin/env bash

script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
release_version="${RELEASE_VERSION:-development}"
release_name="${RELEASE_NAME:-development}"
release_body="${RELEASE_BODY:-development}"

parent_branch="${PARENT_BRANCH:-main}"

create_pr="${CREATE_PR:-false}"

docs_repo_dir="${script_dir}/../term-finance-developer-docs"
release_dir="${docs_repo_dir}/periphery-contracts/curated-vaults/solidity-api-${release_version}"

set -eux -o pipefail

# Remove files/directories that will be replaced
rm -rf "${release_dir}"
mkdir -p "${release_dir}"

# Copy only necessary files
cp -r "${script_dir}/docs/src/src/RepoTokenList.sol/library.RepoTokenList.md" "${release_dir}/repotokenlist.sol-repotokenlist.md"
cp -r "${script_dir}/docs/src/src/RepoTokenList.sol/struct.RepoTokenListData.md" "${release_dir}/repotokenlist.sol-repotokenlistdata.md"
cp -r "${script_dir}/docs/src/src/RepoTokenList.sol/struct.RepoTokenListNode.md" "${release_dir}/repotokenlist.sol-repotokenlistnode.md"
cp -r "${script_dir}/docs/src/src/RepoTokenUtils.sol/library.RepoTokenUtils.md" "${release_dir}/repotokenutils.sol-repotokenutils.md"
cp -r "${script_dir}/docs/src/src/Strategy.sol/contract.Strategy.md" "${release_dir}/strategy.sol-strategy.md"
cp -r "${script_dir}/docs/src/src/TermAuctionList.sol/library.TermAuctionList.md" "${release_dir}/termauctionlist.sol-termauctionlist.md"
cp -r "${script_dir}/docs/src/src/TermAuctionList.sol/struct.PendingOffer.md" "${release_dir}/termauctionlist.sol-pendingoffer.md"
cp -r "${script_dir}/docs/src/src/TermAuctionList.sol/struct.TermAuctionListData.md" "${release_dir}/termauctionlist.sol-termauctionlistdata.md"
cp -r "${script_dir}/docs/src/src/TermAuctionList.sol/struct.TermAuctionListNode.md" "${release_dir}/termauctionlist.sol-termauctionlistnode.md"
cp -r "${script_dir}/docs/src/src/TermDiscountRateAdapter.sol/contract.TermDiscountRateAdapter.md" "${release_dir}/termdiscountrateadapter.sol-termdiscountrateadapter.md"
cp -r "${script_dir}/docs/src/src/TermVaultEventEmitter.sol/contract.TermVaultEventEmitter.md" "${release_dir}/termvaulteventemitter.sol-termvaulteventemitter.md"
cp -r "${script_dir}/docs/src/src/util/TermFinanceVaultWrappedVotesToken.sol/contract.TermFinanceVaultWrappedVotesToken.md" "${release_dir}/termfinancevaultwrappedvotestoken.sol-termfinancevaultwrappedvotestoken.md"

# Only copy docgen if it exists
if [ -d "${script_dir}/docgen" ]; then
  mkdir -p "${release_dir}/docgen"
  cp -r "${script_dir}/docgen/"* "${release_dir}"
fi

# Add headers to generated docs
if [ -d "${script_dir}/docgen-headers" ]; then
  for file in "${script_dir}"/docgen-headers/*; do
    filename="$(basename -- "${file}")"
    tmp_file="$(mktemp)"
    cat "${file}" > "${tmp_file}"
    echo >> "${tmp_file}"
    echo >> "${tmp_file}"
    cat "${release_dir}/${filename}" >> "${tmp_file}"
    mv "${tmp_file}" "${release_dir}/${filename}"
  done
fi

# Copy docs to latest
rm -rf "${docs_repo_dir}/periphery-contracts/curated-vaults/solidity-api-latest"
cp -r "${release_dir}" "${docs_repo_dir}/periphery-contracts/curated-vaults/solidity-api-latest"

# Update SUMMARY.md
sed -i '' '/<!-- __MARKER_VAULTS_SOLIDITY_API_VERSIONS__ -->/r /dev/stdin' "${docs_repo_dir}/SUMMARY.md" << EOF
  * [Solidity API - ${release_version}](periphery-contracts/curated-vaults/${release_version}/README.md)
    * [RepoTokenList.sol#RepoTokenList](periphery-contracts/curated-vaults/${release_version}/RepoTokenList.md)
    * [RepoTokenList.sol#RepoTokenListData](periphery-contracts/curated-vaults/${release_version}/RepoTokenListData.md)
    * [RepoTokenList.sol#RepoTokenListNode](periphery-contracts/curated-vaults/${release_version}/RepoTokenListNode.md)
    * [RepoTokenUtils.sol#RepoTokenUtils](periphery-contracts/curated-vaults/${release_version}/RepoTokenUtils.md)
    * [Strategy.sol#Strategy](periphery-contracts/curated-vaults/${release_version}/Strategy.md)
    * [TermAuctionList.sol#TermAuctionList](periphery-contracts/curated-vaults/${release_version}/TermAuctionList.md)
    * [TermAuctionList.sol#PendingOffer](periphery-contracts/curated-vaults/${release_version}/PendingOffer.md)
    * [TermAuctionList.sol#TermAuctionListData](periphery-contracts/curated-vaults/${release_version}/TermAuctionListData.md)
    * [TermAuctionList.sol#TermAuctionListNode](periphery-contracts/curated-vaults/${release_version}/TermAuctionListNode.md)
    * [TermDiscountRateAdapter.sol#TermDiscountRateAdapter](periphery-contracts/curated-vaults/${release_version}/TermDiscountRateAdapter.md)
    * [TermVaultEventEmitter.sol#TermVaultEventEmitter](periphery-contracts/curated-vaults/${release_version}/TermVaultEventEmitter.md)
    * [TermFinanceVaultWrappedVotesToken.sol#TermFinanceVaultWrappedVotesToken](periphery-contracts/curated-vaults/${release_version}/TermFinanceVaultWrappedVotesToken.md)
EOF

# Only run the following if `create_pr` is set to "true"
if [ "${create_pr}" = "true" ]; then
  cd "${docs_repo_dir}"

  # Setup git config
  git config user.name "Term Finance"
  git config user.email "devops@termfinance.io"

  # Commit changes to new release branch.
  git switch -c "listings-release-${release_version}"
  git add .
  git commit -m "${release_name}" -m "${release_body}"
  git push -f origin "listings-release-${release_name}"

  # Create a PR for the new branch to the parent branch
  gh pr --repo term-finance/term-finance-developer-docs create \
    --base "${parent_branch}" \
    --title "${release_name}" \
    --body "${release_body}"

  # Cleanup
  cd -
  rm -rf "${docs_repo_dir}"
fi
