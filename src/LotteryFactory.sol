// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Lottery} from "./Lotto.sol";
import {IERC20} from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";
//import {VRFCoordinatorV2Interface} from "@chainlink/contracts/src/v0.8/vrf/interfaces/VRFCoordinatorV2Interface.sol";
import {IVRFCoordinatorV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/interfaces/IVRFCoordinatorV2Plus.sol";
contract LotteryFactory {
    address[] public allLotteries;
    uint256 public vrfSubscriptionId; // Chainlink VRF subscription ID (shared across all lotteries)
    address public owner;
    address private linkToken;
    bytes32 private vrfKeyHash;
    IVRFCoordinatorV2Plus public vrfCoordinator;

    event LotteryCreated(address indexed lotteryAddress, address indexed creator, uint256 minFee);

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    constructor(uint256 _subscriptionId, address _vrfCoordinator, address _linkToken, bytes32 _keyHash) {
        vrfSubscriptionId = _subscriptionId;
        vrfCoordinator = IVRFCoordinatorV2Plus(_vrfCoordinator);
        linkToken = _linkToken;
        vrfKeyHash = _keyHash;
        owner = msg.sender;
    }

    function createLottery(
        uint256 _ticketPrice,
        uint256 maxPlayers,
        uint256 lotteryDurationSeconds,
        uint32 _callbackGasLimit,
        uint16 _requestConfirmations,
        uint32 _numWords,
        uint256 _vrfRequestTimeoutSeconds
    ) external onlyOwner {
        Lottery newLottery = new Lottery(
            address(vrfCoordinator),
            _ticketPrice,
            maxPlayers,
            lotteryDurationSeconds,
            vrfSubscriptionId,
            _callbackGasLimit,
            _requestConfirmations,
            _numWords,
            _vrfRequestTimeoutSeconds,
            linkToken,
            vrfKeyHash
        );

        allLotteries.push(address(newLottery));
        emit LotteryCreated(address(newLottery), msg.sender, _ticketPrice);
    }

    function getAllLotteries() external view returns (address[] memory) {
        return allLotteries;
    }

    function getLinkBalance(address account) external view returns (uint256) {
        return IERC20(linkToken).balanceOf(account);
    }

    function getSubscriptionBalance() external view returns (uint96 balance) {    
        (balance,,,,) = vrfCoordinator.getSubscription(vrfSubscriptionId);
    }
}
