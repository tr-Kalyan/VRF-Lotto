// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Lottery} from "./Lotto.sol";
import {IERC20} from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {VRFCoordinatorV2Interface} from "@chainlink/contracts/src/v0.8/vrf/interfaces/VRFCoordinatorV2Interface.sol";

contract LotteryFactory {
    address[] public allLotteries;
    uint64 public subscriptionId; // Chainlink VRF subscription ID (shared across all lotteries)
    address public owner;
    address private linkToken;
    bytes32 private keyHash;
    VRFCoordinatorV2Interface public vrfCoordinator;

    event LotteryCreated(address indexed lotteryAddress, address indexed creator, uint256 minFee);

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    

    constructor(uint64 _subscriptionId, address _vrfCoordinator, address _linkToken, bytes32 _keyHash) {
        subscriptionId = _subscriptionId;
        vrfCoordinator = VRFCoordinatorV2Interface(_vrfCoordinator);
        linkToken = _linkToken;
        keyHash = _keyHash;
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
            address(vrfCoordinator),
            _minFee,
            maxPlayers,
            duration,
            subscriptionId,
            _callbackGasLimit,
            _requestConfirmations,
            _numWords,
            _timeout,
            linkToken,
            keyHash
        );

        allLotteries.push(address(newLottery));
        emit LotteryCreated(address(newLottery), msg.sender, _minFee);
    }

    function getAllLotteries() external view returns (address[] memory) {
        return allLotteries;
    }

    function getLinkBalance(address account) external view returns (uint256) {
        return IERC20(linkToken).balanceOf(account);
    }

    function getSubscriptionBalance(uint64 subId) external view returns (uint96 balance) {
        (balance, , , ) = vrfCoordinator.getSubscription(subId);
    }
}
