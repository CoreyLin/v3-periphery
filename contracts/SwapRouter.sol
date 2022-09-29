// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.7.6;
pragma abicoder v2;

import '@uniswap/v3-core/contracts/libraries/SafeCast.sol';
import '@uniswap/v3-core/contracts/libraries/TickMath.sol';
import '@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol';

import './interfaces/ISwapRouter.sol';
import './base/PeripheryImmutableState.sol';
import './base/PeripheryValidation.sol';
import './base/PeripheryPaymentsWithFee.sol';
import './base/Multicall.sol';
import './base/SelfPermit.sol';
import './libraries/Path.sol';
import './libraries/PoolAddress.sol';
import './libraries/CallbackValidation.sol';
import './interfaces/external/IWETH9.sol';

/// @title Uniswap V3 Swap Router
/// @notice Router for stateless execution of swaps against Uniswap V3
contract SwapRouter is
    ISwapRouter,
    PeripheryImmutableState,
    PeripheryValidation,
    PeripheryPaymentsWithFee,
    Multicall,
    SelfPermit
{
    using Path for bytes;
    using SafeCast for uint256;

    /// @dev Used as the placeholder value for amountInCached, because the computed amount in for an exact output swap
    /// can never actually be this value
    uint256 private constant DEFAULT_AMOUNT_IN_CACHED = type(uint256).max;

    /// @dev Transient storage variable used for returning the computed amount in for an exact output swap.
    /// 用于返回精确输出交换的计算的amount in的瞬态状态变量。
    uint256 private amountInCached = DEFAULT_AMOUNT_IN_CACHED;

    constructor(address _factory, address _WETH9) PeripheryImmutableState(_factory, _WETH9) {}

    /// @dev Returns the pool for the given token pair and fee. The pool contract may or may not exist.
    // 返回给定token对和fee对应的池。池合约可能存在，也可能不存在。
    function getPool(
        address tokenA,
        address tokenB,
        uint24 fee
    ) private view returns (IUniswapV3Pool) {
        return IUniswapV3Pool(PoolAddress.computeAddress(factory, PoolAddress.getPoolKey(tokenA, tokenB, fee)));
    }

    struct SwapCallbackData {
        bytes path; // token路径
        address payer; // 付款方
    }

    /// @inheritdoc IUniswapV3SwapCallback
    function uniswapV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata _data
    ) external override {
        require(amount0Delta > 0 || amount1Delta > 0); // swaps entirely within 0-liquidity regions are not supported 完全在零流动性区域内的swap不受支持
        SwapCallbackData memory data = abi.decode(_data, (SwapCallbackData));
        (address tokenIn, address tokenOut, uint24 fee) = data.path.decodeFirstPool();
        CallbackValidation.verifyCallback(factory, tokenIn, tokenOut, fee); // 校验并返回有效的Uniswap V3池的地址，此处没有使用返回值，只做了校验

        (bool isExactInput, uint256 amountToPay) =
            amount0Delta > 0 // 是否用token0换token1
                // 如果tokenIn是token0，则说明token0换token1，amount0Delta大于0,则说明是isExactInput；如果tokenIn是token1，则说明token1换token0
                ? (tokenIn < tokenOut, uint256(amount0Delta))
                // amount1Delta > 1. 如果tokenIn是token1，则说明token1换token0，amount1Delta大于0,则说明是isExactInput；如果tokenIn是token0，则说明token0换token1
                : (tokenOut < tokenIn, uint256(amount1Delta));
        if (isExactInput) {
            pay(tokenIn, data.payer, msg.sender, amountToPay); // 从payer转账给pool合约
        } else { // isExactInput为false，场景比如token1换token0, tokenIn是token1, 但amountToPay是amount0Delta，是token0
            // either initiate the next swap or pay
            if (data.path.hasMultiplePools()) { // 如果是多跳swap
                data.path = data.path.skipToken(); // 跳过缓冲区中的一个token + fee元素并返回剩余的路径
                exactOutputInternal(amountToPay, msg.sender, 0, data); // 第一个参数是amountOut，场景比如token1换token0, tokenIn是token1, 但amountToPay是amount0Delta，是token0，则必须换取amountToPay数量的amount0
            } else { // 不是isExactInput，且非多跳swap
                amountInCached = amountToPay; // amountInCached是用于返回精确输出交换的计算的amount in的瞬态状态变量。
                // 场景比如token1换token0, tokenIn是token1，现在变成了tokenIn是token0，amountToPay是amount0Delta，是token0
                tokenIn = tokenOut; // swap in/out because exact output swaps are reversed 在pool swap中，对于exact output swap，对in/out进行了反转，所以这里需要反转回来
                pay(tokenIn, data.payer, msg.sender, amountToPay); // 接上述场景，payer向pool转amount0Delta数量的token0，tokenIn是token0
            }
        }
    }

    /// @dev Performs a single exact input swap
    /// 执行一次exact input swap
    function exactInputInternal(
        uint256 amountIn,
        address recipient,
        uint160 sqrtPriceLimitX96,
        SwapCallbackData memory data
    ) private returns (uint256 amountOut) {
        // allow swapping to the router address with address 0
        if (recipient == address(0)) recipient = address(this); // 如果recipient为0地址，把其改为router合约地址，即router合约收款

        // 这里的path是路径中第一个池对应的segment，即一个token地址+fee+另一个token地址
        (address tokenIn, address tokenOut, uint24 fee) = data.path.decodeFirstPool(); // 解码路径中的第一个池

        bool zeroForOne = tokenIn < tokenOut; // 如果tokenIn小于tokenOut，则是用token0换取token1

        (int256 amount0, int256 amount1) =
            getPool(tokenIn, tokenOut, fee).swap( // 返回给定token对和fee对应的池。池合约可能存在，也可能不存在。然后调用pool的swap方法
                recipient,
                zeroForOne, // 是否是用token0换取token1
                amountIn.toInt256(), // SafeCast中的toInt256
                sqrtPriceLimitX96 == 0
                    ? (zeroForOne ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1) // 如果用户没有指定价格限制，则根据交换方向，取tick的最小值或者最大值
                    : sqrtPriceLimitX96,
                abi.encode(data) // struct编码为bytes
            );
        // 以上pool swap方法在pool改变了很多状态变量，但并没有传导到periphery NonFungiblePositionManager中，LP NFT的属性值现在并没有变化

        // 1.根据交换方向确定是返回amount1还是amount0 2.pool.swap返回的是负数，所以需要加个负号转为正数，然后再转为uint256
        return uint256(-(zeroForOne ? amount1 : amount0));
    }

    /// @inheritdoc ISwapRouter
    // 将一种token的amountIn交换为尽可能多的另一种token。重点：不是多跳交换。
    function exactInputSingle(ExactInputSingleParams calldata params)
        external
        payable
        override
        checkDeadline(params.deadline)
        returns (uint256 amountOut)
    {
        amountOut = exactInputInternal(
            params.amountIn,
            params.recipient,
            params.sqrtPriceLimitX96,
            SwapCallbackData({path: abi.encodePacked(params.tokenIn, params.fee, params.tokenOut), payer: msg.sender})
        );
        require(amountOut >= params.amountOutMinimum, 'Too little received');
    }

    /// @inheritdoc ISwapRouter
    /// 沿着指定的路径，将一种token的amountIn尽可能多地交换为另一种token
    function exactInput(ExactInputParams memory params)
        external
        payable
        override
        checkDeadline(params.deadline)
        returns (uint256 amountOut)
    {
        address payer = msg.sender; // msg.sender pays for the first hop msg.sender需要首先付款

        while (true) { // 通过循环，遍历传入的路径，进行交易
            bool hasMultiplePools = params.path.hasMultiplePools(); // 如果路径包含两个或更多的池，则返回true，这就涉及多跳swap。注意：此语句放在while循环内，而非循环外，因为path每次交换后会截短，就需要重新判断是否是多跳交换

            // the outputs of prior swaps become the inputs to subsequent ones
            // 前一个交换的输出成为后一个交换的输入
            params.amountIn = exactInputInternal(
                params.amountIn,
                hasMultiplePools ? address(this) : params.recipient, // for intermediate swaps, this contract custodies 对于中间交换，该合约负责保管。即如果是中间交易，由合约代为收取和支付中间代币
                0, // 重点：此处固定传0，也就是说用户没有指定价格限制，则根据交换方向，取tick的最小值或者最大值
                SwapCallbackData({ // 给回调函数用的参数
                    path: params.path.getFirstPool(), // only the first pool in the path is necessary 获取与路径中第一个池对应的segment，即一个token地址+fee+另一个token地址
                    payer: payer
                })
            );

            // decide whether to continue or terminate
            // 决定是继续还是终止
            if (hasMultiplePools) { // 如果是多跳交换
                payer = address(this); // at this point, the caller has paid 目前caller已经支付了，且recipient是router合约，即router合约已经收到了换来的token
                params.path = params.path.skipToken(); // 跳过缓冲区中的一个token + fee元素并返回剩余的
            } else { // 非多跳交换
                amountOut = params.amountIn; // 返回值
                break;
            }
        }

        require(amountOut >= params.amountOutMinimum, 'Too little received');
    }

    /// @dev Performs a single exact output swap
    function exactOutputInternal(
        uint256 amountOut,
        address recipient,
        uint160 sqrtPriceLimitX96,
        SwapCallbackData memory data
    ) private returns (uint256 amountIn) {
        // allow swapping to the router address with address 0
        if (recipient == address(0)) recipient = address(this);

        (address tokenOut, address tokenIn, uint24 fee) = data.path.decodeFirstPool();

        bool zeroForOne = tokenIn < tokenOut;

        (int256 amount0Delta, int256 amount1Delta) =
            getPool(tokenIn, tokenOut, fee).swap(
                recipient,
                zeroForOne,
                -amountOut.toInt256(),
                sqrtPriceLimitX96 == 0
                    ? (zeroForOne ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1)
                    : sqrtPriceLimitX96,
                abi.encode(data)
            );

        uint256 amountOutReceived;
        (amountIn, amountOutReceived) = zeroForOne
            ? (uint256(amount0Delta), uint256(-amount1Delta))
            : (uint256(amount1Delta), uint256(-amount0Delta));
        // it's technically possible to not receive the full output amount,
        // so if no price limit has been specified, require this possibility away
        if (sqrtPriceLimitX96 == 0) require(amountOutReceived == amountOut);
    }

    /// @inheritdoc ISwapRouter
    function exactOutputSingle(ExactOutputSingleParams calldata params)
        external
        payable
        override
        checkDeadline(params.deadline)
        returns (uint256 amountIn)
    {
        // avoid an SLOAD by using the swap return data
        amountIn = exactOutputInternal(
            params.amountOut,
            params.recipient,
            params.sqrtPriceLimitX96,
            SwapCallbackData({path: abi.encodePacked(params.tokenOut, params.fee, params.tokenIn), payer: msg.sender})
        );

        require(amountIn <= params.amountInMaximum, 'Too much requested');
        // has to be reset even though we don't use it in the single hop case
        amountInCached = DEFAULT_AMOUNT_IN_CACHED;
    }

    /// @inheritdoc ISwapRouter
    function exactOutput(ExactOutputParams calldata params)
        external
        payable
        override
        checkDeadline(params.deadline)
        returns (uint256 amountIn)
    {
        // it's okay that the payer is fixed to msg.sender here, as they're only paying for the "final" exact output
        // swap, which happens first, and subsequent swaps are paid for within nested callback frames
        exactOutputInternal(
            params.amountOut,
            params.recipient,
            0,
            SwapCallbackData({path: params.path, payer: msg.sender})
        );

        amountIn = amountInCached;
        require(amountIn <= params.amountInMaximum, 'Too much requested');
        amountInCached = DEFAULT_AMOUNT_IN_CACHED;
    }
}
