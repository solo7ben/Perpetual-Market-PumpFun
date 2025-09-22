// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import "forge-std/Script.sol";

abstract contract Utils is Script {
    function _key() internal view returns (uint256) {
        uint256 key = vm.envUint("PRIVATE_KEY");
        return key;
    }
}
