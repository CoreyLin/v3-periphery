// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.7.0;
pragma abicoder v2;

import '@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol';
import '@uniswap/v3-core/contracts/libraries/TickMath.sol';
import '@uniswap/v3-core/contracts/libraries/BitMath.sol';
import '@uniswap/v3-core/contracts/libraries/FullMath.sol';
import '@openzeppelin/contracts/utils/Strings.sol';
import '@openzeppelin/contracts/math/SafeMath.sol';
import '@openzeppelin/contracts/math/SignedSafeMath.sol';
import 'base64-sol/base64.sol';
import './HexStrings.sol';
import './NFTSVG.sol';

library NFTDescriptor {
    using TickMath for int24;
    using Strings for uint256;
    using SafeMath for uint256;
    using SafeMath for uint160;
    using SafeMath for uint8;
    using SignedSafeMath for int256;
    using HexStrings for uint256;

    uint256 constant sqrt10X128 = 1076067327063303206878105757264492625226;

    struct ConstructTokenURIParams {
        uint256 tokenId;
        address quoteTokenAddress;
        address baseTokenAddress;
        string quoteTokenSymbol;
        string baseTokenSymbol;
        uint8 quoteTokenDecimals;
        uint8 baseTokenDecimals;
        bool flipRatio; // 是否进行价格翻转
        int24 tickLower;
        int24 tickUpper;
        int24 tickCurrent; // 当前tick
        int24 tickSpacing;
        uint24 fee; // 费率模式
        address poolAddress; // core pool地址
    }

    // ERC721 Metadata JSON Schema https://eips.ethereum.org/EIPS/eip-721
    // 生成的token URI中，包含name,description,image。尤其值得注意的是image，直接以SVG的格式（xml）存储在链上，没有存储在中心化服务器中，这样绝对安全和去中心化，大家才信任
    function constructTokenURI(ConstructTokenURIParams memory params) public pure returns (string memory) {
        // 基于NFT token的信息生成name。name定义在ERC721 Metadata JSON Schema中，表示"Identifies the asset to which this NFT represents"
        // 生成ERC721 NFT token的name，包含5个内容：feeTier,quoteTokenSymbol,baseTokenSymbol,头寸价格下限，头寸价格上限
        string memory name = generateName(params, feeToPercentString(params.fee));
        // 生成ERC721 metadata的description，表示"Describes the asset to which this NFT represents"
        // 注意：之所以要分开生成partOne和partTwo，是因为如果abi.encodePacked的参数过多，会报Stack too deep的错误，参考
        // https://ethereum.stackexchange.com/questions/120513/abi-encode-stack-too-deep
        string memory descriptionPartOne =
            generateDescriptionPartOne(//TODO
                escapeQuotes(params.quoteTokenSymbol),
                escapeQuotes(params.baseTokenSymbol),
                addressToString(params.poolAddress)
            );
        string memory descriptionPartTwo =
            generateDescriptionPartTwo(
                params.tokenId.toString(),
                escapeQuotes(params.baseTokenSymbol),
                addressToString(params.quoteTokenAddress),
                addressToString(params.baseTokenAddress),
                feeToPercentString(params.fee)
            );
        // 生成NFT token的image，采用SVG格式
        // Base64.encode出自base64-sol package，用于solidity中的base64编码，链接 https://www.npmjs.com/package/base64-sol/v/1.0.1
        string memory image = Base64.encode(bytes(generateSVGImage(params)));

        // 注意，生成的token URI遵循data URI scheme，data为前缀，是application/json类型，用base64编码，参考
        // https://en.wikipedia.org/wiki/Data_URI_scheme
        // https://www.rfc-editor.org/rfc/rfc2397#section-2
        // 另外，image的类型是image/svg+xml
        // 前端javascript如何解析参考： https://stackoverflow.com/questions/65075062/data-uri-to-json-in-javascript
        return
            string(
                abi.encodePacked(
                    'data:application/json;base64,',
                    Base64.encode(
                        bytes(
                            abi.encodePacked(
                                '{"name":"',
                                name,
                                '", "description":"',
                                descriptionPartOne,
                                descriptionPartTwo,
                                '", "image": "',
                                'data:image/svg+xml;base64,',
                                image,
                                '"}'
                            )
                        )
                    )
                )
            );
    }

    // 给symbol中的双引号加上\\转义
    function escapeQuotes(string memory symbol) internal pure returns (string memory) {
        bytes memory symbolBytes = bytes(symbol); // string转bytes
        uint8 quotesCount = 0; // 双引号计数器
        for (uint8 i = 0; i < symbolBytes.length; i++) {
            if (symbolBytes[i] == '"') { // 判断字节是否是双引号
                quotesCount++;
            }
        }
        if (quotesCount > 0) { // 如果symbol中包含双引号
            bytes memory escapedBytes = new bytes(symbolBytes.length + (quotesCount)); // 定义一个新的bytes，长度扩展
            uint256 index; // 默认值为0
            for (uint8 i = 0; i < symbolBytes.length; i++) {
                if (symbolBytes[i] == '"') {
                    escapedBytes[index++] = '\\'; // 转义。先取index值，再++
                }
                escapedBytes[index++] = symbolBytes[i];
            }
            return string(escapedBytes); // bytes转string
        }
        return symbol; //  symbol中没有双引号，直接返回
    }

    function generateDescriptionPartOne(
        string memory quoteTokenSymbol,
        string memory baseTokenSymbol,
        string memory poolAddress
    ) private pure returns (string memory) {
        return
            string(
                abi.encodePacked(
                    'This NFT represents a liquidity position in a Uniswap V3 ',
                    quoteTokenSymbol,
                    '-',
                    baseTokenSymbol,
                    ' pool. ',
                    'The owner of this NFT can modify or redeem the position.\\n',
                    '\\nPool Address: ',
                    poolAddress,
                    '\\n',
                    quoteTokenSymbol
                )
            );
    }

    function generateDescriptionPartTwo(
        string memory tokenId,
        string memory baseTokenSymbol,
        string memory quoteTokenAddress,
        string memory baseTokenAddress,
        string memory feeTier
    ) private pure returns (string memory) {
        // 从solidity 0.7开始，支持unicode特殊字符
        // 常规字符串只能包含ASCII，而Unicode文字(以关键字unicode为前缀)可以包含任何有效的UTF-8序列。
        return
            string(
                abi.encodePacked(
                    ' Address: ',
                    quoteTokenAddress,
                    '\\n',
                    baseTokenSymbol,
                    ' Address: ',
                    baseTokenAddress,
                    '\\nFee Tier: ',
                    feeTier,
                    '\\nToken ID: ',
                    tokenId,
                    '\\n\\n',
                    unicode'⚠️ DISCLAIMER: Due diligence is imperative when assessing this NFT. Make sure token addresses match the expected tokens, as token symbols may be imitated.'
                )
            );
    }

    // 生成ERC721 NFT token的name，包含5个内容：feeTier,quoteTokenSymbol,baseTokenSymbol,头寸价格下限，头寸价格上限
    function generateName(ConstructTokenURIParams memory params, string memory feeTier)
        private
        pure
        returns (string memory)
    {
        return
            string(
                abi.encodePacked( // 未填充，紧凑
                    'Uniswap - ',
                    feeTier,
                    ' - ',
                    escapeQuotes(params.quoteTokenSymbol), // 给symbol中的双引号加上\\转义
                    '/',
                    escapeQuotes(params.baseTokenSymbol),
                    ' - ',
                    tickToDecimalString( // 把tick转换为带小数的价格字符串，比如81.000,121.00,12100,1210000
                        !params.flipRatio ? params.tickLower : params.tickUpper, // 如果价格不翻转，就取tickLower
                        params.tickSpacing,
                        params.baseTokenDecimals,
                        params.quoteTokenDecimals,
                        params.flipRatio
                    ), // 此处得到价格下限的字符串表示。即使价格翻转，传的tickUpper进去，也会取倒数，所以得到的也是价格下限。
                    '<>',
                    tickToDecimalString(
                        !params.flipRatio ? params.tickUpper : params.tickLower, // 如果价格不翻转，就取tickUpper
                        params.tickSpacing,
                        params.baseTokenDecimals,
                        params.quoteTokenDecimals,
                        params.flipRatio
                    ) // 此处得到价格上限的字符串表示。
                )
            );
    }

    struct DecimalStringParams {
        // significant figures of decimal
        uint256 sigfigs;
        // length of decimal string
        uint8 bufferLength;
        // ending index for significant figures (funtion works backwards when copying sigfigs)
        uint8 sigfigIndex;
        // index of decimal place (0 if no decimal)
        uint8 decimalIndex;
        // start index for trailing/leading 0's for very small/large numbers
        uint8 zerosStartIndex;
        // end index for trailing/leading 0's for very small/large numbers
        uint8 zerosEndIndex;
        // true if decimal number is less than one
        bool isLessThanOne;
        // true if string should include "%"
        bool isPercent;
    }

    function generateDecimalString(DecimalStringParams memory params) private pure returns (string memory) {
        bytes memory buffer = new bytes(params.bufferLength);
        if (params.isPercent) {
            buffer[buffer.length - 1] = '%';
        }
        if (params.isLessThanOne) {
            buffer[0] = '0';
            buffer[1] = '.';
        }

        // add leading/trailing 0's
        for (uint256 zerosCursor = params.zerosStartIndex; zerosCursor < params.zerosEndIndex.add(1); zerosCursor++) {
            buffer[zerosCursor] = bytes1(uint8(48));
        }
        // add sigfigs
        while (params.sigfigs > 0) {
            if (params.decimalIndex > 0 && params.sigfigIndex == params.decimalIndex) {
                buffer[params.sigfigIndex--] = '.';
            }
            buffer[params.sigfigIndex--] = bytes1(uint8(uint256(48).add(params.sigfigs % 10)));
            params.sigfigs /= 10;
        }
        return string(buffer);
    }

    // 把tick转换为带小数的价格字符串，比如81.000,121.00,12100,1210000
    function tickToDecimalString(
        int24 tick,
        int24 tickSpacing,
        uint8 baseTokenDecimals,
        uint8 quoteTokenDecimals,
        bool flipRatio
    ) internal pure returns (string memory) {
        if (tick == (TickMath.MIN_TICK / tickSpacing) * tickSpacing) {
            return !flipRatio ? 'MIN' : 'MAX'; // 价格不翻转，返回MIN
        } else if (tick == (TickMath.MAX_TICK / tickSpacing) * tickSpacing) {
            return !flipRatio ? 'MAX' : 'MIN'; // 价格不翻转，返回MAX
        } else {
            uint160 sqrtRatioX96 = TickMath.getSqrtRatioAtTick(tick); // tick-->根号价格
            if (flipRatio) { // 如果价格翻转
                sqrtRatioX96 = uint160(uint256(1 << 192).div(sqrtRatioX96)); // SafeMath.div，此处是计算价格的倒数
            }
            // 在remix中实测过，返回类似于81.000,121.00,12100,1210000等
            return fixedPointToDecimalString(sqrtRatioX96, baseTokenDecimals, quoteTokenDecimals);
        }
    }

    function sigfigsRounded(uint256 value, uint8 digits) private pure returns (uint256, bool) {
        bool extraDigit;
        if (digits > 5) {
            value = value.div((10**(digits - 5)));
        }
        bool roundUp = value % 10 > 4;
        value = value.div(10);
        if (roundUp) {
            value = value + 1;
        }
        // 99999 -> 100000 gives an extra sigfig
        if (value == 100000) {
            value /= 10;
            extraDigit = true;
        }
        return (value, extraDigit);
    }

    // 根据quote和base的decimal差值，对根号价格进行相应调整（变大或变小）
    function adjustForDecimalPrecision(
        uint160 sqrtRatioX96,
        uint8 baseTokenDecimals,
        uint8 quoteTokenDecimals
    ) private pure returns (uint256 adjustedSqrtRatioX96) {
        uint256 difference = abs(int256(baseTokenDecimals).sub(int256(quoteTokenDecimals))); // 计算base token和quote token decimal相差多少，取绝对值。此处使用了SignedSafeMath.sub
        if (difference > 0 && difference <= 18) { // decimal不相等，但相差不超过18
            if (baseTokenDecimals > quoteTokenDecimals) { // base的decimal比quote多
                adjustedSqrtRatioX96 = sqrtRatioX96.mul(10**(difference.div(2))); // 根号价格应该变大，difference.div(2)的原因就是因为是根号价格，而不是价格本身，所以10的次方数需要除以2
                if (difference % 2 == 1) { // 如果除以2不能除尽，还有余数
                    adjustedSqrtRatioX96 = FullMath.mulDiv(adjustedSqrtRatioX96, sqrt10X128, 1 << 128);
                }
            } else {
                adjustedSqrtRatioX96 = sqrtRatioX96.div(10**(difference.div(2))); // 根号价格应该变小
                if (difference % 2 == 1) {
                    adjustedSqrtRatioX96 = FullMath.mulDiv(adjustedSqrtRatioX96, 1 << 128, sqrt10X128);
                }
            }
        } else { // decimal相等，或者decimal相差超过18
            adjustedSqrtRatioX96 = uint256(sqrtRatioX96);
        }
    }

    // 计算绝对值
    function abs(int256 x) private pure returns (uint256) {
        return uint256(x >= 0 ? x : -x);
    }

    // @notice Returns string that includes first 5 significant figures of a decimal number
    // @param sqrtRatioX96 a sqrt price
    // 经过在remix中实测此函数，输入sqrtRatioX96为713053462628379038341895553024（9左移96位），得到的结果为81.000，十进制，整数和小数加起来总共5位
    // 输入sqrtRatioX96为871509787656907713528983453696（11左移96位），得到的结果为121.00，十进制，整数和小数加起来总共5位
    // 输入sqrtRatioX96为8715097876569077135289834536960（110左移96位），得到的结果为12100，十进制，整数已经5位了，所以舍弃小数
    // 输入sqrtRatioX96为87150978765690771352898345369600（1100左移96位），得到的结果为1210000，十进制，整数已经超过5位了，所以舍弃小数
    function fixedPointToDecimalString(
        uint160 sqrtRatioX96,
        uint8 baseTokenDecimals,
        uint8 quoteTokenDecimals
    ) internal pure returns (string memory) {
        // 根据quote和base的decimal差值，对根号价格进行相应调整（变大或变小）
        uint256 adjustedSqrtRatioX96 = adjustForDecimalPrecision(sqrtRatioX96, baseTokenDecimals, quoteTokenDecimals);
        uint256 value = FullMath.mulDiv(adjustedSqrtRatioX96, adjustedSqrtRatioX96, 1 << 64);//TODO 为什么除以1 << 64,暂时搁置

        bool priceBelow1 = adjustedSqrtRatioX96 < 2**96; // 由于价格是用Q64.96表示，所以2**96表示1,此处判断adjustedSqrtRatioX96是否小于1
        if (priceBelow1) {
            // 10 ** 43 is precision needed to retreive 5 sigfigs of smallest possible price + 1 for rounding
            value = FullMath.mulDiv(value, 10**44, 1 << 128);
        } else {
            // leave precision for 4 decimal places + 1 place for rounding
            value = FullMath.mulDiv(value, 10**5, 1 << 128);
        }

        // get digit count
        uint256 temp = value;
        uint8 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        // don't count extra digit kept for rounding
        digits = digits - 1;

        // address rounding
        (uint256 sigfigs, bool extraDigit) = sigfigsRounded(value, digits);
        if (extraDigit) {
            digits++;
        }

        DecimalStringParams memory params;
        if (priceBelow1) {
            // 7 bytes ( "0." and 5 sigfigs) + leading 0's bytes
            params.bufferLength = uint8(uint8(7).add(uint8(43).sub(digits)));
            params.zerosStartIndex = 2;
            params.zerosEndIndex = uint8(uint256(43).sub(digits).add(1));
            params.sigfigIndex = uint8(params.bufferLength.sub(1));
        } else if (digits >= 9) {
            // no decimal in price string
            params.bufferLength = uint8(digits.sub(4));
            params.zerosStartIndex = 5;
            params.zerosEndIndex = uint8(params.bufferLength.sub(1));
            params.sigfigIndex = 4;
        } else {
            // 5 sigfigs surround decimal
            params.bufferLength = 6;
            params.sigfigIndex = 5;
            params.decimalIndex = uint8(digits.sub(5).add(1));
        }
        params.sigfigs = sigfigs;
        params.isLessThanOne = priceBelow1;
        params.isPercent = false;

        return generateDecimalString(params);
    }

    // @notice Returns string as decimal percentage of fee amount.
    // 返回字符串作为fee百分比的小数，比如0.05%,0.3%,1%。
    // @param fee fee amount
    // fee的取值有三个：500(0.05%),3000(0.3%),10000(1%)
    function feeToPercentString(uint24 fee) internal pure returns (string memory) {
        if (fee == 0) {
            return '0%';
        }
        uint24 temp = fee;
        uint256 digits;
        uint8 numSigfigs;
        while (temp != 0) {
            if (numSigfigs > 0) {
                // count all digits preceding least significant figure
                numSigfigs++;
            } else if (temp % 10 != 0) {
                numSigfigs++;
            }
            digits++;
            temp /= 10;
        }

        DecimalStringParams memory params;
        uint256 nZeros;
        if (digits >= 5) {
            // if decimal > 1 (5th digit is the ones place)
            uint256 decimalPlace = digits.sub(numSigfigs) >= 4 ? 0 : 1;
            nZeros = digits.sub(5) < (numSigfigs.sub(1)) ? 0 : digits.sub(5).sub(numSigfigs.sub(1));
            params.zerosStartIndex = numSigfigs;
            params.zerosEndIndex = uint8(params.zerosStartIndex.add(nZeros).sub(1));
            params.sigfigIndex = uint8(params.zerosStartIndex.sub(1).add(decimalPlace));
            params.bufferLength = uint8(nZeros.add(numSigfigs.add(1)).add(decimalPlace));
        } else {
            // else if decimal < 1
            nZeros = uint256(5).sub(digits);
            params.zerosStartIndex = 2;
            params.zerosEndIndex = uint8(nZeros.add(params.zerosStartIndex).sub(1));
            params.bufferLength = uint8(nZeros.add(numSigfigs.add(2)));
            params.sigfigIndex = uint8((params.bufferLength).sub(2));
            params.isLessThanOne = true;
        }
        params.sigfigs = uint256(fee).div(10**(digits.sub(numSigfigs)));
        params.isPercent = true;
        params.decimalIndex = digits > 4 ? uint8(digits.sub(4)) : 0;

        return generateDecimalString(params);
    }

    function addressToString(address addr) internal pure returns (string memory) {
        return (uint256(addr)).toHexString(20); // 20代表字节，从最右边算起
    }

    function generateSVGImage(ConstructTokenURIParams memory params) internal pure returns (string memory svg) {
        NFTSVG.SVGParams memory svgParams =
            NFTSVG.SVGParams({
                quoteToken: addressToString(params.quoteTokenAddress),
                baseToken: addressToString(params.baseTokenAddress),
                poolAddress: params.poolAddress,
                quoteTokenSymbol: params.quoteTokenSymbol,
                baseTokenSymbol: params.baseTokenSymbol,
                feeTier: feeToPercentString(params.fee),
                tickLower: params.tickLower,
                tickUpper: params.tickUpper,
                tickSpacing: params.tickSpacing,
                overRange: overRange(params.tickLower, params.tickUpper, params.tickCurrent), // 当前价格是在价格区间内，还是超出了价格区间
                tokenId: params.tokenId,
                color0: tokenToColorHex(uint256(params.quoteTokenAddress), 136),
                color1: tokenToColorHex(uint256(params.baseTokenAddress), 136),
                color2: tokenToColorHex(uint256(params.quoteTokenAddress), 0),
                color3: tokenToColorHex(uint256(params.baseTokenAddress), 0),
                x1: scale(getCircleCoord(uint256(params.quoteTokenAddress), 16, params.tokenId), 0, 255, 16, 274),
                y1: scale(getCircleCoord(uint256(params.baseTokenAddress), 16, params.tokenId), 0, 255, 100, 484),
                x2: scale(getCircleCoord(uint256(params.quoteTokenAddress), 32, params.tokenId), 0, 255, 16, 274),
                y2: scale(getCircleCoord(uint256(params.baseTokenAddress), 32, params.tokenId), 0, 255, 100, 484),
                x3: scale(getCircleCoord(uint256(params.quoteTokenAddress), 48, params.tokenId), 0, 255, 16, 274),
                y3: scale(getCircleCoord(uint256(params.baseTokenAddress), 48, params.tokenId), 0, 255, 100, 484)
            });

        return NFTSVG.generateSVG(svgParams);
    }

    function overRange(
        int24 tickLower,
        int24 tickUpper,
        int24 tickCurrent
    ) private pure returns (int8) {
        if (tickCurrent < tickLower) {
            return -1;
        } else if (tickCurrent > tickUpper) {
            return 1;
        } else {
            return 0;
        }
    }

    function scale(
        uint256 n,
        uint256 inMn,
        uint256 inMx,
        uint256 outMn,
        uint256 outMx
    ) private pure returns (string memory) {
        return (n.sub(inMn).mul(outMx.sub(outMn)).div(inMx.sub(inMn)).add(outMn)).toString();
    }

    function tokenToColorHex(uint256 token, uint256 offset) internal pure returns (string memory str) {
        return string((token >> offset).toHexStringNoPrefix(3));
    }

    function getCircleCoord(
        uint256 tokenAddress,
        uint256 offset,
        uint256 tokenId
    ) internal pure returns (uint256) {
        return (sliceTokenHex(tokenAddress, offset) * tokenId) % 255;
    }

    function sliceTokenHex(uint256 token, uint256 offset) internal pure returns (uint256) {
        return uint256(uint8(token >> offset));
    }
}
