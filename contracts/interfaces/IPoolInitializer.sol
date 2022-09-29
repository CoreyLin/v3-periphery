// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.7.5;
pragma abicoder v2;

/// @title Creates and initializes V3 Pools 创建和初始化v3池
/// @notice Provides a method for creating and initializing a pool, if necessary, for bundling with other methods that
/// require the pool to exist.
// 提供一个方法，用于创建和初始化一个池(如果需要的话)，以便与需要该池存在的其他方法绑定。
interface IPoolInitializer {
    /// @notice Creates a new pool if it does not exist, then initializes if not initialized 如果新池不存在，则创建它;如果未初始化，则初始化它
    /// @dev This method can be bundled with others via IMulticall for the first action (e.g. mint) performed against a pool 对于针对池执行的第一个操作(例如mint)，该方法可以通过IMulticall与其他方法捆绑在一起
    /// @param token0 The contract address of token0 of the pool
    /// @param token1 The contract address of token1 of the pool
    /// @param fee The fee amount of the v3 pool for the specified token pair
    /// @param sqrtPriceX96 The initial square root price of the pool as a Q64.96 value 池的初始平方根价格，为Q64.96值
    /// @return pool Returns the pool address based on the pair of tokens and fee, will return the newly created pool address if necessary 根据token对和fee返回池地址，如果需要将返回新创建的池地址
    function createAndInitializePoolIfNecessary(
        address token0,
        address token1,
        uint24 fee,
        uint160 sqrtPriceX96
    ) external payable returns (address pool);
}
