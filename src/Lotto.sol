// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "openzeppelin-contracts/contracts/access/Ownable.sol";
import "openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import "@chainlink/contracts/v0.8/VRFConsumerBaseV2.sol";
import "@chainlink/contracts/v0.8/interfaces/VRFCoordinatorV2Interface.sol";

contract Lottery is Ownable, VRFConsumerBaseV2, ReentrancyGuard {
    enum LotteryState { OPEN, CLOSED, CALCULATING, CANCELLED, FINISHED }

    // Core state
    LotteryState public s_lotteryState;
    address[] private s_players;
    mapping(address => uint256) private s_ticketCount;

    // Params
    uint256 public s_maxPlayers;
    uint256 public s_maxTicketsPerAddress;
    uint256 public s_deadline;
    uint256 public factoryMinFee;

    // VRF tracking
    uint256 public s_vrfRequestTimestamp;
    uint256 public s_timeout;
    uint256 public constant MAX_TICKETS_PER_TX = 100;

    // Outcome
    address public s_winner;
    uint256 public s_requestId;
    bool public s_prizeClaimed;

    // Chainlink VRF config
    VRFCoordinatorV2Interface public COORDINATOR;
    IERC20 public LINK_TOKEN;
    uint64 public subscriptionId;
    address public linkToken = 0x779877A7B0D9E8603169DdbD7836e478b4624789;   // Sepolia LINK
    bytes32 public keyHash = 0x474e34a077df58807dbe9c96d3c009b23b3c6d0cce433e59bbf5b34f823bc56c;

    uint32 public callbackGasLimit;
    uint16 public requestConfirmations;
    uint32 public numWords;

    uint256 public constant ESTIMATED_LINK_COST = 2 * 10**18; // 2 LINK

    // Events
    event Entered(address indexed player, uint256 tickets, uint256 amount);
    event RefundClaimed(address indexed player, uint256 amount);
    event WinnerRequested(uint256 requestId);
    event WinnerSelected(address indexed winner);
    event PrizeClaimed(address indexed winner, uint256 amount);
    event RoundCancelled();

    constructor(
        address _vrfCoordinator,
        uint256 _minFee,
        uint256 maxPlayers,
        uint256 duration,
        uint64 _subscriptionId,
        uint32 _callbackGasLimit,
        uint16 _requestConfirmations,
        uint32 _numWords,
        uint256 _timeout
    ) VRFConsumerBaseV2(_vrfCoordinator) Ownable(msg.sender){
        require(_minFee > 0, "FREE_ENTRY_FORBIDDEN");
        require(maxPlayers > 0, "INVALID_MAX_PLAYERS");
        require(_timeout >= 60 && _timeout <= 24 hours, "TIMEOUT_RANGE");
        require(_numWords >= 1, "NUM_WORDS");

        factoryMinFee = _minFee;
        s_maxPlayers = maxPlayers;
        s_maxTicketsPerAddress = maxPlayers / 20;
        if (s_maxTicketsPerAddress == 0) s_maxTicketsPerAddress = 1;

        s_deadline = block.timestamp + duration;
        s_lotteryState = LotteryState.OPEN;

        COORDINATOR = VRFCoordinatorV2Interface(_vrfCoordinator);
        LINK_TOKEN = IERC20(linkToken);
        subscriptionId = _subscriptionId;

        callbackGasLimit = _callbackGasLimit;
        requestConfirmations = _requestConfirmations;
        numWords = _numWords;
        s_timeout = _timeout;
    }

    function enter(uint256 tickets) external payable {
        require(s_lotteryState == LotteryState.OPEN, "LOTTERY_NOT_OPEN");
        require(block.timestamp < s_deadline, "DEADLINE_PASSED");
        require(tickets > 0 && tickets <= MAX_TICKETS_PER_TX, "INVALID_TICKET_COUNT");
        require(s_players.length + tickets <= s_maxPlayers, "MAX_TICKETS_REACHED");

        uint256 newCount = s_ticketCount[msg.sender] + tickets;
        require(newCount <= s_maxTicketsPerAddress, "ADDRESS_CAP");

        uint256 cost = tickets * factoryMinFee;
        require(msg.value == cost, "INCORRECT_ETH");

        s_ticketCount[msg.sender] = newCount;
        for (uint256 i = 0; i < tickets; i++) {
            s_players.push(msg.sender);
        }

        emit Entered(msg.sender, tickets, cost);

        if (s_players.length == s_maxPlayers) {
            s_lotteryState = LotteryState.CLOSED;
        }
    }

    // Close on deadline or cap and request VRF for multi-player
    function closeAndRequestWinner() external {
        require(
            s_lotteryState == LotteryState.OPEN || s_lotteryState == LotteryState.CLOSED,
            "INVALID_STATE"
        );
        require(s_vrfRequestTimestamp == 0, "VRF_ALREADY_REQUESTED");

        bool deadlineReached = block.timestamp >= s_deadline;
        bool capFilled = s_players.length == s_maxPlayers;
        require(deadlineReached || capFilled, "NOT_READY");

        if (s_players.length == 0) {
            s_lotteryState = LotteryState.CANCELLED;
            return;
        }

        if (s_players.length == 1) {
            s_winner = s_players[0];
            s_lotteryState = LotteryState.FINISHED;
            emit WinnerSelected(s_winner);
            return;
        }

        require(_hasEnoughLink(), "VRF_FUNDS_LOW");

        s_lotteryState = LotteryState.CALCULATING;
        s_requestId = COORDINATOR.requestRandomWords(
            keyHash,
            subscriptionId,
            requestConfirmations,
            callbackGasLimit,
            numWords
        );
        s_vrfRequestTimestamp = block.timestamp;

        emit WinnerRequested(s_requestId);
    }

    // VRF callback: finalize winner
    function fulfillRandomWords(uint256 requestId, uint256[] memory randomWords) internal override {
        require(s_lotteryState == LotteryState.CALCULATING, "BAD_STATE");
        require(requestId == s_requestId, "INVALID_REQUEST_ID");
        require(randomWords.length > 0, "NO_RANDOM_WORDS");

        uint256 totalTickets = s_players.length;
        require(totalTickets > 0, "NOT_ENOUGH_PLAYERS");

        uint256 winnerIndex = randomWords[0] % totalTickets;
        s_winner = s_players[winnerIndex];
        s_lotteryState = LotteryState.FINISHED;
        s_vrfRequestTimestamp = 0;

        emit WinnerSelected(s_winner);
    }

    // Timeout-ased cancel for liveness
    function cancelIfTimedOut() external {
        require(s_lotteryState == LotteryState.CALCULATING, "BAD_STATE");
        require(s_vrfRequestTimestamp != 0, "NO_VRF_REQUEST");
        require(block.timestamp >= s_vrfRequestTimestamp + s_timeout, "NOT_TIMED_OUT");

        s_lotteryState = LotteryState.CANCELLED;
        s_vrfRequestTimestamp = 0;

        emit RoundCancelled();
    }

    // Winner claims prize(pull)
    function claimPrize() external nonReentrant {
        require(s_lotteryState == LotteryState.FINISHED, "Not finished");
        require(msg.sender == s_winner,"Not winner");
        require(!s_prizeClaimed, "Prize already claimed");

        s_prizeClaimed = true;
        uint256 prize = address(this).balance;
        (bool success, ) = msg.sender.call{value: prize}("");
        require(success, "Transfer failed");

        emit PrizeClaimed(msg.sender, prize);
    }

    // Players claims refund when cancelled (pull)
    function claimRefund() external nonReentrant {
        require(s_lotteryState == LotteryState.CANCELLED, "Lottery not cancelled");
        uint256 ticketsBought = s_ticketCount[msg.sender];
        require(ticketsBought > 0, "No refund available");

        s_ticketCount[msg.sender] = 0;
        uint256 refundAmount = ticketsBought * factoryMinFee;

        (bool success, ) = msg.sender.call{value: refundAmount}("");
        require(success, "Refund failed");

        emit RefundClaimed(msg.sender, refundAmount);
    }

    // Subscription LINK heuristic check
    function _hasEnoughLink() internal view returns (bool) {
        (uint96 balance, , , ) = COORDINATOR.getSubscription(subscriptionId);
        return balance >= ESTIMATED_LINK_COST;
    }

    // Views
    function getPlayersCount() external view returns (uint256) {
        return s_players.length;
    }

    function getTicketsOf(address player) external view returns (uint256) {
        return s_ticketCount[player];
    }

    function getPot() external view returns (uint256) {
        return address(this).balance;
    }
}
