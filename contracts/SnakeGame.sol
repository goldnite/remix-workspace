// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

// import "hardhat/console.sol";

contract SnakeGame is Context, Ownable, ReentrancyGuard {
    using SafeMath for uint256;

    // Structure for recording award information
    struct AwardRecord {
        address[5] awardees; // Address of awardees
        uint256[5] scores; //  Scores earned in period
        uint256[5] amounts; // Award amounts
        uint256 timestamp; // Award timestamp
    }

    // Setting variables
    address public withdrawAddress =
        address(0xf753C11e5167247f156D22B0dd6C6333b934835c);
    uint256[5] public awardShare = [29, 24, 19, 14, 9]; // Share rates of award, eg. 29%/24%/19%/14%/9%
    uint256 public price; // Price for playing a single game

    // Permanent variables
    address[] public players; // Address of players
    mapping(address => uint256) public accPoints; // Points accumulated by players
    mapping(address => uint256) public accAwards; // Awards accumulated by players
    mapping(address => bool) public playable; // True if address has paid to play

    AwardRecord[] public awardRecords; // Award records

    // Temporary variables
    uint256 gameCount; // Count of games during a period
    address[] public participants; // Participants during a period
    mapping(address => uint256) public totalPoints; // Points earned by players during a period
    mapping(address => uint256) public lastPlayedTimes; // Last playing time of players during a period

    event StartGame(address player, uint256 timestamp);
    event EndGame(address player, uint256 point, uint256 timestamp);
    event Award(
        address player,
        uint256 rank,
        uint256 amount,
        uint256 timestamp
    );

    // Check if enough payment is covered
    modifier paymentCovered() {
        require(msg.value >= price, "Not enough payment");
        _;
    }

    // Start game
    function startGame() external payable paymentCovered {
        playable[_msgSender()] = true;
        emit StartGame(_msgSender(), block.timestamp);
    }

    // End Game
    function endGame(uint256 point) external nonReentrant {
        require(point > 0 && playable[_msgSender()], "bad operation");
        playable[_msgSender()] = false;
        // Store permanent variables
        if (accPoints[_msgSender()] == 0) {
            players.push(_msgSender());
        }
        accPoints[_msgSender()] += point;

        // Store temporary variables
        if (totalPoints[_msgSender()] == 0) {
            participants.push(_msgSender());
        }
        totalPoints[_msgSender()] += point;
        lastPlayedTimes[_msgSender()] = block.timestamp;
        gameCount++;
        emit EndGame(_msgSender(), point, block.timestamp);
    }

    // Awardize function, this function can be called by only owner.
    function awardize() external onlyOwner {
        address[5] memory winners;
        AwardRecord memory record;
        for (uint256 i = 0; i < participants.length; i++) {
            for (uint256 j = 0; j < 5; j++) {
                if (
                    winners[j] == address(0) ||
                    (totalPoints[participants[i]] >= totalPoints[winners[j]] &&
                        lastPlayedTimes[participants[i]] <
                        lastPlayedTimes[winners[j]])
                ) {
                    for (uint256 k = j + 1; k < 5; k++)
                        winners[k] = winners[k - 1];
                    winners[j] = participants[j];
                    break;
                }
            }
        }
        for (uint256 j = 0; j < 5; j++) {
            if (winners[j] == address(0)) break;
            record.awardees[j] = winners[j];
            record.scores[j] = totalPoints[winners[j]];
            uint256 amount = (awardShare[j] * gameCount * price) / 100;
            record.amounts[j] = amount;
            (bool awardSuccess, ) = payable(winners[j]).call{value: amount}("");
            require(awardSuccess, "Award transfer failed");
            accAwards[winners[j]] += amount;
            emit Award(winners[j], j + 1, amount, block.timestamp);
        }
        record.timestamp = block.timestamp;
        (bool withdrawSuccess, ) = payable(withdrawAddress).call{
            value: address(this).balance
        }("");
        require(withdrawSuccess, "Fee transfer failed");
        while (participants.length > 0) {
            totalPoints[participants[participants.length - 1]] = 0;
            lastPlayedTimes[participants[participants.length - 1]] = 0;
            participants.pop();
        }
        gameCount = 0;
        awardRecords.push(record);
    }

    // Change withdraw address, this function can be called by only owner.
    function setWithdrawAddress(address _withdrawAddress) external onlyOwner {
        withdrawAddress = _withdrawAddress;
    }

    // Change price, this function can be called by only owner.
    function setPrice(uint256 _price) external onlyOwner {
        price = _price;
    }

    // Change award share rate, this function can be called by only owner.
    function setAward(
        uint256 first,
        uint256 second,
        uint256 third,
        uint256 fourth,
        uint256 fifth
    ) external onlyOwner {
        awardShare[0] = first;
        awardShare[1] = second;
        awardShare[2] = third;
        awardShare[3] = fourth;
        awardShare[4] = fifth;
    }

    // Get functions
    function getAwardShare() external view returns (uint256[5] memory) {
        return awardShare;
    }

    function getAwardRecords() external view returns (AwardRecord[] memory) {
        return awardRecords;
    }

    function getPlayers() external view returns (address[] memory) {
        return players;
    }

    function getParticipants() external view returns (address[] memory) {
        return participants;
    }
}
