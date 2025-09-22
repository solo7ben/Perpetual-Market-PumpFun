// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IOracle} from "../interfaces/IOracle.sol";

contract MockOracle is IOracle {
    int256 public px; // 1e8
    constructor(int256 _px) { px = _px; }
    function set(int256 _px) external { px = _px; }
    function latestAnswer() external view returns (int256) { return px; }
    function decimals() external pure returns (uint8) { return 8; }
}
