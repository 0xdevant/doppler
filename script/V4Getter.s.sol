// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import { Script, console } from "forge-std/Script.sol";
import { AssetData, ModuleState } from "src/Airlock.sol";
import { VestingData } from "src/DERC20.sol";

interface IAirlock {
    function getAssetData(
        address asset
    ) external view returns (AssetData memory assetData);

    function migrate(
        address asset
    ) external;

    function setModuleState(address[] calldata modules, ModuleState[] calldata states) external;
}

interface IDERC20 {
    function getVestingDataOf(
        address account
    ) external view returns (VestingData memory);

    function vestingStart() external view returns (uint256);

    function vestingDuration() external view returns (uint256);

    function computeAvailableVestedAmount(
        address account
    ) external view returns (uint256);

    function release() external;
    function tokenURI() external view returns (string memory);
}

interface IDoppler {
    function startingTime() external view returns (uint256);
    function endingTime() external view returns (uint256);

    function numTokensToSell() external view returns (uint256);
    function initialLpFee() external view returns (uint24);
}

interface IUniswapV4Initializer {
    function deployer() external view returns (address);
}

contract V4GetterScript is Script {
    function run() public {
        // address unichainSepoliaAirlock = 0x651ab94B4777e2e4cdf96082d90C65bd947b73A4;
        // address baseSepoliaAirlock = 0x193F48A45B6025dDeD10bc4BaeEF65c833696387;
        address baseAirlock = 0xAa7f55aB611Ea07A6D4F4D58a05F4338C52e494b;
        address asset = 0x533dB3A4CEf9F024c0Acf8049274f6D4150E1D5b;
        // address recipient = 0xAA25790C239B0Aa94A6A223B13C0b81D1E68942b;
        address hook = 0xD0BDC3c33975FF7D450Be5aFc8e1DF57Bf18B8E0;

        vm.startBroadcast();
        IAirlock airlock = IAirlock(baseAirlock);
        // IDERC20 derc20 = IDERC20(asset);
        // IDoppler doppler = IDoppler(hook);
        IUniswapV4Initializer uniswapV4Initializer = IUniswapV4Initializer(0x7727f8353A30f9753CF8bF7489dAF0ef038900bA);
        // airlock.migrate(asset);

        // address customModule = 0xd97120D5da1eE124c0f9d0379BeBA4903454b314;

        // address[] memory modules = new address[](1);
        // modules[0] = customModule;
        // ModuleState[] memory states = new ModuleState[](1);
        // states[0] = ModuleState.LiquidityMigrator;
        // airlock.setModuleState(modules, states);

        // AssetData memory assetData = airlock.getAssetData(asset);
        // console.log("numeraire:", assetData.numeraire);
        // console.log("numTokensToSell:", assetData.numTokensToSell);
        // console.log("totalSupply:", assetData.totalSupply);
        // console.log("pool:", assetData.pool);

        // uint256 vestingStart = derc20.vestingStart();
        // uint256 vestingDuration = derc20.vestingDuration();
        // VestingData memory vestingData = derc20.getVestingDataOf(recipient);
        // uint256 totalAmount = vestingData.totalAmount;
        // uint256 releasedAmount = vestingData.releasedAmount;

        // console.log("vestingStart:", vestingStart);
        // console.log("vestingDuration:", vestingDuration);
        // console.log("block timestamp:", block.timestamp);

        // console.log("totalAmount:", totalAmount);
        // console.log("releasedAmount:", releasedAmount);
        // console.log("vested amount:", totalAmount * (block.timestamp - vestingStart) / vestingDuration);
        // console.log("compute vested amount:", derc20.computeAvailableVestedAmount(recipient));

        // derc20.release();

        // console.log("startingTime:", doppler.startingTime());
        // console.log("endingTime:", doppler.endingTime());

        // console.log("doppler.numTokensToSell()", doppler.numTokensToSell());
        // console.log("doppler.initialLpFee()", doppler.initialLpFee());

        console.log("uniswapV4Initializer.deployer()", uniswapV4Initializer.deployer());

        vm.stopBroadcast();
    }
}
