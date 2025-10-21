// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ReentrancyGuard} from "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {IVRFCoordinatorV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/interfaces/IVRFCoordinatorV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract Lottery is  VRFConsumerBaseV2Plus, ReentrancyGuard {

    using SafeERC20 for IERC20;

    // --- State variables ---

    // Possible states of the lottery lifecycle
    enum LotteryState {
        OPEN,
        CLOSED,
        CALCULATING,
        CANCELLED,
        FINISHED
    }

    // Token Variables
    IERC20 public immutable i_paymentToken;


    // Core state
    LotteryState public lotteryState; // Current state of the lottery
    address[] private players;  // Array of players (each ticket = 1 entry)
    mapping(address => uint256) private ticketCount;  // Track ticket purchases per player
    uint256 public totalTickets; // Total tickets sold (for weighted randomness)

    // Configurable parameters
    uint256 public immutable maxPlayers;
    uint256 public immutable maxTicketsPerAddress;
    uint256 public immutable deadline;
    uint256 public immutable ticketPrice; // Fee per ticket in wei
    uint256 public platformFees; // Fees collected to subsidize gas costs for automated game closure and winner selection.

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
    mapping(address => uint256) public fulfillCallReward; // Track withdrawable rewards for fulfill function call
    mapping(address => uint256) public cancelTimeoutReward; // Track withdrawable rewards for calling cancelTimeout function

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
    event FulfillCallRewardScheduled(address indexed claimer, uint256 amount);
    event FulfillCallRewardWithdrawn(address indexed claimer, uint amount);
    event CancelTimeoutRewardScheduled(address indexed claimer, uint256 amount);
    event CancelTimeoutRewardWithdrawn(address indexed claimer, uint256 amount);
    event WinnerRequested(uint256 requestId);
    event WinnerSelected(address indexed winner);
    event PrizeClaimed(address indexed winner, uint256 amount);
    event LotteryCancelled(string reason);
    event RandomnessStored(uint256 indexed requestId, uint256 randomWord);
    event FulfillmentIgnored(uint256 indexed requestId, string reason);
    

    constructor(
        address _vrfCoordinator,
        address _paymentTokenAddress,
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

        i_paymentToken = IERC20(_paymentTokenAddress);

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
    // Unique and New players added to the array
    function enter(uint256 tickets) external {
        require(lotteryState == LotteryState.OPEN, "LOTTERY_NOT_OPEN");
        require(block.timestamp < deadline, "DEADLINE_PASSED");
        require(tickets > 0 && tickets <= MAX_TICKETS_PER_TX, "INVALID_TICKET_COUNT");
        require(totalTickets + tickets <= maxPlayers, "MAX_TICKETS_REACHED");

        uint256 newCount = ticketCount[msg.sender] + tickets;
        require(newCount <= maxTicketsPerAddress, "ADDRESS_CAP");

        uint256 ticketCost = tickets * ticketPrice;
        uint256 operationalCost = ticketCost / 100; // 1% fee for operations
        uint totalCost = ticketCost + operationalCost;

        bool success = i_paymentToken.safeTransferFrom(
            msg.sender,
            address(this),
            totalCost
        );
        require(success, "TRANSFER_FAILED: Check Balance");
        // Store unique players's address only once
        if (ticketCount[msg.sender] == 0) {
            players.push(msg.sender);
        }

        ticketCount[msg.sender] = newCount;
        totalTickets += tickets;
        platformFees += operationalCost;

        emit Entered(msg.sender, tickets, totalCost);

        // Auto-close if capacity is reached
        if (totalTickets == maxPlayers) {
            lotteryState = LotteryState.CLOSED;
        }
    }

    
    // Closes the lottery and request randomness from Chainlink
    // Anyone can close the lottery. The function is open for any caller
    // Caller who triggers randomness receives a reward of 0.5% of pot value
    function closeAndRequestWinner() external nonReentrant {
        
        require(vrfRequestTimestamp == 0, "VRF_ALREADY_REQUESTED");
        require(lotteryState == LotteryState.OPEN || lotteryState == LotteryState.CLOSED, "INVALID_STATE");

        bool deadlineReached = block.timestamp >= deadline;
        bool capFilled = totalTickets == maxPlayers;
        require(deadlineReached || capFilled, "NOT_READY");

        // No players → cancel round
        if (players.length == 0) {
            lotteryState = LotteryState.CANCELLED;
            emit LotteryCancelled("NO Players");
            return;
        }

        // Single player → auto-win
        if (players.length == 1) {
            winner = players[0];

            uint256 totalBalance = i_paymentToken.balanceOf(address(this));
            prizePool = totalBalance - platformFees; // Set the prize pool for claiming
            
            uint256 rewardAmount = platformFees / 2; // Use 50% for reward
            platformFees -= rewardAmount;
            
            lotteryState = LotteryState.FINISHED;
            emit WinnerSelected(winner);
            return;
        }

        // Compute rewards and prize pool
        uint256 totalBalance = i_paymentToken.balanceOf(address(this));
        prizePool = totalBalance - platformFees;
        uint256 rewardAmount = platformFees / 2; // use 50% for reward
        platformFees -= rewardAmount;
        

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
            extraArgs: VRFV2PlusClient._argsToBytes(
                VRFV2PlusClient.ExtraArgsV1({ nativePayment: false })
            )
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

        bool success = i_paymentToken.safeTransfer(msg.sender, amt);

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
            emit LotteryCancelled("NO Players");
            return;
        }

        // Store randomness for later, safe processing
        _storedRandomWord = randomWords[0] ;
        randomReady = true;
        vrfRequestTimestamp = 0;

        emit RandomnessStored(_requestId, _storedRandomWord);
    }

    // Finalize lottery with stored randomness by selecting the winner
    // Separating storage and consumption of randomness ensures safety
    // The function is open for any caller
    // Caller who finalizes the winner receives a reward of 0.5% of pot value
    function finalizeWithStoredRandomness() external nonReentrant {
        require(randomReady, "RANDOM_NOT_READY");
        require(lotteryState == LotteryState.CALCULATING, "BAD_STATE");
        require(totalTickets > 0, "NOT_ENOUGH_PLAYERS");


        uint256 randomNumber = _storedRandomWord % totalTickets;
        uint256 cumulative = 0;
        address selected;

        uint256 uniquePlayers = players.length;

        for (uint256 i=0; i<uniquePlayers; i++){
            cumulative += ticketCount[players[i]];
            if (randomNumber < cumulative) {
                selected = players[i];
                break;
            }
        }
        winner = selected;

        // Consume the randomness
        randomReady = false;
        _storedRandomWord = 0;




        lotteryState = LotteryState.FINISHED;

        fulfillCallReward[msg.sender] = platformFees;
        platformFees = 0;

        emit FulfillCallRewardScheduled(msg.sender, fulfillCallReward[msg.sender]);
        emit WinnerSelected(winner);
    }

    // Allows caller to withdraw finalize reward
    function withdrawFulfillCallReward() external nonReentrant {
        uint256 amt = fulfillCallReward[msg.sender];
        require(amt > 0, "NO_REWARD");

        fulfillCallReward[msg.sender] = 0;

        bool success = i_paymentToken.safeTransfer(msg.sender, amt);

        emit FulfillCallRewardWithdrawn(msg.sender, amt);
    }

    // Cancel if VRF response has timed out
    function cancelIfTimedOut() external {
        require(lotteryState == LotteryState.CALCULATING, "BAD_STATE");
        require(vrfRequestTimestamp != 0, "NO_VRF_REQUEST");
        require(block.timestamp >= vrfRequestTimestamp + _TIMEOUT, "NOT_TIMED_OUT");

        uint256 cancelRewardAmount = platformFees;
        platformFees = 0;
        cancelTimeoutReward[msg.sender] = cancelRewardAmount;

        lotteryState = LotteryState.CANCELLED;
        vrfRequestTimestamp = 0;

        emit LotteryCancelled("VRF Timeout");
        emit CancelTimeoutRewardScheduled(msg.sender, uint256 cancelRewardAmount);
    }

    // Allows caller to withdraw cancelTimeout function call reward
    function withdrawCancelTimeoutReward() external {
        uint256 amt = cancelTimeoutReward[msg.sender];
        require(amt>0, "NO_REWARD");

        cancelTimeoutReward[msg.sender] = 0;

        bool success = i_paymentToken.safeTransfer(msg.sender, amt);

        emit CancelTimeoutRewardWithdrawn(msg.sender, amt);

    }

    // Winner claims prize
    function claimPrize() external nonReentrant {
        require(lotteryState == LotteryState.FINISHED, "Not finished");
        require(msg.sender == winner, "Not winner");
        require(!prizeClaimed, "Prize already claimed");

        uint256 prizeMoney = prizePool;
        prizeClaimed = true;
        prizePool = 0;
        bool success = i_paymentToken.safeTransfer(msg.sender, prizeMoney);

        emit PrizeClaimed(msg.sender, prizeMoney);
    }

    // Players can claim refund if round is cancelled
    function claimRefund() external nonReentrant {
        require(lotteryState == LotteryState.CANCELLED, "Lottery not cancelled");
        uint256 ticketsBought = ticketCount[msg.sender];
        require(ticketsBought > 0, "No refund available");

        ticketCount[msg.sender] = 0;
        uint256 refundAmount = ticketsBought * ticketPrice;

        bool success = i_paymentToken.safeTransfer(msg.sender,refundAmount);

        emit RefundClaimed(msg.sender, refundAmount);
    }

    // --- Internal helpers ---

    // Check LINK subscription has enough balance
    function _hasEnoughLink() internal view returns (bool) {
        (uint96 balance,,,,) = _COORDINATOR.getSubscription(_SUBSCRIPTION_ID);
        return balance >= ESTIMATED_LINK_COST;
    }

    /**
     * @notice Returns whether the VRF request has timed out and how much time is left
     * @return shouldCancel True if timeout has expired and cancelIfTimedOut() can be safely called.
     * @return timeRemainingSeconds Remaining seconds untill timeout expires (0 if expired or not applicable)
     */
    function VRFRequestTimeOutStatus() external view returns (bool shouldCancel, uint256 seconds) {
        // If contract is not waiting for a VRF fufillment, no timeout check required

        if (lotteryState != LotteryState.CALCULATING || vrfRequestTimestamp == 0) {
            return (false, 0); // No timeout check required
        }

        uint256 timeOutAt = vrfRequestTimestamp+_TIMEOUT;

        // If timeout passed, return 0 (no time left)
        if (block.timestamp >= timeOutAt){
            return (true, 0);
        }

        // Otherwise, return how many seconds are left
        return timeOutAt - block.timestamp;
    }

    // --- View helpers ---
    function getPlayersCount() external view returns (uint256) {
        return players.length;
    }

    function getTicketsOf(address player) external view returns (uint256) {
        return ticketCount[player];
    }

    function getPot() external view returns (uint256) {
        return i_paymentToken.balanceOf(address(this));
    }
}
