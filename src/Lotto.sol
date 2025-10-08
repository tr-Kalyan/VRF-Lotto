// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ReentrancyGuard} from "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {IVRFCoordinatorV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/interfaces/IVRFCoordinatorV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";


contract Lottery is  VRFConsumerBaseV2Plus, ReentrancyGuard {

    // --- State variables ---

    // Possible states of the lottery lifecycle
    enum LotteryState {
        OPEN,
        CLOSED,
        CALCULATING,
        CANCELLED,
        FINISHED
    }

    // Core state
    LotteryState public lotteryState; // Current state of the lottery
    address[] private players;  // Array of players (each ticket = 1 entry)
    mapping(address => uint256) private ticketCount;  // Track ticket purchases per player

    // Configurable parameters
    uint256 public maxPlayers;
    uint256 public maxTicketsPerAddress;
    uint256 public deadline;
    uint256 public ticketPrice; // Fee per ticket in wei


    // Prize pool accounting
    uint256 public prizePool;       // Total prize (excludes trigger reward)


    // VRF tracking
    uint256 private vrfRequestTimestamp; // Timestamp of last randomness request
    uint256 public immutable _TIMEOUT;  // How long before VRF can be considered timed out
    uint256 public constant MAX_TICKETS_PER_TX = 100;

    // Outcome variables
    address public winner;
    uint256 public s_requestId;
    bool public prizeClaimed;
    mapping(address => uint256) public pendingRewards;  // Track withdrawable trigger rewards

    // Chainlink VRF config
    IVRFCoordinatorV2Plus public immutable _COORDINATOR;
    uint256 private immutable _SUBSCRIPTION_ID;
    address private immutable _LINKTOKENADDRESS; // Sepolia LINK token
    bytes32 private immutable _KEYHASH;

    uint32 public immutable _CALLBACKGASLIMIT;
    uint16 public immutable _REQUESTCONFIRMATIONS;
    uint32 public immutable _NUMWORDS;

    uint256 public constant ESTIMATED_LINK_COST = 2 * 10 ** 18; // 2 LINK

    // Randomness storage
    uint256 private _storedRandomWord;
    bool public randomReady;

    // --- Events ---
    event Entered(address indexed player, uint256 tickets, uint256 amount);
    event RefundClaimed(address indexed player, uint256 amount);
    event TriggerRewardScheduled(address indexed claimer, uint256 amount);
    event TriggerRewardWithdrawn(address indexed claimer, uint256 amount);
    event WinnerRequested(uint256 requestId);
    event WinnerSelected(address indexed winner);
    event PrizeClaimed(address indexed winner, uint256 amount);
    event RoundCancelled(string reason);
    event RandomnessStored(uint256 indexed requestId, uint256 randomWord);
    event FulfillmentIgnored(uint256 indexed requestId, string reason);

    constructor(
        address _vrfCoordinator,
        uint256 _ticketPrice,
        uint256 _maxPlayers,
        uint256 _duration,
        uint256 _subscriptionId,
        uint32 _callbackGasLimit,
        uint16 _requestConfirmations,
        uint32 _numWords,
        uint256 _vrfRequestTimeoutSeconds,
        address _linkTokenAddress,
        bytes32 _keyHash
    ) VRFConsumerBaseV2Plus(_vrfCoordinator) {
        require(_ticketPrice > 0, "FREE_ENTRY_FORBIDDEN");
        require(_maxPlayers > 0, "INVALID_MAX_PLAYERS");
        require(_vrfRequestTimeoutSeconds >= 60 && _vrfRequestTimeoutSeconds <= 24 hours, "TIMEOUT_RANGE");
        require(_numWords >= 1, "NUM_WORDS");

        ticketPrice = _ticketPrice;
        maxPlayers = _maxPlayers;
        maxTicketsPerAddress = _maxPlayers / 20;
        if (maxTicketsPerAddress == 0) maxTicketsPerAddress = 1;

        deadline = block.timestamp + _duration;
        lotteryState = LotteryState.OPEN;

        _COORDINATOR = IVRFCoordinatorV2Plus(_vrfCoordinator);
        _SUBSCRIPTION_ID = _subscriptionId;
        _LINKTOKENADDRESS = _linkTokenAddress;
        _KEYHASH = _keyHash;

        _CALLBACKGASLIMIT = _callbackGasLimit;
        _REQUESTCONFIRMATIONS = _requestConfirmations;
        _NUMWORDS = _numWords;
        _TIMEOUT = _vrfRequestTimeoutSeconds;
    }

    // --- Core functions ---

    // Allows players to enter the lottery by buying tickets
    // Each ticket adds one entry into the players array
    function enter(uint256 tickets) external payable {
        require(lotteryState == LotteryState.OPEN, "LOTTERY_NOT_OPEN");
        require(block.timestamp < deadline, "DEADLINE_PASSED");
        require(tickets > 0 && tickets <= MAX_TICKETS_PER_TX, "INVALID_TICKET_COUNT");
        require(players.length + tickets <= maxPlayers, "MAX_TICKETS_REACHED");

        uint256 newCount = ticketCount[msg.sender] + tickets;
        require(newCount <= maxTicketsPerAddress, "ADDRESS_CAP");

        uint256 cost = tickets * ticketPrice;
        require(msg.value == cost, "INCORRECT_ETH");

        ticketCount[msg.sender] = newCount;
        for (uint256 i = 0; i < tickets; i++) {
            players.push(msg.sender);
        }

        emit Entered(msg.sender, tickets, cost);

        // Auto-close if capacity is reached
        if (players.length == maxPlayers) {
            lotteryState = LotteryState.CLOSED;
        }
    }

    // Closes the lottery and request randomness from Chainlink
    // Caller who triggers randomness gets a reward
    function closeAndRequestWinner() external nonReentrant {
        require(ticketCount[msg.sender] > 0, "MUST_BE_PLAYER");
        require(vrfRequestTimestamp == 0, "VRF_ALREADY_REQUESTED");
        require(lotteryState == LotteryState.OPEN || lotteryState == LotteryState.CLOSED, "INVALID_STATE");

        bool deadlineReached = block.timestamp >= deadline;
        bool capFilled = players.length == maxPlayers;
        require(deadlineReached || capFilled, "NOT_READY");

        // No players → cancel round
        if (players.length == 0) {
            lotteryState = LotteryState.CANCELLED;
            emit RoundCancelled("NO Players");
            return;
        }

        // Single player → auto-win
        if (players.length == 1) {
            winner = players[0];
            lotteryState = LotteryState.FINISHED;
            emit WinnerSelected(winner);
            return;
        }

        // Compute rewards and prize pool
        uint256 totalBalance = address(this).balance;
        uint256 rewardAmount = totalBalance / 100; //1%
        prizePool = totalBalance - rewardAmount;

        lotteryState = LotteryState.CALCULATING;
        randomReady = false;
        _storedRandomWord = 0;
         

        require(_hasEnoughLink(), "VRF_FUNDS_LOW");

        // Prepare VRF request
        VRFV2PlusClient.RandomWordsRequest memory req = VRFV2PlusClient.RandomWordsRequest({
            keyHash: _KEYHASH,
            subId: _SUBSCRIPTION_ID,
            requestConfirmations: _REQUESTCONFIRMATIONS,
            callbackGasLimit: _CALLBACKGASLIMIT,
            numWords: _NUMWORDS,
            extraArgs: ""
        });

        // Submit randomness request
        s_requestId = _COORDINATOR.requestRandomWords(req);
        vrfRequestTimestamp = block.timestamp;

        // Reward caller who triggered VRF
        pendingRewards[msg.sender] += rewardAmount;


        emit TriggerRewardScheduled(msg.sender, rewardAmount);
        emit WinnerRequested(s_requestId);
    }

    // Allows caller to withdraw trigger reward
    function withdrawTriggerReward() external nonReentrant {
        uint256 amt = pendingRewards[msg.sender];
        require(amt > 0, "NO_REWARD");
        pendingRewards[msg.sender] = 0;
        (bool ok, ) = msg.sender.call{value: amt}("");
        require(ok, "WITHDRAW_FAILED");
        emit TriggerRewardWithdrawn(msg.sender, amt);
    }

    // Callback from Chainlink VRF
    // Never reverts - unexpected fulfilllments are ignored
    function fulfillRandomWords(uint256 _requestId, uint256[] calldata randomWords ) internal override {
        
        // Fulfill function should never revert.
        // If this reverted, the randomness request would remain pending forever,
        // leaving the lottery stuck in the "CALCULATING" state.
        // Instead, we defensively ignore unexpected fulfillments.

        if (lotteryState != LotteryState.CALCULATING) {
            emit FulfillmentIgnored(_requestId, "BAD_STATE");
            return;
        }

        if (_requestId != s_requestId) {
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
            emit RoundCancelled("NO Players");
            return;
        }

        // Store randomness for later, safe processing
        _storedRandomWord = randomWords[0];
        randomReady = true;
        vrfRequestTimestamp = 0;

        emit RandomnessStored(_requestId, _storedRandomWord);
    }

    // Finalize lottery with stored randomness
    // Separating storage and consumption of randomness ensures safety
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

    // Cancel if VRF response has timed out
    function cancelIfTimedOut() external {
        require(lotteryState == LotteryState.CALCULATING, "BAD_STATE");
        require(vrfRequestTimestamp != 0, "NO_VRF_REQUEST");
        require(block.timestamp >= vrfRequestTimestamp + _TIMEOUT, "NOT_TIMED_OUT");

        lotteryState = LotteryState.CANCELLED;
        vrfRequestTimestamp = 0;

        emit RoundCancelled("VRF Timeout");
    }

    // Winner claims prize
    function claimPrize() external nonReentrant {
        require(lotteryState == LotteryState.FINISHED, "Not finished");
        require(msg.sender == winner, "Not winner");
        require(!prizeClaimed, "Prize already claimed");

        prizeClaimed = true;
        (bool success,) = msg.sender.call{value: prizePool}("");
        require(success, "Transfer failed");

        emit PrizeClaimed(msg.sender, prizePool);
    }

    // Players can claim refund if round is cancelled
    function claimRefund() external nonReentrant {
        require(lotteryState == LotteryState.CANCELLED, "Lottery not cancelled");
        uint256 ticketsBought = ticketCount[msg.sender];
        require(ticketsBought > 0, "No refund available");

        ticketCount[msg.sender] = 0;
        uint256 refundAmount = ticketsBought * ticketPrice;

        (bool success,) = msg.sender.call{value: refundAmount}("");
        require(success, "Refund failed");

        emit RefundClaimed(msg.sender, refundAmount);
    }

    // --- Internal helpers ---

    // Check LINK subscription has enough balance
    function _hasEnoughLink() internal view returns (bool) {
        (uint96 balance,,,,) = _COORDINATOR.getSubscription(_SUBSCRIPTION_ID);
        return balance >= ESTIMATED_LINK_COST;
    }

    // --- View helpers ---
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
