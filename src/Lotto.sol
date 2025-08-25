// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {IERC20} from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {VRFConsumerBaseV2} from "@chainlink/contracts/src/v0.8/vrf/VRFConsumerBaseV2.sol";
import {VRFCoordinatorV2Interface} from "@chainlink/contracts/src/v0.8/vrf/interfaces/VRFCoordinatorV2Interface.sol";

contract Lottery is Ownable, VRFConsumerBaseV2, ReentrancyGuard {
    enum LotteryState { 
        OPEN, 
        CLOSED, 
        CALCULATING, 
        CANCELLED, 
        FINISHED 
    }

    // Core state
    LotteryState public lotteryState;
    address[] private players;
    mapping(address => uint256) private ticketCount;

    // Params
    uint256 public maxPlayers;
    uint256 public maxTicketsPerAddress;
    uint256 public deadline;
    uint256 public factoryMinFee;


    // VRF tracking
    uint256 private vrfRequestTimestamp;
    uint256 public immutable timeout;
    uint256 public constant MAX_TICKETS_PER_TX = 100;

    // Outcome
    address public winner;
    uint256 public requestId;
    bool public prizeClaimed;

    // Chainlink VRF config
    VRFCoordinatorV2Interface public immutable coordinator;
    uint64 private immutable subscriptionId;
    address private immutable linkTokenAddress; // Sepolia LINK
    bytes32 private immutable keyHash;

    uint32 public immutable callbackGasLimit;
    uint16 public immutable requestConfirmations;
    uint32 public immutable numWords;

    uint256 public constant ESTIMATED_LINK_COST = 2 * 10**18; // 2 LINK

    uint256 private _storedRandomWord;
    bool public randomReady;

    // Events
    event Entered(address indexed player, uint256 tickets, uint256 amount);
    event RefundClaimed(address indexed player, uint256 amount);
    event WinnerRequested(uint256 requestId);
    event WinnerSelected(address indexed winner);
    event PrizeClaimed(address indexed winner, uint256 amount);
    event RoundCancelled();
    event RandomnessStored(uint256 indexed requestId, uint256 randomWord);
    event FulfillmentIgnored(uint256 indexed requestId, string reason);

    constructor(
        address _vrfCoordinator,
        uint256 _minFee,
        uint256 _maxPlayers,
        uint256 _duration,
        uint64 _subscriptionId,
        uint32 _callbackGasLimit,
        uint16 _requestConfirmations,
        uint32 _numWords,
        uint256 _timeout,
        address _linkTokenAddress,
        bytes32 _keyHash 
    ) VRFConsumerBaseV2(_vrfCoordinator) Ownable(msg.sender) {
        require(_minFee > 0, "FREE_ENTRY_FORBIDDEN");
        require(_maxPlayers > 0, "INVALID_MAX_PLAYERS");
        require(_timeout >= 60 && _timeout <= 24 hours, "TIMEOUT_RANGE");
        require(_numWords >= 1, "NUM_WORDS");

        factoryMinFee = _minFee;
        maxPlayers = _maxPlayers;
        maxTicketsPerAddress = _maxPlayers / 20;
        if (maxTicketsPerAddress == 0) maxTicketsPerAddress = 1;

        deadline = block.timestamp + _duration;
        lotteryState = LotteryState.OPEN;

        coordinator = VRFCoordinatorV2Interface(_vrfCoordinator);
        subscriptionId = _subscriptionId;
        linkTokenAddress = _linkTokenAddress;
        keyHash = _keyHash;

        callbackGasLimit = _callbackGasLimit;
        requestConfirmations = _requestConfirmations;
        numWords = _numWords;
        timeout = _timeout;
    }

    function enter(uint256 tickets) external payable {
        require(lotteryState == LotteryState.OPEN, "LOTTERY_NOT_OPEN");
        require(block.timestamp < deadline, "DEADLINE_PASSED");
        require(tickets > 0 && tickets <= MAX_TICKETS_PER_TX, "INVALID_TICKET_COUNT");
        require(players.length + tickets <= maxPlayers, "MAX_TICKETS_REACHED");

        uint256 newCount = ticketCount[msg.sender] + tickets;
        require(newCount <= maxTicketsPerAddress, "ADDRESS_CAP");

        uint256 cost = tickets * factoryMinFee;
        require(msg.value == cost, "INCORRECT_ETH");

        ticketCount[msg.sender] = newCount;
        for (uint256 i = 0; i < tickets; i++) {
            players.push(msg.sender);
        }

        emit Entered(msg.sender, tickets, cost);

        if (players.length == maxPlayers) {
            lotteryState = LotteryState.CLOSED;
        }
    }

    function closeAndRequestWinner() external {
        require(vrfRequestTimestamp == 0, "VRF_ALREADY_REQUESTED");
        require(
            lotteryState == LotteryState.OPEN || lotteryState == LotteryState.CLOSED,
            "INVALID_STATE"
        );
        

        bool deadlineReached = block.timestamp >= deadline;
        bool capFilled = players.length == maxPlayers;
        require(deadlineReached || capFilled, "NOT_READY");

        if (players.length == 0) {
            lotteryState = LotteryState.CANCELLED;
            return;
        }

        if (players.length == 1) {
            winner = players[0];
            lotteryState = LotteryState.FINISHED;
            emit WinnerSelected(winner);
            return;
        }

        require(_hasEnoughLink(), "VRF_FUNDS_LOW");

        lotteryState = LotteryState.CALCULATING;

        // Clear previous randomness snapshot
        randomReady = false;
        _storedRandomWord = 0;


        requestId = coordinator.requestRandomWords(
            keyHash,
            subscriptionId,
            requestConfirmations,
            callbackGasLimit,
            numWords
        );
        vrfRequestTimestamp = block.timestamp;

        emit WinnerRequested(requestId);
    }

    function fulfillRandomWords(uint256 _requestId, uint256[] memory randomWords) internal override {
    // Never revert here. Just ignore unexpected fulfillments.
        if (lotteryState != LotteryState.CALCULATING) {
            emit FulfillmentIgnored(_requestId, "BAD_STATE");
            return;
        }
        if (_requestId != requestId) {
            emit FulfillmentIgnored(_requestId, "STALE_OR_UNKNOWN_REQUEST");
            return;
        }
        if (randomWords.length == 0) {
            emit FulfillmentIgnored(_requestId, "NO_RANDOM_WORDS");
            return;
        }
        if (players.length == 0) {
            // No players — mark round cancelled and move on.
            lotteryState = LotteryState.CANCELLED;
            vrfRequestTimestamp = 0;
            emit RoundCancelled();
            return;
        }

        // Store randomness for later, safe processing
        _storedRandomWord = randomWords[0];
        randomReady = true;
        vrfRequestTimestamp = 0;

        emit RandomnessStored(_requestId, _storedRandomWord);
    }

    function finalizeWithStoredRandomness() external nonReentrant {
        require(randomReady, "RANDOM_NOT_READY");
        require(lotteryState == LotteryState.CALCULATING, "BAD_STATE");

        uint256 totalTickets = players.length;
        require(totalTickets > 0, "NOT_ENOUGH_PLAYERS");

        uint256 winnerIndex = _storedRandomWord % totalTickets;
        winner = players[winnerIndex];

        // Consume the randomness
        randomReady = false;
        _storedRandomWord = 0;

        lotteryState = LotteryState.FINISHED;
        emit WinnerSelected(winner);
    }

    function cancelIfTimedOut() external {
        require(lotteryState == LotteryState.CALCULATING, "BAD_STATE");
        require(vrfRequestTimestamp != 0, "NO_VRF_REQUEST");
        require(block.timestamp >= vrfRequestTimestamp + timeout, "NOT_TIMED_OUT");

        lotteryState = LotteryState.CANCELLED;
        vrfRequestTimestamp = 0;

        emit RoundCancelled();
    }

    function claimPrize() external nonReentrant {
        require(lotteryState == LotteryState.FINISHED, "Not finished");
        require(msg.sender == winner, "Not winner");
        require(!prizeClaimed, "Prize already claimed");

        prizeClaimed = true;
        uint256 prize = address(this).balance;
        (bool success, ) = msg.sender.call{value: prize}("");
        require(success, "Transfer failed");

        emit PrizeClaimed(msg.sender, prize);
    }

    function claimRefund() external nonReentrant {
        require(lotteryState == LotteryState.CANCELLED, "Lottery not cancelled");
        uint256 ticketsBought = ticketCount[msg.sender];
        require(ticketsBought > 0, "No refund available");

        ticketCount[msg.sender] = 0;
        uint256 refundAmount = ticketsBought * factoryMinFee;

        (bool success, ) = msg.sender.call{value: refundAmount}("");
        require(success, "Refund failed");

        emit RefundClaimed(msg.sender, refundAmount);
    }

    function _hasEnoughLink() internal view returns (bool) {
        (uint96 balance, , , ) = coordinator.getSubscription(subscriptionId);
        return balance >= ESTIMATED_LINK_COST;
    }

    function getPlayersCount() external view returns (uint256) {
        return players.length;
    }



    function getTicketsOf(address player) external view returns (uint256) {
        return ticketCount[player];
    }

    function getPot() external view returns (uint256) {
        return address(this).balance;
    }
}