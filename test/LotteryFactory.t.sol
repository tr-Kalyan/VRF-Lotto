// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Lottery} from "../src/Lotto.sol";
import {LotteryFactory} from "../src/LotteryFactory.sol";
import {VRFCoordinatorV2Mock} from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2Mock.sol";

contract LotteryFactoryTest is Test {
    // Actors
    address internal constant USER = address(0x1);
    address internal constant USER2 = address(0x2);

    // System under test
    LotteryFactory internal factory;
    Lottery internal lottery;
    VRFCoordinatorV2Mock internal coord;

    // VRF mock config
    uint64 internal subId;
    uint96 constant BASE_FEE = uint96(0.25 ether);
    uint96 constant GAS_PRICE_LINK = uint96(1e9);
    uint96 constant FUNDING_AMOUNT = uint96(100 ether);

    function setUp() public {
        // 1) Deploy VRF v2 mock
        coord = new VRFCoordinatorV2Mock(BASE_FEE, GAS_PRICE_LINK);

        // 2) Create and fund subscription
        subId = coord.createSubscription();
        coord.fundSubscription(subId, FUNDING_AMOUNT);

        // 3) Deploy factory passing the coordinator address (adjust constructor to accept it)
        // If your factory constructor currently only takes subscriptionId, update it to accept coordinator address too
        factory = new LotteryFactory(subId, address(coord),address(0));
    }

    function _createLottery(
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

        // 4) Add the lottery as a consumer on the VRF mock sub
        coord.addConsumer(subId, address(lot));
        return lot;
    }

    // Basic enter test remains as before
    function test_CanCreateAndEnterLottery() public {
        lottery = _createLottery(0.1 ether, 100, 7 days, 100000, 3, 1, 2 hours);

        vm.deal(USER, 1 ether);
        vm.prank(USER);
        lottery.enter{value: 0.1 ether}(1);

        assertEq(lottery.getPlayersCount(), 1);
        assertEq(lottery.getTicketsOf(USER), 1);
        assertEq(address(lottery).balance, 0.1 ether);
    }

    // End-to-end: request → fulfill → claim
    function test_CloseRequest_Fulfill_ClaimPrize() public {
        lottery = _createLottery(0.1 ether, 100, 1 days, 200000, 3, 1, 2 hours);

        // Two players
        vm.deal(USER, 1 ether);
        vm.prank(USER);
        lottery.enter{value: 0.1 ether}(1);

        vm.deal(USER2, 1 ether);
        vm.prank(USER2);
        lottery.enter{value: 0.1 ether}(1);

        // Close: either after deadline or simulate deadline reached
        vm.warp(block.timestamp + 2 days);
        lottery.closeAndRequestWinner();

        // Pull the requestId from event or public var (assume public s_requestId)
        uint256 reqId = lottery.requestId();

        // Fulfill via the v2 mock
        coord.fulfillRandomWords(reqId, address(lottery));
        lottery.finalizeWithStoredRandomness();

        // Should be finished with a valid winner
        assertEq(uint256(lottery.lotteryState()), uint256(Lottery.LotteryState.FINISHED));
        address w = lottery.winner();
        assertTrue(w == USER || w == USER2, "winner must be one of the entrants");

        // Winner claims
        uint256 pot = address(lottery).balance;
        uint256 balBefore = w.balance;
        vm.prank(w);
        lottery.claimPrize();
        assertEq(address(lottery).balance, 0);
        assertEq(w.balance, balBefore + pot);
    }

    // End-to-end: request → timeout → cancel → refund for each buyer
    function test_CloseRequest_Timeout_Cancel_Refund() public {
        lottery = _createLottery(0.1 ether, 100, 1 days, 200000, 3, 1, 2 hours);

        // Two players
        vm.deal(USER, 1 ether);
        vm.prank(USER);
        lottery.enter{value: 0.2 ether}(2); // buy 2 tickets

        vm.deal(USER2, 1 ether);
        vm.prank(USER2);
        lottery.enter{value: 0.1 ether}(1);

        // Close and request randomness
        vm.warp(block.timestamp + 2 days);
        lottery.closeAndRequestWinner();

        // Do not fulfill; simulate timeout
        vm.warp(block.timestamp + lottery.timeout() + 1);
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
        assertEq(address(lottery).balance, 0);
    }

    // Guard tests (brief samples)
    function test_CannotCloseBeforeDeadlineOrCap() public {
        lottery = _createLottery(0.1 ether, 3, 7 days, 100000, 3, 1, 2 hours);
        vm.deal(USER, 1 ether);
        vm.prank(USER);
        lottery.enter{value: 0.1 ether}(1);

        // Not deadline and cap not full
        vm.expectRevert("NOT_READY");
        lottery.closeAndRequestWinner();
    }

    function test_DoubleCloseReverts() public {
        lottery = _createLottery(0.1 ether, 2, 1 days, 100000, 3, 1, 2 hours);

        vm.deal(USER, 1 ether);
        vm.prank(USER);
        lottery.enter{value: 0.1 ether}(1);

        vm.deal(USER2, 1 ether);
        vm.prank(USER2);
        lottery.enter{value: 0.1 ether}(1);

        vm.warp(block.timestamp + 2 days);
        lottery.closeAndRequestWinner();

        vm.expectRevert("VRF_ALREADY_REQUESTED");
        lottery.closeAndRequestWinner();
    }
}
