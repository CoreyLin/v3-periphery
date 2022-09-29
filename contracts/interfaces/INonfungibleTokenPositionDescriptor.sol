// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

import './INonfungiblePositionManager.sol';

/// @title Describes position NFT tokens via URI
interface INonfungibleTokenPositionDescriptor {
    /// @notice Produces the URI describing a particular token ID for a position manager
    /// 生成描述一个position manager的特定token ID的URI
    /// @dev Note this URI may be a data: URI with the JSON contents directly inlined
    /// 这个URI可以是直接内联JSON内容的data
    /// @param positionManager The position manager for which to describe the token
    /// 要描述token所在的position manager
    /// @param tokenId The ID of the token for which to produce a description, which may not be valid
    /// 要为其产生描述的token的ID，可能无效
    /// @return The URI of the ERC721-compliant metadata
    /// 符合ERC721的元数据的URI
    function tokenURI(INonfungiblePositionManager positionManager, uint256 tokenId)
        external
        view
        returns (string memory);
}
