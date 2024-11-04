pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";

import {Deployers} from "v4-core/test/utils/Deployers.sol";
import {MAX_SWAP_FEE} from "src/Doppler.sol";
import {TestERC20} from "v4-core/src/test/TestERC20.sol";
import {PoolId, PoolIdLibrary} from "v4-periphery/lib/v4-core/src/types/PoolId.sol";
import {StateLibrary} from "v4-periphery/lib/v4-core/src/libraries/StateLibrary.sol";
import {PoolKey} from "v4-periphery/lib/v4-core/src/types/PoolKey.sol";
import {PoolManager, IPoolManager} from "v4-core/src/PoolManager.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {Currency} from "v4-periphery/lib/v4-core/src/types/Currency.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {PoolSwapTest} from "v4-core/src/test/PoolSwapTest.sol";
import {PoolModifyLiquidityTest} from "v4-core/src/test/PoolModifyLiquidityTest.sol";
import {Quoter, IQuoter} from "v4-periphery/src/lens/Quoter.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "v4-core/src/types/BalanceDelta.sol";
import {CustomRouter} from "test/shared/CustomRouter.sol";
import {ProtocolFeeLibrary} from "v4-periphery/lib/v4-core/src/libraries/ProtocolFeeLibrary.sol";
import {FullMath} from "v4-periphery/lib/v4-core/src/libraries/FullMath.sol";

import {DopplerImplementation} from "./DopplerImplementation.sol";
import "forge-std/console.sol";

using PoolIdLibrary for PoolKey;
using StateLibrary for IPoolManager;

contract BaseTest is Test, Deployers {
    using ProtocolFeeLibrary for *;

    // TODO: Maybe add the start and end ticks to the config?
    struct DopplerConfig {
        uint256 numTokensToSell;
        uint256 minimumProceeds;
        uint256 maximumProceeds;
        uint256 startingTime;
        uint256 endingTime;
        int24 gamma;
        uint256 epochLength;
        uint24 fee;
        int24 tickSpacing;
        uint256 numPDSlugs;
    }

    // Constants

    uint256 constant DEFAULT_NUM_TOKENS_TO_SELL = 100_000e18;
    uint256 constant DEFAULT_MINIMUM_PROCEEDS = 100e18;
    uint256 constant DEFAULT_MAXIMUM_PROCEEDS = 10_000e18;
    uint256 constant DEFAULT_STARTING_TIME = 1 days;
    uint256 constant DEFAULT_ENDING_TIME = 2 days;
    int24 constant DEFAULT_GAMMA = 800;
    uint256 constant DEFAULT_EPOCH_LENGTH = 400 seconds;

    // default to feeless case for now
    uint24 constant DEFAULT_FEE = 0;
    int24 constant DEFAULT_TICK_SPACING = 8;
    uint256 constant DEFAULT_NUM_PD_SLUGS = 3;

    int24 constant DEFAULT_START_TICK = 1600;
    int24 constant DEFAULT_END_TICK = 171_200;

    address constant TOKEN_A = address(0x8888);
    address constant TOKEN_B = address(0x9999);

    uint160 constant SQRT_RATIO_2_1 = 112045541949572279837463876454;

    DopplerConfig DEFAULT_DOPPLER_CONFIG = DopplerConfig({
        numTokensToSell: DEFAULT_NUM_TOKENS_TO_SELL,
        minimumProceeds: DEFAULT_MINIMUM_PROCEEDS,
        maximumProceeds: DEFAULT_MAXIMUM_PROCEEDS,
        startingTime: DEFAULT_STARTING_TIME,
        endingTime: DEFAULT_ENDING_TIME,
        gamma: DEFAULT_GAMMA,
        epochLength: DEFAULT_EPOCH_LENGTH,
        fee: DEFAULT_FEE,
        tickSpacing: DEFAULT_TICK_SPACING,
        numPDSlugs: DEFAULT_NUM_PD_SLUGS
    });

    // Context

    DopplerImplementation hook = DopplerImplementation(
        payable(
            address(
                uint160(
                    Hooks.BEFORE_INITIALIZE_FLAG | Hooks.AFTER_INITIALIZE_FLAG | Hooks.BEFORE_ADD_LIQUIDITY_FLAG
                        | Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG
                ) ^ (0x4444 << 144)
            )
        )
    );

    address asset;
    address numeraire;
    address token0;
    address token1;
    PoolId poolId;

    bool isToken0;
    bool usingEth;
    int24 startTick;
    int24 endTick;

    // Users

    address alice = address(0xa71c3);
    address bob = address(0xb0b);

    // Contracts

    Quoter quoter;
    CustomRouter router;

    // Deploy functions

    /// @dev Deploys a new pair of asset and numeraire tokens and the related Doppler hook
    /// with the default configuration.
    function _deploy() public {
        _deployTokens();
        _deployDoppler();
    }

    /// @dev Reuses an existing pair of asset and numeraire tokens and deploys the related
    /// Doppler hook with the default configuration.
    function _deploy(address asset_, address numeraire_) public {
        asset = asset_;
        numeraire = numeraire_;
        _deployDoppler();
    }

    /// @dev Deploys a new pair of asset and numeraire tokens and the related Doppler hook with
    /// a given configuration.
    function _deploy(DopplerConfig memory config) public {
        _deployTokens();
        _deployDoppler(config);
    }

    /// @dev Reuses an existing pair of asset and numeraire tokens and deploys the related Doppler
    /// hook with a given configuration.
    function _deploy(address asset_, address numeraire_, DopplerConfig memory config) public {
        asset = asset_;
        numeraire = numeraire_;
        _deployDoppler(config);
    }

    /// @dev Deploys a new pair of asset and numeraire tokens.
    function _deployTokens() public {
        isToken0 = vm.envOr("IS_TOKEN_0", true);
        usingEth = vm.envOr("USING_ETH", false);

        if (usingEth) {
            isToken0 = false;
            deployCodeTo("TestERC20.sol:TestERC20", abi.encode(2 ** 128), address(TOKEN_B));
            token0 = address(0);
            token1 = address(TOKEN_B);
            numeraire = token0;
            asset = token1;
        } else {
            deployCodeTo(
                "TestERC20.sol:TestERC20", abi.encode(2 ** 128), isToken0 ? address(TOKEN_A) : address(TOKEN_B)
            );
            deployCodeTo(
                "TestERC20.sol:TestERC20", abi.encode(2 ** 128), isToken0 ? address(TOKEN_B) : address(TOKEN_A)
            );
            asset = isToken0 ? TOKEN_A : TOKEN_B;
            numeraire = isToken0 ? TOKEN_B : TOKEN_A;
        }
    }

    /// @dev Deploys a new Doppler hook with the default configuration.
    function _deployDoppler() public {
        _deployDoppler(DEFAULT_DOPPLER_CONFIG);
    }

    /// @dev Deploys a new Doppler hook with a given configuration.
    function _deployDoppler(DopplerConfig memory config) public {
        (token0, token1) = asset < numeraire ? (asset, numeraire) : (numeraire, asset);
        vm.label(address(token0), "Token0");
        vm.label(address(token1), "Token1");

        TestERC20(asset).transfer(address(hook), config.numTokensToSell);

        // isToken0 ? startTick > endTick : endTick > startTick
        // In both cases, price(startTick) > price(endTick)
        startTick = isToken0
            ? int24(vm.envOr("START_TICK", DEFAULT_START_TICK))
            : int24(vm.envOr("START_TICK", -DEFAULT_START_TICK));
        endTick =
            isToken0 ? int24(vm.envOr("END_TICK", -DEFAULT_END_TICK)) : int24(vm.envOr("END_TICK", DEFAULT_END_TICK));

        // Default to feeless case because it's easier to reason about
        config.fee = uint24(vm.envOr("FEE", uint24(0)));

        key = PoolKey({
            currency0: Currency.wrap(address(token0)),
            currency1: Currency.wrap(address(token1)),
            fee: config.fee,
            tickSpacing: config.tickSpacing,
            hooks: IHooks(address(hook))
        });

        deployCodeTo(
            "DopplerImplementation.sol:DopplerImplementation",
            abi.encode(
                manager,
                config.numTokensToSell,
                config.minimumProceeds,
                config.maximumProceeds,
                config.startingTime,
                config.endingTime,
                startTick,
                endTick,
                config.epochLength,
                config.gamma,
                isToken0,
                config.numPDSlugs,
                address(0xbeef),
                hook
            ),
            address(hook)
        );

        poolId = key.toId();

        manager.initialize(key, TickMath.getSqrtPriceAtTick(startTick), new bytes(0));

        uint24 protocolFee = uint24(vm.envOr("PROTOCOL_FEE", uint256(0)));

        protocolFee = (uint24(protocolFee) << 12) | uint24(protocolFee);

        if (protocolFee > 0) {
            vm.startPrank(address(0));
            manager.setProtocolFee(key, protocolFee);
            vm.stopPrank();
        }
    }

    function setUp() public virtual {
        manager = new PoolManager();
        _deploy();

        // Deploy swapRouter
        swapRouter = new PoolSwapTest(manager);
        vm.label(address(swapRouter), "SwapRouter");

        // Deploy modifyLiquidityRouter
        // Note: Only used to validate that liquidity can't be manually modified
        modifyLiquidityRouter = new PoolModifyLiquidityTest(manager);

        if (token0 != address(0)) {
            // Approve the router to spend tokens on behalf of the test contract
            TestERC20(token0).approve(address(swapRouter), type(uint256).max);
            TestERC20(token0).approve(address(modifyLiquidityRouter), type(uint256).max);
        }
        TestERC20(token1).approve(address(swapRouter), type(uint256).max);
        TestERC20(token1).approve(address(modifyLiquidityRouter), type(uint256).max);

        quoter = new Quoter(manager);
        vm.label(address(quoter), "Quoter");

        router = new CustomRouter(swapRouter, quoter, key, isToken0, usingEth);
        vm.label(address(router), "Router");
    }

    function computeBuyExactOut(uint256 amountOut) public returns (uint256) {
        (int128[] memory deltaAmounts,,) = quoter.quoteExactOutputSingle(
            IQuoter.QuoteExactSingleParams({
                poolKey: key,
                zeroForOne: !isToken0,
                exactAmount: uint128(amountOut),
                sqrtPriceLimitX96: !isToken0 ? MIN_PRICE_LIMIT : MAX_PRICE_LIMIT,
                hookData: ""
            })
        );

        return uint256(uint128(deltaAmounts[0]));
    }

    function computeSellExactOut(uint256 amountOut) public returns (uint256) {
        (int128[] memory deltaAmounts,,) = quoter.quoteExactOutputSingle(
            IQuoter.QuoteExactSingleParams({
                poolKey: key,
                zeroForOne: isToken0,
                exactAmount: uint128(amountOut),
                sqrtPriceLimitX96: isToken0 ? MIN_PRICE_LIMIT : MAX_PRICE_LIMIT,
                hookData: ""
            })
        );

        return uint256(uint128(deltaAmounts[0]));
    }

    function buyExactIn(uint256 amount) public {
        buy(-int256(amount));
    }

    function buyExactOut(uint256 amount) public {
        buy(int256(amount));
    }

    function sellExactIn(uint256 amount) public {
        sell(-int256(amount));
    }

    function sellExactOut(uint256 amount) public {
        sell(int256(amount));
    }

    /// @dev Buys a given amount of asset tokens.
    /// @param amount A negative value specificies the amount of numeraire tokens to spend,
    /// a positive value specifies the amount of asset tokens to buy.
    /// @return Amount of asset tokens bought.
    /// @return Amount of numeraire tokens used.
    function buy(int256 amount) public returns (uint256, uint256) {
        // Negative means exactIn, positive means exactOut.
        uint256 mintAmount = amount < 0 ? uint256(-amount) : computeBuyExactOut(uint256(amount));

        if (usingEth) {
            deal(address(this), uint256(mintAmount));
        } else {
            TestERC20(numeraire).mint(address(this), uint256(mintAmount));
            TestERC20(numeraire).approve(address(swapRouter), uint256(mintAmount));
        }

        BalanceDelta delta = swapRouter.swap{value: usingEth ? mintAmount : 0}(
            key,
            IPoolManager.SwapParams(!isToken0, amount, isToken0 ? MAX_PRICE_LIMIT : MIN_PRICE_LIMIT),
            PoolSwapTest.TestSettings(false, false),
            ""
        );

        uint256 delta0 = uint256(int256(delta.amount0() < 0 ? -delta.amount0() : delta.amount0()));
        uint256 delta1 = uint256(int256(delta.amount1() < 0 ? -delta.amount1() : delta.amount1()));

        return isToken0 ? (delta0, delta1) : (delta1, delta0);
    }

    /// @dev Sells a given amount of asset tokens.
    /// @param amount A negative value specificies the amount of asset tokens to sell, a positive value
    /// specifies the amount of numeraire tokens to receive.
    /// @return Amount of asset tokens sold.
    /// @return Amount of numeraire tokens received.
    function sell(int256 amount) public returns (uint256, uint256) {
        // Negative means exactIn, positive means exactOut.
        uint256 approveAmount = amount < 0 ? uint256(-amount) : computeSellExactOut(uint256(amount));
        TestERC20(asset).approve(address(swapRouter), uint256(approveAmount));

        BalanceDelta delta = swapRouter.swap(
            key,
            IPoolManager.SwapParams(isToken0, amount, isToken0 ? MIN_PRICE_LIMIT : MAX_PRICE_LIMIT),
            PoolSwapTest.TestSettings(false, false),
            ""
        );

        uint256 delta0 = uint256(int256(delta.amount0() < 0 ? -delta.amount0() : delta.amount0()));
        uint256 delta1 = uint256(int256(delta.amount1() < 0 ? -delta.amount1() : delta.amount1()));

        return isToken0 ? (delta0, delta1) : (delta1, delta0);
    }

    function sellExpectRevert(int256 amount, bytes4 selector) public {
        // Negative means exactIn, positive means exactOut.
        if (amount > 0) {
            revert UnexpectedPositiveAmount();
        }
        uint256 approveAmount = uint256(-amount);
        TestERC20(asset).approve(address(swapRouter), approveAmount);
        vm.expectRevert(
            abi.encodeWithSelector(Hooks.Wrap__FailedHookCall.selector, hook, abi.encodeWithSelector(selector))
        );
        swapRouter.swap(
            key,
            IPoolManager.SwapParams(isToken0, amount, isToken0 ? MIN_PRICE_LIMIT : MAX_PRICE_LIMIT),
            PoolSwapTest.TestSettings(true, false),
            ""
        );
    }

    function buyExpectRevert(int256 amount, bytes4 selector) public {
        // Negative means exactIn, positive means exactOut.
        if (amount > 0) {
            revert UnexpectedPositiveAmount();
        }
        uint256 mintAmount = uint256(-amount);

        if (usingEth) {
            deal(address(this), uint256(mintAmount));
        } else {
            TestERC20(numeraire).mint(address(this), uint256(mintAmount));
            TestERC20(numeraire).approve(address(swapRouter), uint256(mintAmount));
        }

        vm.expectRevert(
            abi.encodeWithSelector(Hooks.Wrap__FailedHookCall.selector, hook, abi.encodeWithSelector(selector))
        );
        swapRouter.swap{value: usingEth ? mintAmount : 0}(
            key,
            IPoolManager.SwapParams(!isToken0, amount, isToken0 ? MAX_PRICE_LIMIT : MIN_PRICE_LIMIT),
            PoolSwapTest.TestSettings(true, false),
            ""
        );
    }

    function computeFees(uint256 amount0, uint256 amount1) public view returns (uint256, uint256) {
        (,, uint24 protocolFee, uint24 lpFee) = manager.getSlot0(key.toId());

        uint256 amount0ExpectedFee;
        uint256 amount1ExpectedFee;
        if (protocolFee > 0) {
            uint24 amount0SwapFee = protocolFee.getZeroForOneFee().calculateSwapFee(lpFee);
            uint24 amount1SwapFee = protocolFee.getOneForZeroFee().calculateSwapFee(lpFee);
            amount0ExpectedFee = FullMath.mulDiv(amount0, amount0SwapFee, MAX_SWAP_FEE);
            amount1ExpectedFee = FullMath.mulDiv(amount1, amount1SwapFee, MAX_SWAP_FEE);
        } else {
            amount0ExpectedFee = FullMath.mulDiv(amount0, lpFee, MAX_SWAP_FEE);
            amount1ExpectedFee = FullMath.mulDiv(amount1, lpFee, MAX_SWAP_FEE);
        }

        return (amount0ExpectedFee, amount1ExpectedFee);
    }
}

error UnexpectedPositiveAmount();
