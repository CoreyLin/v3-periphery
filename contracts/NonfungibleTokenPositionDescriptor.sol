// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.7.6;
pragma abicoder v2;

import '@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol';
import '@uniswap/lib/contracts/libraries/SafeERC20Namer.sol';

import './libraries/ChainId.sol';
import './interfaces/INonfungiblePositionManager.sol';
import './interfaces/INonfungibleTokenPositionDescriptor.sol';
import './interfaces/IERC20Metadata.sol';
import './libraries/PoolAddress.sol';
import './libraries/NFTDescriptor.sol';
import './libraries/TokenRatioSortOrder.sol';

/// @title Describes NFT token positions
/// @notice Produces a string containing the data URI for a JSON metadata string
contract NonfungibleTokenPositionDescriptor is INonfungibleTokenPositionDescriptor {
    address private constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address private constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address private constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address private constant TBTC = 0x8dAEBADE922dF735c38C80C7eBD708Af50815fAa;
    address private constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;

    address public immutable WETH9;
    /// @dev A null-terminated string
    bytes32 public immutable nativeCurrencyLabelBytes;

    constructor(address _WETH9, bytes32 _nativeCurrencyLabelBytes) {
        WETH9 = _WETH9;
        nativeCurrencyLabelBytes = _nativeCurrencyLabelBytes;
    }

    /// @notice Returns the native currency label as a string
    /// 以字符串形式返回native currency label
    function nativeCurrencyLabel() public view returns (string memory) {
        uint256 len = 0;
        while (len < 32 && nativeCurrencyLabelBytes[len] != 0) {
            len++; // len递增，最多递增到32字节，如果遇到字节内容为0时则退出循环
        }
        bytes memory b = new bytes(len); // 初始化一个固定长度的bytes
        for (uint256 i = 0; i < len; i++) {
            b[i] = nativeCurrencyLabelBytes[i];
        }
        return string(b); // bytes转string
    }

    /// @inheritdoc INonfungibleTokenPositionDescriptor
    // 关于如何在链上用SVG+xml格式存储NFT token的image，可参考三篇文章：
    // https://blog.cryptostars.is/how-to-build-dynamically-generating-svg-nfts-on-chain-f6a24423ea29
    // https://andyhartnett.medium.com/solidity-tutorial-how-to-store-nft-metadata-and-svgs-on-the-blockchain-6df44314406b
    // https://blog.simondlr.com/posts/flavours-of-on-chain-svg-nfts-on-ethereum
    // 生成描述一个position manager的特定token ID的URI,这个URI可以是直接内联JSON内容的data,符合ERC721的元数据
    function tokenURI(INonfungiblePositionManager positionManager, uint256 tokenId)
        external
        view
        override
        returns (string memory)
    {
        // 从INonfungiblePositionManager中取出tokenId的元数据
        // 不需要的数据为：nonce,operator,liquidity,feeGrowthInside0LastX128,feeGrowthInside1LastX128,tokensOwed0,tokensOwed1
        (, , address token0, address token1, uint24 fee, int24 tickLower, int24 tickUpper, , , , , ) =
            positionManager.positions(tokenId);

        // 确定性地计算给定factory和PoolKey的pool地址，POOL_INIT_CODE_HASH在PoolAddress中写死了
        IUniswapV3Pool pool =
            IUniswapV3Pool(
                PoolAddress.computeAddress(
                    positionManager.factory(), // factory用immutable修饰的，NonfungiblePositionManager部署后就不变了
                    PoolAddress.PoolKey({token0: token0, token1: token1, fee: fee})
                )
            );

        bool _flipRatio = flipRatio(token0, token1, ChainId.get()); // 判断NFT价格计算的时候是否需要进行价格翻转，默认是以token0计价，即token1/token0
        address quoteTokenAddress = !_flipRatio ? token1 : token0; // 如果不翻转，token1为quote token
        address baseTokenAddress = !_flipRatio ? token0 : token1; // 如果不翻转，token0为base token
        (, int24 tick, , , , , ) = pool.slot0(); // pool中当前价格对应的tick

        return
            NFTDescriptor.constructTokenURI(//TODO
                NFTDescriptor.ConstructTokenURIParams({
                    tokenId: tokenId, // NFT token id
                    quoteTokenAddress: quoteTokenAddress, // quote token地址，计算价格时作为分子
                    baseTokenAddress: baseTokenAddress, // base token地址，计算价格时作为分母
                    quoteTokenSymbol: quoteTokenAddress == WETH9
                        ? nativeCurrencyLabel() // 以字符串形式返回native currency label
                        : SafeERC20Namer.tokenSymbol(quoteTokenAddress), // 获取ERC20 token symbol，即调用标准接口symbol(), 如果没有实现symbol()，则返回从地址派生的名称。代码实现：https://github.com/Uniswap/solidity-lib/blob/v4.0.0-alpha/contracts/libraries/SafeERC20Namer.sol
                    baseTokenSymbol: baseTokenAddress == WETH9
                        ? nativeCurrencyLabel()
                        : SafeERC20Namer.tokenSymbol(baseTokenAddress),
                    quoteTokenDecimals: IERC20Metadata(quoteTokenAddress).decimals(), // 返回用于获取展示的小数的个数
                    baseTokenDecimals: IERC20Metadata(baseTokenAddress).decimals(),
                    flipRatio: _flipRatio,
                    tickLower: tickLower, // 价格下限tick
                    tickUpper: tickUpper, // 价格上限tick
                    tickCurrent: tick, // 当前价格tick
                    tickSpacing: pool.tickSpacing(),
                    fee: fee, // 手续费率
                    poolAddress: address(pool) // 交易池地址
                })
            );
    }

    // 判断NFT价格计算的时候是否需要进行价格翻转
    // 不翻转的意思就是默认计价是以token0的价格计价，即token1/token0
    function flipRatio(
        address token0,
        address token1,
        uint256 chainId
    ) public view returns (bool) {
        // 举个例子，假设token0是WETH9，token1是USDT，则-100 < 200，那么flipRatio不翻转，所以NFT metadata计算价格的时候计算的是token0，即WETH9的价格，token1/token0
        // 假设token0是USDT，token1是WETH9，则200 > -100，那么flipRatio翻转，所以NFT metadata计算价格的时候计算的是token1，即WETH9的价格，token1/token0
        // 所以，不管WETH9是token0,还是token1,NFT价格计算都以WETH9计价，而不是以USDT计价
        return tokenRatioPriority(token0, chainId) > tokenRatioPriority(token1, chainId);
    }

    // hardcode，按照需求来
    function tokenRatioPriority(address token, uint256 chainId) public view returns (int256) {
        if (token == WETH9) {
            return TokenRatioSortOrder.DENOMINATOR; // -100
        }
        if (chainId == 1) { // 以太坊主网
            if (token == USDC) {
                return TokenRatioSortOrder.NUMERATOR_MOST; // 300
            } else if (token == USDT) {
                return TokenRatioSortOrder.NUMERATOR_MORE; // 200
            } else if (token == DAI) {
                return TokenRatioSortOrder.NUMERATOR; // 100
            } else if (token == TBTC) {
                return TokenRatioSortOrder.DENOMINATOR_MORE; // -200
            } else if (token == WBTC) {
                return TokenRatioSortOrder.DENOMINATOR_MOST; // -300
            } else {
                return 0;
            }
        }
        return 0; // 非主网除了WETH9意外，默认都是0，不区分了
    }
}
