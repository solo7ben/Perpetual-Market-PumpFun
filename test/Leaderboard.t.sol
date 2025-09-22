// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../contracts/PerpMarket.sol";
import "../contracts/mocks/MockPumpToken.sol";
import "../contracts/oracles/MockOracle.sol";

contract LeaderboardTest is Test {
    PerpMarket market;
    MockPumpToken pump;
    MockOracle oracle;
    address a = address(0xA1);
    address b = address(0xB1);

    function setUp() public {
        pump = new MockPumpToken();
        market = new PerpMarket(IERC20(address(pump)));
        oracle = new MockOracle(1_00_000_000);
        market.listMarket(address(pump), address(oracle), 10, 50);
        pump.mint(a, 100_000 ether);
        pump.mint(b, 100_000 ether);
        vm.startPrank(a);
        pump.approve(address(market), type(uint256).max);
        market.openPosition(address(pump), true, 1_000 ether, 5e18);
        vm.stopPrank();
        vm.startPrank(b);
        pump.approve(address(market), type(uint256).max);
        market.openPosition(address(pump), false, 2_000 ether, 3e18);
        vm.stopPrank();
    }

    function testTop() public {
        oracle.set(1_10_000_000); // profit for long, loss for short
        vm.prank(a);
        market.closePosition(address(pump), 1_000 ether);
        vm.prank(b);
        market.closePosition(address(pump), 1_000 ether);
        (address[] memory addrs, int256[] memory pnls) = market.getTopTraders(2);
        assertEq(addrs.length, 2);
        assertEq(pnls.length, 2);
    }
}
