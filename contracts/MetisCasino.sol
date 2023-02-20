// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

// import "hardhat/console.sol";

contract MetisCasino is Context, Ownable, ReentrancyGuard {
    using SafeMath for uint256;

    address[] public players;
    mapping(address => uint256) public betAmounts;
    mapping(address => uint256) public winAmounts;

    // Check if enough payment is covered
    modifier paymentCovered() {
        require(msg.value > 0, "Not enough payment");
        _;
    }

    event CoinFlip(address player, uint256 bet, bool win, uint256 timestamp);

    // Start game
    function flipCoin()
        external
        payable
        paymentCovered
        nonReentrant
        returns (bool)
    {
        if (betAmounts[_msgSender()] == 0) {
            players.push(_msgSender());
        }
        betAmounts[_msgSender()] += msg.value;
        if (RNG(2) == 1) {
            (bool success, ) = payable(_msgSender()).call{value: msg.value * 2}(
                ""
            );
            require(success, "Transfer failed");
            winAmounts[_msgSender()] += msg.value * 2;
            emit CoinFlip(_msgSender(), msg.value, true, block.timestamp);
            return true;
        }
        emit CoinFlip(_msgSender(), msg.value, false, block.timestamp);
        return false;
    }

    receive() external payable {}

    function donate() external payable {}

    function RNG(uint256 number) public view returns (uint256) {
        return uint256(blockhash(block.number - 1)) % number;
    }

    function withdraw(address withdrawAddress, uint256 amount)
        external
        onlyOwner
    {
        (bool success, ) = payable(withdrawAddress).call{value: amount}("");
        require(success, "Withdraw failed");
    }
}
