/// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ERC20} from "@openzeppelin/token/ERC20/ERC20.sol";
import {ERC20Votes} from "@openzeppelin/token/ERC20/extensions/ERC20Votes.sol";
import {Ownable} from "@openzeppelin/access/Ownable.sol";
import {ERC20Permit} from "@openzeppelin/token/ERC20/extensions/ERC20Permit.sol";
import {Nonces} from "@openzeppelin/utils/Nonces.sol";

/**
 * TODO:
 * - Add mint cap: bounded annual max inflation which can only go down
 */
error MintingNotStartedYet();

contract DERC20 is ERC20, ERC20Votes, ERC20Permit, Ownable {
    uint256 public immutable mintStartDate;
    uint256 public immutable yearlyMintCap;

    constructor(string memory name_, string memory symbol_, uint256 initialSupply, address recipient, address owner_)
        ERC20(name_, symbol_)
        ERC20Permit(name_)
        Ownable(owner_)
    {
        _mint(recipient, initialSupply);
        mintStartDate = block.timestamp + 365 days;
    }

    function mint(address to, uint256 value) external onlyOwner {
        require(block.timestamp >= mintStartDate, MintingNotStartedYet());
        _mint(to, value);
    }

    function _update(address from, address to, uint256 value) internal override(ERC20, ERC20Votes) {
        super._update(from, to, value);
    }

    function nonces(address owner) public view override(ERC20Permit, Nonces) returns (uint256) {
        return super.nonces(owner);
    }
}
