// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../contracts/PerpMarket.sol";
import "../contracts/mocks/MockPumpToken.sol";
import "../contracts/oracles/MockOracle.sol";

contract PerpLiqTest is Test {
    PerpMarket market;
    MockPumpToken pump;
    MockOracle oracle;
    address alice = address(0xA11CE);
    address bob = address(0xB0B);

    function setUp() public {
        pump = new MockPumpToken();
        market = new PerpMarket(IERC20(address(pump)));
        oracle = new MockOracle(1_00_000_000);
        market.listMarket(address(pump), address(oracle), 10, 50);
        pump.mint(alice, 100_000 ether);
        pump.mint(bob, 10_000 ether);
        vm.prank(alice);
        pump.approve(address(market), type(uint256).max);
        vm.prank(bob);
        pump.approve(address(market), type(uint256).max);
        vm.prank(alice);
        market.openPosition(address(pump), true, 1_000 ether, 10e18);
    }

    function testLiquidation() public {
        oracle.set(0_80_000_000); // $0.80 large drop
        vm.prank(bob);
        market.liquidate(address(pump), alice);
    }
}
