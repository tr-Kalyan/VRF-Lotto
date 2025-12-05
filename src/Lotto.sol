// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {VRFConsumerBaseV2Plus} from "@chainlink/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/vrf/dev/libraries/VRFV2PlusClient.sol";
import {AutomationCompatibleInterface} from "@chainlink/automation/AutomationCompatible.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";


/// @title Weighted VRF v2.5 Lottery
/// @author Security Researcher
/// @notice Implements Cumulative Sum Pattern for gas-efficient weighted odds
contract Lottery is VRFConsumerBaseV2Plus, AutomationCompatibleInterface, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    enum LotteryState { OPEN, CALCULATING, FINISHED }
    
    // Immutable Config
    IERC20 public immutable paymentToken;
    uint256 public immutable ticketPrice;
    uint256 public immutable duration;
    uint256 public immutable maxTickets;
    
    // VRF v2.5 Config
    uint256 public s_subscriptionId;
    bytes32 public s_keyHash;
    uint32 public s_callbackGasLimit;
    uint16 public constant REQUEST_CONFIRMATIONS = 3;
    uint32 public constant NUM_WORDS = 1;

    // Safety / Timeout Config
    uint256 public immutable vrfTimeoutSeconds; 
    uint256 public vrfRequestTimestamp;

    // State
    LotteryState public lotteryState;
    uint256 public deadline;
    uint256 public prizePool;
    uint256 public platformFees;
    
    address public winner;
    bool public prizeClaimed;

    // Logic: Cumulative Sums (Ranges)
    // We track "up to which ticket number" a player owns.
    struct TicketRange {
        address player;
        uint256 currentTotalTickets; // The upper bound of their ticket range
    }
    
    TicketRange[] public playersRanges;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event Entered(address indexed player, uint256 tickets, uint256 rangeEnd);
    event WinnerPicked(address indexed winner, uint256 prizeAmount, uint256 winningTicketId);
    event AutoWinTriggered(address indexed winner, uint256 prizeAmount);
    event FeesDistributed(uint256 amount);
    event LotteryClosed(uint256 requestId);
    event LotteryStateRecovered(uint256 timestamp);

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

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
        transferOwnership(_admin);
        s_subscriptionId = _subscriptionId;
        s_keyHash = _keyHash;
        s_callbackGasLimit = _callbackGasLimit;
        
        paymentToken = IERC20(_paymentToken);
        ticketPrice = _ticketPrice;
        maxTickets = _maxTickets;
        duration = _duration;
        vrfTimeoutSeconds = _vrfTimeoutSeconds;

        // Initialize
        deadline = block.timestamp + _duration;
        lotteryState = LotteryState.OPEN;
    }

    /*//////////////////////////////////////////////////////////////
                            USER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Buy tickets. Gas cost is O(1) regardless of amount.
    /// @param _ticketAmount Number of tickets to buy
    function enter(uint256 _ticketAmount) external nonReentrant {
        require(lotteryState == LotteryState.OPEN, "Lottery not open");
        require(block.timestamp < deadline, "Lottery ended");
        require(_ticketAmount > 0, "Zero tickets");

        // 1. Calculate Costs
        uint256 cost = _ticketAmount * ticketPrice;
        uint256 fee = cost / 100; // 1% Fee
        uint256 totalTransfer = cost + fee;

        // 2. Determine New Range
        uint256 currentTotal = 0;
        if (playersRanges.length > 0) {
            currentTotal = playersRanges[playersRanges.length - 1].currentTotalTickets;
        }
        
        uint256 newTotal = currentTotal + _ticketAmount;
        require(newTotal <= maxTickets, "Max tickets exceeded");

        // 3. Transfer Tokens (Checks-Effects-Interactions)
        paymentToken.safeTransferFrom(msg.sender, address(this), totalTransfer);

        
        // 4. Update State
        prizePool += cost;
        platformFees += fee;

        // O(1) Storage Write
        playersRanges.push(TicketRange({
            player: msg.sender,
            currentTotalTickets: newTotal
        }));

        emit Entered(msg.sender, _ticketAmount, newTotal);
    }

    /// @notice Claim prize if you are the winner
    function claimPrize() external nonReentrant {
        require(lotteryState == LotteryState.FINISHED, "Not finished");
        require(msg.sender == winner, "Not winner");
        require(!prizeClaimed, "Already claimed");

        prizeClaimed = true;
        uint256 amount = prizePool;
        prizePool = 0; // Prevent re-entrancy drain

        paymentToken.safeTransfer(winner, amount);
    }

    /*//////////////////////////////////////////////////////////////
                           AUTOMATION LOGIC
    //////////////////////////////////////////////////////////////*/

    function checkUpkeep(bytes calldata /* checkData */) 
        external 
        view 
        override 
        returns (bool upkeepNeeded, bytes memory /* performData */) 
    {
        bool isOpen = lotteryState == LotteryState.OPEN;
        bool timePassed = block.timestamp >= deadline;
        bool hasPlayers = playersRanges.length > 0;

        upkeepNeeded = isOpen && timePassed && hasPlayers;
        return (upkeepNeeded, "");
    }

    function performUpkeep(bytes calldata /* performData */) external override nonReentrant {
        (bool upkeepNeeded, ) = this.checkUpkeep("");
        require(upkeepNeeded, "Upkeep not needed");

        // 1. Lock State
        lotteryState = LotteryState.CALCULATING;

        // 2. Distribute Fees (Keep 50% in contract for Gas, Send 50% to Owner)
        
        if (platformFees > 0) {
            paymentToken.safeTransfer(owner(), platformFees); // VRFConsumerBaseV2Plus has owner()
            emit FeesDistributed(platformFees);
            platformFees = 0;
        }

        // 3. OPTIMIZATION: Single Player Auto-Win
        // If only 1 person entered, don't waste LINK on VRF.
        if (playersRanges.length == 1) {
            winner = playersRanges[0].player;
            lotteryState = LotteryState.FINISHED;
            prizeClaimed = false;
            emit AutoWinTriggered(winner, prizePool);
            return;
        }

        // 4. Standard Flow: Request VRF v2.5
        VRFV2PlusClient.RandomWordsRequest memory req = VRFV2PlusClient.RandomWordsRequest({
            keyHash: s_keyHash,
            subId: s_subscriptionId,
            requestConfirmations: REQUEST_CONFIRMATIONS,
            callbackGasLimit: s_callbackGasLimit,
            numWords: NUM_WORDS,
            extraArgs: VRFV2PlusClient._argsToBytes(VRFV2PlusClient.ExtraArgsV1({nativePayment: false}))
        });

        // Use s_vrfCoordinator from Base Contract
        uint256 requestId = s_vrfCoordinator.requestRandomWords(req);
        emit LotteryClosed(requestId);
    }

    /*//////////////////////////////////////////////////////////////
                        SAFETY / RECOVERY
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Resets the lottery state if Chainlink VRF fails to respond within timeout.
     * @dev Allows the Owner to retry the VRF request by setting state back to OPEN.
     */
    function recoverStuckLottery() external nonReentrant onlyOwner {
        require(lotteryState == LotteryState.CALCULATING, "Not stuck");
        require(block.timestamp > vrfRequestTimestamp + vrfTimeoutSeconds, "Timeout not passed");

        // Reset state to OPEN so performUpkeep can try again
        lotteryState = LotteryState.OPEN; 
        
        emit LotteryStateRecovered(block.timestamp);
    }


    /*//////////////////////////////////////////////////////////////
                             VRF CALLBACK
    //////////////////////////////////////////////////////////////*/

    function fulfillRandomWords(uint256 /* requestId */, uint256[] calldata randomWords) internal override {
        // Sanity Check
        if (lotteryState != LotteryState.CALCULATING) return;

        // 1. Get total tickets (The upper bound of the last range)
        uint256 totalSold = playersRanges[playersRanges.length - 1].currentTotalTickets;
        
        // 2. Determine Winning Ticket ID
        uint256 winningTicketId = randomWords[0] % totalSold;

        // 3. Find the Winner (Linear Search)
        // Since playersRanges stores *entries* (batches), not tickets, this loop is short.
        // E.g., 100 players buying 10,000 tickets = only 100 loops.
        // Gas Usage: ~1500 gas per unique player. Safe for up to ~1500-2000 unique players.
        address foundWinner = address(0);
        
        for (uint256 i = 0; i < playersRanges.length; i++) {
            if (playersRanges[i].currentTotalTickets > winningTicketId) {
                foundWinner = playersRanges[i].player;
                break;
            }
        }

        // 4. Finalize
        winner = foundWinner;
        lotteryState = LotteryState.FINISHED;
        prizeClaimed = false;

        emit WinnerPicked(winner, prizePool, winningTicketId);
    }

    /*//////////////////////////////////////////////////////////////
                             VIEW HELPERS
    //////////////////////////////////////////////////////////////*/

    function getPot() external view returns (uint256) {
        return prizePool;
    }

    function getTotalTicketsSold() external view returns (uint256) {
        if (playersRanges.length == 0) return 0;
        return playersRanges[playersRanges.length - 1].currentTotalTickets;
    }
    
    function getPlayerCount() external view returns (uint256) {
        return playersRanges.length;
    }
}
