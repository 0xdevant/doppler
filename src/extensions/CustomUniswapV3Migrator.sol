// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { SafeTransferLib, ERC20 } from "@solmate/utils/SafeTransferLib.sol";
import { WETH as IWETH } from "@solmate/tokens/WETH.sol";
import { TickMath } from "@v4-core/libraries/TickMath.sol";
import { FullMath } from "@v4-core/libraries/FullMath.sol";
import { IUniswapV3Factory } from "@v3-core/interfaces/IUniswapV3Factory.sol";
import { IUniswapV3Pool } from "@v3-core/interfaces/IUniswapV3Pool.sol";
import { IUniswapV3MintCallback } from "@v3-core/interfaces/callback/IUniswapV3MintCallback.sol";
import { INonfungiblePositionManager } from "@v3-periphery/interfaces/INonfungiblePositionManager.sol";
import { IWETH9 } from "@v3-periphery/interfaces/external/IWETH9.sol";
import { ILiquidityMigrator } from "src/interfaces/ILiquidityMigrator.sol";
import { ISwapRouter02 } from "src/extensions/interfaces/ISwapRouter02.sol";
import { MigrationMath } from "src/libs/MigrationMath.sol";
import { CustomLPUniswapV2Locker } from "src/extensions/CustomLPUniswapV2Locker.sol";
import { ImmutableAirlock } from "src/base/ImmutableAirlock.sol";

/**
 * @author ant from Long
 * @notice An extension built on top of UniswapV2Migrator to enable locking LP for a custom period
 */
contract CustomUniswapV3Migrator is ILiquidityMigrator, ImmutableAirlock {
    using SafeTransferLib for ERC20;

    /// @dev Constant used to increase precision during calculations
    uint256 constant WAD = 1 ether;
    /// @dev Maximum amount of liquidity that can be allocated to `lpAllocationRecipient` (% expressed in WAD i.e. max 5%)
    uint256 constant MAX_CUSTOM_LP_WAD = 0.05 ether;
    /// @dev Minimum lock up period for the custom LP allocation
    uint256 public constant MIN_LOCK_PERIOD = 30 days;

    INonfungiblePositionManager public immutable NONFUNGIBLE_POSITION_MANAGER;
    IUniswapV3Factory public immutable FACTORY;
    IWETH9 public immutable WETH;
    CustomLPUniswapV2Locker public immutable CUSTOM_LP_LOCKER;

    /// @dev Lock up period for the LP tokens allocated to `customLPRecipient`
    uint32 public lockUpPeriod;
    /// @dev Allow custom allocation of LP tokens other than `LP_TO_LOCK_WAD` (% expressed in WAD)
    uint64 public customLPWad;
    /// @dev Address of the recipient of the custom LP allocation
    address public customLPRecipient;

    uint24 public fee;

    /// @notice Thrown when the custom LP allocation exceeds `MAX_CUSTOM_LP_WAD`
    error MaxCustomLPWadExceeded();
    /// @notice Thrown when the recipient is not an EOA
    error RecipientNotEOA();
    /// @notice Thrown when the lock up period is less than `MIN_LOCK_PERIOD`
    error LessThanMinLockPeriod();
    /// @notice Thrown when the input is zero
    error InvalidInput();

    receive() external payable onlyAirlock { }

    constructor(
        address airlock_,
        INonfungiblePositionManager positionManager_,
        ISwapRouter02 router,
        address owner
    ) ImmutableAirlock(airlock_) {
        NONFUNGIBLE_POSITION_MANAGER = positionManager_;
        FACTORY = router.factory();
        WETH = IWETH9(router.WETH9());
        CUSTOM_LP_LOCKER = new CustomLPUniswapV2Locker(airlock_, FACTORY, this, owner);
    }

    function initialize(
        address asset,
        address numeraire,
        uint256 totalTokensOnBondingCurve,
        bytes32,
        bytes calldata liquidityMigratorData
    ) external onlyAirlock returns (address pool) {
        if (liquidityMigratorData.length > 0) {
            (uint24 fee_, uint64 customLPWad_, address customLPRecipient_, uint32 lockUpPeriod_) =
                abi.decode(liquidityMigratorData, (uint24, uint64, address, uint32));
            require(customLPWad_ > 0 && customLPRecipient_ != address(0), InvalidInput());
            require(customLPWad_ <= MAX_CUSTOM_LP_WAD, MaxCustomLPWadExceeded());
            // initially only allow EOA to receive the lp allocation
            require(customLPRecipient_.code.length == 0, RecipientNotEOA());
            require(lockUpPeriod_ >= MIN_LOCK_PERIOD, LessThanMinLockPeriod());

            int24 tickSpacing = FACTORY.feeAmountTickSpacing(fee);
            if (tickSpacing == 0) revert InvalidFee(fee);

            customLPWad = customLPWad_;
            customLPRecipient = customLPRecipient_;
            lockUpPeriod = lockUpPeriod_;
            fee = fee_;
        }

        // InitData memory initData = abi.decode(data, (InitData));
        // (uint24 fee, int24 tickLower, int24 tickUpper, uint16 numPositions, uint256 maxShareToBeSold) =
        //     (initData.fee, initData.tickLower, initData.tickUpper, initData.numPositions, initData.maxShareToBeSold);

        // require(maxShareToBeSold <= WAD, MaxShareToBeSoldExceeded(maxShareToBeSold, WAD));
        // require(tickLower < tickUpper, InvalidTickRangeMisordered(tickLower, tickUpper));

        // checkPoolParams(tickLower, tickSpacing);
        // checkPoolParams(tickUpper, tickSpacing);

        (address token0, address token1) = asset < numeraire ? (asset, numeraire) : (numeraire, asset);

        // uint256 numTokensToSell = FullMath.mulDiv(totalTokensOnBondingCurve, maxShareToBeSold, WAD);
        // uint256 numTokensToBond = totalTokensOnBondingCurve - numTokensToSell;

        pool = factory.getPool(token0, token1, fee);
        // require(getState[pool].isInitialized == false, PoolAlreadyInitialized());
        if (pool == address(0)) {
            pool = factory.createPool(token0, token1, fee);
        }

        bool isToken0 = asset == token0;
        uint160 sqrtPriceX96 = TickMath.getSqrtPriceAtTick(isToken0 ? tickLower : tickUpper);

        // try IUniswapV3Pool(pool).initialize(sqrtPriceX96) { } catch { }
        IUniswapV3Pool(pool).initialize(sqrtPriceX96);

        // getState[pool] = PoolState({
        //     asset: asset,
        //     numeraire: numeraire,
        //     tickLower: tickLower,
        //     tickUpper: tickUpper,
        //     isInitialized: true,
        //     isExited: false,
        //     numPositions: numPositions,
        //     maxShareToBeSold: maxShareToBeSold,
        //     totalTokensOnBondingCurve: totalTokensOnBondingCurve
        // });

        // (LpPosition[] memory lbpPositions, uint256 reserves) =
        //     calculateLogNormalDistribution(tickLower, tickUpper, tickSpacing, isToken0, numPositions, numTokensToSell);

        // lbpPositions[numPositions] =
        //     calculateLpTail(numPositions, tickLower, tickUpper, isToken0, reserves, numTokensToBond, tickSpacing);

        // mintPositions(asset, numeraire, fee, pool, lbpPositions, numPositions);

        emit Create(pool, asset, numeraire);
    }

    /**
     * @notice Migrates the liquidity into a Uniswap V3 pool
     * @param sqrtPriceX96 Square root price of the pool as a Q64.96 value
     * @param token0 Smaller address of the two tokens
     * @param token1 Larger address of the two tokens
     * @param recipient Address receiving the liquidity pool tokens
     */
    function migrate(
        uint160 sqrtPriceX96,
        address token0,
        address token1,
        address recipient
    ) external payable onlyAirlock returns (uint256 liquidity) {
        uint256 balance0;
        uint256 balance1 = ERC20(token1).balanceOf(address(this));

        if (token0 == address(0)) {
            token0 = address(WETH);
            WETH.deposit{ value: address(this).balance }();
            balance0 = WETH.balanceOf(address(this));
        } else {
            balance0 = ERC20(token0).balanceOf(address(this));
        }

        if (token0 > token1) {
            (token0, token1) = (token1, token0);
            (balance0, balance1) = (balance1, balance0);
        }

        // Approve the position manager
        SafeTransferLib.safeApprove(token0, address(NONFUNGIBLE_POSITION_MANAGER), balance0);
        SafeTransferLib.safeApprove(token1, address(NONFUNGIBLE_POSITION_MANAGER), balance1);

        INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
            token0: token0,
            token1: token1,
            fee: fee,
            tickLower: TickMath.MIN_TICK,
            tickUpper: TickMath.MAX_TICK,
            amount0Desired: balance0,
            amount1Desired: balance1,
            amount0Min: 0,
            amount1Min: 0,
            recipient: address(this),
            deadline: block.timestamp
        });

        // NOTE: the pool defined by token0/token1 must already be created and initialized in order to mint
        (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1) =
            NONFUNGIBLE_POSITION_MANAGER.mint(params);

        // Custom LP allocation: (n <= `MAX_CUSTOM_LP_WAD`)% to `customLPRecipient` after `lockUpPeriod`, rest will be sent to timelock
        // liquidity = IUniswapV2Pair(pool).mint(address(this));
        // uint256 customLiquidityToLock = liquidity * customLPWad / WAD;
        // uint256 liquidityToTransfer = liquidity - customLiquidityToLock;

        // IUniswapV2Pair(pool).transfer(recipient, liquidityToTransfer);
        // IUniswapV2Pair(pool).transfer(address(CUSTOM_LP_LOCKER), customLiquidityToLock);
        // CUSTOM_LP_LOCKER.receiveAndLock(pool, customLPRecipient, lockUpPeriod);

        // Remove allowance and refund in both assets.
        if (address(this).balance > 0) {
            SafeTransferLib.safeTransferETH(recipient, address(this).balance);
        }

        if (amount0 < balance0) {
            SafeTransferLib.safeApprove(token0, address(NONFUNGIBLE_POSITION_MANAGER), 0);
            uint256 refund0 = balance0 - amount0;
            SafeTransferLib.safeTransfer(token0, msg.sender, refund0);
        }

        if (amount1 < balance1) {
            SafeTransferLib.safeApprove(token1, address(NONFUNGIBLE_POSITION_MANAGER), 0);
            uint256 refund1 = balance1 - amount1;
            SafeTransferLib.safeTransfer(token1, msg.sender, refund1);
        }
    }
}
