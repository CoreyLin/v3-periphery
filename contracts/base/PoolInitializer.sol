// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.7.6;

import '@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol';
import '@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol';

import './PeripheryImmutableState.sol';
import '../interfaces/IPoolInitializer.sol';

/// @title Creates and initializes V3 Pools
// 创建并初始化V3资金池pool
abstract contract PoolInitializer is IPoolInitializer, PeripheryImmutableState {
    /// @inheritdoc IPoolInitializer
    function createAndInitializePoolIfNecessary(
        address token0,
        address token1,
        uint24 fee,
        uint160 sqrtPriceX96
    ) external payable override returns (address pool) {
        // 参数传入的token0和token1必须是已经排过序的，地址值更小的是token0,地址值更大的是token1,这样方便后续交易池的查询和计算
        require(token0 < token1);
        // getPool方法是solidity自动为UniswapV3Factory合约中的状态变量getPool生成的外部方法，getPool的数据类型为
        // mapping(address => mapping(address => mapping(uint24 => address))) public override getPool;
        // v3版本使用token0,token1,fee来作为一个pool的键，意味着相同的tokens，不同费率的pool不一样，会有一定程度的流动性分裂
        pool = IUniswapV3Factory(factory).getPool(token0, token1, fee);

        if (pool == address(0)) { // pool还不存在
            pool = IUniswapV3Factory(factory).createPool(token0, token1, fee); // 创建pool
            IUniswapV3Pool(pool).initialize(sqrtPriceX96); // 初始化pool，主要是初始化价格和tick
        } else { // pool已经存在
            (uint160 sqrtPriceX96Existing, , , , , , ) = IUniswapV3Pool(pool).slot0();
            if (sqrtPriceX96Existing == 0) { // 说明还未初始化价格
                IUniswapV3Pool(pool).initialize(sqrtPriceX96); // 如果当前价格为0，重新初始化价格
            }
        }
    }
}
