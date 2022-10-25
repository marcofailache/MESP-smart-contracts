//SPDX-License-Identifier: MIT
// 
// by krakovia (@karola96)
pragma solidity ^0.8.16;
import "./stakingBase.sol";

interface IStak {
    function emergencyClose(address target) external;
}
contract MespStakingFactory is Ownable {
//BYTES
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
//STRING
    string private constant SIGNING_DOMAIN = "MESPStakingVouchers";
    string private constant SIGNATURE_VERSION = "1";
//UINT
    uint256 totalStakings;
    uint256 public stakingCreationPrice = 3 ether;
//ADDRESS
    address[] private stakingList;
    address private medusaFundReceiver;
//STRUCT
    struct stakingCoupon {
        uint256 maxUsages;
        uint256 stakingPrice;
        uint256 couponOwnerFee;
        uint256 timeUsed;
        address couponOwner;
    }
//MAPPING
    mapping(bytes32 => stakingCoupon) public coupons;
    mapping (address => stakingBase.stakingInitData) public stakingData;
//EVENT
    event StakingCreated(address indexed stakingAddress, address indexed stakedToken, address indexed rewardToken, address owner, uint256 date);
//CONSTRUCTOR
    constructor() {
    }
//USER FUNCTIONS
    function createStaking(address[2] calldata _adr, uint256[4] calldata _uint, string[3] calldata _str,
                           string calldata referralCoupon , bytes32 couponHash, bool lockedUntilTheEnd
    ) public payable returns(address) {
        // staking configuration
        bool couponValid;
        if(verifyHash(couponHash,referralCoupon)) {
            if(verifyCoupon(couponHash)) {
                couponValid = true;
                require(msg.value == coupons[couponHash].stakingPrice + coupons[couponHash].couponOwnerFee,"wrong BNB amount with coupon");
                (bool sent,) = coupons[couponHash].couponOwner.call{value: coupons[couponHash].couponOwnerFee}("");
                require(sent, "Failed to send Ether");
                (sent,) = medusaFundReceiver.call{value: coupons[couponHash].stakingPrice}("");
                require(sent, "Failed to send Ether");
                coupons[couponHash].timeUsed += 1;
            }
        }
        if(!couponValid) {
            require(msg.value == stakingCreationPrice,"wrong BNB amount");
            (bool sent,) = medusaFundReceiver.call{value: msg.value}("");
            require(sent, "Failed to send Ether");
        }
        stakingBase.stakingInitData memory staking;
        staking.stakedToken = _adr[0];
        staking.rewardToken = _adr[1];
        staking.rewardAmount = _uint[0];
        staking.activeUntil = _uint[1];
        staking.minDeposit = _uint[2];
        staking.maxDeposit = _uint[3];
        staking.logoUrl = _str[0];
        staking.websiteUrl = _str[1];
        staking.description = _str[2];
        staking.owner = msg.sender;
        staking.factory = address(this);
        staking.lockedUntilTheEnd = lockedUntilTheEnd;
        // staking creation
        stakingBase newStaking = new stakingBase(staking);
        // state updates
        totalStakings += 1;
        stakingList.push(address(newStaking));
        IBEP20(staking.rewardToken).transferFrom(msg.sender, address(this), _uint[0]);
        stakingData[address(newStaking)] = staking;
        IBEP20(staking.rewardToken).approve(address(newStaking),_uint[0]);
        newStaking.fundPool(_uint[0]);
        newStaking.transferOwnership(msg.sender);
        emit StakingCreated(address(newStaking),_adr[0],_adr[1],msg.sender,block.timestamp);
        return address(newStaking);
    }
//VIEWS
    function getStakingData(address _stakingAddress) public view returns (stakingBase.stakingInitData memory) {
        return stakingData[_stakingAddress];
    }
    
    function getStakingList() public view returns(address[] memory) {
        return stakingList;
    }
    function calcTokenPerBlock(uint256 _startDate, uint256 _endDate, uint256 _totalRewards) view external returns(uint256) {
        return this.calcTokenPerBlock(_startDate,_endDate,_totalRewards);
    }
    //Coupons related functions
    function verifyHash(bytes32 _hash, string calldata ver) public pure returns(bool) {
        return keccak256(abi.encodePacked(ver)) == _hash;
    }
    function verifyCoupon(bytes32 _hash) private view returns(bool) {
        return coupons[_hash].couponOwner != address(0x0) ? true : false;
    }
    function generateHash(string calldata _str) external pure returns(bytes32) {
        return keccak256(abi.encodePacked(_str));
    }
    function stakingCreationPriceWithCoupon(bytes32 _hash) public view returns(uint) {
        return coupons[_hash].stakingPrice + coupons[_hash].couponOwnerFee;
    }
// ADMIN FUNCTIONS
    function emergencyCloseStaking(address staking, address resqueAddress) external onlyOwner {
        IStak(staking).emergencyClose(resqueAddress);
    }
    function setMedusaFundReceiver(address newReceiver) external onlyOwner {
        medusaFundReceiver = newReceiver;
    }
    function setStakingCreationPrice(uint newPrice) external onlyOwner {
        stakingCreationPrice = newPrice;
    }
    // Coupons
    function setCouponMaxUsages(bytes32 couponHash, uint maxUsages) external onlyOwner {
        coupons[couponHash].maxUsages = maxUsages;
    }
    function setCouponStakingPrice(bytes32 couponHash, uint stakingPrice) external onlyOwner {
        coupons[couponHash].stakingPrice = stakingPrice;
    }
    function setCouponOwnerFee(bytes32 couponHash, uint couponOwnerFee) external onlyOwner {
        coupons[couponHash].couponOwnerFee = couponOwnerFee;
    }
    function setCouponOwner(bytes32 couponHash, address couponOwner) external onlyOwner {
        coupons[couponHash].couponOwner = couponOwner;
    }
    function setCoupon(
        bytes32 couponHash, uint maxUsages,
        uint stakingPrice, uint couponOwnerFee, address couponOwner
        ) external onlyOwner {
        coupons[couponHash].maxUsages = maxUsages;
        coupons[couponHash].stakingPrice = stakingPrice;
        coupons[couponHash].couponOwnerFee = couponOwnerFee;
        coupons[couponHash].couponOwner = couponOwner;
    }
}
