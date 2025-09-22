// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../contracts/PerpMarket.sol";

contract ListMarket is Script {
    function run(address asset, address oracle, uint16 feeBps, uint16 liqFeeBps) external {
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        PerpMarket m = PerpMarket(vm.envAddress("PERP_MARKET"));
        m.listMarket(asset, oracle, feeBps, liqFeeBps);
        vm.stopBroadcast();
    }
}
