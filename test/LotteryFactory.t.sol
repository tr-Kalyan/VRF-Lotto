// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {Lottery} from "../src/Lotto.sol";
import {LotteryFactory} from "../src/LotteryFactory.sol";
import {VRFCoordinatorV2_5Mock} from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";

contract LotteryFactoryTest is Test {
    // Actors
    address internal constant USER = address(0x1);
    address internal constant USER2 = address(0x2);

    // System under test
    LotteryFactory internal factory;
    Lottery internal lottery;
    VRFCoordinatorV2_5Mock internal coord;

    // VRF mock config
    uint256 internal subId;
    uint96 constant BASE_FEE = uint96(0.25 ether);
    uint96 constant GAS_PRICE_LINK = uint96(1e9);
    uint96 constant FUNDING_AMOUNT = uint96(10000 ether);
    bytes32 constant KEYHASH = 0x787d74caea10b2b357790d5b5247c2f63d1d91572a9846f780606e4d953677ae;

    function setUp() public {
        // 1) Deploy VRF v2 mock
        uint256 ETH_PER_LINK_RATE = 1 ether; // 10^18 Wei per Link unit
        coord = new VRFCoordinatorV2_5Mock(BASE_FEE, GAS_PRICE_LINK, int256(ETH_PER_LINK_RATE));

        // 2) Create and fund subscription
        subId = coord.createSubscription();
        // coord.fundSubscriptionWithNative{value:FUNDING_AMOUNT} (subId);
        coord.fundSubscription(subId, FUNDING_AMOUNT);

        factory = new LotteryFactory(subId, address(coord), address(0), KEYHASH);
        coord.requestSubscriptionOwnerTransfer(subId, address(factory));

        
        // The Factory calls acceptSubscriptionOwnerTransfer to finalize ownership.
        vm.prank(address(factory)); // Impersonate the Factory
        coord.acceptSubscriptionOwnerTransfer(subId); // Factory now becomes the active owner
        vm.stopPrank();
        
    }

    function test_createLottery(
        uint256 minFee,
        uint256 maxPlayers,
        uint256 duration,
        uint32 cbGas,
        uint16 conf,
        uint32 words,
        uint256 timeout
    ) internal returns (Lottery) {

        factory.createLottery(minFee, maxPlayers, duration, cbGas, conf, words, timeout);
        address addr = factory.allLotteries(0);
        Lottery lot = Lottery(payable(addr));
        
        // Add the lottery as a consumer on the VRF mock sub
        return lot;
    }

    // Basic enter test remains as before
    function test_CanCreateAndEnterLottery() public {
        lottery = test_createLottery(0.1 ether, 100, 7 days, 100000, 3, 1, 2 hours);
        
        uint256 expectedSent = 0.101 ether;
        vm.deal(USER, 1 ether);
        vm.prank(USER);
        lottery.enter{value: expectedSent}(1);

        assertEq(lottery.totalTickets(), 1);
        assertEq(lottery.getTicketsOf(USER), 1);
        assertEq(address(lottery).balance, expectedSent, "Operational fees were not collected correctly.");
    }

    // End-to-end: request → fulfill → claim
    function test_CloseRequest_Fulfill_ClaimPrize() public {
        lottery = test_createLottery(0.1 ether, 100, 1 days, 200000, 3, 1, 2 hours);
        address triggerUser = USER2;

        // Two players
        vm.deal(USER, 1 ether);
        vm.prank(USER);
        lottery.enter{value: 0.101 ether}(1);

        vm.deal(USER2, 1 ether);
        vm.prank(USER2);
        lottery.enter{value: 0.101 ether}(1);

        // --- Expected values ---
        uint256 ticketPrice = 0.1 ether;
        uint256 platformFeePerEntry = 0.001 ether;
        uint256 totalTickets = 2;
        uint256 totalPlatformFee = platformFeePerEntry * totalTickets; // 0.002 ether
        uint256 totalTicketValue = ticketPrice * totalTickets; // 0.2 ether

        uint256 expectedRewardPerCaller = totalPlatformFee / 2; // 0.001 ether each
        uint256 expectedPrizePool = totalTicketValue; // full 0.2 ether prize pool


        // Close: either after deadline or simulate deadline reached
        vm.warp(block.timestamp + 2 days);
        vm.prank(triggerUser);
        lottery.closeAndRequestWinner();

        // ASSERT: post-close
        assertEq(uint256(lottery.lotteryState()), uint256(Lottery.LotteryState.CALCULATING), "State is not CALCULATING");

        // Attempts to enter after randomness is requested must revert
        address late = address(0xBEEF);
        vm.deal(late, 1 ether);
        vm.prank(late);
        vm.expectRevert("LOTTERY_NOT_OPEN");
        lottery.enter{value: 0.1 ether}(1);

        // Fulfill VRF
        uint256 reqId = lottery.s_requestId();
        coord.fulfillRandomWords(reqId, address(lottery));

        // --- Manually finalize ---
        address finalizer = address(0xAAA);
        vm.deal(finalizer, 1 ether);
        vm.prank(finalizer);
        lottery.finalizeWithStoredRandomness();
        uint256 finalizeBalanceBefore = finalizer.balance;
        vm.prank(finalizer);
        lottery.withdrawFulfillCallReward();

        // ASSERT: post-close
        assertEq(uint256(lottery.lotteryState()), uint256(Lottery.LotteryState.FINISHED), "State is not FINISHED");
        assertEq(finalizer.balance,finalizeBalanceBefore + expectedRewardPerCaller, "Finalize user did not receive reward" );

        address w = lottery.winner();
        assertTrue(w == USER || w == USER2, "winner must be one of the entrants");

        // Payout Phase 1: Winner Claims Prize
        uint256 winnerBalanceBefore = w.balance;
        vm.prank(w);
        lottery.claimPrize();

        assertEq(w.balance, winnerBalanceBefore + expectedPrizePool, "Winner did not receive correct PrizePool amount");

        // Payout Phase 2: Trigger User claims Reward
        uint256 triggerBalanceBefore = triggerUser.balance;
        vm.prank(triggerUser);
        lottery.withdrawTriggerReward();

        assertEq(triggerUser.balance, triggerBalanceBefore + expectedRewardPerCaller, "Trigger user did not receive reward");

        // Final Check: Contract drained
        assertEq(address(lottery).balance, 0, "contract should be empty");
        
    }

    // End-to-end: request → timeout → cancel → refund for each buyer
    function test_CloseRequest_Timeout_Cancel_Refund() public {
        lottery = test_createLottery(0.1 ether, 100, 1 days, 200000, 3, 1, 2 hours);

        // Two players
        vm.deal(USER, 1 ether);
        vm.prank(USER);
        lottery.enter{value: 0.202 ether}(2); // buy 2 tickets

        vm.deal(USER2, 1 ether);
        vm.prank(USER2);
        lottery.enter{value: 0.101 ether}(1);

        // Close and request randomness
        vm.warp(block.timestamp + 2 days);
        lottery.closeAndRequestWinner();

        // Do not fulfill; simulate timeout
        vm.warp(block.timestamp + lottery._TIMEOUT() + 1);
        lottery.cancelIfTimedOut();

        assertEq(uint256(lottery.lotteryState()), uint256(Lottery.LotteryState.CANCELLED));

        // Refunds
        uint256 userBefore = USER.balance;
        vm.prank(USER);
        lottery.claimRefund();
        assertEq(USER.balance, userBefore + 0.2 ether); // 2 tickets refunded

        uint256 user2Before = USER2.balance;
        vm.prank(USER2);
        lottery.claimRefund();
        assertEq(USER2.balance, user2Before + 0.1 ether);

        // Contract drained
        assertEq(address(lottery).balance, 0.003 ether);
    }

    // Wrong requestId is ignored
    function test_FulfillWithWrongRequestId() public {
        lottery = test_createLottery(0.1 ether, 100, 1 days, 200000, 3, 1, 2 hours);

        // Two players
        vm.deal(USER, 1 ether);
        vm.prank(USER);
        lottery.enter{value: 0.202 ether}(2); // buy 2 tickets

        vm.deal(USER2, 1 ether);
        vm.prank(USER2);
        lottery.enter{value: 0.101 ether}(1);

        // Request randomness
        vm.warp(block.timestamp + 2 days);
        lottery.closeAndRequestWinner();
        uint256 correctReq = lottery.s_requestId();

        // Act: fulfill with wrong id (ignored)
        vm.expectRevert(); // mock reverts on nonexistent request
        coord.fulfillRandomWords(correctReq + 1, address(lottery));

        // Assert: still not finished; finalize cannot run yet
        require(
            uint256(lottery.lotteryState()) != uint256(Lottery.LotteryState.FINISHED),
            "should not finish on wrong reqId"
        );

        // Act: fulfill with correct id, then finalize
        coord.fulfillRandomWords(correctReq, address(lottery));
        lottery.finalizeWithStoredRandomness();

        // Assert: finished now
        require(
            uint256(lottery.lotteryState()) == uint256(Lottery.LotteryState.FINISHED),
            "must finish after correct fulfill"
        );
    }

    // Single-player shortcut (no VRF)
    function test_SinglePlayerNoVRFShortcut_step4() public {
        // Arrange: one player
        lottery = test_createLottery(0.1 ether, 10, 1 days, 200000, 3, 1, 2 hours);

        vm.deal(USER, 1 ether);
        vm.prank(USER);
        lottery.enter{value: 0.101 ether}(1);

        // Act: deadline reached and close
        vm.warp(block.timestamp + 2 days);
        lottery.closeAndRequestWinner();

        // Assert: finished, winner is the only player, no VRF request
        require(uint256(lottery.lotteryState()) == uint256(Lottery.LotteryState.FINISHED), "should finish immediately");
        require(lottery.winner() == USER, "single player should be winner");
        require(lottery.s_requestId() == 0, "no VRF request expected");
    }

    // Guard tests (brief samples)
    function test_CannotCloseBeforeDeadlineOrCap() public {
        lottery = test_createLottery(0.1 ether, 3, 7 days, 100000, 3, 1, 2 hours);
        vm.deal(USER, 1 ether);
        vm.prank(USER);
        lottery.enter{value: 0.101 ether}(1);

        // Not deadline and cap not full
        vm.expectRevert("NOT_READY");
        lottery.closeAndRequestWinner();
    }

    // Prevent multiple VRF requests
    function test_DoubleCloseReverts() public {
        lottery = test_createLottery(0.1 ether, 2, 1 days, 100000, 3, 1, 2 hours);

        // Two players
        vm.deal(USER, 1 ether);
        vm.prank(USER);
        lottery.enter{value: 0.101 ether}(1);

        vm.deal(USER2, 1 ether);
        vm.prank(USER2);
        lottery.enter{value: 0.101 ether}(1);

        vm.warp(block.timestamp + 2 days);
        lottery.closeAndRequestWinner();

        vm.expectRevert("VRF_ALREADY_REQUESTED");
        lottery.closeAndRequestWinner();
    }

    // LINK Token balance access
    function test_SubscriptionBalance_ReadsAndDecreasesAfterFulfill() public {
        lottery = test_createLottery(0.1 ether, 100, 1 days, 200000, 3, 1, 2 hours);

        // Two players
        vm.deal(USER, 1 ether);
        vm.prank(USER);
        lottery.enter{value: 0.101 ether}(1);

        vm.deal(USER2, 1 ether);
        vm.prank(USER2);
        lottery.enter{value: 0.101 ether}(1);

        uint96 balBefore = factory.getLinkBalanceOfSubscription();

        assertGt(balBefore, 0, "expected funded sub");

        // Act: request and fulfill
        vm.warp(block.timestamp + 2 days);
        lottery.closeAndRequestWinner();
        uint256 reqId = lottery.s_requestId();
        coord.fulfillRandomWords(reqId, address(lottery));
        lottery.finalizeWithStoredRandomness();

        // Assert: balance decreased
        uint96 balAfter = factory.getLinkBalanceOfSubscription();
        assertLt(balAfter, balBefore, "balance should decrease after fulfill");
    }

    // Guard: Revert VRF reuest with low fund balance
    function test_RevertIfVRFFundsLow() public {
        uint256 emptySub = coord.createSubscription();

        // New factory wired to the empty sub
        LotteryFactory emptyFactory = new LotteryFactory(emptySub, address(coord), address(0), KEYHASH);
        coord.requestSubscriptionOwnerTransfer(emptySub, address(emptyFactory));
        vm.prank(address(emptyFactory));
        coord.acceptSubscriptionOwnerTransfer(emptySub);
        vm.stopPrank();
        emptyFactory.createLottery(0.1 ether, 100, 1 days, 200000, 3, 1, 2 hours);
        address addr = emptyFactory.allLotteries(0);
        Lottery lot = Lottery(payable(addr));



        // Two players to trigger VRF
        vm.deal(USER, 1 ether);
        vm.prank(USER);
        lot.enter{value: 0.101 ether}(1);
        vm.deal(USER2, 1 ether);
        vm.prank(USER2);
        lot.enter{value: 0.101 ether}(1);

        // Deadline reached
        vm.warp(block.timestamp + 2 days);

        // Should revert with low funds
        vm.expectRevert("VRF_FUNDS_LOW");
        lot.closeAndRequestWinner();
    }

    function test_NoPlayers_CancelOnClose() public {
        lottery = test_createLottery(0.1 ether, 100, 1 days, 200000, 3, 1, 2 hours);
        vm.warp(block.timestamp + 2 days);
        lottery.closeAndRequestWinner();
        assertEq(uint256(lottery.lotteryState()), uint256(Lottery.LotteryState.CANCELLED), "Should cancel with no players");
        assertEq(lottery.s_requestId(), 0, "No VRF request expected");
    }

    function test_CapFilled_CloseBeforeDeadline() public {
        lottery = test_createLottery(0.1 ether, 2, 7 days, 200000, 3, 1, 2 hours);
        vm.deal(USER, 1 ether);
        vm.prank(USER);
        lottery.enter{value: 0.101 ether}(1);
        vm.deal(USER2, 1 ether);
        vm.prank(USER2);
        lottery.enter{value: 0.101 ether}(1);
        lottery.closeAndRequestWinner(); // Cap filled, no warp needed
        assertEq(uint256(lottery.lotteryState()), uint256(Lottery.LotteryState.CALCULATING), "Should close when cap filled");
    }

    function test_EnterReverts_InvalidCases() public {
        lottery = test_createLottery(0.1 ether, 1, 1 days, 200000, 3, 1, 2 hours);

        vm.deal(USER, 1 ether);
        vm.prank(USER);

        vm.expectRevert("INSUFFICIENT FUNDS"); 
        lottery.enter{value: 0.05 ether}(1);

        lottery.enter{value: 0.101 ether}(1); // Fill cap
        //assertEq(uint8(lottery.lotteryState()), uint8(Lottery.LotteryState.CLOSED), "State must be CLOSED after cap is met");

        vm.expectRevert("LOTTERY_NOT_OPEN");
        lottery.enter{value: 0.101 ether}(1);
        vm.warp(block.timestamp + 2 days);
        lottery.closeAndRequestWinner();

    }

    function test_WithdrawRewardsReverts_NoReward() public {
        lottery = test_createLottery(0.1 ether, 100, 1 days, 200000, 3, 1, 2 hours);
        vm.expectRevert("NO_REWARD");
        lottery.withdrawTriggerReward();
        vm.expectRevert("NO_REWARD");
        lottery.withdrawFulfillCallReward();
    }

    function test_FinalizeReverts_Invalid() public {
        lottery = test_createLottery(0.1 ether, 100, 1 days, 200000, 3, 1, 2 hours);
        vm.deal(USER, 1 ether);
        vm.prank(USER);
        lottery.enter{value: 0.101 ether}(1);
        vm.deal(USER2, 1 ether);
        vm.prank(USER2);
        lottery.enter{value: 0.101 ether}(1);

        // --- 1. Test INITIAL state: Must revert because it's not CALCULATING and random is not ready ---
        vm.expectRevert("RANDOM_NOT_READY");
        lottery.finalizeWithStoredRandomness();
        
        // --- 2. Request Draw (State is now CALCULATING) ---
        vm.warp(block.timestamp + 2 days);
        lottery.closeAndRequestWinner(); // State is now CALCULATING (2)

        // --- 3. Test PENDING state: Must revert because random is not ready ---
        vm.expectRevert("RANDOM_NOT_READY");
        lottery.finalizeWithStoredRandomness();
    }


    function test_CreateLotteryReverts_NotOwner() public {
        vm.prank(address(0xDEAD));
        vm.expectRevert("Not owner");
        factory.createLottery(0.1 ether, 100, 1 days, 200000, 3, 1, 2 hours);
    }
}
