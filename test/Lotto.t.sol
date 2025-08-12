// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {Lottery} from "../src/Lotto.sol";

contract LotteryTest is Test {
    Lottery lot;

    uint256 constant minimumFee = 0.01 ether;
    uint256 constant maxPlayers = 1000;
    uint256 constant duration = 1 days;
    uint64 constant SUB_ID = 1;


    address alice = address(0xA11CE);
    address bob   = address(0xB0B);

    function setUp() public {
        lot = new Lottery(minimumFee, maxPlayers, duration, SUB_ID);
    }
}
