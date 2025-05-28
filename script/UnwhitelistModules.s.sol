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
        // TODO: change to PRODUCTION DEPLOYMENT airlock address
        address baseAirlock = 0xAa7f55aB611Ea07A6D4F4D58a05F4338C52e494b;

        vm.startBroadcast();
        IAirlock airlock = IAirlock(baseAirlock);

        // disable token factory module to make any asset creation impossible
        address tokenFactoryModule = 0xd97120D5da1eE124c0f9d0379BeBA4903454b314;

        address[] memory modules = new address[](1);
        modules[0] = tokenFactoryModule;
        ModuleState[] memory states = new ModuleState[](1);
        states[0] = ModuleState.NotWhitelisted;
        airlock.setModuleState(modules, states);

        vm.stopBroadcast();
    }
}
