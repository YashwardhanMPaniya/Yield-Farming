// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract YieldFarming is ERC20 {
    uint256 private currentPoolId = 0;

    uint constant WHALE_REWARD_PERCENTAGE = 120;

    address public owner;

    // Pool info struct
    struct Pool {
        uint maxAmount;
        uint yieldPercent;
        uint minDeposit;
        uint rewardTime;
        uint currentAmount;
    }

    // array for holding pools
    Pool[] poolsList;

    // users list
    address[] users;

    // User deposit info
    struct DepositInfo {
        uint amount;
        uint depositTimestamp;
    }

    // user -> pool -> depositInfo
    mapping(address => mapping(uint256 => DepositInfo)) userToPoolDeposit;

    // user -> total deposit
    mapping(address => uint256) userTotalDeposit;

    constructor() ERC20("HoliHarvest", "HLHV") {
        owner = msg.sender;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) {
            revert();
        }
        _;
    }

    function addPool(
        uint maxAmount,
        uint yieldPercent,
        uint minDeposit,
        uint rewardTime
    ) public onlyOwner {
        if (minDeposit > maxAmount) revert();
        poolsList.push(
            Pool(maxAmount, yieldPercent, minDeposit, rewardTime, 0)
        );
        unchecked {
            currentPoolId++;
        }
    }

    function depositWei(uint poolId) public payable {
        if (poolId > currentPoolId) {
            revert();
        }

        if (msg.value < poolsList[poolId].minDeposit) {
            revert();
        }
        unchecked {
            if (
                msg.value + poolsList[poolId].currentAmount >
                poolsList[poolId].maxAmount
            ) revert();

            if (userToPoolDeposit[msg.sender][poolId].depositTimestamp != 0)
                revert();

            userToPoolDeposit[msg.sender][poolId] = DepositInfo(
                msg.value,
                block.timestamp
            );

            poolsList[poolId].currentAmount += msg.value;

            if (userTotalDeposit[msg.sender] == 0) {
                users.push(msg.sender);
            }
            userTotalDeposit[msg.sender] += msg.value;
        }
    }

    function withdrawWei(uint poolId, uint amount) public {
        uint userBalance = userToPoolDeposit[msg.sender][poolId].amount;

        if (amount > userBalance) {
            revert();
        }
        unchecked {
            poolsList[poolId].currentAmount -= amount;
            userToPoolDeposit[msg.sender][poolId].amount -= amount;
        }

        (bool success, ) = payable(msg.sender).call{value: amount}("");

        require(success);
    }

    function claimRewards(uint poolId) public {
        (uint reward, ) = getRewardAmountByPool(poolId, msg.sender);

        if (reward == 0) {
            revert();
        }

        userToPoolDeposit[msg.sender][poolId].depositTimestamp = block
            .timestamp;
        unchecked {
            _mint(
                msg.sender,
                isWhale(msg.sender)
                    ? (reward * WHALE_REWARD_PERCENTAGE) / 100
                    : reward
            );
        }
    }

    function checkPoolDetails(
        uint poolId
    ) public view returns (uint, uint, uint, uint) {
        Pool memory pool = poolsList[poolId];
        return (
            pool.maxAmount,
            pool.yieldPercent,
            pool.minDeposit,
            pool.rewardTime
        );
    }

    function checkUserDeposits(address user) public view returns (uint, uint) {
        uint poolsAmount = poolsList.length;

        uint depositOverall;
        uint rewardOverall;

        for (uint i = 0; i < poolsAmount; i++) {
            (uint reward, uint deposit) = getRewardAmountByPool(i, user);
            depositOverall += deposit;
            rewardOverall += reward;
        }

        return (depositOverall, rewardOverall);
    }

    function checkUserDepositInPool(
        uint poolId
    ) public view returns (address[] memory, uint[] memory) {
        uint usersCount = users.length;
        uint poolUsersLength;
        for (uint i = 0; i < usersCount; i++) {
            if (userToPoolDeposit[users[i]][poolId].amount != 0)
                poolUsersLength++;
        }

        uint[] memory deposits = new uint[](poolUsersLength);
        address[] memory currentPoolUsers = new address[](poolUsersLength);

        for (uint i = 0; i < usersCount; i++) {
            if (userToPoolDeposit[users[i]][poolId].amount != 0) {
                deposits[i] = userToPoolDeposit[users[i]][poolId].amount;
                currentPoolUsers[i] = users[i];
            }
        }

        return (currentPoolUsers, deposits);
    }

    function checkClaimableRewards(uint poolId) public view returns (uint) {
        (uint reward, ) = getRewardAmountByPool(poolId, msg.sender);
        return reward;
    }

    function checkRemainingCapacity(uint poolId) public view returns (uint) {
        Pool memory pool = poolsList[poolId];
        return pool.maxAmount - pool.currentAmount;
    }

    function checkWhaleWallets() public view returns (address[] memory) {
        uint usersLength = users.length;

        uint len;
        for (uint i = 0; i < usersLength; i++) {
            address userAddress = users[i];
            if (isWhale(userAddress)) len++;
        }

        address[] memory whales = new address[](len);
        for (uint i = 0; i < usersLength; i++) {
            address userAddress = users[i];
            if (isWhale(userAddress)) {
                whales[whales.length - len] = userAddress;
                len--;
            }
        }

        return whales;
    }

    function getRewardAmountByPool(
        uint256 poolId,
        address user
    ) private view returns (uint reward, uint deposit) {
        unchecked {
            uint timePassed = block.timestamp -
                userToPoolDeposit[user][poolId].depositTimestamp;
            uint rewards_count = timePassed / poolsList[poolId].rewardTime;
            reward =
                (userToPoolDeposit[user][poolId].amount *
                    poolsList[poolId].yieldPercent *
                    rewards_count) /
                100;
            deposit = userToPoolDeposit[user][poolId].amount;
        }
    }

    function isWhale(address user) private view returns (bool) {
        return userTotalDeposit[user] > 10_000;
    }
}
