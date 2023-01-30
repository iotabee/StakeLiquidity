//SPDX-License-Identifier: UNLICENSED

pragma solidity =0.8.17;

contract StakeLiquidity {
    uint32 public constant divConst = 1000000;

    //token=>staker=>balance
    mapping(address => mapping(address => uint256)) public balanceOf;

    struct StakingDeposit {
        address token; //staking token
        address staker; //staker
        uint256 amount; // stake amount
        uint8 k; // staking time，1 to 52 weeks
        uint32 timestamp; // end time
    }
    uint256 public stakingNonce; // auto increment
    mapping(uint256 => StakingDeposit) public stakingDepositOf; //staking number => StakingDeposit data
    mapping(address => uint256[]) public stakingDepositsOf; //staker => staking numbers

    mapping(uint256 => mapping(uint24 => bool)) public claimRewardOf; //staking number => reward number => reward is claimed or not
    address public rewardToken;
    struct Reward {
        address token;
        uint256 perAmount;
        uint256 divConst;
        uint32 timestamp;
    }
    mapping(uint24 => Reward) public rewards;

    address public owner;
    address internal newOwner;

    event Deposit(address indexed user, address indexed token, uint256 amount);
    event Withdraw(address indexed user, address indexed token, uint256 amount);
    event Stake(address indexed user, address indexed token, uint256 nonce);
    event UnStake(address indexed user, address indexed token, uint256 nonce);
    event ClaimReward(
        address indexed user,
        address indexed token,
        uint256 fdNo,
        uint24 rewardNo
    );
    event SetReward(
        address indexed user,
        address indexed token,
        uint256 rewardNo
    );

    constructor(address token) {
        owner = msg.sender;
        rewardToken = token;
        stakingNonce = 0;
    }

    function deposit(address token, uint256 amount) external {
        _safeTransferFrom(token, msg.sender, address(this), amount);
        balanceOf[token][msg.sender] += amount;
        emit Deposit(msg.sender, token, amount);
    }

    function withdraw(address token, uint256 amount) external {
        require(balanceOf[token][msg.sender] >= amount, "not enough");
        balanceOf[token][msg.sender] -= amount;
        _safeTransfer(token, msg.sender, amount);
        emit Withdraw(msg.sender, token, amount);
    }

    function stakeToken(
        address token,
        uint256 amount,
        uint8 k
    ) external returns (uint256) {
        require(k > 0 && k < 53, "1~52");
        balanceOf[token][msg.sender] -= amount;
        stakingNonce++;
        stakingDepositOf[stakingNonce] = StakingDeposit({
            token: token,
            staker: msg.sender,
            amount: amount,
            k: k,
            timestamp: uint32(block.timestamp) + uint32(k) * 604800
        });
        emit Stake(msg.sender, token, stakingNonce);
        return stakingNonce;
    }

    function unstakeToken(uint256 no) external returns (uint256) {
        StakingDeposit storage fd = stakingDepositOf[no];
        require(fd.staker == msg.sender, "forbbiden");
        require(fd.amount > 0, "not exist fixed deposit");
        require(fd.timestamp < block.timestamp, "unexpired time");
        balanceOf[fd.token][msg.sender] += fd.amount;
        fd.amount = 0;
        delete stakingDepositOf[no];
        emit Stake(msg.sender, fd.token, no);
        return fd.amount;
    }

    function claimReward(uint256 fdNo, uint24 rewardNo) external {
        require(claimRewardOf[fdNo][rewardNo] == false, "have been taken");
        StakingDeposit memory fd = stakingDepositOf[fdNo];
        require(fd.staker == msg.sender, "forbbiden");
        uint32 bT = fd.timestamp - uint32(fd.k) * 604800;
        uint32 rT = rewards[rewardNo].timestamp;
        require(bT < rT && fd.timestamp >= rT, "expired time");
        claimRewardOf[fdNo][rewardNo] = true;

        Reward memory rd = rewards[rewardNo];
        require(rd.token == fd.token, "token wrong");

        uint256 multiAmount = (fd.amount * (divConst * fd.k + 52 * divConst)) /
            (52 * divConst);

        uint256 rewardAmount = (multiAmount * rd.perAmount) / rd.divConst;
        _safeTransfer(rewardToken, msg.sender, rewardAmount);

        emit ClaimReward(msg.sender, fd.token, fdNo, rewardNo);
    }

    function setReward(
        uint24 rewardNo,
        address token,
        uint256 amount,
        uint256 per,
        uint256 div,
        uint32 timestamp
    ) external {
        //require(rewards[rewardNo].perAmount > 0, "exsit reward");
        require(timestamp < block.timestamp);
        require(msg.sender == owner, "forbidden");
        _safeTransferFrom(rewardToken, msg.sender, address(this), amount);
        rewards[rewardNo] = Reward({
            token: token,
            perAmount: per,
            divConst: div,
            timestamp: timestamp
        });

        emit SetReward(msg.sender, token, rewardNo);
    }

    function setOwner(address _owner) external {
        require(msg.sender == owner, "FORBIDDEN");
        newOwner = _owner;
    }

    function acceptOwner() external {
        require(msg.sender == newOwner, " FORBIDDEN");
        owner = newOwner;
        newOwner = address(0);
    }

    function _safeTransferFrom(
        address token,
        address from,
        address to,
        uint256 value
    ) private {
        // bytes4(keccak256(bytes('transferFrom(address,address,uint256)')));
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(0x23b872dd, from, to, value)
        );
        require(
            success && (data.length == 0 || abi.decode(data, (bool))),
            "transferFrom failed"
        );
    }

    function _safeTransfer(
        address token,
        address to,
        uint256 value
    ) private {
        // bytes4(keccak256(bytes('transfer(address,uint256)')));
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(0xa9059cbb, to, value)
        );
        require(
            success && (data.length == 0 || abi.decode(data, (bool))),
            "TRANSFER_FAILED"
        );
    }
}
