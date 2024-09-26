/// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ERC20} from "openzeppelin/token/ERC20/ERC20.sol";
import {ERC20Votes} from "openzeppelin/token/ERC20/extensions/ERC20Votes.sol";
import {EIP712} from "openzeppelin/utils/cryptography/EIP712.sol";
import {Ownable} from "openzeppelin/access/Ownable.sol";

/**
 * TODO:
 * - Add mint cap: bounded annual max inflation which can only go down
 */
error MintingNotStartedYet();

contract DERC20 is ERC20Votes, Ownable {
    uint256 public feeOnTransfer;
    mapping(address => bool) public isExemptFromFees;
    address public feeCollector;

    uint256 public immutable mintStartDate;
    uint256 public immutable yearlyMintCap;

    constructor(
        string memory name_,
        string memory symbol_,
        uint256 totalSupply_,
        address recipient,
        uint256 feeOnTransfer_,
        address[] memory exemptFromFees,
        address feeCollector_,
        address owner_
    ) EIP712(name_, symbol_) ERC20(name_, symbol_) Ownable(owner_) {
        _mint(recipient, totalSupply_);
        feeOnTransfer = feeOnTransfer_;

        for (uint256 i = 0; i < exemptFromFees.length; i++) {
            isExemptFromFees[exemptFromFees[i]] = true;
        }

        feeCollector = feeCollector_;
        isExemptFromFees[feeCollector_] = true; // Just in case

        mintStartDate = block.timestamp + 365 days;
    }

    function mint(address to, uint256 value) external onlyOwner {
        require(block.timestamp >= mintStartDate, MintingNotStartedYet());
        _mint(to, value);
    }

    function _update(address from, address to, uint256 value) internal virtual override {
        super._update(from, to, value);

        // TODO: Check when should we charge / NOT charge the fee?
        if (feeOnTransfer > 0 && !isExemptFromFees[from] && !isExemptFromFees[to]) {
            uint256 fee = feeOnTransfer * value / 10_000;
            _transfer(to, feeCollector, fee);
        }
    }
}
