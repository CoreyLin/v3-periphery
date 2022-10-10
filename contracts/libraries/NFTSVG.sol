// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.7.6;

import '@openzeppelin/contracts/utils/Strings.sol';
import '@uniswap/v3-core/contracts/libraries/BitMath.sol';
import 'base64-sol/base64.sol';

/// @title NFTSVG
/// @notice Provides a function for generating an SVG associated with a Uniswap NFT
library NFTSVG {
    using Strings for uint256;

    // 只有8种curve用于代表流动性价格曲线，写死的，这部分涉及到SVG的专业知识，如何画曲线：
    // https://developer.mozilla.org/en-US/docs/Web/SVG/Tutorial/Paths
    string constant curve1 = 'M1 1C41 41 105 105 145 145';
    string constant curve2 = 'M1 1C33 49 97 113 145 145';
    string constant curve3 = 'M1 1C33 57 89 113 145 145';
    string constant curve4 = 'M1 1C25 65 81 121 145 145';
    string constant curve5 = 'M1 1C17 73 73 129 145 145';
    string constant curve6 = 'M1 1C9 81 65 137 145 145';
    string constant curve7 = 'M1 1C1 89 57.5 145 145 145';
    string constant curve8 = 'M1 1C1 97 49 145 145 145';

    struct SVGParams {
        string quoteToken; // 注意：是字符串格式
        string baseToken;
        address poolAddress;
        string quoteTokenSymbol;
        string baseTokenSymbol;
        string feeTier;
        int24 tickLower;
        int24 tickUpper;
        int24 tickSpacing;
        int8 overRange; // 当前tick大于tickUpper，为1；当前tick小于tickLower，为-1
        uint256 tokenId;
        string color0;
        string color1;
        string color2;
        string color3;
        string x1;
        string y1;
        string x2;
        string y2;
        string x3;
        string y3;
    }

    // uniswap v3 NFT图片的样子，参考：https://blog.apy.vision/uniswapnft/
    // 生成NFT图片的所有内容
    function generateSVG(SVGParams memory params) internal pure returns (string memory svg) {
        /*
        address: "0xe8ab59d3bcde16a29912de83a90eb39628cfc163",
        msg: "Forged in SVG for Uniswap in 2021 by 0xe8ab59d3bcde16a29912de83a90eb39628cfc163",
        sig: "0x2df0e99d9cbfec33a705d83f75666d98b22dea7c1af412c584f7d626d83f02875993df740dc87563b9c73378f8462426da572d7989de88079a382ad96c57b68d1b",
        version: "2"
        */
        return
            string(
                abi.encodePacked(
                    generateSVGDefs(params), // 生成SVG的基本框架，包括一个矩形f1，三个圆形p1,p2,p3，还有剩余的其他内容，暂时没有深究，因为需要SVG的专业知识
                    generateSVGBorderText( // 生成整个图片边缘上的文字，base token地址+点号+base token symbol，以及quote token地址+点号+quote token symbol
                        params.quoteToken,
                        params.baseToken,
                        params.quoteTokenSymbol,
                        params.baseTokenSymbol
                    ),
                    generateSVGCardMantle(params.quoteTokenSymbol, params.baseTokenSymbol, params.feeTier), // 生成NFT图片最上面的两行内容，比如MEGA/WETH，1%，字体白色
                    generageSvgCurve(params.tickLower, params.tickUpper, params.tickSpacing, params.overRange), // 生成NFT图片中间的价格曲线，以及曲线左上角和右下角的两个圆点
                    generateSVGPositionDataAndLocationCurve( // 生成NFT图片最右下角的那个小曲线和曲线上面的那个小圆点，以及外层包裹这个曲线的正方形框
                        params.tokenId.toString(),
                        params.tickLower,
                        params.tickUpper
                    ),
                    generateSVGRareSparkle(params.tokenId, params.poolAddress), // 生成NFT图片右下角闪光的罕见属性
                    '</svg>'
                )
            );
    }

    // 生成SVG的基本框架，包括一个矩形f1，三个圆形p1,p2,p3，还有剩余的其他内容，暂时没有深究，因为需要SVG的专业知识：
    // https://www.jianshu.com/p/b3f2d9eefa4c
    function generateSVGDefs(SVGParams memory params) private pure returns (string memory svg) {
        svg = string(
            abi.encodePacked(
                '<svg width="290" height="500" viewBox="0 0 290 500" xmlns="http://www.w3.org/2000/svg"',
                " xmlns:xlink='http://www.w3.org/1999/xlink'>",
                '<defs>',
                '<filter id="f1"><feImage result="p0" xlink:href="data:image/svg+xml;base64,',
                Base64.encode( // 对bytes进行base64编码
                    bytes(
                        abi.encodePacked(
                            "<svg width='290' height='500' viewBox='0 0 290 500' xmlns='http://www.w3.org/2000/svg'><rect width='290px' height='500px' fill='#", // fill表示填充颜色
                            params.color0,
                            "'/></svg>"
                        )
                    )
                ),
                '"/><feImage result="p1" xlink:href="data:image/svg+xml;base64,',
                Base64.encode(
                    bytes(
                        abi.encodePacked(
                            "<svg width='290' height='500' viewBox='0 0 290 500' xmlns='http://www.w3.org/2000/svg'><circle cx='",
                            params.x1,
                            "' cy='",
                            params.y1,
                            "' r='120px' fill='#", // circle 圆 cx、cy 定义圆心坐标，r定义圆半径
                            params.color1,
                            "'/></svg>"
                        )
                    )
                ),
                '"/><feImage result="p2" xlink:href="data:image/svg+xml;base64,',
                Base64.encode(
                    bytes(
                        abi.encodePacked(
                            "<svg width='290' height='500' viewBox='0 0 290 500' xmlns='http://www.w3.org/2000/svg'><circle cx='",
                            params.x2,
                            "' cy='",
                            params.y2,
                            "' r='120px' fill='#", // circle 圆 cx、cy 定义圆心坐标，r定义圆半径
                            params.color2,
                            "'/></svg>"
                        )
                    )
                ),
                '" />',
                '<feImage result="p3" xlink:href="data:image/svg+xml;base64,',
                Base64.encode(
                    bytes(
                        abi.encodePacked(
                            "<svg width='290' height='500' viewBox='0 0 290 500' xmlns='http://www.w3.org/2000/svg'><circle cx='",
                            params.x3,
                            "' cy='",
                            params.y3,
                            "' r='100px' fill='#", // circle 圆 cx、cy 定义圆心坐标，r定义圆半径
                            params.color3,
                            "'/></svg>"
                        )
                    )
                ),
                '" /><feBlend mode="overlay" in="p0" in2="p1" /><feBlend mode="exclusion" in2="p2" /><feBlend mode="overlay" in2="p3" result="blendOut" /><feGaussianBlur ',
                'in="blendOut" stdDeviation="42" /></filter> <clipPath id="corners"><rect width="290" height="500" rx="42" ry="42" /></clipPath>',
                '<path id="text-path-a" d="M40 12 H250 A28 28 0 0 1 278 40 V460 A28 28 0 0 1 250 488 H40 A28 28 0 0 1 12 460 V40 A28 28 0 0 1 40 12 z" />',
                '<path id="minimap" d="M234 444C234 457.949 242.21 463 253 463" />',
                '<filter id="top-region-blur"><feGaussianBlur in="SourceGraphic" stdDeviation="24" /></filter>',
                '<linearGradient id="grad-up" x1="1" x2="0" y1="1" y2="0"><stop offset="0.0" stop-color="white" stop-opacity="1" />',
                '<stop offset=".9" stop-color="white" stop-opacity="0" /></linearGradient>',
                '<linearGradient id="grad-down" x1="0" x2="1" y1="0" y2="1"><stop offset="0.0" stop-color="white" stop-opacity="1" /><stop offset="0.9" stop-color="white" stop-opacity="0" /></linearGradient>',
                '<mask id="fade-up" maskContentUnits="objectBoundingBox"><rect width="1" height="1" fill="url(#grad-up)" /></mask>',
                '<mask id="fade-down" maskContentUnits="objectBoundingBox"><rect width="1" height="1" fill="url(#grad-down)" /></mask>',
                '<mask id="none" maskContentUnits="objectBoundingBox"><rect width="1" height="1" fill="white" /></mask>',
                '<linearGradient id="grad-symbol"><stop offset="0.7" stop-color="white" stop-opacity="1" /><stop offset=".95" stop-color="white" stop-opacity="0" /></linearGradient>',
                '<mask id="fade-symbol" maskContentUnits="userSpaceOnUse"><rect width="290px" height="200px" fill="url(#grad-symbol)" /></mask></defs>',
                '<g clip-path="url(#corners)">',
                '<rect fill="',
                params.color0,
                '" x="0px" y="0px" width="290px" height="500px" />',
                '<rect style="filter: url(#f1)" x="0px" y="0px" width="290px" height="500px" />',
                ' <g style="filter:url(#top-region-blur); transform:scale(1.5); transform-origin:center top;">',
                '<rect fill="none" x="0px" y="0px" width="290px" height="500px" />',
                '<ellipse cx="50%" cy="0px" rx="180px" ry="120px" fill="#000" opacity="0.85" /></g>',
                '<rect x="0" y="0" width="290" height="500" rx="42" ry="42" fill="rgba(0,0,0,0)" stroke="rgba(255,255,255,0.2)" /></g>'
            )
        );
    }

    // 生成整个图片边缘上的文字，base token地址+点号+base token symbol，以及quote token地址+点号+quote token symbol
    function generateSVGBorderText(
        string memory quoteToken,
        string memory baseToken,
        string memory quoteTokenSymbol,
        string memory baseTokenSymbol
    ) private pure returns (string memory svg) {
        svg = string(
            abi.encodePacked(
                '<text text-rendering="optimizeSpeed">',
                '<textPath startOffset="-100%" fill="white" font-family="\'Courier New\', monospace" font-size="10px" xlink:href="#text-path-a">',
                baseToken,
                unicode' • ',
                baseTokenSymbol, // base token地址+点号+base token symbol
                ' <animate additive="sum" attributeName="startOffset" from="0%" to="100%" begin="0s" dur="30s" repeatCount="indefinite" />',
                '</textPath> <textPath startOffset="0%" fill="white" font-family="\'Courier New\', monospace" font-size="10px" xlink:href="#text-path-a">',
                baseToken,
                unicode' • ',
                baseTokenSymbol,
                ' <animate additive="sum" attributeName="startOffset" from="0%" to="100%" begin="0s" dur="30s" repeatCount="indefinite" /> </textPath>',
                '<textPath startOffset="50%" fill="white" font-family="\'Courier New\', monospace" font-size="10px" xlink:href="#text-path-a">',
                quoteToken,
                unicode' • ',
                quoteTokenSymbol, // quote token地址+点号+quote token symbol
                ' <animate additive="sum" attributeName="startOffset" from="0%" to="100%" begin="0s" dur="30s"',
                ' repeatCount="indefinite" /></textPath><textPath startOffset="-50%" fill="white" font-family="\'Courier New\', monospace" font-size="10px" xlink:href="#text-path-a">',
                quoteToken,
                unicode' • ',
                quoteTokenSymbol,
                ' <animate additive="sum" attributeName="startOffset" from="0%" to="100%" begin="0s" dur="30s" repeatCount="indefinite" /></textPath></text>'
            )
        );
    }

    // 生成NFT图片最上面的两行内容，比如MEGA/WETH，1%，字体白色
    function generateSVGCardMantle(
        string memory quoteTokenSymbol,
        string memory baseTokenSymbol,
        string memory feeTier
    ) private pure returns (string memory svg) {
        svg = string(
            abi.encodePacked(
                '<g mask="url(#fade-symbol)"><rect fill="none" x="0px" y="0px" width="290px" height="200px" /> <text y="70px" x="32px" fill="white" font-family="\'Courier New\', monospace" font-weight="200" font-size="36px">',
                quoteTokenSymbol,
                '/',
                baseTokenSymbol, // NFT图片最上面的内容，比如MEGA/WETH, 字体白色
                '</text><text y="115px" x="32px" fill="white" font-family="\'Courier New\', monospace" font-weight="200" font-size="36px">',
                feeTier, // 费率，比如1%，字体白色
                '</text></g>',
                '<rect x="16" y="16" width="258" height="468" rx="26" ry="26" fill="rgba(0,0,0,0)" stroke="rgba(255,255,255,0.2)" />'
            )
        );
    }

    // 生成NFT图片中间的价格曲线，以及曲线左上角和右下角的两个圆点
    function generageSvgCurve(
        int24 tickLower,
        int24 tickUpper,
        int24 tickSpacing,
        int8 overRange
    ) private pure returns (string memory svg) {
        // 当前tick大于tickUpper，为1；当前tick小于tickLower，为-1
        // #fade-up:自下而上地淡入，曲线的下面模糊，上面清晰，因为当前价格已经超过了LP指定的最高限价，y轴/x轴表示base的价格，当前价格跑到曲线上面去了
        // #fade-down:自上而下地淡入，曲线的上面模糊，下面清晰，因为当前价格已经低于LP指定的最低限价，y轴/x轴表示base的价格，当前价格跑到曲线下面去了
        // #none:没有淡出淡入效果，因为当前价格在LP指定的最高限价和最低限价之间，说明当前时刻LP正在正常提供流动性，正常赚取手续费
        // 可以参考opensea uniswap v3 positions:
        // https://opensea.io/collection/uniswap-v3-positions
        string memory fade = overRange == 1 ? '#fade-up' : overRange == -1 ? '#fade-down' : '#none';
        string memory curve = getCurve(tickLower, tickUpper, tickSpacing); // 得到流动性价格曲线，基于tickRange的大小，只有8种曲线，写死的
        svg = string(
            abi.encodePacked(
                '<g mask="url(',
                fade,
                ')"',
                ' style="transform:translate(72px,189px)">'
                '<rect x="-16px" y="-16px" width="180px" height="180px" fill="none" />'
                '<path d="',
                curve,
                '" stroke="rgba(0,0,0,0.3)" stroke-width="32px" fill="none" stroke-linecap="round" />', // 灰色粗线
                '</g><g mask="url(',
                fade,
                ')"',
                ' style="transform:translate(72px,189px)">',
                '<rect x="-16px" y="-16px" width="180px" height="180px" fill="none" />',
                '<path d="',
                curve,
                '" stroke="rgba(255,255,255,1)" fill="none" stroke-linecap="round" /></g>', // 白色细线
                generateSVGCurveCircle(overRange) // 生成价格曲线的左上角和右下角的两个圆点，两个圆点的坐标都是固定的，只是半径有可能不同，如果当前价格不在tickLower和tickUpper之间，其中一个圆点的半径就会更大，一看就知道价格越限了
            )
        );
        // 综上，实际上同样的一根曲线，生成了两根线，一根白色细线，一根灰色粗线
    }

    // curve就8种，固定的
    function getCurve(
        int24 tickLower,
        int24 tickUpper,
        int24 tickSpacing
    ) internal pure returns (string memory curve) {
        // 打个比方，如果tickUpper是9,tickLower是1,那么相差就是8
        // 如果tickSpacing是1,那么tickRange是8，相距大
        // 如果tickSpacing是2,那么tickRange是4，相距小
        int24 tickRange = (tickUpper - tickLower) / tickSpacing;
        if (tickRange <= 4) {
            curve = curve1;
        } else if (tickRange <= 8) {
            curve = curve2;
        } else if (tickRange <= 16) {
            curve = curve3;
        } else if (tickRange <= 32) {
            curve = curve4;
        } else if (tickRange <= 64) {
            curve = curve5;
        } else if (tickRange <= 128) {
            curve = curve6;
        } else if (tickRange <= 256) {
            curve = curve7;
        } else {
            curve = curve8;
        }
    }

    // 生成价格曲线的左上角和右下角的两个圆点，两个圆点的坐标都是固定的，只是半径有可能不同，如果当前价格不在tickLower和tickUpper之间，其中一个圆点的半径就会更大，一看就知道价格越限了
    function generateSVGCurveCircle(int8 overRange) internal pure returns (string memory svg) {
        string memory curvex1 = '73';
        string memory curvey1 = '190';
        string memory curvex2 = '217';
        string memory curvey2 = '334';
        if (overRange == 1 || overRange == -1) { // 如果当前价格越限
            svg = string(
                abi.encodePacked(
                    '<circle cx="', // cx表示圆心的横坐标，cy表示圆心的纵坐标，r表示圆的半径
                    // 当前tick小于tickLower，返回-1，这种情况下，大圆点应该在曲线右上角，小圆点应该在曲线左上角，小圆点的坐标为73,190；如果当前tick大于tickUpper，小圆点坐标在右下角，为217,334
                    // 注意：坐标原点在左上角 https://zhuanlan.zhihu.com/p/96444730
                    overRange == -1 ? curvex1 : curvex2,
                    'px" cy="',
                    overRange == -1 ? curvey1 : curvey2,
                    'px" r="4px" fill="white" /><circle cx="', // 小圆点
                    overRange == -1 ? curvex1 : curvex2,
                    'px" cy="',
                    overRange == -1 ? curvey1 : curvey2,
                    'px" r="24px" fill="none" stroke="white" />' // 大圆点，明显看得出半径，表示价格越限了
                )
            );
        } else {
            svg = string(
                abi.encodePacked(
                    '<circle cx="',
                    curvex1,
                    'px" cy="',
                    curvey1,
                    'px" r="4px" fill="white" />',
                    '<circle cx="',
                    curvex2,
                    'px" cy="',
                    curvey2,
                    'px" r="4px" fill="white" />'
                )
            );
        }
        // 综上，可以看出，任何曲线的两个圆点的坐标都是固定的，只是半径有可能不同
    }

    // 生成NFT图片最右下角的那个小曲线和曲线上面的那个小圆点，以及外层包裹这个曲线的正方形框
    function generateSVGPositionDataAndLocationCurve(
        string memory tokenId,
        int24 tickLower,
        int24 tickUpper
    ) private pure returns (string memory svg) {
        string memory tickLowerStr = tickToString(tickLower);
        string memory tickUpperStr = tickToString(tickUpper);
        uint256 str1length = bytes(tokenId).length + 4; // tokenId长度+4
        uint256 str2length = bytes(tickLowerStr).length + 10; // tickLowerStr长度+10
        uint256 str3length = bytes(tickUpperStr).length + 10; // tickUpperStr长度+10
        // 生成NFT图片最右下角的那个小曲线里的那个圆点，这个圆点的位置只和tickLower和tickUpper的平均值有关，值越小，越靠左上角，值越大，越靠右下角
        (string memory xCoord, string memory yCoord) = rangeLocation(tickLower, tickUpper);
        svg = string(
            abi.encodePacked(
                ' <g style="transform:translate(29px, 384px)">',
                '<rect width="',
                uint256(7 * (str1length + 4)).toString(),
                'px" height="26px" rx="8px" ry="8px" fill="rgba(0,0,0,0.6)" />',
                '<text x="12px" y="17px" font-family="\'Courier New\', monospace" font-size="12px" fill="white"><tspan fill="rgba(255,255,255,0.6)">ID: </tspan>',
                tokenId,
                '</text></g>',
                ' <g style="transform:translate(29px, 414px)">',
                '<rect width="',
                uint256(7 * (str2length + 4)).toString(),
                'px" height="26px" rx="8px" ry="8px" fill="rgba(0,0,0,0.6)" />',
                '<text x="12px" y="17px" font-family="\'Courier New\', monospace" font-size="12px" fill="white"><tspan fill="rgba(255,255,255,0.6)">Min Tick: </tspan>',
                tickLowerStr,
                '</text></g>',
                ' <g style="transform:translate(29px, 444px)">',
                '<rect width="',
                uint256(7 * (str3length + 4)).toString(),
                'px" height="26px" rx="8px" ry="8px" fill="rgba(0,0,0,0.6)" />',
                '<text x="12px" y="17px" font-family="\'Courier New\', monospace" font-size="12px" fill="white"><tspan fill="rgba(255,255,255,0.6)">Max Tick: </tspan>',
                tickUpperStr, // 以上生成了NFT图片下方的三个信息框：ID,Min Tick,Max Tick
                '</text></g>'
                '<g style="transform:translate(226px, 433px)">',
                '<rect width="36px" height="36px" rx="8px" ry="8px" fill="none" stroke="rgba(255,255,255,0.2)" />', // NFT图片最右下角的那个小曲线外层包裹的正方形框，是固定的
                '<path stroke-linecap="round" d="M8 9C8.00004 22.9494 16.2099 28 27 28" fill="none" stroke="white" />', // NFT图片最右下角的那个小曲线，是固定的
                '<circle style="transform:translate3d(',
                xCoord,
                'px, ',
                yCoord,
                'px, 0px)" cx="0px" cy="0px" r="4px" fill="white"/></g>'
                // https://developer.mozilla.org/en-US/docs/Web/CSS/transform-function/translate3d
            )
        );
    }

    function tickToString(int24 tick) private pure returns (string memory) {
        string memory sign = '';
        if (tick < 0) { // tick为负的情况，tick表示的价格都固定是token0的价格，即token1/token0
            tick = tick * -1; // 取反，变为正数
            sign = '-'; // 加上负号
        }
        return string(abi.encodePacked(sign, uint256(tick).toString()));
    }

    // 生成NFT图片最右下角的那个小曲线里的那个圆点，这个圆点的位置只和tickLower和tickUpper的平均值有关，值越小，越靠左上角，值越大，越靠右下角
    // 点的坐标都是写死的
    function rangeLocation(int24 tickLower, int24 tickUpper) internal pure returns (string memory, string memory) {
        int24 midPoint = (tickLower + tickUpper) / 2;
        if (midPoint < -125_000) { // 如果tick很小，即token0价格很低
            return ('8', '7');
        } else if (midPoint < -75_000) {
            return ('8', '10.5');
        } else if (midPoint < -25_000) {
            return ('8', '14.25');
        } else if (midPoint < -5_000) {
            return ('10', '18');
        } else if (midPoint < 0) {
            return ('11', '21');
        } else if (midPoint < 5_000) {
            return ('13', '23');
        } else if (midPoint < 25_000) {
            return ('15', '25');
        } else if (midPoint < 75_000) {
            return ('18', '26');
        } else if (midPoint < 125_000) {
            return ('21', '27');
        } else { // 如果tick很大，即token0价格很高
            return ('24', '27');
        }
    }

    // 生成闪光的罕见属性
    function generateSVGRareSparkle(uint256 tokenId, address poolAddress) private pure returns (string memory svg) {
        if (isRare(tokenId, poolAddress)) {
            svg = string(
                abi.encodePacked(
                    '<g style="transform:translate(226px, 392px)"><rect width="36px" height="36px" rx="8px" ry="8px" fill="none" stroke="rgba(255,255,255,0.2)" />',
                    '<g><path style="transform:translate(6px,6px)" d="M12 0L12.6522 9.56587L18 1.6077L13.7819 10.2181L22.3923 6L14.4341 ',
                    '11.3478L24 12L14.4341 12.6522L22.3923 18L13.7819 13.7819L18 22.3923L12.6522 14.4341L12 24L11.3478 14.4341L6 22.39',
                    '23L10.2181 13.7819L1.6077 18L9.56587 12.6522L0 12L9.56587 11.3478L1.6077 6L10.2181 10.2181L6 1.6077L11.3478 9.56587L12 0Z" fill="white" />',
                    '<animateTransform attributeName="transform" type="rotate" from="0 18 18" to="360 18 18" dur="10s" repeatCount="indefinite"/></g></g>'
                )
            );
        } else {
            svg = '';
        }
    }

    // NFT上的闪光是一个罕见的属性，有很小的几率产生，随着token ID的增加而减少(ID 100时约10%，ID 100k时约3%)
    // 此方法还没细看
    function isRare(uint256 tokenId, address poolAddress) internal pure returns (bool) {
        bytes32 h = keccak256(abi.encodePacked(tokenId, poolAddress)); // 对tokenId和poolAddress做哈希计算
        return uint256(h) < type(uint256).max / (1 + BitMath.mostSignificantBit(tokenId) * 2);
    }
}
