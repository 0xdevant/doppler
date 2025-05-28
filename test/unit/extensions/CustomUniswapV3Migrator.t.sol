// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { Test } from "forge-std/Test.sol";
import { TestERC20 } from "@v4-core/test/TestERC20.sol";
import { TickMath } from "@v4-core/libraries/TickMath.sol";
import { ERC20 } from "@openzeppelin/token/ERC20/ERC20.sol";
import { CustomUniswapV3Migrator } from "src/extensions/CustomUniswapV3Migrator.sol";
import { IUniswapV2Factory, IUniswapV2Router02, IUniswapV2Pair } from "src/UniswapV2Migrator.sol";
import { MigrationMath } from "src/UniswapV2Migrator.sol";
import { SenderNotAirlock } from "src/base/ImmutableAirlock.sol";
import {
    UNISWAP_V3_NONFUNGIBLE_POSITION_MANAGER_BASE,
    UNISWAP_V3_ROUTER_02_BASE,
    WETH_BASE
} from "test/shared/Addresses.sol";

contract CustomUniswapV3MigratorTest is Test {
    CustomUniswapV3Migrator public migrator;

    function setUp() public {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), 21_093_509);
        migrator = new CustomUniswapV3Migrator(
            address(this),
            INonfungiblePositionManager(UNISWAP_V3_NONFUNGIBLE_POSITION_MANAGER_BASE),
            ISwapRouter02(UNISWAP_V3_ROUTER_02_BASE),
            address(0xb055)
        );
    }

    function test_receive_ReceivesETHFromAirlock() public {
        uint256 preBalance = address(migrator).balance;
        deal(address(this), 1 ether);
        payable(address(migrator)).transfer(1 ether);
        assertEq(address(migrator).balance, preBalance + 1 ether, "Wrong balance");
    }

    function test_receive_RevertsWhenETHSenderNotAirlock() public {
        deal(address(0xbeef), 1 ether);
        vm.startPrank(address(0xbeef));
        vm.expectRevert(SenderNotAirlock.selector);
        payable(address(migrator)).transfer(1 ether);
    }

    function test_initialize_CreatesPair() public {
        address token0 = address(0x1111);
        address token1 = address(0x2222);
        address pair = migrator.initialize(token0, token1, new bytes(0));
        assertEq(pair, IUniswapV2Factory(UNISWAP_V2_FACTORY_MAINNET).getPair(token0, token1), "Wrong pair");
    }

    function test_initialize_UsesWETHWhenToken0IsZero() public {
        address token0 = address(0);
        address token1 = address(0x2222);
        address pair = migrator.initialize(token0, token1, new bytes(0));
        assertEq(pair, IUniswapV2Factory(UNISWAP_V2_FACTORY_MAINNET).getPair(token1, WETH_MAINNET), "Wrong pair");
    }

    function test_initialize_DoesNotFailWhenPairIsAlreadyCreated() public {
        address token0 = address(0x1111);
        address token1 = address(0x2222);
        IUniswapV2Factory(UNISWAP_V2_FACTORY_MAINNET).createPair(token0, token1);
        address pair = migrator.initialize(token0, token1, new bytes(0));
        assertEq(pair, IUniswapV2Factory(UNISWAP_V2_FACTORY_MAINNET).getPair(token0, token1), "Wrong pair");
    }

    function test_migrate_RevertsWhenSenderNotAirlock() public {
        vm.prank(address(0xbeef));
        vm.expectRevert(SenderNotAirlock.selector);
        migrator.migrate(uint160(0), address(0x1111), address(0x2222), address(0));
    }

    function test_migrate() public {
        TestERC20 token0 = new TestERC20(1000 ether);
        TestERC20 token1 = new TestERC20(1000 ether);

        address pool = migrator.initialize(address(token0), address(token1), new bytes(0));

        token0.transfer(address(migrator), 1000 ether);
        token1.transfer(address(migrator), 1000 ether);
        uint256 liquidity = migrator.migrate(uint160(2 ** 96), address(token0), address(token1), address(0xbeef));

        assertEq(token0.balanceOf(address(migrator)), 0, "Wrong migrator token0 balance");
        assertEq(token1.balanceOf(address(migrator)), 0, "Wrong migrator token1 balance");

        assertEq(token0.balanceOf(pool), 1000 ether, "Wrong pool token0 balance");
        assertEq(token1.balanceOf(pool), 1000 ether, "Wrong pool token1 balance");

        uint256 lockedLiquidity = liquidity / 20;
        assertEq(liquidity - lockedLiquidity, IUniswapV2Pair(pool).balanceOf(address(0xbeef)), "Wrong liquidity");
        assertEq(lockedLiquidity, IUniswapV2Pair(pool).balanceOf(address(migrator.locker())), "Wrong locked liquidity");
    }

    function test_migrate_KeepsCorrectPrice() public {
        TestERC20 token0 = new TestERC20(131_261_409_265_385_327_997_940);
        TestERC20 token1 = new TestERC20(16_622_742_685_037);

        uint160 sqrtPriceX96 = 3_893_493_510_706_508_098_175_185;

        address pool = migrator.initialize(address(token0), address(token1), new bytes(0));

        token0.transfer(address(migrator), 13_126_140_926_538_532_799_794);
        token1.transfer(address(migrator), 16_622_742_685_037);
        migrator.migrate(sqrtPriceX96, address(token0), address(token1), address(0xbeef));
        assertEq(token0.balanceOf(address(migrator)), 0, "Wrong migrator token0 balance");
        assertEq(token1.balanceOf(address(migrator)), 0, "Wrong migrator token1 balance");
        (uint112 reserve0, uint112 reserve1,) = IUniswapV2Pair(pool).getReserves();
        uint256 price = uint256(reserve1) * 2 ** 192 / uint256(reserve0);
        assertApproxEqRel(price, uint256(sqrtPriceX96) * uint256(sqrtPriceX96), 0.00000001e18);
    }

    function test_migrate(uint256 balance0, uint256 balance1, uint160 sqrtPriceX96) public {
        vm.skip(true);
        uint256 max = uint256(int256(type(int128).max));

        vm.assume(balance0 > 0 && balance0 <= max);
        vm.assume(balance1 > 0 && balance1 <= max);
        vm.assume(sqrtPriceX96 > TickMath.MIN_SQRT_PRICE && sqrtPriceX96 <= TickMath.MAX_SQRT_PRICE);

        TestERC20 token0 = new TestERC20(balance0);
        TestERC20 token1 = new TestERC20(balance1);

        address pool = migrator.initialize(address(token0), address(token1), new bytes(0));

        token0.transfer(address(migrator), balance0);
        token1.transfer(address(migrator), balance1);
        uint256 liquidity = migrator.migrate(sqrtPriceX96, address(token0), address(token1), address(0xbeef));

        assertEq(token0.balanceOf(address(migrator)), 0, "Wrong migrator token0 balance");
        assertEq(token1.balanceOf(address(migrator)), 0, "Wrong migrator token1 balance");

        assertEq(token0.balanceOf(pool), balance0, "Wrong pool token0 balance");
        assertEq(token1.balanceOf(pool), balance1, "Wrong pool token1 balance");

        uint256 lockedLiquidity = liquidity / 20;
        assertEq(liquidity - lockedLiquidity, IUniswapV2Pair(pool).balanceOf(address(0xbeef)), "Wrong liquidity");
        assertEq(lockedLiquidity, IUniswapV2Pair(pool).balanceOf(address(migrator.locker())), "Wrong locked liquidity");
    }

    function test_migrate_WrapsETH() public {
        TestERC20 token1 = new TestERC20(1000 ether);
        address pool = migrator.initialize(address(0), address(token1), new bytes(0));

        deal(address(migrator), 100 ether);
        token1.transfer(address(migrator), 100 ether);

        uint256 nativeBalanceBefore = address(migrator).balance;
        migrator.migrate(uint160(2 ** 96), address(0), address(token1), address(0xbeef));
        assertEq(address(migrator).balance, 0, "Migrator ETH balance is wrong");
        assertEq(TestERC20(WETH_MAINNET).balanceOf(address(migrator)), 0, "Migrator WETH balance is wrong");
        assertEq(TestERC20(WETH_MAINNET).balanceOf(address(pool)), nativeBalanceBefore, "Pool WETH balance is wrong");
    }

    // function test_migrate_CustomLPToEOA_WhenLiquidityMigratorDataNotEmpty() public {
    //     TestERC20 token0 = new TestERC20(1000 ether);
    //     TestERC20 token1 = new TestERC20(1000 ether);
    //     // allocate 3% LP to alice during migration
    //     uint256 customLPWad = 0.03 ether;
    //     uint32 lockUpPeriod = 30 days;
    //     address alice = makeAddr("alice");

    //     bytes memory liquidityMigratorData = abi.encode(customLPWad, alice, lockUpPeriod);
    //     address pool = migrator.initialize(address(token0), address(token1), liquidityMigratorData);

    //     assertEq(migrator.customLPWad(), customLPWad, "Wrong custom LP wad");
    //     assertEq(migrator.lockUpPeriod(), lockUpPeriod, "Wrong lock up period");
    //     assertEq(migrator.customLPRecipient(), alice, "Wrong custom LP recipient");

    //     token0.transfer(address(migrator), 1000 ether);
    //     token1.transfer(address(migrator), 1000 ether);
    //     uint256 liquidity = migrator.migrate(uint160(2 ** 96), address(token0), address(token1), address(0xbeef));

    //     assertEq(token0.balanceOf(address(migrator)), 0, "Wrong migrator token0 balance");
    //     assertEq(token1.balanceOf(address(migrator)), 0, "Wrong migrator token1 balance");

    //     assertEq(token0.balanceOf(pool), 1000 ether, "Wrong pool token0 balance");
    //     assertEq(token1.balanceOf(pool), 1000 ether, "Wrong pool token1 balance");

    //     uint256 customLockedLiquidity = liquidity * customLPWad / 1 ether;
    //     assertEq(liquidity - customLockedLiquidity, IUniswapV2Pair(pool).balanceOf(address(0xbeef)), "Wrong liquidity");
    //     assertEq(0, IUniswapV2Pair(pool).balanceOf(alice), "Wrong custom locked liquidity");
    //     assertEq(
    //         customLockedLiquidity,
    //         IUniswapV2Pair(pool).balanceOf(address(migrator.CUSTOM_LP_LOCKER())),
    //         "Wrong custom locked liquidity"
    //     );
    // }

    // function test_migrate_CustomLPToEOA_RevertsWhenMaxLPAllocationExceeded() public {
    //     TestERC20 token0 = new TestERC20(1000 ether);
    //     TestERC20 token1 = new TestERC20(1000 ether);
    //     // try to allocate 20% LP to alice during migration
    //     uint256 customLPWad = 0.2 ether;
    //     uint32 lockUpPeriod = 30 days;
    //     address alice = makeAddr("alice");

    //     bytes memory liquidityMigratorData = abi.encode(customLPWad, alice, lockUpPeriod);
    //     vm.expectRevert(abi.encodeWithSelector(ICustomLPUniswapV2Migrator.MaxCustomLPWadExceeded.selector));
    //     migrator.initialize(address(token0), address(token1), liquidityMigratorData);
    // }

    // function test_migrate_CustomLPToSmartContract_RevertsWhenLPRecipientIsNotEOA() public {
    //     TestERC20 token0 = new TestERC20(1000 ether);
    //     TestERC20 token1 = new TestERC20(1000 ether);
    //     uint256 customLPWad = 0.01 ether;
    //     uint32 lockUpPeriod = 30 days;
    //     address testContract = makeAddr("testContract");
    //     vm.etch(testContract, new bytes(1));

    //     bytes memory liquidityMigratorData = abi.encode(customLPWad, testContract, lockUpPeriod);
    //     vm.expectRevert(abi.encodeWithSelector(ICustomLPUniswapV2Migrator.RecipientNotEOA.selector));
    //     migrator.initialize(address(token0), address(token1), liquidityMigratorData);
    // }

    // function test_migrate_CustomLPToSmartContract_RevertsWhenLessThanMinLockPeriod() public {
    //     TestERC20 token0 = new TestERC20(1000 ether);
    //     TestERC20 token1 = new TestERC20(1000 ether);
    //     uint256 customLPWad = 0.03 ether;
    //     uint32 lockUpPeriod = 29 days;
    //     address alice = makeAddr("alice");

    //     bytes memory liquidityMigratorData = abi.encode(customLPWad, alice, lockUpPeriod);
    //     vm.expectRevert(abi.encodeWithSelector(ICustomLPUniswapV2Migrator.LessThanMinLockPeriod.selector));
    //     migrator.initialize(address(token0), address(token1), liquidityMigratorData);
    // }
}
