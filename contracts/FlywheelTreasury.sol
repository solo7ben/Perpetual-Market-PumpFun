// SPDX-License-Identifier:
pragma solidity ^0.8.24;

import {IERC20} from "./interfaces/IERC20.sol";

contract FlywheelTreasury {
    IERC20 public immutable pumpToken;
    address public immutable market;

    event Recycled(address indexed from, uint256 amount);
    event Swept(address indexed to, uint256 amount);

    modifier onlyMarket() {
        require(msg.sender == market, "Not market");
        _;
    }

    constructor(IERC20 _pumpToken, address _market) {
        pumpToken = _pumpToken;
        market = _market;
    }

    function recycle(uint256 amount) external onlyMarket {
        emit Recycled(msg.sender, amount);
    }

    function sweep(address to, uint256 amount) external {
        require(msg.sender == market, "Only market");
        pumpToken.transfer(to, amount);
        emit Swept(to, amount);
    }
}
