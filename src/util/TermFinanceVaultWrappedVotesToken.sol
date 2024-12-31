// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract TermFinanceVaultWrappedVotesToken is ERC20Votes, Ownable {
    ERC20 public immutable underlyingToken;

    // Mapping to track the amount of underlying tokens deposited by each account
    mapping(address => uint256) public deposits;

    event Wrapped(address indexed user, uint256 amount);
    event Unwrapped(address indexed user, uint256 amount);

    constructor(
        ERC20 _underlyingToken,
        string memory name,
        string memory symbol
    ) ERC20(name, symbol) ERC20Permit(name) {
        underlyingToken = _underlyingToken;
    }

    function decimals() public view override returns (uint8) {
        return underlyingToken.decimals();
    }

    // Function to wrap the underlying tokens and mint ERC20Votes tokens
    function wrap(uint256 amount) external {
        require(amount > 0, "Amount must be greater than zero");

        // Transfer the underlying tokens from the user to the contract
        require(
            underlyingToken.transferFrom(msg.sender, address(this), amount),
            "Transfer failed"
        );

        // Track the deposit
        deposits[msg.sender] += amount;

        // Mint ERC20Votes tokens to the user
        _mint(msg.sender, amount);

        emit Wrapped(msg.sender, amount);
    }

    // Function to unwrap the ERC20Votes tokens and retrieve the underlying tokens
    function unwrap(uint256 amount) external {
        require(amount > 0, "Amount must be greater than zero");
        require(balanceOf(msg.sender) >= amount, "Insufficient balance");

        // Burn the ERC20Votes tokens
        _burn(msg.sender, amount);

        // Reduce the deposit record
        deposits[msg.sender] -= amount;

        // Transfer the underlying tokens back to the user
        require(
            underlyingToken.transfer(msg.sender, amount),
            "Transfer failed"
        );

        emit Unwrapped(msg.sender, amount);
    }
}
