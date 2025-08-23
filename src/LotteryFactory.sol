// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Lottery} from "./Lotto.sol";

contract LotteryFactory {
    address[] public allLotteries;
    uint64 public subscriptionId; // Chainlink VRF subscription ID (shared across all lotteries)
    address public owner;
    address public vrfCoordinator;

    event LotteryCreated(address indexed lotteryAddress, address indexed creator, uint256 minFee);

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    constructor(uint64 _subscriptionId, address _vrfCoordinator) {
        subscriptionId = _subscriptionId;
        vrfCoordinator = _vrfCoordinator;
        owner = msg.sender;
    }

    function createLottery(
        uint256 _minFee,
        uint256 maxPlayers,
        uint256 duration,
        uint32 _callbackGasLimit,
        uint16 _requestConfirmations,
        uint32 _numWords,
        uint256 _timeout
    ) external onlyOwner{
        Lottery newLottery = new Lottery(
            vrfCoordinator,
            _minFee,
            maxPlayers,
            duration,
            subscriptionId,
            _callbackGasLimit,
            _requestConfirmations,
            _numWords,
            _timeout
        );

        allLotteries.push(address(newLottery));
        emit LotteryCreated(address(newLottery), msg.sender, _minFee);
    }

    function getAllLotteries() external view returns (address[] memory) {
        return allLotteries;
    }
}
