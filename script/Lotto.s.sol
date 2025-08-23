// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
//import {Lottery} from "../src/Lotto.sol";

contract CounterScript is Script {
    //Counter public counter;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();
        vm.stopBroadcast();
    }
}
