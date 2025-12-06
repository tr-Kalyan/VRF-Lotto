// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {VRFConsumerBaseV2Plus} from "@chainlink/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/vrf/dev/libraries/VRFV2PlusClient.sol";
import {AutomationCompatibleInterface} from "@chainlink/automation/AutomationCompatible.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";


/// @title Gas-Optimized Weighted Lottery with Chainlink VRF v2.5 & Automation
/// @author Security Researcher
/// @notice Fully autonomous lottery using cumulative sum pattern for O(1) entry and weighted randomness
/// @dev Factory deploys this contract — subscription owned by factory — all fees go to owner
contract Lottery is VRFConsumerBaseV2Plus, AutomationCompatibleInterface, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                                STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    enum LotteryState { OPEN, CALCULATING, FINISHED }

    // Immutable configuration
    IERC20 public immutable paymentToken;
    uint256 public immutable ticketPrice;
    uint256 public immutable duration;
    uint256 public immutable maxTickets;
    address public immutable feeRecipient;

    // VRF configuration (required by base contract)
    uint256 public s_subscriptionId;
    bytes32 public s_keyHash;
    uint32 public s_callbackGasLimit;
    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private constant NUM_WORDS = 1;


    // Safety timeout
    uint256 public immutable vrfTimeoutSeconds;
    uint256 public vrfRequestTimestamp;

    // Runtime state
    LotteryState public lotteryState;
    uint256 public deadline;
    uint256 public prizePool;
    uint256 public platformFees;

    address public winner;
    bool public prizeClaimed;

    // Weighted randomness via cumulative sum pattern
    struct TicketRange {
        address player;
        uint256 currentTotalTickets; // Upper bound of tickets owned
    }
    
    TicketRange[] public playersRanges;

    /*//////////////////////////////////////////////////////////////
                                   EVENTS
    //////////////////////////////////////////////////////////////*/

    event Entered(address indexed player, uint256 tickets, uint256 rangeStart, uint256 rangeEnd);
    event WinnerPicked(address indexed winner, uint256 prizeAmount, uint256 winningTicketId);
    event AutoWinTriggered(address indexed winner, uint256 prizeAmount);
    event FeesDistributed(uint256 amount);
    event LotteryClosed(uint256 indexed requestId);
    event LotteryStateRecovered(uint256 timestamp);

    /*//////////////////////////////////////////////////////////////
                                  CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Deploys lottery with VRF and payment configuration
    /// @param _admin Owner who receives all platform fees
    constructor(
        address _admin,
        address _vrfCoordinator,
        uint256 _subscriptionId,
        bytes32 _keyHash,
        uint32 _callbackGasLimit,
        address _paymentToken,
        uint256 _ticketPrice,
        uint256 _maxTickets,
        uint256 _duration,
        uint256 _vrfTimeoutSeconds
    ) VRFConsumerBaseV2Plus(_vrfCoordinator) {
        
        feeRecipient = _admin;

        // VRF parameters required by base contract
        s_subscriptionId = _subscriptionId;
        s_keyHash = _keyHash;
        s_callbackGasLimit = _callbackGasLimit;

        paymentToken = IERC20(_paymentToken);
        ticketPrice = _ticketPrice;
        maxTickets = _maxTickets;
        duration = _duration;
        vrfTimeoutSeconds = _vrfTimeoutSeconds;

        deadline = block.timestamp + _duration;
        lotteryState = LotteryState.OPEN;
    }

    /*//////////////////////////////////////////////////////////////
                               USER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Purchase tickets — O(1) gas cost using cumulative sum pattern
    /// @param _ticketCount Number of tickets to buy
    function enter(uint256 _ticketCount) external nonReentrant {
        require(lotteryState == LotteryState.OPEN, "Lottery not open");
        require(block.timestamp < deadline, "Lottery ended");
        require(_ticketCount > 0, "Zero tickets");

        uint256 cost = _ticketCount * ticketPrice;
        uint256 fee = cost / 100; // 1% platform fee
        uint256 totalTransfer = cost + fee;

        uint256 currentTotal = playersRanges.length == 0 
            ? 0 
            : playersRanges[playersRanges.length - 1].currentTotalTickets;
        
        uint256 newTotal = currentTotal + _ticketCount;
        require(newTotal <= maxTickets, "Max tickets exceeded");

        prizePool += cost;
        platformFees += fee;

        playersRanges.push(TicketRange({
            player: msg.sender,
            currentTotalTickets: newTotal
        }));    


        paymentToken.safeTransferFrom(msg.sender, address(this), totalTransfer);

        

        emit Entered(msg.sender, _ticketCount, currentTotal, newTotal - 1);
    }

    /// @notice Winner claims prize after draw completes
    function claimPrize() external nonReentrant {
        require(lotteryState == LotteryState.FINISHED, "Not finished");
        require(msg.sender == winner, "Not winner");
        require(!prizeClaimed, "Already claimed");

        prizeClaimed = true;
        uint256 amount = prizePool;
        prizePool = 0;

        paymentToken.safeTransfer(winner, amount);
    }

    /*//////////////////////////////////////////////////////////////
                             AUTOMATION LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Chainlink Automation: check if lottery should be closed
    function checkUpkeep(bytes calldata) 
        external 
        view 
        override 
        returns (bool upkeepNeeded, bytes memory) 
    {
        bool isOpen = lotteryState == LotteryState.OPEN;
        bool timePassed = block.timestamp > deadline;
        bool hasPlayers = playersRanges.length > 0;

        upkeepNeeded = isOpen && timePassed && hasPlayers;
        return (upkeepNeeded, "");
    }

    /// @notice Chainlink Automation: close lottery and request randomness
    function performUpkeep(bytes calldata) external override nonReentrant {
        (bool upkeepNeeded, ) = this.checkUpkeep("");
        require(upkeepNeeded, "Upkeep not needed");

        lotteryState = LotteryState.CALCULATING;

        // Distribute all platform fees to owner
        if (platformFees > 0) {
            paymentToken.safeTransfer(feeRecipient, platformFees);
            emit FeesDistributed(platformFees);
            platformFees = 0;
        }

        // Single player = instant win (saves LINK)
        if (playersRanges.length == 1) {
            winner = playersRanges[0].player;
            lotteryState = LotteryState.FINISHED;
            prizeClaimed = false;
            emit AutoWinTriggered(winner, prizePool);
            return;
        }

        // Request randomness from Chainlink VRF
        VRFV2PlusClient.RandomWordsRequest memory req = VRFV2PlusClient.RandomWordsRequest({
            keyHash: s_keyHash,
            subId: s_subscriptionId,
            requestConfirmations: REQUEST_CONFIRMATIONS,
            callbackGasLimit: s_callbackGasLimit,
            numWords: NUM_WORDS,
            extraArgs: VRFV2PlusClient._argsToBytes(VRFV2PlusClient.ExtraArgsV1({nativePayment: false}))
        });

        uint256 requestId = s_vrfCoordinator.requestRandomWords(req);
        vrfRequestTimestamp = block.timestamp;
        emit LotteryClosed(requestId);
    }

    /*//////////////////////////////////////////////////////////////
                           VRF CALLBACK & WINNER SELECTION
    //////////////////////////////////////////////////////////////*/

    /// @dev Chainlink VRF callback — selects winner using cumulative sum
    function fulfillRandomWords(uint256, uint256[] calldata randomWords) internal override {
        if (lotteryState != LotteryState.CALCULATING) return;

        uint256 totalSold = playersRanges[playersRanges.length - 1].currentTotalTickets;
        uint256 winningTicketId = randomWords[0] % totalSold;

        address foundWinner = address(0);
        for (uint256 i = 0; i < playersRanges.length; i++) {
            if (playersRanges[i].currentTotalTickets > winningTicketId) {
                foundWinner = playersRanges[i].player;
                break;
            }
        }

        winner = foundWinner;
        lotteryState = LotteryState.FINISHED;
        prizeClaimed = false;

        emit WinnerPicked(winner, prizePool, winningTicketId);
    }

    /*//////////////////////////////////////////////////////////////
                               RECOVERY
    //////////////////////////////////////////////////////////////*/

    /// @notice Recover from stuck VRF request after timeout
    /// @dev Only owner can call — resets to OPEN state
    function recoverStuckLottery() external nonReentrant onlyOwner {
        require(lotteryState == LotteryState.CALCULATING, "Not stuck");
        require(block.timestamp > vrfRequestTimestamp + vrfTimeoutSeconds, "Timeout not passed");

        lotteryState = LotteryState.OPEN;
        emit LotteryStateRecovered(block.timestamp);
    }

    /*//////////////////////////////////////////////////////////////
                               VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function getPot() external view returns (uint256) { return prizePool; }
    function getTotalTicketsSold() external view returns (uint256) {
        return playersRanges.length == 0 ? 0 : playersRanges[playersRanges.length - 1].currentTotalTickets;
    }
    function getPlayerCount() external view returns (uint256) { return playersRanges.length; }
}