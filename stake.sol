// SPDX-License-Identifier: UNLICENSED
//

pragma solidity =0.8.17;
import "./ownable.sol";

contract StakeLiquidity is Ownable {
    // Division constant
    uint32 public constant divConst = 1000000;

    // token=>staker=>balance
    mapping(address => mapping(address => uint256)) public balanceOf;

    struct StakingDeposit {
        address token; // staking token
        address staker; // staker
        uint256 amount; // stake amount
        uint8 k; // staking time，1 to 52 weeks
        uint32 timestamp; // end time
    }
    uint256 public stakingNonce; // auto increment, as staking number
    mapping(uint256 => StakingDeposit) public stakingDepositOf; // staking number => StakingDeposit data

    mapping(address => uint256[]) internal stakingDepositsOf; // internal,  staker => staking numbers
    mapping(address => mapping(uint256 => uint256)) internal sdIndex; // internal,  staker => staking numbers => the index of uint256[] of stakingDepositsOf

    mapping(uint256 => mapping(uint24 => bool)) public claimRewardOf; // staking number => reward number => reward is claimed or not
    address public rewardToken; // token address, to set by the owner
    struct Reward {
        address token; // the staking token address
        uint256 perAmount;
        uint256 divConst;
        uint32 timestamp;
    }
    mapping(uint24 => Reward) public rewards; // the owner to set

    event Deposit(address indexed user, address indexed token, uint256 amount);
    event Withdraw(address indexed user, address indexed token, uint256 amount);
    event Stake(address indexed user, address indexed token, uint256 nonce);
    event UnStake(address indexed user, address indexed token, uint256 nonce);
    event ClaimReward(
        address indexed user,
        address indexed token,
        uint256 sdNo,
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

    // user transfer the token to this contract with amount.
    function deposit(address token, uint256 amount) external {
        _safeTransferFrom(token, msg.sender, address(this), amount);
        balanceOf[token][msg.sender] += amount;
        emit Deposit(msg.sender, token, amount);
    }

    // withdraw user's token with amount
    function withdraw(address token, uint256 amount) external {
        require(balanceOf[token][msg.sender] >= amount, "not enough");
        balanceOf[token][msg.sender] -= amount;
        _safeTransfer(token, msg.sender, amount);
        emit Withdraw(msg.sender, token, amount);
    }

    // stake token for a time between 1 week and 52 weeks
    // @token token address for staking
    // @amount token amount for staking
    // @k the week count for staking
    // return the staking number, and user should remember it
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

        stakingDepositsOf[msg.sender].push(stakingNonce);
        sdIndex[msg.sender][stakingNonce] =
            stakingDepositsOf[msg.sender].length -
            1;

        emit Stake(msg.sender, token, stakingNonce);
        return stakingNonce;
    }

    // no is the staking number
    // no can be got by calling the getStakingDeposits
    function unstakeToken(uint256 no) external returns (uint256) {
        StakingDeposit storage sd = stakingDepositOf[no];
        require(sd.staker == msg.sender, "forbbiden");
        require(sd.amount > 0, "not exist fixed deposit");
        require(sd.timestamp < block.timestamp, "unexpired time");
        balanceOf[sd.token][msg.sender] += sd.amount;
        sd.amount = 0;
        delete stakingDepositOf[no];

        // delete the unstaked no from stakingDepositsOf
        uint256[] storage data = stakingDepositsOf[msg.sender];
        uint256 i = sdIndex[msg.sender][no];
        if ((data.length - 1) != i) {
            data[i] = data[data.length - 1];
            sdIndex[msg.sender][data[i]] = i;
        }
        data.pop();
        delete sdIndex[msg.sender][no];

        emit Stake(msg.sender, sd.token, no);
        return sd.amount;
    }

    function getStakingDeposits() external view returns (uint256[] memory) {
        return stakingDepositsOf[msg.sender];
    }

    function claimReward(uint256 sdNo, uint24 rewardNo) external {
        require(claimRewardOf[sdNo][rewardNo] == false, "have been claimed");
        StakingDeposit memory sd = stakingDepositOf[sdNo];
        require(sd.staker == msg.sender, "forbbiden");
        uint32 bT = sd.timestamp - uint32(sd.k) * 604800;
        uint32 rT = rewards[rewardNo].timestamp;
        require(bT < rT && sd.timestamp >= rT, "expired time");
        claimRewardOf[sdNo][rewardNo] = true;

        Reward memory rd = rewards[rewardNo];
        require(rd.token == sd.token, "token wrong");

        uint256 multiAmount = (sd.amount * (divConst * sd.k + 52 * divConst)) /
            (52 * divConst);

        uint256 rewardAmount = (multiAmount * rd.perAmount) / rd.divConst;
        _safeTransfer(rewardToken, msg.sender, rewardAmount);

        emit ClaimReward(msg.sender, sd.token, sdNo, rewardNo);
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
