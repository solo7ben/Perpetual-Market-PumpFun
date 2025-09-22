// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IOracle} from "../interfaces/IOracle.sol";

interface IAggregator {
    function latestRoundData() external view returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    );
    function decimals() external view returns (uint8);
}

contract ChainlinkOracleAdapter is IOracle {
    IAggregator public immutable feed;
    uint256 public immutable maxStale; // seconds

    constructor(address _feed, uint256 _maxStale) {
        feed = IAggregator(_feed);
        maxStale = _maxStale;
    }

    function latestAnswer() external view returns (int256) {
        (, int256 price,, uint256 updatedAt,) = feed.latestRoundData();
        require(price > 0, "bad price");
        require(block.timestamp - updatedAt <= maxStale, "stale");
        uint8 d = feed.decimals();
        if (d == 8) return price;
        if (d > 8) return price / int256(10 ** (d - 8));
        return price * int256(10 ** (8 - d));
    }

    function decimals() external pure returns (uint8) {
        return 8;
    }
}
