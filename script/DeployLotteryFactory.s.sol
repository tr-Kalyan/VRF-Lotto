// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {LotteryFactory} from "../src/LotteryFactory.sol";

contract DeployLotteryFactory is Script {
    function run() external returns (LotteryFactory factory) {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY"); // deployer key
        uint256 subscriptionId = uint256(vm.envUint("SUBSCRIPTION_ID")); // VRF sub (uint64)
        address vrfCoordinator = vm.envAddress("VRF_COORDINATOR"); // coordinator
        address linkToken = vm.envAddress("LINK_TOKEN"); // LINK token
        bytes32 keyHash = vm.envBytes32("KEY_HASH"); // keyHash

        vm.startBroadcast(deployerKey);
        factory = new LotteryFactory(subscriptionId, vrfCoordinator, linkToken, keyHash);
        vm.stopBroadcast();

        return factory;
    }
}
