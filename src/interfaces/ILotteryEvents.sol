// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface ILotteryEvents {
    event Entered(address indexed player, uint256 tickets, uint256 rangeStart, uint256 rangeEnd);
    event WinnerPicked(address indexed winner, uint256 prizeAmount, uint256 winningTicketId);
    event PrizeClaimed(address indexed winner, uint256 amount);
    event AutoWinTriggered(address indexed winner, uint256 prizeAmount);
    event FeesDistributed(uint256 amount);
    event LotteryClosed(uint256 indexed requestId); // Indexed for easier searching
    event LotteryStateRecovered(uint256 timestamp);
}
