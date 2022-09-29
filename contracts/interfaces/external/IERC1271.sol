// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

/// @title Interface for verifying contract-based account signatures
/// @notice Interface that verifies provided signature for the data
/// @dev Interface defined by EIP-1271
interface IERC1271 {
    /// @notice Returns whether the provided signature is valid for the provided data
    /// 返回所提供的签名对于所提供的数据是否有效
    /// @dev MUST return the bytes4 magic value 0x1626ba7e when function passes. 当函数通过时必须返回bytes4魔法值0x1626ba7e。
    /// MUST NOT modify state (using STATICCALL for solc < 0.5, view modifier for solc > 0.5).
    /// MUST allow external calls.
    /// @param hash Hash of the data to be signed 要签名的数据的哈希
    /// @param signature Signature byte array associated with _data 与_data关联的签名字节数组
    /// @return magicValue The bytes4 magic value 0x1626ba7e
    function isValidSignature(bytes32 hash, bytes memory signature) external view returns (bytes4 magicValue);
}
