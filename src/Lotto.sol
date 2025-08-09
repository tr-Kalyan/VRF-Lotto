// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";
import "@chianlink/contracts/src/v0.8/VRFCoordinatorV2Interface.sol";

contract Lottery is Ownable, VRFConsumerBaseV2 {
    enum LotteryState { OPEN, CLOSED, CALCULATING, CANCELLED, FINISHED }

    LotteryState public s_lotteryState;
    address[] private s_players;
    mapping(address => uint256) private s_ticketCount;
    uint256 public s_minimumFee;
    uint256 public s_maxPlayers;
    uint256 public s_maxTicketsPerAddress;
    uint256 public s_vrfRequestTimestamp;
    uint256 public constant TIMEOUT = 1 hours;
    uint256 public constant MAX_TICKETS_PER_TX = 100;
    address public s_winner;
    uint256 public s_requestId;
    uint256 public constant ESTIMAtED_LINK_COST = 2 * 10**18; 

    // ChainLink VRF 
    VRFCoordinatorV2Interface COORDINATOR;
    IERC20 LINK_TOKEN;
    uint64 subscriptionId;
    address vrfCoordinator = 0x8103B0A8A00be2DDC778e6e7eaa21791Cd364625;
    address linkToken = 0x779877A7B0D9E8603169DdbD7836e478b4624789;
    bytes32 keyHash = 0x474e34a077df58807dbe9c96d3c009b23b3c6d0cce433e59bbf5b34f823bc56c;
    uint32 callbackGasLimit = 100000;
    uint16 requestConfirmations = 3;
    uint32 numWords = 1;

    event Entered(address indexed player,uint256 tickets, uint amount);
    event RefundClaimed(address indexed player, uint256 amount);
    event winnerRequested(uint256 requestId);
    event winnerSelected(address indexed winner);

    constructor(
        uint256 minimumFee,
        uint256 maxPlayers,
        uint256 duration,
        uint256 _subscriptionId
    ) Ownable(msg.sender) VRFConsumerBaseV2(vrfCoordinator) {
        s_minimumFee = minimumFee;
        s_maxPlayers = maxPlayers;
        s_maxTicketsPerAddress = maxPlayers / 20;  //5% cap
        s_deadline = block.timestamp + duration;
        s_lotteryState = LotteryState.OPEN;
        COORDINATOR = VRFCoordinatorV2Interface(vrfCoordinator);
        LINK_TOKEN = IERC20(linkToken);
        subscriptionId = _subscriptionId;
    }

    function enter(uint256 _noOfTickets) external payable {
        require(s_lotteryState == LotteryState.OPEN, "Lottery is not open" );
        require(_noOfTickets > 0 && _noOfTickets <= MAX_TICKETS_PER_TX,"Invalid ticket count" );
        require(msg.value == s_minimumFee * _noOfTickets, "Insufficient entry fee");
        require(block.timestamp < s_deadline, "Lottery expired");
        require(s_players.length + _noOfTickets <= s_maxPlayers,"Max tickets reached");
        require(s_ticketCount[msg.sender]+_noOfTickets <= s_maxTicketsPerAddress,"Exceeds per-address limit");

        s_ticketCount[msg.sender] += _noOfTickets;

        for (uint256 i=0; i< _noOfTickets; i++){
            s_players.push(msg.sender);
        }

        emit Entered(msg.sender, _noOfTickets,msg.value);

        if (s_players.length == s_maxPlayers){
            s_lotteryState = LotteryState.CLOSED;
        }

    } 

}
