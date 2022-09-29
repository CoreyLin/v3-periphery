// SPDX-License-Identifier: MIT
pragma solidity =0.7.6;

library TokenRatioSortOrder {
    // 分子
    int256 constant NUMERATOR_MOST = 300;
    int256 constant NUMERATOR_MORE = 200;
    int256 constant NUMERATOR = 100;

    // 分母
    int256 constant DENOMINATOR_MOST = -300;
    int256 constant DENOMINATOR_MORE = -200;
    int256 constant DENOMINATOR = -100;
}
