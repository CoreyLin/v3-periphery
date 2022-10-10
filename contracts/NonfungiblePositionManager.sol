// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.7.6;
pragma abicoder v2;

import '@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol';
import '@uniswap/v3-core/contracts/libraries/FixedPoint128.sol';
import '@uniswap/v3-core/contracts/libraries/FullMath.sol';

import './interfaces/INonfungiblePositionManager.sol';
import './interfaces/INonfungibleTokenPositionDescriptor.sol';
import './libraries/PositionKey.sol';
import './libraries/PoolAddress.sol';
import './base/LiquidityManagement.sol';
import './base/PeripheryImmutableState.sol';
import './base/Multicall.sol';
import './base/ERC721Permit.sol';
import './base/PeripheryValidation.sol';
import './base/SelfPermit.sol';
import './base/PoolInitializer.sol';

/// @title NFT positions NFT头寸
/// @notice Wraps Uniswap V3 positions in the ERC721 non-fungible token interface 在ERC721非同质化token接口中封装Uniswap V3头寸
// 注意继承关系，NonfungiblePositionManager的功能很丰富
// 此合约替代用户完成提供流动性操作，然后将流动性的数据元记录下来，并给用户铸造一个 NFT Token
contract NonfungiblePositionManager is
    INonfungiblePositionManager,
    Multicall,
    ERC721Permit,
    PeripheryImmutableState,
    PoolInitializer,
    LiquidityManagement,
    PeripheryValidation,
    SelfPermit
{
    // details about the uniswap position
    // 一个position表示一个用户提供的一次流动性，是非同质化的，和V2不同。一个position对应一个ERC721 token
    struct Position {
        // the nonce for permits
        // 每次通过离线签名进行permit，即approve，nonce就递增1
        uint96 nonce;
        // the address that is approved for spending this token 被批准可以花费这个token的地址
        address operator;
        // the ID of the pool with which this token is connected 连接此token的pool的id，每个pool有一个唯一的id
        uint80 poolId;
        // the tick range of the position tick代表此position的价格范围的上下限，以token0计价，即token1/token0,也就是Y/X
        int24 tickLower; // 价格下限
        int24 tickUpper; // 价格上限
        // the liquidity of the position 此position的流动性大小，即L，token0*token1的平方根
        uint128 liquidity;
        // the fee growth of the aggregate position as of the last action on the individual position
        // 截至到上次对单独的头寸做操作，累计头寸的手续费增长
        uint256 feeGrowthInside0LastX128;
        uint256 feeGrowthInside1LastX128;
        // how many uncollected tokens are owed to the position, as of the last computation
        // 截止到最后一次计算，此头寸还欠多少未收集的tokens。用户移除流动性时，此合约并不会直接将移除的token数发送给用户，
        // 而是记录在position的tokensOwed0和tokensOwed1上，用户可以自取，这是遵循智能合约的最佳实践"对于外部合约优先使用pull 而不是push"，链接如下：
        // https://github.com/ConsenSys/smart-contract-best-practices/blob/master/README-zh.md#%E5%AF%B9%E4%BA%8E%E5%A4%96%E9%83%A8%E5%90%88%E7%BA%A6%E4%BC%98%E5%85%88%E4%BD%BF%E7%94%A8pull-%E8%80%8C%E4%B8%8D%E6%98%AFpush
        uint128 tokensOwed0;
        uint128 tokensOwed1;
    }

    /// @dev IDs of pools assigned by this contract
    // 此合约为每个pool分配的pool ID，此mapping记录交易池地址和pool ID的对应关系
    mapping(address => uint80) private _poolIds;

    /// @dev Pool keys by pool ID, to save on SSTOREs for position data
    // pool ID对应的Pool keys，为了节约对position数据做SSTOREs时的gas费
    mapping(uint80 => PoolAddress.PoolKey) private _poolIdToPoolKey;

    /// @dev The token ID position data
    // NFT token ID对应的position
    mapping(uint256 => Position) private _positions;

    /// @dev The ID of the next token that will be minted. Skips 0
    // 下一个NFT token的id，从1开始递增
    uint176 private _nextId = 1;
    /// @dev The ID of the next pool that is used for the first time. Skips 0
    // 下一个pool的ID，从1开始递增。注意：一定要是第一次使用的pool，一个pool可以包含很多positions，但只有一个pool ID.
    uint80 private _nextPoolId = 1;

    /// @dev The address of the token descriptor contract, which handles generating token URIs for position tokens
    // _tokenDescriptor是ERC721描述信息的接口地址。ERC721 token描述合约用于为position tokens生成token URIs
    // constant常量是在编译期确定值，不支持使用运行时状态赋值。而immutable是在合约部署的时候确定值，同样不会占用storage空间，
    // 且变量的值会被追加到运行时字节码中，使用immutable比使用状态变量便宜很多，同时安全性更强，无法修改。
    address private immutable _tokenDescriptor;

    constructor(
        address _factory, // core UniswapV3Factory合约的地址
        address _WETH9, // ETH合约的地址
        address _tokenDescriptor_ // ERC721 token描述合约的地址
    ) ERC721Permit('Uniswap V3 Positions NFT-V1', 'UNI-V3-POS', '1') PeripheryImmutableState(_factory, _WETH9) {
        _tokenDescriptor = _tokenDescriptor_;
    }

    /// @inheritdoc INonfungiblePositionManager
    /// 返回与给定token ID关联的头寸信息。
    function positions(uint256 tokenId)
        external
        view
        override
        returns ( // 注意：返回值不是一个struct，而是很多值
            uint96 nonce,
            address operator,
            address token0,
            address token1,
            uint24 fee,
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity,
            uint256 feeGrowthInside0LastX128,
            uint256 feeGrowthInside1LastX128,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        )
    {
        Position memory position = _positions[tokenId];
        require(position.poolId != 0, 'Invalid token ID'); // 校验poolId合法性
        PoolAddress.PoolKey memory poolKey = _poolIdToPoolKey[position.poolId];
        return (
            position.nonce,
            position.operator,
            poolKey.token0,
            poolKey.token1,
            poolKey.fee,
            position.tickLower,
            position.tickUpper,
            position.liquidity,
            position.feeGrowthInside0LastX128,
            position.feeGrowthInside1LastX128,
            position.tokensOwed0,
            position.tokensOwed1
        );
    }

    /// @dev Caches a pool key
    function cachePoolKey(address pool, PoolAddress.PoolKey memory poolKey) private returns (uint80 poolId) {
        poolId = _poolIds[pool]; // pool是core pool的地址，需要为其在NonfungiblePositionManager中保存一个对应的poolId
        if (poolId == 0) { // 如果poolId还不存在，就新生成一个，且保存在状态变量中，注：poolId是递增的
            _poolIds[pool] = (poolId = _nextPoolId++); // 1.poolId是++前的_nextPoolId 2._nextPoolId递增了 3.poolId是本地变量，节约gas费 4.新建pool合约地址到poolId的映射
            _poolIdToPoolKey[poolId] = poolKey; // 新建poolId到poolKey的映射
        }
    }

    /// @inheritdoc INonfungiblePositionManager
    // 创建一个包装在一个NFT中的新position，一个position对应一个NFT。调用此方法的前提是pool已经存在并且已经初始化。
    // 交易执行时的区块时间必须小于用户指定的deadline时间
    // mint方法和increaseLiquidity方法有一些不同，mint方法每次都会铸造一个新的NFT
    function mint(MintParams calldata params)
        external
        payable
        override
        checkDeadline(params.deadline)
        returns (
            uint256 tokenId,
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        )
    {
        IUniswapV3Pool pool;
        // 向一个已经初始化的pool中添加流动性，并完成token0和token1的发送
        (liquidity, amount0, amount1, pool) = addLiquidity(
            AddLiquidityParams({
                token0: params.token0,
                token1: params.token1,
                fee: params.fee,
                recipient: address(this), // 在core pool中，所有的positions的recipient都是NonfungiblePositionManager合约，由NonfungiblePositionManager合约统一管理
                tickLower: params.tickLower,
                tickUpper: params.tickUpper,
                amount0Desired: params.amount0Desired,
                amount1Desired: params.amount1Desired,
                amount0Min: params.amount0Min,
                amount1Min: params.amount1Min
            })
        );

        // 铸造一个ERC721 NFT token给用户，代表用户所持有的流动性
        // 此合约继承了ERC721Permit，ERC721Permit又继承了openzeppelin里的ERC721，此处_mint是openzeppelin里的ERC721提供的方法。故NonfungiblePositionManager本身就是一个ERC721合约。
        _mint(params.recipient, (tokenId = _nextId++)); // _nextId先赋值再++

        // 计算在pool中position的hash值，keccak256(abi.encodePacked(owner, tickLower, tickUpper)
        // pool中所有position的owner都是NonfungiblePositionManager合约，而非用户本人，所以NonfungiblePositionManager通过NFT token把position和用户关联起来
        // pool中所有position是以owner,tickLower,tickUpper作为键来存储的，owner又统一是NonfungiblePositionManager合约，这意味着
        // 当多个用户在同一个价格区间提供流动性时，在底层的UniswapV3Pool合约中会将他们合并存储。而在NonfungiblePositionManager合约中会按用户来区别每个用户拥有的Position。
        // 也就是说，pool合约里面并不会记录每个用户拥有的position，而是通过NonfungiblePositionManager合约来记录
        bytes32 positionKey = PositionKey.compute(address(this), params.tickLower, params.tickUpper);
        // feeGrowth代表了每单位虚拟流动性所赚取的手续费总额
        // 此处逻辑尤其值得注意，由于core pool中的一个position有可能是多个用户的同一个价格范围position的聚合，而NonfungiblePositionManager中一个position就是指一个用户独一无二的一个position，
        // 这两者有可能是包含关系。所以，mint一个新的position有两种情况：
        // 1.如果相同价格范围的position之前从没有被mint过，那么意味着是第一次在core pool里创建这个价格范围的position，feeGrowth一定是0
        // 2.如果之前已经有用户mint过相同价格范围的position，那么意味着可能已经有了swap交易，已经积累了一些手续费，那么feeGrowth就大于0,但这些手续费不是当前用户本次mint的position所赚取的，
        // 所以需要把feeGrowth作为本次mint的position的元数据记录下来，作为一个计算手续费的基准线，为当前position以后计算手续费打下基础
        (, uint256 feeGrowthInside0LastX128, uint256 feeGrowthInside1LastX128, , ) = pool.positions(positionKey); // 返回之前每单位虚拟流动性已经积累的手续费，这些手续费不是本次将要mint的position赚取的

        // idempotent set
        // 如果poolId还不存在，就新生成一个，且保存在状态变量中，注：poolId是递增的。如果poolId已经存在，就忽略。
        // 这一步完成后，pool合约地址到poolId的映射，以及poolId到poolKey的映射就都有了
        // poolId只存在于NonfungiblePositionManager中
        uint80 poolId =
            cachePoolKey(
                address(pool),
                PoolAddress.PoolKey({token0: params.token0, token1: params.token1, fee: params.fee})
            );

        // 用ERC721的token ID作为键，将用户提供流动性的元信息保存起来
        // 注意：NFT除了铸造了一个ERC721 token外，最重要的就是这个position信息了，一个tokenId和一个position信息一一对应
        _positions[tokenId] = Position({
            nonce: 0,
            operator: address(0), // 被批准可以花费这个NFT token的地址，设置为0地址，即默认没有任何人能够花费这个NFT token
            poolId: poolId, // 此poolId是NonfungiblePositionManager中的递增ID，一个poolId对应一个core pool地址，一个core pool包含多个positions
            tickLower: params.tickLower,
            tickUpper: params.tickUpper,
            liquidity: liquidity, // 在core pool中添加流动性后返回的值，由core pool计算而得
            feeGrowthInside0LastX128: feeGrowthInside0LastX128, // 把core pool中的feeGrowthInside0LastX128同步更新到此合约。截至到上次对单独的头寸做操作，累计头寸的手续费增长
            feeGrowthInside1LastX128: feeGrowthInside1LastX128,
            tokensOwed0: 0, // mint一个新的position，还没有开始赚取手续费，所以tokensOwed0和tokensOwed1都为0
            tokensOwed1: 0
        });

        // mint一个流动性本质上也是增加流动性
        emit IncreaseLiquidity(tokenId, liquidity, amount0, amount1);
    }

    // 检查必须是NFT token的owner或者owner approve的地址
    modifier isAuthorizedForToken(uint256 tokenId) {
        require(_isApprovedOrOwner(msg.sender, tokenId), 'Not approved');
        _;
    }

    // 生成描述一个position manager的特定token ID的URI,这个URI可以是直接内联JSON内容的data,符合ERC721的元数据
    function tokenURI(uint256 tokenId) public view override(ERC721, IERC721Metadata) returns (string memory) {
        require(_exists(tokenId)); // openzeppelin里的ERC721提供的方法
        return INonfungibleTokenPositionDescriptor(_tokenDescriptor).tokenURI(this, tokenId); // this指当前的合约对象，INonfungibleTokenPositionDescriptor.tokenURI通过INonfungiblePositionManager接口接收此参数
    }

    // save bytecode by removing implementation of unused method
    // 在"@openzeppelin/contracts": "3.4.2-solc-0.7"中，ERC721.sol有一个public方法叫baseURI()，这个方法在此合约中不会被用到，所以，用空代码override其实现，这样就能节约合约bytecode的大小，进而节约部署gas费
    function baseURI() public pure override returns (string memory) {}

    /// @inheritdoc INonfungiblePositionManager
    // 此方法和mint方法很类似，mint方法实现初始流动性的添加，即创建一个新的position，而increaseLiquidity方法实现了对已存在的一个position的流动性的增加
    // IncreaseLiquidityParams用tokenId取代了MintParams中的token0,token1,fee,tickLower,tickUpper,recipient。tokenId就是第一次添加流动性时已经铸造的NFT id
    function increaseLiquidity(IncreaseLiquidityParams calldata params)
        external
        payable
        override
        checkDeadline(params.deadline)
        returns (
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        )
    {
        // 根据NFT token id取出已经存在的流动性，注意，用storage修饰，是因为后面的代码要更新position，且保存在storage中
        Position storage position = _positions[params.tokenId];

        // 根据poolId取出poolKey
        PoolAddress.PoolKey memory poolKey = _poolIdToPoolKey[position.poolId];

        IUniswapV3Pool pool;
        // 向一个已经初始化的pool中添加流动性，在mint方法中也是调用的addLiquidity，因为对于core pool来说都是添加流动性
        (liquidity, amount0, amount1, pool) = addLiquidity(
            AddLiquidityParams({
                token0: poolKey.token0,
                token1: poolKey.token1,
                fee: poolKey.fee,
                tickLower: position.tickLower,
                tickUpper: position.tickUpper,
                amount0Desired: params.amount0Desired,
                amount1Desired: params.amount1Desired,
                amount0Min: params.amount0Min,
                amount1Min: params.amount1Min,
                recipient: address(this)
            })
        );

        bytes32 positionKey = PositionKey.compute(address(this), position.tickLower, position.tickUpper); // 返回core library中position的键，用来定位一个position

        // this is now updated to the current transaction
        // feeGrowth代表了每单位虚拟流动性所赚取的手续费总额。
        // core pool中每个position记录在流动性不变的情况下的一定时间内的费用增长率（feeGrowthInside），所以在每个position更新流动性时，
        // core pool会自动触发更新feeGrowthInside，由于本地增加流动性操作触发了流动性更新，所以必须在NonfungiblePositionManager更新一次feeGrowthInside、tokenOwed、流动性L。
        // 由于是对一个已存在的position的增加流动性操作，所以之前position中已有的流动性可能已经赚取了一些手续费，也就是说core pool中已经赚了一些手续费，
        // 但还没有同步更新到NonfungiblePositionManager合约中，NonfungiblePositionManager合约中的feeGrowth还是老的值，increaseLiquidity方法触发了更新
        (, uint256 feeGrowthInside0LastX128, uint256 feeGrowthInside1LastX128, , ) = pool.positions(positionKey);

        // 如果core pool中最新的feeGrowth大于NonfungiblePositionManager合约中此position的feeGrowth，意味着此position在core pool中从swap交易中赚取了交易费，
        // 既然赚取了新的交易费，就应该在NonfungiblePositionManager合约中记账，添加到当前position已赚取的交易费中，交易费以token0,token1体现。
        position.tokensOwed0 += uint128( // 把过去一段时间赚取的交易费添加到tokensOwed0中
            FullMath.mulDiv(
                feeGrowthInside0LastX128 - position.feeGrowthInside0LastX128,
                position.liquidity, // 用更新前的position流动性参与计算，因为feeGrowth针对的是在本次增加流动性操作之前已经赚取的手续费
                FixedPoint128.Q128
            )
        );
        position.tokensOwed1 += uint128( // 把过去一段时间赚取的交易费添加到tokensOwed1中
            FullMath.mulDiv(
                feeGrowthInside1LastX128 - position.feeGrowthInside1LastX128,
                position.liquidity,
                FixedPoint128.Q128
            )
        );

        position.feeGrowthInside0LastX128 = feeGrowthInside0LastX128; // 更新feeGrowthInside0LastX128，feeGrowthInside0LastX128变大了
        position.feeGrowthInside1LastX128 = feeGrowthInside1LastX128;
        position.liquidity += liquidity; // 修改position.liquidity必须发生在通过feeGrowth计算tokensOwed之后
        // 以上，实际上更新了NonfungiblePositionManager中该position的tokensOwed0,tokensOwed1,feeGrowthInside0LastX128,feeGrowthInside1LastX128,liquidity

        emit IncreaseLiquidity(params.tokenId, liquidity, amount0, amount1);
    }

    /// @inheritdoc INonfungiblePositionManager
    // 移除一个position的流动性（全部或者部分），注意，移除流动性不影响价格P，L和P同时只会有一个变化，L变化了，P就不会变化
    function decreaseLiquidity(DecreaseLiquidityParams calldata params)
        external
        payable
        override
        isAuthorizedForToken(params.tokenId) // 检查必须是NFT token的owner或者owner approve的地址
        checkDeadline(params.deadline)
        returns (uint256 amount0, uint256 amount1)
    {
        require(params.liquidity > 0); // 要移除的流动性必须大于0
        Position storage position = _positions[params.tokenId]; // 获取tokenId对应的头寸

        uint128 positionLiquidity = position.liquidity; // 把storage变量赋值给栈变量，节省gas费
        require(positionLiquidity >= params.liquidity); // 移除全部流动性或者部分流动性

        PoolAddress.PoolKey memory poolKey = _poolIdToPoolKey[position.poolId];
        IUniswapV3Pool pool = IUniswapV3Pool(PoolAddress.computeAddress(factory, poolKey));
        // 从core pool中移除流动性，即burn，也就是说移除掉的token0,token1应该归还给用户，返回应该给用户的amount0,amount1
        (amount0, amount1) = pool.burn(position.tickLower, position.tickUpper, params.liquidity);

        // 防止价格滑点过大。移除的L=amount0*amount1，通过同时控制amount0和amount1的最小值，就能把价格滑点控制在一定范围内。
        require(amount0 >= params.amount0Min && amount1 >= params.amount1Min, 'Price slippage check');

        bytes32 positionKey = PositionKey.compute(address(this), position.tickLower, position.tickUpper); // positionKey是pool中用于保存position的键
        // this is now updated to the current transaction
        (, uint256 feeGrowthInside0LastX128, uint256 feeGrowthInside1LastX128, , ) = pool.positions(positionKey);

        // 移除流动性时，欠用户的token分为两部分：
        // 1.从core pool中移除的token，即amount0,amount1
        // 2.赚取的手续费
        position.tokensOwed0 +=
            uint128(amount0) +
            uint128(
                FullMath.mulDiv(
                    feeGrowthInside0LastX128 - position.feeGrowthInside0LastX128,
                    positionLiquidity,
                    FixedPoint128.Q128
                ) // 每单位流动性赚取的fee*position拥有的所有流动性
            );
        position.tokensOwed1 +=
            uint128(amount1) +
            uint128(
                FullMath.mulDiv(
                    feeGrowthInside1LastX128 - position.feeGrowthInside1LastX128,
                    positionLiquidity,
                    FixedPoint128.Q128
                ) // 每单位流动性赚取的fee*position拥有的所有流动性
            );
        // 以上tokensOwed0,tokensOwed1变多了

        position.feeGrowthInside0LastX128 = feeGrowthInside0LastX128;
        position.feeGrowthInside1LastX128 = feeGrowthInside1LastX128;
        // subtraction is safe because we checked positionLiquidity is gte params.liquidity
        position.liquidity = positionLiquidity - params.liquidity; // 既然移除了流动性，position拥有的所有流动性就应该减少

        emit DecreaseLiquidity(params.tokenId, params.liquidity, amount0, amount1);
    }

    /// @inheritdoc INonfungiblePositionManager
    // 只有mint时的recipient或其approve的地址能够收集所有属于某NFT token的费用，包含手续费和减少流动性归还的token
    function collect(CollectParams calldata params)
        external
        payable
        override
        isAuthorizedForToken(params.tokenId) // 检查必须是NFT token的owner或者owner approve的地址
        returns (uint256 amount0, uint256 amount1)
    {
        require(params.amount0Max > 0 || params.amount1Max > 0);
        // allow collecting to the nft position manager address with address 0
        address recipient = params.recipient == address(0) ? address(this) : params.recipient;

        Position storage position = _positions[params.tokenId];

        PoolAddress.PoolKey memory poolKey = _poolIdToPoolKey[position.poolId];

        IUniswapV3Pool pool = IUniswapV3Pool(PoolAddress.computeAddress(factory, poolKey));

        (uint128 tokensOwed0, uint128 tokensOwed1) = (position.tokensOwed0, position.tokensOwed1);

        // trigger an update of the position fees owed and fee growth snapshots if it has any liquidity
        // core pool中的feeGrowth和NonfungiblePositionManager合约中的feeGrowth很可能已经不同步了，需要触发同步一次
        if (position.liquidity > 0) {
            // collect方法不涉及更新core pool的流动性，所以需要单独调用core pool的burn方法更新一下feeGrowth，这样才能同步给NonfungiblePositionManager，用于计算用户应该收取的手续费
            pool.burn(position.tickLower, position.tickUpper, 0);//TODO
            (, uint256 feeGrowthInside0LastX128, uint256 feeGrowthInside1LastX128, , ) =
                pool.positions(PositionKey.compute(address(this), position.tickLower, position.tickUpper));

            tokensOwed0 += uint128(
                FullMath.mulDiv( // 一个二进制定点数乘以十进制数之后，除以定点数1，得到一个十进制数
                    feeGrowthInside0LastX128 - position.feeGrowthInside0LastX128,
                    position.liquidity,
                    FixedPoint128.Q128
                )
            );
            tokensOwed1 += uint128(
                FullMath.mulDiv(
                    feeGrowthInside1LastX128 - position.feeGrowthInside1LastX128,
                    position.liquidity,
                    FixedPoint128.Q128
                )
            );

            position.feeGrowthInside0LastX128 = feeGrowthInside0LastX128;
            position.feeGrowthInside1LastX128 = feeGrowthInside1LastX128;
        }

        // compute the arguments to give to the pool#collect method
        (uint128 amount0Collect, uint128 amount1Collect) =
            (
                params.amount0Max > tokensOwed0 ? tokensOwed0 : params.amount0Max,
                params.amount1Max > tokensOwed1 ? tokensOwed1 : params.amount1Max
            );

        // the actual amounts collected are returned
        // 真正的collect最终还是落实到core pool上，调用pool的collect方法，完成交易费的收取
        (amount0, amount1) = pool.collect(//TODO
            recipient,
            position.tickLower,
            position.tickUpper,
            amount0Collect,
            amount1Collect
        );

        // sometimes there will be a few less wei than expected due to rounding down in core, but we just subtract the full amount expected
        // instead of the actual amount so we can burn the token
        // 由于在core合约中为避免坏账，采取了round down，有时会比预期少一些wei，但我们只是减去预期的全部金额，而不是实际发送的金额，这样我们才可以burn掉token，因为burn方法中有如下判断
        // require(position.liquidity == 0 && position.tokensOwed0 == 0 && position.tokensOwed1 == 0, 'Not cleared');
        (position.tokensOwed0, position.tokensOwed1) = (tokensOwed0 - amount0Collect, tokensOwed1 - amount1Collect);

        // 注意，event参数中是预期的全部金额，而不是实际的金额
        emit Collect(params.tokenId, recipient, amount0Collect, amount1Collect);
    }

    /// @inheritdoc INonfungiblePositionManager
    // burn一个NFT token ID，将其从NFT合约中删除。这个NFT token的流动性必须为0，且所有tokens必须已经被用户(recipient)收集。 
    function burn(uint256 tokenId) external payable override isAuthorizedForToken(tokenId) {
        Position storage position = _positions[tokenId];
        require(position.liquidity == 0 && position.tokensOwed0 == 0 && position.tokensOwed1 == 0, 'Not cleared');
        delete _positions[tokenId];
        _burn(tokenId); // 调用openzeppelin ERC721的_burn方法
    }

    function _getAndIncrementNonce(uint256 tokenId) internal override returns (uint256) {
        return uint256(_positions[tokenId].nonce++);
    }

    /// @inheritdoc IERC721
    function getApproved(uint256 tokenId) public view override(ERC721, IERC721) returns (address) {
        require(_exists(tokenId), 'ERC721: approved query for nonexistent token');

        return _positions[tokenId].operator;
    }

    /// @dev Overrides _approve to use the operator in the position, which is packed with the position permit nonce
    function _approve(address to, uint256 tokenId) internal override(ERC721) {
        _positions[tokenId].operator = to;
        emit Approval(ownerOf(tokenId), to, tokenId);
    }
}
