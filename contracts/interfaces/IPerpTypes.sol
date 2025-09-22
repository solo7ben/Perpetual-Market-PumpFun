// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IPerpTypes {
    struct Market {
        address asset;
        address oracle;
        bool listed;
        uint16 feeBps;
        uint16 liqFeeBps;
    }

    struct Position {
        bool isLong;
        bool open;
        uint256 sizeUsd;
        uint256 entryPrice;
        uint256 collateral;
    }
}
