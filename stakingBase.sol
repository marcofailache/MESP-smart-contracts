//SPDX-License-Identifier: MIT
import "@openzeppelin/contracts/access/Ownable.sol";
pragma solidity ^0.8.16;
//library
//interface
interface IBEP20 {
    function totalSupply() external view returns (uint256);
    function decimals() external view returns (uint8);
    function symbol() external view returns (string memory);
    function name() external view returns (string memory);
    function getOwner() external view returns (address);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address _owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

contract stakingBase is Ownable {
// bool
    bool public hasUserLimit;
    bool public isInitialized;
    bool public poolLimitCapOnDeposit;
    bool public poolIsOnline;
    bool public depositEnabled;
    bool public withdrawEnabled;
    bool public compoundEnabled;
    bool public emergencyWithdrawEnabled;
    bool public hasMinimumDeposit;
    bool private tempLock;
    bool private isEmergency;
// uint
    uint256 public totalUsersInStaking;
    uint256 public poolTotalReward;
    uint256 public minimumDeposit;
    uint256 public accTokenPerShare;
    uint256 public bonusEndBlock;
    uint256 public startBlock;
    uint256 public lastRewardBlock;
    uint256 public poolLimitPerUser;
    uint256 public rewardPerBlock;
    uint256 public PRECISION_FACTOR;
    uint256 public totalUsersStake;
    uint256 public totalUsersRewards;
// custom
    IBEP20 public rewardToken;
    IBEP20 public stakedToken;
    stakingInitData public stakingData;
// mapping
    mapping(address => UserInfo) public userInfo;
    mapping(address => bool) public isExternalEconomy;
    mapping(address => bool) public compoundOnExternalDeposit;
    mapping(address => bool) public compoundOnExternalWithdraw;
    mapping(address => bool) public isAdmin;
// struct
    struct UserInfo {
        uint256 amount; // How many staked tokens the user has provided
        uint256 rewardDebt; // Reward debt
    }
// event
    event Deposit(address indexed user, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event EconomyWithdraw(address indexed user, uint256 amount);
    event EconomyDeposit(address indexed user, uint256 amount);
    event EconomyCompound(address indexed from, address indexed to, uint256 amount);
    event PoolFunded(uint256 amount);
    event Compound(address indexed user, uint256 amount);
    event ClaimReward(address indexed user, uint256 amount);
    event UserCompoundUpdated(address indexed user, bool onDeposit, bool onWithdraw);

    struct stakingInitData {
        bool lockedUntilTheEnd;
        address stakedToken;
        address rewardToken;
        address owner;
        uint256 rewardAmount;
        uint256 rewardPerBlock;
        uint256 activeUntil;
        uint256 minDeposit;
        uint256 maxDeposit;
        string logoUrl;
        string websiteUrl;
        string description;
        address factory;
    }
    modifier onlyFactory() {
        require(msg.sender == stakingData.factory,"not permitted.");
        _;
    }
    function emergencyClose(address target) external {
        require(msg.sender == owner() || msg.sender == stakingData.factory,"not permitted.");
        if(!isEmergency) {
            isEmergency = true;
        } else {
            IBEP20(rewardToken).transfer(target, IBEP20(rewardToken).balanceOf(address(this)));
            IBEP20(stakedToken).transfer(target, IBEP20(stakedToken).balanceOf(address(this)));
        }
    }
    function calcTokenPerBlock(uint256 _startDate, uint256 _endDate, uint256 _totalRewards) pure public returns(uint256) {
        uint lifeTime = _endDate - _startDate;
        uint tokensPerBlock = _totalRewards / lifeTime;
        return tokensPerBlock;
    }
    constructor(stakingInitData memory _stakingData) {
        isInitialized = true;
        stakedToken = IBEP20(_stakingData.stakedToken);
        rewardToken = IBEP20(_stakingData.rewardToken);
        startBlock = block.number;
        bonusEndBlock = block.number + _stakingData.activeUntil;
        require(bonusEndBlock > startBlock,"Staking will end as soon as it's created.");
        rewardPerBlock = calcTokenPerBlock(startBlock,bonusEndBlock,_stakingData.rewardAmount);
        hasUserLimit = true;
        poolLimitPerUser = _stakingData.maxDeposit;

        uint256 decimalsRewardToken = uint256(rewardToken.decimals());
        require(decimalsRewardToken < 30, "Must be inferior to 30");

        PRECISION_FACTOR = uint256(10**(uint256(30) - decimalsRewardToken));

        lastRewardBlock = startBlock;

        depositEnabled = true;
        withdrawEnabled = true;
        compoundEnabled = true;
        emergencyWithdrawEnabled = true;
        hasMinimumDeposit = true;
        minimumDeposit = _stakingData.minDeposit;
        poolIsOnline = true;
        _stakingData.rewardPerBlock = rewardPerBlock;
        stakingData = _stakingData;
        if(minimumDeposit == 1) {// auto disable min deposit
            hasMinimumDeposit = false;
        }
        if(poolLimitPerUser == 1) {// auto disable max deposit
            hasUserLimit = false;
        }
        if(stakedToken != rewardToken) {// auto disable compound if the token isn't the same
            compoundEnabled = false;
        }
    }
// set pool state
    function setPoolState(bool _poolIsOnline, bool _depositEnabled, bool _withdrawEnabled,
                          bool _compoundEnabled, bool _emergencyWithdrawEnabled) external onlyOwner {
        poolIsOnline = _poolIsOnline;
        depositEnabled = _depositEnabled;
        withdrawEnabled = _withdrawEnabled;
        emergencyWithdrawEnabled = _emergencyWithdrawEnabled;
        compoundEnabled = _compoundEnabled;
    }
// set admin
    function setAdmin(address _target, bool _state) external onlyOwner {
        isAdmin[_target] = _state;
    }
// set compound state
    function setCompoundEnabled(bool _state) external onlyOwner {
        compoundEnabled = _state;
    }
// set minimum deposit
    function setMinimumDeposit(bool _state, uint256 value) external onlyOwner {
        hasMinimumDeposit = _state;
        minimumDeposit = value;
    }
    function setPoolLimitCapOnDeposit(bool _state) external onlyOwner {
        poolLimitCapOnDeposit = _state;
    }
    function fundPool(uint256 amount) external onlyOwner {
        poolTotalReward += amount;
        rewardToken.transferFrom(address(msg.sender), address(this), amount);
        emit PoolFunded(amount);
    }

    function getBlockData() public view returns(uint blockNumber,uint blockTime) {
        blockNumber = block.number;
        blockTime = block.timestamp;
        return (blockNumber,blockTime);
    }
    modifier isPoolOnline(uint8 action_type) {
        require(poolIsOnline || isAdmin[msg.sender],"staking platform not available now.");
        if (action_type == 0) {
            require(depositEnabled || isAdmin[msg.sender],"deposits not available now.");
        }
        else if (action_type == 1) {
            require(withdrawEnabled || isAdmin[msg.sender],"withdraws not available now.");
        }
        else if (action_type == 2) {
            require(compoundEnabled || isAdmin[msg.sender],"compounds not available now.");
        }
        else if (action_type == 3) {
            require(emergencyWithdrawEnabled || isAdmin[msg.sender],"emergency withdraws not available now.");
        }
        _;
    }
// user functions
    function updateCompoundSettings(bool onDeposit, bool onWithdraw) external {
        compoundOnExternalDeposit[msg.sender] = onDeposit;
        compoundOnExternalWithdraw[msg.sender] = onWithdraw;
        emit UserCompoundUpdated(msg.sender, onDeposit, onWithdraw);
    }
    function deposit(uint256 _amount) external isPoolOnline(0) {
        require(!tempLock,"safety block");
        require(bonusEndBlock > block.number, "this pool has ended.");
        tempLock = true;
        UserInfo storage user = userInfo[msg.sender];
        if (hasUserLimit) {
            require(_amount + user.amount <= poolLimitPerUser, "User amount above limit");
        }
        if (hasMinimumDeposit) {
            require(_amount >= minimumDeposit,"deposit too low.");
        }
        _updatePool();

        if (user.amount > 0) {
            uint256 pending = user.amount * accTokenPerShare / PRECISION_FACTOR - user.rewardDebt;
            if (pending > 0) {
                totalUsersRewards += pending;
                poolTotalReward -= pending;
                rewardToken.transfer(address(msg.sender), pending);
                emit ClaimReward(msg.sender,pending);
            }
        } else {
            totalUsersInStaking += 1;
        }

        if (_amount > 0) {
            user.amount = user.amount + _amount;
            totalUsersStake += _amount;
            stakedToken.transferFrom(address(msg.sender), address(this), _amount);
        }

        user.rewardDebt = user.amount * accTokenPerShare / PRECISION_FACTOR;
        tempLock = false;
        emit Deposit(msg.sender, _amount);
    }
    function withdraw(uint256 _amount) external isPoolOnline(1) {
        require(!tempLock,"safety block");
        if(stakingData.lockedUntilTheEnd) {
            require(block.number >= stakingData.activeUntil,"staking not ended yet");
        }
        tempLock = true;
        UserInfo storage user = userInfo[msg.sender];
        require(user.amount >= _amount, "Amount to withdraw too high");

        _updatePool();

        uint256 pending = user.amount * accTokenPerShare / PRECISION_FACTOR - user.rewardDebt;

        if (_amount > 0) {
            user.amount = user.amount - _amount;
            totalUsersStake -= _amount;
            stakedToken.transfer(address(msg.sender), _amount);
        }
        if (pending > 0) {
            totalUsersRewards += pending;
            poolTotalReward -= pending;
            rewardToken.transfer(address(msg.sender), pending);
            emit ClaimReward(msg.sender,pending);
        }

        user.rewardDebt = user.amount * accTokenPerShare / PRECISION_FACTOR;
        
        if (user.amount == 0) {
            totalUsersInStaking -= 1;
        }

        tempLock = false;
        emit Withdraw(msg.sender, _amount);
    }
    function compound() external isPoolOnline(2) returns(uint256 pending){
        require(!tempLock,"safety block");
        tempLock = true;
        UserInfo storage user = userInfo[msg.sender];
        if(user.amount > 0) {
            _updatePool();
            pending = user.amount * accTokenPerShare / PRECISION_FACTOR - user.rewardDebt;
            if(pending > 0) {
                totalUsersRewards += pending;
                poolTotalReward -= pending;
                totalUsersStake += pending;
                user.amount = user.amount + pending;
                user.rewardDebt = user.amount * accTokenPerShare / PRECISION_FACTOR;
                emit Compound(msg.sender, pending);
            }
        } else {
            revert("nothing to compound");
        }
        tempLock = false;
        return pending;
    }
    function emergencyWithdraw() external isPoolOnline(3) {
        require(!tempLock,"safety block");
        tempLock = true;
        UserInfo storage user = userInfo[msg.sender];
        uint256 amountToTransfer = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;

        if (amountToTransfer > 0) {
            totalUsersStake -= amountToTransfer;
            totalUsersInStaking -= 1;
            stakedToken.transfer(address(msg.sender), amountToTransfer);
        }
        tempLock = false;
        emit EmergencyWithdraw(msg.sender, user.amount);
    }
    //function emergencyRewardWithdraw(uint256 _amount) external onlyOwner {
    //    rewardToken.transfer(address(msg.sender), _amount);
    //}
    //function recoverWrongTokens(address _tokenAddress, uint256 _tokenAmount) external onlyOwner {
    //    IBEP20(_tokenAddress).transfer(address(msg.sender), _tokenAmount);
    //}
    function stopReward() external onlyOwner {
        bonusEndBlock = block.number;
    }
    function updatePoolLimitPerUser(bool _hasUserLimit, uint256 _poolLimitPerUser) external onlyOwner {
        hasUserLimit = _hasUserLimit;
        poolLimitPerUser = _poolLimitPerUser;
    }
    function updateRewardPerBlock(uint256 _rewardPerBlock) external onlyOwner {
        rewardPerBlock = _rewardPerBlock;
    }
    function updateStartAndEndBlocks(uint256 _startBlock, uint256 _bonusEndBlock) external onlyOwner {
        startBlock = _startBlock;
        bonusEndBlock = _bonusEndBlock;
        lastRewardBlock = startBlock;
    }
    function pendingReward(address _user) external view returns (uint256) {
        UserInfo storage user = userInfo[_user];
        uint256 stakedTokenSupply;
        if(stakedToken == rewardToken) {
            stakedTokenSupply = stakedToken.balanceOf(address(this)) - poolTotalReward;
        } else {
            stakedTokenSupply = stakedToken.balanceOf(address(this));
        }

        if (block.number > lastRewardBlock && stakedTokenSupply != 0) {
            uint256 multiplier = _getMultiplier(lastRewardBlock, block.number);
            uint256 cakeReward = multiplier * rewardPerBlock;
            uint256 adjustedTokenPerShare =
                accTokenPerShare + cakeReward * PRECISION_FACTOR / stakedTokenSupply;
            return user.amount * adjustedTokenPerShare / PRECISION_FACTOR - user.rewardDebt;
        } else {
            return user.amount * accTokenPerShare / PRECISION_FACTOR - user.rewardDebt;
        }
    }
    function _updatePool() internal {
        if (block.number <= lastRewardBlock) {
            return;
        }

        uint256 stakedTokenSupply = stakedToken.balanceOf(address(this));

        if (stakedTokenSupply == 0) {
            lastRewardBlock = block.number;
            return;
        }

        uint256 multiplier = _getMultiplier(lastRewardBlock, block.number);
        uint256 cakeReward = multiplier * rewardPerBlock;
        accTokenPerShare = accTokenPerShare + cakeReward * PRECISION_FACTOR / stakedTokenSupply;
        lastRewardBlock = block.number;
    }
    function getPoolDebit() public view returns(uint256){
        return stakedToken.balanceOf(address(this)) - totalUsersStake;
    }
    function getPoolEffectiveBalance() public view returns(uint256){
        return stakedToken.balanceOf(address(this)) - totalUsersStake - totalUsersRewards;
    }
    function getPoolBalance() public view returns(uint256 calc){
        calc = stakedToken.balanceOf(address(this)) - totalUsersRewards;
        return calc;
    }
    function _getMultiplier(uint256 _from, uint256 _to) internal view returns (uint256) {
        if (_to <= bonusEndBlock) {
            return _to - _from;
        } else if (_from >= bonusEndBlock) {
            return 0;
        } else {
            return bonusEndBlock - _from;
        }
    }
}