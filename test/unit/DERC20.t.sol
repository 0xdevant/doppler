/// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { Test } from "forge-std/Test.sol";
import { DERC20 } from "src/DERC20.sol";

uint256 constant INITIAL_SUPPLY = 1e26;
uint256 constant YEARLY_MINT_CAP = 1e25;
uint256 constant VESTING_DURATION = 365 days;

contract DERC20Test is Test {
    DERC20 public token;

    function test_constructor() public {
        address[] memory recipients = new address[](2);
        recipients[0] = address(0xa);
        recipients[1] = address(0xb);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1e23;
        amounts[1] = 2e23;

        token = new DERC20(
            "Test",
            "TST",
            INITIAL_SUPPLY,
            address(0xb0b),
            address(0xbeef),
            YEARLY_MINT_CAP,
            VESTING_DURATION,
            recipients,
            amounts
        );

        assertEq(token.name(), "Test", "Wrong name");
        assertEq(token.symbol(), "TST", "Wrong symbol");
        assertEq(token.totalSupply(), INITIAL_SUPPLY, "Wrong total supply");
        assertEq(
            token.balanceOf(address(0xb0b)), INITIAL_SUPPLY - amounts[0] - amounts[1], "Wrong balance of recipient"
        );
        assertEq(token.mintStartDate(), block.timestamp + 365 days, "Wrong mint start date");
        assertEq(token.owner(), address(0xbeef), "Wrong owner");
        assertEq(token.yearlyMintCap(), YEARLY_MINT_CAP, "Wrong yearly mint cap");
        assertEq(token.vestingStart(), block.timestamp, "Wrong vesting start");
        assertEq(token.vestingDuration(), VESTING_DURATION, "Wrong vesting duration");
    }
}
