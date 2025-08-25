// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {LotteryFactory} from "../src/LotteryFactory.sol";

contract DeployLotteryFactory is Script {


    function run() external returns (LotteryFactory factory) {

        uint256 pk = vm.envUint("PRIVATE_KEY"); // deployer key
        uint64 subId = uint64(vm.envUint("SUBSCRIPTION_ID")); // VRF sub (uint64)
        address vrf = vm.envAddress("VRF_COORDINATOR"); // coordinator
        address link = vm.envAddress("LINK_TOKEN"); // LINK token
        bytes32 gasLane = vm.envBytes32("KEY_HASH"); // keyHash
        
        vm.startBroadcast(pk);
        factory = new LotteryFactory(subId, vrf, link, gasLane);
        vm.stopBroadcast();

        return factory;
    }
}
