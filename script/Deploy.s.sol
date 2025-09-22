// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../contracts/PerpMarket.sol";
import "../contracts/FlywheelTreasury.sol";
import "../contracts/mocks/MockPumpToken.sol";
import "../contracts/oracles/MockOracle.sol";

contract Deploy is Script {
    function run() external {
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));

        MockPumpToken pump = new MockPumpToken();
        PerpMarket market = new PerpMarket(IERC20(address(pump)));
        FlywheelTreasury flywheel = FlywheelTreasury(market.flywheelAddress());

        pump.mint(msg.sender, 1_000_000 ether);

        MockOracle oracle = new MockOracle(1_00_000_000); // $1.00

        market.listMarket(address(pump), address(oracle), 10, 50);

        vm.stopBroadcast();

        console2.log("pumpToken:", address(pump));
        console2.log("perpMarket:", address(market));
        console2.log("flywheel:", address(flywheel));
        console2.log("oracle:", address(oracle));
    }
}
