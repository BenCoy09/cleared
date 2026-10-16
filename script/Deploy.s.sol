// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {Treasury} from "../src/Treasury.sol";

contract Deploy is Script {
    address constant USDC = 0x3600000000000000000000000000000000000000;

    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address agent = vm.envAddress("AGENT_ADDRESS");
        vm.startBroadcast(pk);
        Treasury t = new Treasury(USDC, agent, 5_000e6);
        vm.stopBroadcast();
        console2.log("Treasury deployed at", address(t));
    }
}
