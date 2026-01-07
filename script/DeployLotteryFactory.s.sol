// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {LotteryFactory} from "../src/LotteryFactory.sol";

contract DeployLotteryFactory is Script {
    function run() external returns (LotteryFactory factory) {
        address vrfCoordinator = vm.envAddress("VRF_COORDINATOR"); // coordinator
        address linkToken = vm.envAddress("LINK_TOKEN"); // LINK token
        bytes32 keyHash = vm.envBytes32("KEY_HASH"); // keyHash

        vm.startBroadcast();
        factory = new LotteryFactory(vrfCoordinator, linkToken, keyHash);
        vm.stopBroadcast();

        return factory;
    }
}
