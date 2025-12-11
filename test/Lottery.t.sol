// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {Lottery} from "../src/Lotto.sol";
import {LotteryFactory} from "../src/LotteryFactory.sol";
import {VRFCoordinatorV2_5Mock} from "@chainlink/vrf/mocks/VRFCoordinatorV2_5Mock.sol";
import {MockLinkToken} from "@chainlink/mocks/MockLinkToken.sol";
import {MockUSDC} from "./mock/MockUSDC.sol"; 
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ILotteryEvents} from "../src/interfaces/ILotteryEvents.sol";
contract LotteryTest is Test, ILotteryEvents {
    LotteryFactory public factory;
    Lottery public lottery;
    VRFCoordinatorV2_5Mock public vrfMock;
    MockLinkToken public linkToken;
    MockUSDC public usdc;

    address public owner = makeAddr("owner");
    address public player1 = makeAddr("player1");
    address public player2 = makeAddr("player2");
    address public player3 = makeAddr("player3");
    address public automation = makeAddr("automation"); 

    uint256 public constant TICKET_PRICE = 1e6; // 1 USDC (6 decimals)
    uint256 public constant DURATION = 1 hours;
    uint256 public constant MAX_TICKETS = 1000;
    uint256 public constant VRF_TIMEOUT_SECONDS = 3600;

    
    uint256 public subId;

    function setUp() public {
        // 1. Deploy Infrastructure
        linkToken = new MockLinkToken();
        vrfMock = new VRFCoordinatorV2_5Mock(0.1 ether, 1e9, 5e17);

        // 2. Deploy Factory (AS OWNER)
        // Factory automatically creates Sub #1 in its constructor
        vm.startPrank(owner);
        factory = new LotteryFactory(
            address(vrfMock),
            address(linkToken),
            0x787d74caea10b2b357790d5b5247c2f63d1d91572a9846f780606e4d953677ae
        );
        vm.stopPrank();

        // 3. Get the Factory's Sub ID
        subId = factory.vrfSubscriptionId();

        // 4. Fund the Factory's Subscription
        // We use the Mock helper to magically add LINK to the sub
        vrfMock.fundSubscription(subId, 100 ether);

        // 5. Setup USDC
        usdc = new MockUSDC();
        usdc.mint(player1, 1000e6);
        usdc.mint(player2, 1000e6);
        usdc.mint(player3, 1000e6);

        // 6. Create Lottery (AS OWNER)
        // Factory will automatically add this lottery to the subscription
        vm.startPrank(owner);
        address lotteryAddr = factory.createLottery(
            TICKET_PRICE,
            address(usdc),
            MAX_TICKETS,
            DURATION,
            500_000,
            1 hours
        );
        lottery = Lottery(lotteryAddr);
        vm.stopPrank();

        // 7. Approve USDC
        vm.prank(player1);
        usdc.approve(address(lottery), type(uint256).max);
        vm.prank(player2);
        usdc.approve(address(lottery), type(uint256).max);
        vm.prank(player3);
        usdc.approve(address(lottery), type(uint256).max);
    }
    // TESTS START HERE
    function test_01_DeploymentAndConfig() public view {
        assertEq(address(lottery.paymentToken()), address(usdc));
        assertEq(lottery.ticketPrice(), TICKET_PRICE);
        // Verify Factory passed ownership correctly to the Admin (owner)
        assertEq(lottery.owner(), address(factory)); 
        assertEq(lottery.maxTickets(), MAX_TICKETS);
        assertEq(uint256(lottery.lotteryState()), 0); // OPEN
    }

    function test_02_PlayerCanEnterSingleTicket() public {
        uint256 balanceBefore = usdc.balanceOf(player1);
        
        vm.prank(player1);
        lottery.enter(1);
        
        // Check ticket range
        (address p, uint256 total) = lottery.playersRanges(0);
        assertEq(p, player1);
        assertEq(total, 1);
        
        // Check payment (1 USDC + 1% fee = 1.01 USDC)
        assertEq(usdc.balanceOf(player1), balanceBefore - 1.01e6);
        
        // Check prize pool and fees
        assertEq(lottery.prizePool(), TICKET_PRICE);
        assertEq(lottery.platformFees(), TICKET_PRICE / 100);
    }

    function test_03_PlayerCanEnterMultipleTickets() public {
        uint256 tickets = 10;
        uint256 cost = tickets * TICKET_PRICE;
        uint256 fee = cost / 100;
        uint256 totalTransfer = cost + fee;

        uint256 balanceBefore = usdc.balanceOf(player1);

        vm.expectEmit(true, true, false, true);
        // emit Lottery.Entered(
        //     player1,
        //     tickets,
        //     0,      // rangeStart (first entry = 0)
        //     9      // rangeEnd (0 + 10)
        // );

        emit Entered(player1,tickets,0,9);

        vm.prank(player1);
        lottery.enter(tickets);
        
        // CHECK STATE
        (address p, uint256 total) = lottery.playersRanges(0);
        assertEq(p, player1);
        assertEq(total, 10);

        // CHECK BALANCE
        assertEq(usdc.balanceOf(player1), balanceBefore - totalTransfer);

        // CHECK POOL & FEES
        assertEq(lottery.prizePool(), cost);
        assertEq(lottery.platformFees(), fee);
    }
    function test_04_CumulativeSumPatternWorks() public {
        // Player 1 buys 5 tickets (range: 0-4)
        vm.prank(player1);
        lottery.enter(5);
        
        // Player 2 buys 3 tickets (range: 5-7)
        vm.prank(player2);
        lottery.enter(3);
        
        // Player 3 buys 2 tickets (range: 8-9)
        vm.prank(player3);
        lottery.enter(2);
        
        // Verify cumulative totals
        (, uint256 total1) = lottery.playersRanges(0);
        (, uint256 total2) = lottery.playersRanges(1);
        (, uint256 total3) = lottery.playersRanges(2);
        
        assertEq(total1, 5);  // Player 1: tickets 0-4
        assertEq(total2, 8);  // Player 2: tickets 5-7 (cumulative: 8)
        assertEq(total3, 10); // Player 3: tickets 8-9 (cumulative: 10)
        
        assertEq(lottery.getTotalTicketsSold(), 10);
        assertEq(lottery.getPlayerCount(), 3);
    }
    function test_05_SinglePlayerAutoWin() public {
        // Only one player enters
        vm.prank(player1);
        lottery.enter(5);
        
        // Fast forward past deadline
        vm.warp(block.timestamp + DURATION + 1);
        
        // Trigger upkeep (automation calls this)
        lottery.performUpkeep("");
        
        // Should be auto-win (no VRF needed)
        assertEq(lottery.winner(), player1);
        assertEq(uint256(lottery.lotteryState()), 2); // FINISHED
        
        // Winner can claim
        uint256 prize = lottery.prizePool();
        vm.prank(player1);
        lottery.claimPrize();
        
        assertEq(usdc.balanceOf(player1), 1000e6 - 5.05e6 + prize);
        assertTrue(lottery.prizeClaimed());
    }
    function test_06_MultiplePlayersEnter() public {
        vm.prank(player1);
        lottery.enter(10);
        
        vm.prank(player2);
        lottery.enter(5);
        
        vm.prank(player3);
        lottery.enter(15);
        
        assertEq(lottery.getTotalTicketsSold(), 30);
        assertEq(lottery.getPlayerCount(), 3);
        assertEq(lottery.prizePool(), 30 * TICKET_PRICE);
    }
    function test_07_AutomationTriggersCloseWhenDeadlineReached() public {
        // 1. No players → no upkeep
        (bool upkeepNeeded, ) = lottery.checkUpkeep("");
        assertFalse(upkeepNeeded, "No players -> no upkeep");

        // 2. Multiple players enter
        vm.prank(player1);
        lottery.enter(10); // range 0-9

        vm.prank(player2);
        lottery.enter(5);  // range 10-14

        vm.prank(player3);
        lottery.enter(3);  // range 15-17

        // 3. Before deadline → no upkeep
        (upkeepNeeded, ) = lottery.checkUpkeep("");
        assertFalse(upkeepNeeded, "Before deadline -> no upkeep");

        // 4. Exactly at deadline → no upkeep (strict >)
        vm.warp(block.timestamp + DURATION);
        (upkeepNeeded, ) = lottery.checkUpkeep("");
        assertFalse(upkeepNeeded, "Exactly at deadline -> no upkeep");

        // 5. One second after → YES upkeep
        vm.warp(block.timestamp + 1);
        (upkeepNeeded, ) = lottery.checkUpkeep("");
        assertTrue(upkeepNeeded, "After deadline with players -> upkeep");

        // 6. Bonus: State check
        assertEq(uint256(lottery.lotteryState()), 0); // Still OPEN
    }

    function test_08_VRFRollsAndPicksCorrectWinner() public {
        // === Players enter with different ticket amounts ===
        vm.prank(player1);
        lottery.enter(5); // tickets 0–4

        vm.prank(player2);
        lottery.enter(3); // tickets 5–7 → should win if random = 6

        vm.prank(player3);
        lottery.enter(2); // tickets 8–9

        // === Fast forward past deadline ===
        vm.warp(block.timestamp + DURATION + 1);

        // === RECORD ALL EVENTS during performUpkeep() ===
        vm.recordLogs();
        lottery.performUpkeep("");
        

        // === Extract the requestId from LotteryClosed event ===
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 requestId;

        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("LotteryClosed(uint256)")) {
                requestId = uint256(logs[i].topics[1]);
                break;
            }
        }

        assertGt(requestId, 0, "requestId should be emitted");
        
        // === Set up mock randomness: 6 → falls in player2 range (5–7) ===
        uint256[] memory randomWords = new uint256[](1);
        randomWords[0] = 6;

        // === Fulfill VRF request ===
        vrfMock.fulfillRandomWordsWithOverride(requestId, address(lottery), randomWords);

        // === Final checks ===
        assertEq(uint256(lottery.lotteryState()), 2, "Should be FINISHED");
        assertEq(lottery.winner(), player2, "player2 should win with random number 6");
        assertFalse(lottery.prizeClaimed(), "Prize not claimed yet");
    }

    function test_09_WinnerCanClaimPrize() public {
        // Player enters and wins (single player auto-win)
        vm.prank(player1);
        lottery.enter(10);
        
        vm.warp(block.timestamp + DURATION + 1);
        lottery.performUpkeep("");
        
        // Winner claims
        uint256 prize = lottery.prizePool();
        uint256 balanceBefore = usdc.balanceOf(player1);
        
        vm.prank(player1);
        lottery.claimPrize();
        
        assertEq(usdc.balanceOf(player1), balanceBefore + prize);
        assertTrue(lottery.prizeClaimed());
        assertEq(lottery.prizePool(), 0);
    }
    function test_10_FeesAreSentToOwnerInPerformUpkeep() public {
        vm.prank(player1);
        lottery.enter(10);
        
        vm.prank(player2);
        lottery.enter(10);
        
        uint256 expectedFees = (20 * TICKET_PRICE) / 100;
        assertEq(lottery.platformFees(), expectedFees);
        
        uint256 ownerBalanceBefore = usdc.balanceOf(owner);
        
        // Trigger upkeep
        vm.warp(block.timestamp + DURATION + 1);
        lottery.performUpkeep("");
        
        // Owner should receive fees
        assertEq(usdc.balanceOf(owner), ownerBalanceBefore + expectedFees);
        assertEq(lottery.platformFees(), 0);
    }
    function test_11_CannotEnterAfterDeadline() public {
        vm.warp(block.timestamp + DURATION + 1);
        
        vm.expectRevert("Lottery ended");
        vm.prank(player1);
        lottery.enter(1);
    }

    function test_12_CannotEnterWhenCalculating() public {
        vm.prank(player1);
        lottery.enter(1);
        
        vm.warp(block.timestamp + DURATION + 1);
        lottery.performUpkeep("");
        
        // State is now CALCULATING (or FINISHED if single player)
        vm.expectRevert();
        vm.prank(player2);
        lottery.enter(1);
    }

    function test_13_CannotExceedMaxTickets() public {
        usdc.mint(player1, 2000e6);
        vm.prank(player1);
        lottery.enter(MAX_TICKETS);
        
        vm.expectRevert("Max tickets exceeded");
        vm.prank(player2);
        lottery.enter(1);
    }

    function test_14_CannotEnterZeroTickets() public {
        vm.expectRevert("Zero tickets");
        vm.prank(player1);
        lottery.enter(0);
    }

    function test_15_OnlyWinnerCanClaim() public {
        vm.prank(player1);
        lottery.enter(1);
        
        vm.warp(block.timestamp + DURATION + 1);
        lottery.performUpkeep("");
        
        // Player2 tries to claim but isn't winner
        vm.expectRevert("Not winner");
        vm.prank(player2);
        lottery.claimPrize();
    }

    function test_16_CannotClaimTwice() public {
        vm.prank(player1);
        lottery.enter(1);
        
        vm.warp(block.timestamp + DURATION + 1);
        lottery.performUpkeep("");
        
        vm.prank(player1);
        lottery.claimPrize();
        
        vm.expectRevert("Already claimed");
        vm.prank(player1);
        lottery.claimPrize();
    }

    function test_17_RecoverStuckLottery() public {
        vm.prank(player1);
        lottery.enter(5);
        
        vm.prank(player2);
        lottery.enter(5);
        
        // Trigger lottery close
        vm.warp(block.timestamp + DURATION + 1);
        lottery.performUpkeep("");
        
        assertEq(uint256(lottery.lotteryState()), 1); // CALCULATING
        
        // Fast forward past VRF timeout
        vm.warp(block.timestamp + VRF_TIMEOUT_SECONDS + 1);
        
        // Owner can recover
        vm.prank(address(factory));
        lottery.recoverStuckLottery();
        
        assertEq(uint256(lottery.lotteryState()), 0); // OPEN
    }

    /*//////////////////////////////////////////////////////////////
                        FULL END-TO-END TEST
    //////////////////////////////////////////////////////////////*/

    function test_18_FullFlowEndToEnd() public {
        console.log("Starting Full Lottery Flow...");
        
        vm.prank(player1); lottery.enter(10);
        vm.prank(player2); lottery.enter(5);
        vm.prank(player3); lottery.enter(15);

        assertEq(lottery.getTotalTicketsSold(), 30);
        assertEq(lottery.prizePool(), 30 * TICKET_PRICE);

        vm.warp(block.timestamp + DURATION + 1);

        vm.recordLogs();
        lottery.performUpkeep("");

        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 requestId;

        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("LotteryClosed(uint256)")) {
                requestId = uint256(logs[i].topics[1]);
                break;
            }
        }

        assertGt(requestId, 0);

        // FUND MOCK
        vrfMock.fundSubscription(subId, 100 ether);

        // FULFILL VRF
        uint256[] memory words = new uint256[](1);
        words[0] = 20; // player3 wins

        vrfMock.fulfillRandomWords(requestId, address(lottery));

        address winner = lottery.winner();
        console.log("Winner:", winner);

        uint256 prize = lottery.prizePool();
        uint256 balanceBefore = usdc.balanceOf(winner);

        vm.prank(winner);
        lottery.claimPrize();

        assertEq(usdc.balanceOf(winner), balanceBefore + prize);
        assertTrue(lottery.prizeClaimed());

        console.log("Full Flow Complete - Winner Claimed Prize");
    }

    /*//////////////////////////////////////////////////////////////
                        FACTORY TESTS
    //////////////////////////////////////////////////////////////*/

    function test_19_FactoryCanCreateMultipleLotteries() public {
        uint256 initialCount = factory.getAllLotteries().length;

        vm.startPrank(owner);

        address lottery1 = factory.createLottery(
            1e6, address(usdc), 100, 1 hours, 500_000, 1 hours
        );
        address lottery2 = factory.createLottery(
            2e6, address(usdc), 200, 2 hours, 500_000, 1 hours
        );
        address lottery3 = factory.createLottery(
            3e6, address(usdc), 300, 3 hours, 500_000, 1 hours
        );

        vm.stopPrank();

        address[] memory lotteries = factory.getAllLotteries();

        assertEq(lotteries.length, initialCount + 3);
        assertTrue(lottery1 != lottery2 && lottery2 != lottery3 && lottery1 != lottery3);

        console.log("Factory created 3 new lotteries");
        console.log("Lottery 1:", lottery1);
        console.log("Lottery 2:", lottery2);
        console.log("Lottery 3:", lottery3);
    }

    function test_20_OnlyOwnerCanCreateLottery() public {
        vm.expectRevert();
        vm.prank(player1);
        factory.createLottery(1e6, address(usdc), 100, 1 hours, 500_000, 1 hours);
    }

    function test_21_RemoveConsumerFreesSlotAndAllowsNewLottery() public {
        // === Fill up to 99 lotteries (max consumers) ===
        // === Mock counts owner(factory) as consumer ===
        for (uint i = 0; i < 99; i++) {
            vm.prank(owner);
            factory.createLottery(
                TICKET_PRICE,
                address(usdc),
                MAX_TICKETS,
                DURATION,
                500_000,
                1 hours
            );
        }

        // === Try to create 100th lottery → should REVERT (no consumer slot) ===
        vm.expectRevert(); // Chainlink: "Too many consumers"
        vm.prank(owner);
        factory.createLottery(
            TICKET_PRICE,
            address(usdc),
            MAX_TICKETS,
            DURATION,
            500_000,
            1 hours
        );

        // === Get the first lottery address ===
        address[] memory Lotteries = factory.getAllLotteries();
        address firstLottery = Lotteries[0];

        // === Remove it as consumer ===
        vm.prank(owner);
        factory.removeConsumer(firstLottery);

        // === Now create 101th lottery → should PASS ===
        vm.prank(owner);
        address newLottery = factory.createLottery(
            TICKET_PRICE,
            address(usdc),
            MAX_TICKETS,
            DURATION,
            500_000,
            1 hours
        );

        assertTrue(newLottery != address(0), "100th lottery created after removal");
    }
}