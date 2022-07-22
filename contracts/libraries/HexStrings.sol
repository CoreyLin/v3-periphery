// SPDX-License-Identifier: MIT
pragma solidity =0.7.6;

library HexStrings {
    bytes16 internal constant ALPHABET = '0123456789abcdef';

    /// @notice Converts a `uint256` to its ASCII `string` hexadecimal representation with fixed length.
    /// @dev Credit to Open Zeppelin under MIT license https://github.com/OpenZeppelin/openzeppelin-contracts/blob/243adff49ce1700e0ecb99fe522fb16cff1d1ddc/contracts/utils/Strings.sol#L55
    // length长度从右边算起，即从uint256 value的低位算起。length指uint256 value中字节的长度，一个字节等于两个hex数，20个字节等于40个16进制数
    function toHexString(uint256 value, uint256 length) internal pure returns (string memory) {
        // 此处确认转换后的Hex String的字节长度
        // 例子：length为20个字节，对应value中40个16进制数，这40个16进制数需要转换为40个字符，每个字符占用1个字节，那么就总共需要40个字节来存储转换后的字符，再加上0x前缀，还需两个字节
        bytes memory buffer = new bytes(2 * length + 2);
        buffer[0] = '0'; // 前缀0x
        buffer[1] = 'x';
        for (uint256 i = 2 * length + 1; i > 1; --i) { // index从高到底，从2 * length + 1到2
            buffer[i] = ALPHABET[value & 0xf]; // 整个value和0xf进行位与操作，能得出value最右边4位的值，进而得到对应的字符，然后赋给bytes，从高到低
            value >>= 4; // uint256 value向右位移4位，把下一个16进制数推到最右边
        }
        require(value == 0, 'Strings: hex length insufficient'); // 确保value中的16进制数已经全部转换完
        return string(buffer);
    }

    function toHexStringNoPrefix(uint256 value, uint256 length) internal pure returns (string memory) {
        bytes memory buffer = new bytes(2 * length);
        for (uint256 i = buffer.length; i > 0; i--) {
            buffer[i - 1] = ALPHABET[value & 0xf];
            value >>= 4;
        }
        return string(buffer);
    }
}
