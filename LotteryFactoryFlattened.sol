// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// lib/openzeppelin-contracts/contracts/utils/Context.sol

// OpenZeppelin Contracts (last updated v5.0.1) (utils/Context.sol)

/**
 * @dev Provides information about the current execution context, including the
 * sender of the transaction and its data. While these are generally available
 * via msg.sender and msg.data, they should not be accessed in such a direct
 * manner, since when dealing with meta-transactions the account sending and
 * paying for execution may not be the actual sender (as far as an application
 * is concerned).
 *
 * This contract is only required for intermediate, library-like contracts.
 */
abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }

    function _contextSuffixLength() internal view virtual returns (uint256) {
        return 0;
    }
}

// lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol

// OpenZeppelin Contracts (last updated v5.4.0) (token/ERC20/IERC20.sol)

/**
 * @dev Interface of the ERC-20 standard as defined in the ERC.
 */
interface IERC20 {
    /**
     * @dev Emitted when `value` tokens are moved from one account (`from`) to
     * another (`to`).
     *
     * Note that `value` may be zero.
     */
    event Transfer(address indexed from, address indexed to, uint256 value);

    /**
     * @dev Emitted when the allowance of a `spender` for an `owner` is set by
     * a call to {approve}. `value` is the new allowance.
     */
    event Approval(address indexed owner, address indexed spender, uint256 value);

    /**
     * @dev Returns the value of tokens in existence.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns the value of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @dev Moves a `value` amount of tokens from the caller's account to `to`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transfer(address to, uint256 value) external returns (bool);

    /**
     * @dev Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through {transferFrom}. This is
     * zero by default.
     *
     * This value changes when {approve} or {transferFrom} are called.
     */
    function allowance(address owner, address spender) external view returns (uint256);

    /**
     * @dev Sets a `value` amount of tokens as the allowance of `spender` over the
     * caller's tokens.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * IMPORTANT: Beware that changing an allowance with this method brings the risk
     * that someone may use both the old and the new allowance by unfortunate
     * transaction ordering. One possible solution to mitigate this race
     * condition is to first reduce the spender's allowance to 0 and set the
     * desired value afterwards:
     * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
     *
     * Emits an {Approval} event.
     */
    function approve(address spender, uint256 value) external returns (bool);

    /**
     * @dev Moves a `value` amount of tokens from `from` to `to` using the
     * allowance mechanism. `value` is then deducted from the caller's
     * allowance.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(address from, address to, uint256 value) external returns (bool);
}

// lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol

// OpenZeppelin Contracts (last updated v5.1.0) (utils/ReentrancyGuard.sol)

/**
 * @dev Contract module that helps prevent reentrant calls to a function.
 *
 * Inheriting from `ReentrancyGuard` will make the {nonReentrant} modifier
 * available, which can be applied to functions to make sure there are no nested
 * (reentrant) calls to them.
 *
 * Note that because there is a single `nonReentrant` guard, functions marked as
 * `nonReentrant` may not call one another. This can be worked around by making
 * those functions `private`, and then adding `external` `nonReentrant` entry
 * points to them.
 *
 * TIP: If EIP-1153 (transient storage) is available on the chain you're deploying at,
 * consider using {ReentrancyGuardTransient} instead.
 *
 * TIP: If you would like to learn more about reentrancy and alternative ways
 * to protect against it, check out our blog post
 * https://blog.openzeppelin.com/reentrancy-after-istanbul/[Reentrancy After Istanbul].
 */
abstract contract ReentrancyGuard {
    // Booleans are more expensive than uint256 or any type that takes up a full
    // word because each write operation emits an extra SLOAD to first read the
    // slot's contents, replace the bits taken up by the boolean, and then write
    // back. This is the compiler's defense against contract upgrades and
    // pointer aliasing, and it cannot be disabled.

    // The values being non-zero value makes deployment a bit more expensive,
    // but in exchange the refund on every call to nonReentrant will be lower in
    // amount. Since refunds are capped to a percentage of the total
    // transaction's gas, it is best to keep them low in cases like this one, to
    // increase the likelihood of the full refund coming into effect.
    uint256 private constant NOT_ENTERED = 1;
    uint256 private constant ENTERED = 2;

    uint256 private _status;

    /**
     * @dev Unauthorized reentrant call.
     */
    error ReentrancyGuardReentrantCall();

    constructor() {
        _status = NOT_ENTERED;
    }

    /**
     * @dev Prevents a contract from calling itself, directly or indirectly.
     * Calling a `nonReentrant` function from another `nonReentrant`
     * function is not supported. It is possible to prevent this from happening
     * by making the `nonReentrant` function external, and making it call a
     * `private` function that does the actual work.
     */
    modifier nonReentrant() {
        _nonReentrantBefore();
        _;
        _nonReentrantAfter();
    }

    function _nonReentrantBefore() private {
        // On the first call to nonReentrant, _status will be NOT_ENTERED
        if (_status == ENTERED) {
            revert ReentrancyGuardReentrantCall();
        }

        // Any calls to nonReentrant after this point will fail
        _status = ENTERED;
    }

    function _nonReentrantAfter() private {
        // By storing the original value once again, a refund is triggered (see
        // https://eips.ethereum.org/EIPS/eip-2200)
        _status = NOT_ENTERED;
    }

    /**
     * @dev Returns true if the reentrancy guard is currently set to "entered", which indicates there is a
     * `nonReentrant` function in the call stack.
     */
    function _reentrancyGuardEntered() internal view returns (bool) {
        return _status == ENTERED;
    }
}

// lib/chainlink-brownie-contracts/contracts/src/v0.8/vrf/VRFConsumerBaseV2.sol

/** ****************************************************************************
 * @notice Interface for contracts using VRF randomness
 * *****************************************************************************
 * @dev PURPOSE
 *
 * @dev Reggie the Random Oracle (not his real job) wants to provide randomness
 * @dev to Vera the verifier in such a way that Vera can be sure he's not
 * @dev making his output up to suit himself. Reggie provides Vera a public key
 * @dev to which he knows the secret key. Each time Vera provides a seed to
 * @dev Reggie, he gives back a value which is computed completely
 * @dev deterministically from the seed and the secret key.
 *
 * @dev Reggie provides a proof by which Vera can verify that the output was
 * @dev correctly computed once Reggie tells it to her, but without that proof,
 * @dev the output is indistinguishable to her from a uniform random sample
 * @dev from the output space.
 *
 * @dev The purpose of this contract is to make it easy for unrelated contracts
 * @dev to talk to Vera the verifier about the work Reggie is doing, to provide
 * @dev simple access to a verifiable source of randomness. It ensures 2 things:
 * @dev 1. The fulfillment came from the VRFCoordinator
 * @dev 2. The consumer contract implements fulfillRandomWords.
 * *****************************************************************************
 * @dev USAGE
 *
 * @dev Calling contracts must inherit from VRFConsumerBase, and can
 * @dev initialize VRFConsumerBase's attributes in their constructor as
 * @dev shown:
 *
 * @dev   contract VRFConsumer {
 * @dev     constructor(<other arguments>, address _vrfCoordinator, address _link)
 * @dev       VRFConsumerBase(_vrfCoordinator) public {
 * @dev         <initialization with other arguments goes here>
 * @dev       }
 * @dev   }
 *
 * @dev The oracle will have given you an ID for the VRF keypair they have
 * @dev committed to (let's call it keyHash). Create subscription, fund it
 * @dev and your consumer contract as a consumer of it (see VRFCoordinatorInterface
 * @dev subscription management functions).
 * @dev Call requestRandomWords(keyHash, subId, minimumRequestConfirmations,
 * @dev callbackGasLimit, numWords),
 * @dev see (VRFCoordinatorInterface for a description of the arguments).
 *
 * @dev Once the VRFCoordinator has received and validated the oracle's response
 * @dev to your request, it will call your contract's fulfillRandomWords method.
 *
 * @dev The randomness argument to fulfillRandomWords is a set of random words
 * @dev generated from your requestId and the blockHash of the request.
 *
 * @dev If your contract could have concurrent requests open, you can use the
 * @dev requestId returned from requestRandomWords to track which response is associated
 * @dev with which randomness request.
 * @dev See "SECURITY CONSIDERATIONS" for principles to keep in mind,
 * @dev if your contract could have multiple requests in flight simultaneously.
 *
 * @dev Colliding `requestId`s are cryptographically impossible as long as seeds
 * @dev differ.
 *
 * *****************************************************************************
 * @dev SECURITY CONSIDERATIONS
 *
 * @dev A method with the ability to call your fulfillRandomness method directly
 * @dev could spoof a VRF response with any random value, so it's critical that
 * @dev it cannot be directly called by anything other than this base contract
 * @dev (specifically, by the VRFConsumerBase.rawFulfillRandomness method).
 *
 * @dev For your users to trust that your contract's random behavior is free
 * @dev from malicious interference, it's best if you can write it so that all
 * @dev behaviors implied by a VRF response are executed *during* your
 * @dev fulfillRandomness method. If your contract must store the response (or
 * @dev anything derived from it) and use it later, you must ensure that any
 * @dev user-significant behavior which depends on that stored value cannot be
 * @dev manipulated by a subsequent VRF request.
 *
 * @dev Similarly, both miners and the VRF oracle itself have some influence
 * @dev over the order in which VRF responses appear on the blockchain, so if
 * @dev your contract could have multiple VRF requests in flight simultaneously,
 * @dev you must ensure that the order in which the VRF responses arrive cannot
 * @dev be used to manipulate your contract's user-significant behavior.
 *
 * @dev Since the block hash of the block which contains the requestRandomness
 * @dev call is mixed into the input to the VRF *last*, a sufficiently powerful
 * @dev miner could, in principle, fork the blockchain to evict the block
 * @dev containing the request, forcing the request to be included in a
 * @dev different block with a different hash, and therefore a different input
 * @dev to the VRF. However, such an attack would incur a substantial economic
 * @dev cost. This cost scales with the number of blocks the VRF oracle waits
 * @dev until it calls responds to a request. It is for this reason that
 * @dev that you can signal to an oracle you'd like them to wait longer before
 * @dev responding to the request (however this is not enforced in the contract
 * @dev and so remains effective only in the case of unmodified oracle software).
 */
abstract contract VRFConsumerBaseV2 {
  error OnlyCoordinatorCanFulfill(address have, address want);
  // solhint-disable-next-line chainlink-solidity/prefix-immutable-variables-with-i
  address private immutable vrfCoordinator;

  /**
   * @param _vrfCoordinator address of VRFCoordinator contract
   */
  constructor(address _vrfCoordinator) {
    vrfCoordinator = _vrfCoordinator;
  }

  /**
   * @notice fulfillRandomness handles the VRF response. Your contract must
   * @notice implement it. See "SECURITY CONSIDERATIONS" above for important
   * @notice principles to keep in mind when implementing your fulfillRandomness
   * @notice method.
   *
   * @dev VRFConsumerBaseV2 expects its subcontracts to have a method with this
   * @dev signature, and will call it once it has verified the proof
   * @dev associated with the randomness. (It is triggered via a call to
   * @dev rawFulfillRandomness, below.)
   *
   * @param requestId The Id initially returned by requestRandomness
   * @param randomWords the VRF output expanded to the requested number of words
   */
  // solhint-disable-next-line chainlink-solidity/prefix-internal-functions-with-underscore
  function fulfillRandomWords(uint256 requestId, uint256[] memory randomWords) internal virtual;

  // rawFulfillRandomness is called by VRFCoordinator when it receives a valid VRF
  // proof. rawFulfillRandomness then calls fulfillRandomness, after validating
  // the origin of the call
  function rawFulfillRandomWords(uint256 requestId, uint256[] memory randomWords) external {
    if (msg.sender != vrfCoordinator) {
      revert OnlyCoordinatorCanFulfill(msg.sender, vrfCoordinator);
    }
    fulfillRandomWords(requestId, randomWords);
  }
}

// lib/chainlink-brownie-contracts/contracts/src/v0.8/vrf/interfaces/VRFCoordinatorV2Interface.sol

// solhint-disable-next-line interface-starts-with-i
interface VRFCoordinatorV2Interface {
  /**
   * @notice Get configuration relevant for making requests
   * @return minimumRequestConfirmations global min for request confirmations
   * @return maxGasLimit global max for request gas limit
   * @return s_provingKeyHashes list of registered key hashes
   */
  function getRequestConfig() external view returns (uint16, uint32, bytes32[] memory);

  /**
   * @notice Request a set of random words.
   * @param keyHash - Corresponds to a particular oracle job which uses
   * that key for generating the VRF proof. Different keyHash's have different gas price
   * ceilings, so you can select a specific one to bound your maximum per request cost.
   * @param subId  - The ID of the VRF subscription. Must be funded
   * with the minimum subscription balance required for the selected keyHash.
   * @param minimumRequestConfirmations - How many blocks you'd like the
   * oracle to wait before responding to the request. See SECURITY CONSIDERATIONS
   * for why you may want to request more. The acceptable range is
   * [minimumRequestBlockConfirmations, 200].
   * @param callbackGasLimit - How much gas you'd like to receive in your
   * fulfillRandomWords callback. Note that gasleft() inside fulfillRandomWords
   * may be slightly less than this amount because of gas used calling the function
   * (argument decoding etc.), so you may need to request slightly more than you expect
   * to have inside fulfillRandomWords. The acceptable range is
   * [0, maxGasLimit]
   * @param numWords - The number of uint256 random values you'd like to receive
   * in your fulfillRandomWords callback. Note these numbers are expanded in a
   * secure way by the VRFCoordinator from a single random value supplied by the oracle.
   * @return requestId - A unique identifier of the request. Can be used to match
   * a request to a response in fulfillRandomWords.
   */
  function requestRandomWords(
    bytes32 keyHash,
    uint64 subId,
    uint16 minimumRequestConfirmations,
    uint32 callbackGasLimit,
    uint32 numWords
  ) external returns (uint256 requestId);

  /**
   * @notice Create a VRF subscription.
   * @return subId - A unique subscription id.
   * @dev You can manage the consumer set dynamically with addConsumer/removeConsumer.
   * @dev Note to fund the subscription, use transferAndCall. For example
   * @dev  LINKTOKEN.transferAndCall(
   * @dev    address(COORDINATOR),
   * @dev    amount,
   * @dev    abi.encode(subId));
   */
  function createSubscription() external returns (uint64 subId);

  /**
   * @notice Get a VRF subscription.
   * @param subId - ID of the subscription
   * @return balance - LINK balance of the subscription in juels.
   * @return reqCount - number of requests for this subscription, determines fee tier.
   * @return owner - owner of the subscription.
   * @return consumers - list of consumer address which are able to use this subscription.
   */
  function getSubscription(
    uint64 subId
  ) external view returns (uint96 balance, uint64 reqCount, address owner, address[] memory consumers);

  /**
   * @notice Request subscription owner transfer.
   * @param subId - ID of the subscription
   * @param newOwner - proposed new owner of the subscription
   */
  function requestSubscriptionOwnerTransfer(uint64 subId, address newOwner) external;

  /**
   * @notice Request subscription owner transfer.
   * @param subId - ID of the subscription
   * @dev will revert if original owner of subId has
   * not requested that msg.sender become the new owner.
   */
  function acceptSubscriptionOwnerTransfer(uint64 subId) external;

  /**
   * @notice Add a consumer to a VRF subscription.
   * @param subId - ID of the subscription
   * @param consumer - New consumer which can use the subscription
   */
  function addConsumer(uint64 subId, address consumer) external;

  /**
   * @notice Remove a consumer from a VRF subscription.
   * @param subId - ID of the subscription
   * @param consumer - Consumer to remove from the subscription
   */
  function removeConsumer(uint64 subId, address consumer) external;

  /**
   * @notice Cancel a subscription
   * @param subId - ID of the subscription
   * @param to - Where to send the remaining LINK to
   */
  function cancelSubscription(uint64 subId, address to) external;

  /*
   * @notice Check to see if there exists a request commitment consumers
   * for all consumers and keyhashes for a given sub.
   * @param subId - ID of the subscription
   * @return true if there exists at least one unfulfilled request for the subscription, false
   * otherwise.
   */
  function pendingRequestExists(uint64 subId) external view returns (bool);
}

// lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol

// OpenZeppelin Contracts (last updated v5.4.0) (interfaces/IERC20.sol)

// lib/openzeppelin-contracts/contracts/access/Ownable.sol

// OpenZeppelin Contracts (last updated v5.0.0) (access/Ownable.sol)

/**
 * @dev Contract module which provides a basic access control mechanism, where
 * there is an account (an owner) that can be granted exclusive access to
 * specific functions.
 *
 * The initial owner is set to the address provided by the deployer. This can
 * later be changed with {transferOwnership}.
 *
 * This module is used through inheritance. It will make available the modifier
 * `onlyOwner`, which can be applied to your functions to restrict their use to
 * the owner.
 */
abstract contract Ownable is Context {
    address private _owner;

    /**
     * @dev The caller account is not authorized to perform an operation.
     */
    error OwnableUnauthorizedAccount(address account);

    /**
     * @dev The owner is not a valid owner account. (eg. `address(0)`)
     */
    error OwnableInvalidOwner(address owner);

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Initializes the contract setting the address provided by the deployer as the initial owner.
     */
    constructor(address initialOwner) {
        if (initialOwner == address(0)) {
            revert OwnableInvalidOwner(address(0));
        }
        _transferOwnership(initialOwner);
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        _checkOwner();
        _;
    }

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view virtual returns (address) {
        return _owner;
    }

    /**
     * @dev Throws if the sender is not the owner.
     */
    function _checkOwner() internal view virtual {
        if (owner() != _msgSender()) {
            revert OwnableUnauthorizedAccount(_msgSender());
        }
    }

    /**
     * @dev Leaves the contract without owner. It will not be possible to call
     * `onlyOwner` functions. Can only be called by the current owner.
     *
     * NOTE: Renouncing ownership will leave the contract without an owner,
     * thereby disabling any functionality that is only available to the owner.
     */
    function renounceOwnership() public virtual onlyOwner {
        _transferOwnership(address(0));
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public virtual onlyOwner {
        if (newOwner == address(0)) {
            revert OwnableInvalidOwner(address(0));
        }
        _transferOwnership(newOwner);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Internal function without access restriction.
     */
    function _transferOwnership(address newOwner) internal virtual {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}

// src/Lotto.sol

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
    uint256 public immutable _TIMEOUT;
    uint256 public constant MAX_TICKETS_PER_TX = 100;

    // Outcome
    address public winner;
    uint256 public requestId;
    bool public prizeClaimed;

    // Chainlink VRF config
    VRFCoordinatorV2Interface public immutable _COORDINATOR;
    uint64 private immutable _SUBSCRIPTION_ID;
    address private immutable _LINKTOKENADDRESS; // Sepolia LINK
    bytes32 private immutable _KEYHASH;

    uint32 public immutable _CALLBACKGASLIMIT;
    uint16 public immutable _REQUESTCONFIRMATIONS;
    uint32 public immutable _NUMWORDS;

    uint256 public constant ESTIMATED_LINK_COST = 2 * 10 ** 18; // 2 LINK

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

        _COORDINATOR = VRFCoordinatorV2Interface(_vrfCoordinator);
        _SUBSCRIPTION_ID = _subscriptionId;
        _LINKTOKENADDRESS = _linkTokenAddress;
        _KEYHASH = _keyHash;

        _CALLBACKGASLIMIT = _callbackGasLimit;
        _REQUESTCONFIRMATIONS = _requestConfirmations;
        _NUMWORDS = _numWords;
        _TIMEOUT = _timeout;
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
        require(lotteryState == LotteryState.OPEN || lotteryState == LotteryState.CLOSED, "INVALID_STATE");

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

        requestId = _COORDINATOR.requestRandomWords(
            _KEYHASH, _SUBSCRIPTION_ID, _REQUESTCONFIRMATIONS, _CALLBACKGASLIMIT, _NUMWORDS
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
        require(block.timestamp >= vrfRequestTimestamp + _TIMEOUT, "NOT_TIMED_OUT");

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
        (bool success,) = msg.sender.call{value: prize}("");
        require(success, "Transfer failed");

        emit PrizeClaimed(msg.sender, prize);
    }

    function claimRefund() external nonReentrant {
        require(lotteryState == LotteryState.CANCELLED, "Lottery not cancelled");
        uint256 ticketsBought = ticketCount[msg.sender];
        require(ticketsBought > 0, "No refund available");

        ticketCount[msg.sender] = 0;
        uint256 refundAmount = ticketsBought * factoryMinFee;

        (bool success,) = msg.sender.call{value: refundAmount}("");
        require(success, "Refund failed");

        emit RefundClaimed(msg.sender, refundAmount);
    }

    function _hasEnoughLink() internal view returns (bool) {
        (uint96 balance,,,) = _COORDINATOR.getSubscription(_SUBSCRIPTION_ID);
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

// src/LotteryFactory.sol

contract LotteryFactory {
    address[] public allLotteries;
    uint64 public subscriptionId; // Chainlink VRF subscription ID (shared across all lotteries)
    address public owner;
    address private linkToken;
    bytes32 private keyHash;
    VRFCoordinatorV2Interface public vrfCoordinator;

    event LotteryCreated(address indexed lotteryAddress, address indexed creator, uint256 minFee);

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    constructor(uint64 _subscriptionId, address _vrfCoordinator, address _linkToken, bytes32 _keyHash) {
        subscriptionId = _subscriptionId;
        vrfCoordinator = VRFCoordinatorV2Interface(_vrfCoordinator);
        linkToken = _linkToken;
        keyHash = _keyHash;
        owner = msg.sender;
    }

    function createLottery(
        uint256 _minFee,
        uint256 maxPlayers,
        uint256 duration,
        uint32 _callbackGasLimit,
        uint16 _requestConfirmations,
        uint32 _numWords,
        uint256 _timeout
    ) external onlyOwner {
        Lottery newLottery = new Lottery(
            address(vrfCoordinator),
            _minFee,
            maxPlayers,
            duration,
            subscriptionId,
            _callbackGasLimit,
            _requestConfirmations,
            _numWords,
            _timeout,
            linkToken,
            keyHash
        );

        allLotteries.push(address(newLottery));
        emit LotteryCreated(address(newLottery), msg.sender, _minFee);
    }

    function getAllLotteries() external view returns (address[] memory) {
        return allLotteries;
    }

    function getLinkBalance(address account) external view returns (uint256) {
        return IERC20(linkToken).balanceOf(account);
    }

    function getSubscriptionBalance(uint64 subId) external view returns (uint96 balance) {
        (balance,,,) = vrfCoordinator.getSubscription(subId);
    }
}

