// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.7.0;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';

/// @title IERC20Metadata
/// @title Interface for ERC20 Metadata
/// @notice Extension to IERC20 that includes token metadata
// IERC20中没有name,symbol,decimals三个接口，所以需要单独定义IERC20Metadata来包含这三个接口。
// openzeppelin 3.x没有IERC20Metadata接口，而uniswap v3依赖的是openzepplin 3.x，所以需要自己定义此接口。
// openzeppelin 4.x就添加了IERC20Metadata接口，所以就不用自己实现，直接依赖openzeppelin即可
interface IERC20Metadata is IERC20 {
    /// @return The name of the token
    function name() external view returns (string memory);

    /// @return The symbol of the token
    function symbol() external view returns (string memory);

    /// @return The number of decimal places the token has
    function decimals() external view returns (uint8);
}
