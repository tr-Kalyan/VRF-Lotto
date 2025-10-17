// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Lottery} from "./Lotto.sol";
import {IERC20} from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {IVRFCoordinatorV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/interfaces/IVRFCoordinatorV2Plus.sol";
import {IVRFSubscriptionV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/interfaces/IVRFCoordinatorV2Plus.sol";



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

    /** 
     * @notice Deploys and configures the Lottery Factory with Chainlink VRF details.
     * @param _subscriptionId The VRF Subscription ID, funded with LINK.
     * @param _vrfCoordinator The address of the IVRFCoordinatorV2Plus contract.
     * @param _linkToken The address of the LINK ERC-20 token contract.
     * @param _keyHash The key hash used for requesting randomness.
    */
    constructor(uint256 _subscriptionId, address _vrfCoordinator, address _linkToken, bytes32 _keyHash) {
        vrfSubscriptionId = _subscriptionId;
        vrfCoordinator = IVRFCoordinatorV2Plus(_vrfCoordinator);
        linkToken = _linkToken;
        vrfKeyHash = _keyHash;
        owner = msg.sender;
    }

    /**
     * @notice Creates a new Lottery contract, tracks it, and authorizes it as a VRF consumer.
     * @dev Only callable by the owner. Deploys and authorizes atomically.
     */
    function createLottery(
        uint256 _ticketPrice,
        uint256 maxPlayers,
        uint256 lotteryDurationSeconds,
        uint32 _callbackGasLimit,
        uint16 _requestConfirmations,
        uint32 _numWords,
        uint256 _vrfRequestTimeoutSeconds
    ) external onlyOwner {

        // Deply new Lottery contract
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

        // Add the lottery to the Factory's tracking array
        allLotteries.push(address(newLottery));

        // Add newly deployed lottery address as consumer in chainlink
        vrfCoordinator.addConsumer(vrfSubscriptionId, address(newLottery));

        emit LotteryCreated(address(newLottery), msg.sender, _ticketPrice);
    }

    function getAllLotteries() external view returns (address[] memory) {
        return allLotteries;
    }

    /**
     * @notice Returns the standard ERC-20 LINK balance of any address provided.
     * @dev This checks the balance of a normal account (wallet, contract, etc.) for the LINK token specified in the constructor.
    */
    function getLinkBalanceOfVRF(address account) external view returns (uint256) {
        return IERC20(linkToken).balanceOf(account);
    }

    
    // Checks the balance held by the Chainlink VRF Coordinator specifically for this subscription ID.
    function getLinkBalanceOfSubscription() external view returns (uint96 balance) {    
        (balance,,,,) = vrfCoordinator.getSubscription(vrfSubscriptionId);
    }
}
