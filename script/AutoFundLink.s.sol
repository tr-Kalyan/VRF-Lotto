// script/SwapAndFund.s.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {LinkTokenInterface} from "@chainlink/shared/interfaces/LinkTokenInterface.sol";

interface IUniswapV2Router02 {
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);
}

contract SwapAndFund is Script {
    // SEPOLIA
    address constant ROUTER = 0xC532a74256D3Db42D0Bf7a0400fEFDbad7694008;
    address constant USDC = 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238;
    address constant LINK = 0x779877A7B0D9E8603169DdbD7836e478b4624789;
    address constant WETH = 0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14;
    address constant VRF_COORDINATOR = 0x9DdfaCa8183c41ad55329BdeeD9F6A8d53168B1B;

    function run() external {
        uint256 key = vm.envUint("PRIVATE_KEY");
        uint256 subId = vm.envUint("SUBSCRIPTION_ID");

        vm.startBroadcast(key);

        uint256 amountIn = 10 * 1e6; // 10 USDC

        IERC20(USDC).approve(ROUTER, amountIn);

        address[] memory path = new address[](3);
        path[0] = USDC;
        path[1] = WETH;
        path[2] = LINK;

        uint[] memory amounts = IUniswapV2Router02(ROUTER).swapExactTokensForTokens(
            amountIn,
            0,
            path,
            address(this),
            block.timestamp
        );

        uint256 linkBought = amounts[2];
        console.log("Swapped 10 USDC  s LINK", linkBought / 1e18);

        LinkTokenInterface(LINK).transferAndCall(
            VRF_COORDINATOR,
            linkBought,
            abi.encode(subId)
        );

        console.log("Subscription s funded with %s LINK", subId, linkBought / 1e18);
        vm.stopBroadcast();
    }
}