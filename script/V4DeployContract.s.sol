// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import { Script, console } from "forge-std/Script.sol";
import { CustomLPUniswapV2Migrator } from "src/extensions/CustomLPUniswapV2Migrator.sol";
import { IUniswapV2Factory, IUniswapV2Router02 } from "src/UniswapV2Migrator.sol";

contract V4DeployContract is Script {
    function run() public {
        // TODO: change after official airlock is deployed
        address airlock = ;
        address uniswapV2Factory = 0x8909Dc15e40173Ff4699343b6eB8132c65e18eC6;
        address uniswapV2Router02 = 0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24;
        // TODO: finalize after official airlock is deployed
        address owner = 0xDc04f489d8497F850F6729cE23BF10670e903aEa;

        bytes32 salt = bytes32(uint256(1));

        vm.startBroadcast();

        CustomLPUniswapV2Migrator migrator = new CustomLPUniswapV2Migrator{ salt: salt }(
            airlock, IUniswapV2Factory(uniswapV2Factory), IUniswapV2Router02(uniswapV2Router02), owner
        );

        console.log("migrator deployed at", address(migrator));

        vm.stopBroadcast();
    }
}
