// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Lottery} from "../src/Lotto.sol";
import {LotteryFactory} from "../src/LotteryFactory.sol";
import {VRFCoordinatorV2_5Mock} from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";

contract LotteryFactoryTest is Test {
    // State variables 
    LotteryFactory internal factory;
    Lottery internal latestLottery;
    address internal constant USER = address(0x1);

    // Mocks and Config
    uint64 internal subscriptionId;
    VRFCoordinatorV2_5Mock internal vrfCoordinatorMock;
    uint256 internal constant FUNDING_AMOUNT = 100 ether; // 100 LINK

    uint96 public constant MOCK_BASE_FEE = 0.25 ether;
    uint96 public constant MOCK_GAS_PRICE = 1e9; // 1 gwei
    int256 public constant MOCK_WEI_PER_UNIT_LINK = 4e15;
    function setUp() public {
        // Deploy the Mock Coordinator
        vrfCoordinatorMock = new VRFCoordinatorV2_5Mock(
            MOCK_BASE_FEE,
            MOCK_GAS_PRICE,
            MOCK_WEI_PER_UNIT_LINK
        );

        // Create a subscription on the mock
        subscriptionId = uint64(vrfCoordinatorMock.createSubscription());

        // Fund the subscription on the mock
        vrfCoordinatorMock.fundSubscription(subscriptionId, FUNDING_AMOUNT);

        // Deploy our factory, giving it the MOCK coordinator's address
        factory = new LotteryFactory(subscriptionId, address(vrfCoordinatorMock));
    }

    // Only owner can create new Lottery using LotteryFactory
    function test_CanCreateAndEnterLottery() public {

        // Owner (here the Test contract) calls createLottery
        factory.createLottery(
            0.1 ether, // minFee 
            100,       // maxPlayers,
            7 days,    // duration 
            100000,    // callbackGasLimit 
            3,         // requestConfirmations 
            1,         // numWords 
            2 hours   // timeout
        );

        // Get the address of newly created lottery
        address lotteryAddress = factory.allLotteries(0);
        latestLottery = Lottery(lotteryAddress);


        // Give the user 1 ETH to spend
        vm.deal(USER, 1 ether);

        // Simulate the USER entering the lottery 
        vm.prank(USER);
        latestLottery.enter{value: 0.1 ether}(1);

        // Assert: Check that the lottery state is correct
        assertEq(latestLottery.getPlayersCount(), 1, "Player count should be 1");
        assertEq(latestLottery.getTicketsOf(USER), 1, "User should have 1 ticket");
        assertEq(address(latestLottery).balance, 0.1 ether, "Pot should have 0.1 ETH");
    }

    // Error when non owner creates lottery
    function test_RevertsIfNonOwnerCreatesLottery() public {
        vm.expectRevert("Not owner");

        vm.prank(USER);

        factory.createLottery(
            0.1 ether, // minFee 
            100,       // maxPlayers,
            7 days,    // duration 
            100000,    // callbackGasLimit 
            3,         // requestConfirmations 
            1,         // numWords 
            2 hours   // timeout
        );
    }

    // Can enter with correct fee, reverts if incorrect eth is sent
    function test_RevertIfUserPaysIncorrectFee() public {
        // Create a new Lottery with 0.1 ether fee 
        factory.createLottery(
            0.1 ether, // minFee 
            100,       // maxPlayers,
            7 days,    // duration 
            100000,    // callbackGasLimit 
            3,         // requestConfirmations 
            1,         // numWords 
            2 hours   // timeout
        );

        

        // Get the address of newly created lottery 
        address lotteryAddress = factory.allLotteries(0);
        latestLottery = Lottery(lotteryAddress);

        // Give the user 1 ETH to spend
        vm.deal(USER, 1 ether);

        // Simulate the USER entering the lottery 
        vm.expectRevert("INCORRECT_ETH");
        vm.prank(USER);
        latestLottery.enter{value: 0.05 ether}(1);
    }

    // Cannot enter post the Lottery deadline
    function test_RevertIfEnteringAfterDeadline() public {
        factory.createLottery(
            0.1 ether, // minFee 
            100,       // maxPlayers,
            7 days,    // duration 
            100000,    // callbackGasLimit 
            3,         // requestConfirmations 
            1,         // numWords 
            2 hours   // timeout
        );

        address lotteryAddress = factory.allLotteries(0);
        latestLottery = Lottery(lotteryAddress);

        // fast forward the clock by 8 days after the deadline
        vm.warp(block.timestamp + 8 days);

        // Expect Revert 
        vm.expectRevert("DEADLINE_PASSED");

        // A user tries to enter after the deadline 
        vm.deal(USER, 1 ether);
        vm.prank(USER);
        latestLottery.enter{value: 0.1 ether}(1);
    }


    // Testing the players cap 
    function test_RevertsIfPlayersCapIsReached() public {
        uint256 maxPlayers = 10;

        factory.createLottery(
            0.1 ether, maxPlayers, 7 days, 100000, 3, 1, 2 hours
        );

        address lotteryAddress = factory.allLotteries(0);
        latestLottery = Lottery(lotteryAddress);

        // Fill the lottery with 10 unique players using a loop 
        for (uint256 i=1; i< maxPlayers; i++){

            // Create a unique address for each player 
            address player = address(uint160(i));
            vm.deal(player,1 ether);
            vm.prank(player);
            latestLottery.enter{value: 0.1 ether}(1);
        }

        // Expect Revert: The next entry must fail 
        vm.expectRevert("MAX_TICKETS_REACHED");

        // A new user tries to buy 2 tickets when only 1 spot is left
        vm.deal(USER, 1 ether);
        vm.prank(USER);
        latestLottery.enter{value: 0.2 ether}(2);  // Try to buy 2 tickets
    }


    // Per-Address ticket cap 
    function test_RevertsIfAddressCapIsReached() public {

        // Create a lottery with max players of 100
        factory.createLottery(
            0.1 ether, 100, 7 days, 100000, 3, 1, 2 hours
        );

        address lotteryAddress = factory.allLotteries(0);
        latestLottery = Lottery(lotteryAddress);

        // Expect Revert: The call must fail with "ADDRESS_CAP"
        vm.expectRevert("ADDRESS_CAP");

        // Singel user tries to buy 6 tickets (Max is 5 (100 / 20))
        vm.deal(USER, 1 ether);
        vm.prank(USER);
        latestLottery.enter{value:0.6 ether}(6); // 6 tickets * 0.1 ether
    }
}