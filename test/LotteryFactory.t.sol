// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {Lottery} from "../src/Lotto.sol";
import {LotteryFactory} from "../src/LotteryFactory.sol";


contract LotteryFactoryTest is Test {
    // State variables 
    LotteryFactory internal factory;
    Lottery internal latestLottery;
    address internal constant USER = address(0x1);

    uint64 internal constant SUB_ID = 12345;

    function setUp() public {
        factory = new LotteryFactory(SUB_ID);
    }

    function test_CanCreateAndEnterLottery() public {

        // Owner (here the Test contract) calls createLottery
        factory.createLottery(
            0.1 ether, // minFee 
            100,       // maxPlayers,
            7 days,    // duration 
            100000,    // callbackGasLimit 
            3,         // requestConfirmations 
            1,         // numWords 
            2 hours,   // timeout
        );

        // Get the address of newly created lottery
        address lotteryAddress = factory.allLotteries(0);
        latestLottery = Lottery(lotteryAddress);

        // Simulate the USER entering the lottery 
        vm.prank(USER);
        latestLottery.enter{value: 0.1, ether}(1);

        // 4. Assert: Check that the lottery state is correct
        assertEq(latestLottery.getPlayersCount(), 1, "Player count should be 1");
        assertEq(latestLottery.getTicketsOf(USER), 1, "User should have 1 ticket");
        assertEq(address(latestLottery).balance, 0.1 ether, "Pot should have 0.1 ETH");
    }


    function test_RevertsIfNonOwnerCreatesLottery() public {
        vm.expectRevert("Not Owner");

        vm.prank(USER);

        factory.createLottery(
            0.1 ether, // minFee 
            100,       // maxPlayers,
            7 days,    // duration 
            100000,    // callbackGasLimit 
            3,         // requestConfirmations 
            1,         // numWords 
            2 hours,   // timeout
        );
    }
}