// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import { DeployScript, ScriptData } from "script/Deploy.s.sol";

contract DeployBaseSepolia is DeployScript {
    function setUp() public override {
        _scriptData = ScriptData({
            deployBundler: true,
            deployLens: true,
            explorerUrl: "https://base.blockscout.com/address/",
            poolManager: 0x498581fF718922c3f8e6A244956aF099B2652b2b,
            protocolOwner: 0xCCF7582371b4d6e3a77FFD423D1E9500EBD041Ac,
            quoterV2: 0x3d4e44Eb1374240CE5F1B871ab261CD16335B76a,
            uniswapV2Factory: 0x8909Dc15e40173Ff4699343b6eB8132c65e18eC6,
            uniswapV2Router02: 0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24,
            uniswapV3Factory: 0x33128a8fC17869897dcE68Ed026d694621f6FDfD,
            universalRouter: 0x6fF5693b99212Da76ad316178A184AB56D299b43,
            stateView: 0xA3c0c9b65baD0b08107Aa264b0f3dB444b867A71
        });
    }
}
