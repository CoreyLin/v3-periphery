// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.7.6;
pragma abicoder v2;

import '@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol';
import '@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3MintCallback.sol';
import '@uniswap/v3-core/contracts/libraries/TickMath.sol';

import '../libraries/PoolAddress.sol';
import '../libraries/CallbackValidation.sol';
import '../libraries/LiquidityAmounts.sol';

import './PeripheryPayments.sol';
import './PeripheryImmutableState.sol';

/// @title Liquidity management functions
/// @notice Internal functions for safely managing liquidity in Uniswap V3
abstract contract LiquidityManagement is IUniswapV3MintCallback, PeripheryImmutableState, PeripheryPayments {
    struct MintCallbackData {
        PoolAddress.PoolKey poolKey;
        address payer;
    }

    /// @inheritdoc IUniswapV3MintCallback
    // 在LP添加流动性后，core pool合约会回调此方法，把token0,token1从LP转给pool
    function uniswapV3MintCallback(
        uint256 amount0Owed,
        uint256 amount1Owed,
        bytes calldata data
    ) external override {
        MintCallbackData memory decoded = abi.decode(data, (MintCallbackData)); // 用abi.decode把bytes data解码为struct MintCallbackData
        CallbackValidation.verifyCallback(factory, decoded.poolKey); // 检查msg.sender就是decoded.poolKey对应的pool

        if (amount0Owed > 0) pay(decoded.poolKey.token0, decoded.payer, msg.sender, amount0Owed); // payer转token0给pool
        if (amount1Owed > 0) pay(decoded.poolKey.token1, decoded.payer, msg.sender, amount1Owed); // payer转token1给pool
    }

    struct AddLiquidityParams { // 添加流动性的参数，和MintPrams相比，只少一个属性deadline
        address token0;
        address token1;
        uint24 fee;
        address recipient;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
    }

    /// @notice Add liquidity to an initialized pool
    /// 向已初始化的池中添加流动性
    function addLiquidity(AddLiquidityParams memory params)
        internal
        returns (
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1,
            IUniswapV3Pool pool
        )
    {
        PoolAddress.PoolKey memory poolKey =
            PoolAddress.PoolKey({token0: params.token0, token1: params.token1, fee: params.fee}); // PoolKey可以唯一定位和找到一个pool

        pool = IUniswapV3Pool(PoolAddress.computeAddress(factory, poolKey)); // 确定地计算给定工厂和PoolKey的池地址，然后初始化pool接口

        // compute the liquidity amount
        {
            (uint160 sqrtPriceX96, , , , , , ) = pool.slot0(); // 返回pool当前的sqrtPriceX96
            uint160 sqrtRatioAX96 = TickMath.getSqrtRatioAtTick(params.tickLower); // 添加流动性的价格下限
            uint160 sqrtRatioBX96 = TickMath.getSqrtRatioAtTick(params.tickUpper); // 添加流动性的价格上限

            liquidity = LiquidityAmounts.getLiquidityForAmounts(// 计算给定数量的token0、token1、当前池价格和tick边界价格所收到的最大流动性
                sqrtPriceX96,
                sqrtRatioAX96,
                sqrtRatioBX96,
                params.amount0Desired, // 期望添加的token0
                params.amount1Desired // 期望添加的token1
            );
        }

        // pool中添加流动性，返回需要转账的amount0,amount1
        (amount0, amount1) = pool.mint(
            params.recipient,
            params.tickLower,
            params.tickUpper,
            liquidity,
            abi.encode(MintCallbackData({poolKey: poolKey, payer: msg.sender})) // 用abi.encode对struct MintCallbackData进行编码，编码为bytes，然后传给pool，pool用于回调
        );

        require(amount0 >= params.amount0Min && amount1 >= params.amount1Min, 'Price slippage check'); // 价格滑点检查
    }
}
