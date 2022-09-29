// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.6.0;

import './BytesLib.sol';

/// @title Functions for manipulating path data for multihop swaps
library Path {
    using BytesLib for bytes;

    /// @dev The length of the bytes encoded address
    /// 编码地址的字节长度
    uint256 private constant ADDR_SIZE = 20;
    /// @dev The length of the bytes encoded fee
    /// 编码fee的字节长度
    uint256 private constant FEE_SIZE = 3;

    /// @dev The offset of a single token address and pool fee
    /// 单个token地址和pool fee的偏移量
    uint256 private constant NEXT_OFFSET = ADDR_SIZE + FEE_SIZE;
    /// @dev The offset of an encoded pool key
    /// 一个已编码池key的偏移量
    uint256 private constant POP_OFFSET = NEXT_OFFSET + ADDR_SIZE; // 一个token地址+fee+另一个token地址的字节长度，这对应一个池子，因为一个池子就对应两个token，以及fee
    /// @dev The minimum length of an encoding that contains 2 or more pools
    /// 包含两个或更多池的编码的最小长度
    uint256 private constant MULTIPLE_POOLS_MIN_LENGTH = POP_OFFSET + NEXT_OFFSET; // 一个token地址+fee+另一个token地址的字节长度+另一个token地址的字节长度+fee，这对应两个池子，3种token

    /// @notice Returns true iff the path contains two or more pools
    /// 如果路径包含两个或更多的池，则返回true
    /// @param path The encoded swap path 编码后的交换路径
    /// @return True if path contains two or more pools, otherwise false
    function hasMultiplePools(bytes memory path) internal pure returns (bool) {
        return path.length >= MULTIPLE_POOLS_MIN_LENGTH; // 判断是否是多跳swap，即涉及至少两个池子，3种token
    }

    /// @notice Returns the number of pools in the path
    /// @param path The encoded swap path
    /// @return The number of pools in the path
    function numPools(bytes memory path) internal pure returns (uint256) {
        // Ignore the first token address. From then on every fee and token offset indicates a pool.
        return ((path.length - ADDR_SIZE) / NEXT_OFFSET);
    }

    /// @notice Decodes the first pool in path
    /// 解码路径中的第一个池
    /// @param path The bytes encoded swap path 路径中第一个池对应的segment，即一个token地址+fee+另一个token地址
    /// @return tokenA The first token of the given pool
    /// @return tokenB The second token of the given pool
    /// @return fee The fee level of the pool
    function decodeFirstPool(bytes memory path)
        internal
        pure
        returns (
            address tokenA,
            address tokenB,
            uint24 fee
        )
    {
        tokenA = path.toAddress(0); // bytes在指定的位置开始把20个字节转为address，此处把第1到第20字节转为address，即第一个token的地址
        fee = path.toUint24(ADDR_SIZE); // bytes在指定的位置开始把三个字节转为uint24
        tokenB = path.toAddress(NEXT_OFFSET); // bytes在指定的位置开始把20个字节转为address，此处得到第二个token的地址
    }

    /// @notice Gets the segment corresponding to the first pool in the path
    /// 获取与路径中第一个池对应的segment，即一个token地址+fee+另一个token地址
    /// @param path The bytes encoded swap path
    /// @return The segment containing all data necessary to target the first pool in the path
    /// 包含针对路径中的第一个池所需的所有数据的segment
    function getFirstPool(bytes memory path) internal pure returns (bytes memory) {
        return path.slice(0, POP_OFFSET);
    }

    /// @notice Skips a token + fee element from the buffer and returns the remainder
    /// 跳过缓冲区中的一个token + fee元素并返回剩余的
    /// @param path The swap path
    /// @return The remaining token + fee elements in the path 路径中剩下的token+fee元素
    function skipToken(bytes memory path) internal pure returns (bytes memory) {
        return path.slice(NEXT_OFFSET, path.length - NEXT_OFFSET); // BytesLib.slice(_bytes, _start, _length);
    }
}
