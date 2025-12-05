// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {Lottery} from "../src/Lotto.sol";
import {LotteryFactory} from "../src/LotteryFactory.sol";
import {VRFCoordinatorV2_5Mock} from "@chainlink/vrf/mocks/VRFCoordinatorV2_5Mock.sol";
import {MockLinkToken} from "@chainlink/mocks/MockLinkToken.sol";
import {MockUSDC} from "./mock/MockUSDC.sol"; 
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract LotteryTest is Test {
    LotteryFactory public factory;
    Lottery public lottery;
    VRFCoordinatorV2_5Mock public vrfMock;
    LinkToken public linkToken;
    MockUSDC public usdc;

    address public owner = makeAddr("owner");
    address public player1 = makeAddr("player1");
    address public player2 = makeAddr("player2");
    address public player3 = makeAddr("player3");
    address public automation = makeAddr("automation"); 

    uint256 public constant TICKET_PRICE = 1e6; // 1 USDC (6 decimals)
    uint256 public constant DURATION = 1 hours;
    uint256 public constant MAX_TICKETS = 1000;

    // FIX: VRF 2.5 uses uint256 for Subscription ID
    uint256 public subId;

    function setUp() public {
        // 1. Deploy LINK token
        linkToken = new LinkToken();

        // 2. Deploy VRF Mock
        vrfMock = new VRFCoordinatorV2_5Mock(
            0.1 ether, // Base Fee
            1e9,       // Gas Price
            5e17       // Wei per Unit Link
        );

        // 3. Create + fund subscription
        subId = vrfMock.createSubscription();
        linkToken.transferAndCall(address(vrfMock), 100 ether, abi.encode(subId));

        // 4. Deploy Factory
        vm.startPrank(owner);
        factory = new LotteryFactory(
            subId,
            address(vrfMock),
            address(linkToken),
            0x787d74caea10b2b357790d5b5247c2f63d1d91572a9846f780606e4d953677ae
        );
        vm.stopPrank();

        // 5. CRITICAL: Transfer Subscription Ownership to Factory
        // The Test contract owns the sub currently. The Factory needs it to add consumers.
        vrfMock.requestSubscriptionOwnerTransfer(subId, address(factory));
        
        vm.prank(address(factory));
        vrfMock.acceptSubscriptionOwnerTransfer(subId);

        // 6. DEPLOY MOCK USDC
        usdc = new MockUSDC();

        // 7. Mint USDC to players
        usdc.mint(player1, 1000e6);
        usdc.mint(player2, 1000e6);
        usdc.mint(player3, 1000e6);

        // 8. Create lottery
        vm.prank(owner);
        address lotteryAddr = factory.createLottery(
            TICKET_PRICE,
            address(usdc),
            MAX_TICKETS,
            DURATION,
            500_000,
            1 hours
        );
        lottery = Lottery(lotteryAddr);

        // NOTE: We do NOT need vrfMock.addConsumer() here. 
        // The Factory already did it in step 8!

        // 9. Approve lottery to spend USDC
        vm.prank(player1);
        usdc.approve(address(lottery), type(uint256).max);
        vm.prank(player2);
        usdc.approve(address(lottery), type(uint256).max);
        vm.prank(player3);
        usdc.approve(address(lottery), type(uint256).max);
    }

    // TESTS START HERE
    function test_01_DeploymentAndConfig() public {
        assertEq(address(lottery.paymentToken()), address(usdc));
        assertEq(lottery.ticketPrice(), TICKET_PRICE);
        // Verify Factory passed ownership correctly to the Admin (owner)
        assertEq(lottery.owner(), owner); 
    }

    function test_02_PlayerCanEnterSingleTicket() public {
        vm.prank(player1);
        lottery.enter(1);
        // Ranges: Index 0 => (player1, 1)
        (address p, uint256 total) = lottery.playersRanges(0);
        assertEq(p, player1);
        assertEq(total, 1);
    }

    function test_03_PlayerCanEnterMultipleTickets() public {}
    function test_04_CumulativeSumPatternWorks() public {}
    function test_05_SinglePlayerAutoWin() public {}
    function test_06_MultiplePlayersEnter() public {}
    function test_07_AutomationTriggersCloseWhenDeadlineReached() public {}
    function test_08_VRFRollsAndPicksCorrectWinner() public {}
    function test_09_WinnerCanClaimPrize() public {}
    function test_10_FeesAreSentToOwnerInPerformUpkeep() public {}
    function test_11_CannotEnterAfterDeadline() public {}
    function test_12_FullFlowEndToEnd() public {}
}