// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Lottery} from "./Lotto.sol";
import {LinkTokenInterface} from "@chainlink/shared/interfaces/LinkTokenInterface.sol";
import {IVRFCoordinatorV2Plus} from "@chainlink/vrf/dev/interfaces/IVRFCoordinatorV2Plus.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title Lottery Factory with Chainlink VRF v2.5 Subscription Ownership
/// @author Security Researcher
/// @notice Factory owns a single VRF subscription and deploys unlimited weighted lotteries
/// @dev Factory creates subscription on deployment — becomes permanent owner
contract LotteryFactory is Ownable {
    address[] public allLotteries;

    uint256 public immutable vrfSubscriptionId;
    address public immutable linkToken;
    bytes32 public immutable vrfKeyHash;
    IVRFCoordinatorV2Plus public immutable vrfCoordinator;

    event LotteryCreated(address indexed lottery, address indexed creator, uint256 ticketPrice);
    event FactoryDeployed(uint256 subscriptionId);
    event SubscriptionFunded(uint256 indexed subscriptionId, uint256 amount);
    event ConsumerRemoved(address indexed lottery);
    event SubscriptionCancelled(uint256 indexed subscriptionId, address indexed recipient);

    /// @notice Deploys factory and creates VRF subscription owned by the factory
    constructor(address _vrfCoordinator, address _linkToken, bytes32 _keyHash) Ownable(msg.sender) {
        require(_vrfCoordinator != address(0), "Invalid VRF coordinator");
        require(_linkToken != address(0), "Invalid LINK token");
        require(_keyHash != bytes32(0), "Invalid key hash");

        vrfCoordinator = IVRFCoordinatorV2Plus(_vrfCoordinator);
        linkToken = _linkToken;
        vrfKeyHash = _keyHash;

        // Factory creates and owns the subscription forever
        vrfSubscriptionId = vrfCoordinator.createSubscription();

        emit FactoryDeployed(vrfSubscriptionId);
    }

    /// @notice Creates a new lottery — only owner can call
    function createLottery(
        uint256 _ticketPrice,
        address _paymentTokenAddress,
        uint256 _maxPlayers,
        uint256 _lotteryDurationSeconds,
        uint32 _callbackGasLimit,
        uint256 _vrfRequestTimeoutSeconds
    ) external onlyOwner returns (address lotteryAddress) {
        require(_paymentTokenAddress != address(0), "Invalid payment token");
        require(_ticketPrice > 0, "Ticket price must be positive");
        require(_maxPlayers > 0, "Max players must be positive");
        require(_lotteryDurationSeconds > 0, "Duration must be positive");
        require(_callbackGasLimit >= 100000, "Gas limit too low");
        require(_callbackGasLimit <= 2500000, "Gas limit exceeds VRF max");

        Lottery newLottery = new Lottery(
            owner(), // Deployer of LotteryFactory
            address(vrfCoordinator),
            vrfSubscriptionId,
            vrfKeyHash,
            _callbackGasLimit,
            _paymentTokenAddress,
            _ticketPrice,
            _maxPlayers,
            _lotteryDurationSeconds,
            _vrfRequestTimeoutSeconds
        );

        lotteryAddress = address(newLottery);
        allLotteries.push(lotteryAddress);

        // Factory (subscription owner) adds lottery as consumer
        vrfCoordinator.addConsumer(vrfSubscriptionId, lotteryAddress);

        emit LotteryCreated(lotteryAddress, msg.sender, _ticketPrice);
        return lotteryAddress;
    }

    /// @notice Fund the factory-owned subscription with LINK
    /// @param amount Amount of LINK to add (in wei)
    function fundSubscription(uint256 amount) external onlyOwner {
        // Transfer LINK from owner to factory
        require(LinkTokenInterface(linkToken).transferFrom(msg.sender, address(this), amount), "LINK transfer failed");

        // Factory uses transferAndCall to fund subscription
        // transferAndCall sends from factory's balance
        require(
            LinkTokenInterface(linkToken)
                .transferAndCall(address(vrfCoordinator), amount, abi.encode(vrfSubscriptionId)),
            "Subscription funding failed"
        );
        emit SubscriptionFunded(vrfSubscriptionId, amount);
    }

    /// @notice Emergency: Cancel subscription and return remaining LINK
    function cancelSubscription() external onlyOwner {
        vrfCoordinator.cancelSubscription(vrfSubscriptionId, owner());
        emit SubscriptionCancelled(vrfSubscriptionId, owner());
    }

    function getAllLotteries() external view returns (address[] memory) {
        return allLotteries;
    }

    /// @notice Remove a lottery from the VRF subscription to free a consumer slot
    /// @param lotteryAddress Address of the finished lottery
    function removeConsumer(address lotteryAddress) external onlyOwner {
        vrfCoordinator.removeConsumer(vrfSubscriptionId, lotteryAddress);
        emit ConsumerRemoved(lotteryAddress);
    }
}
