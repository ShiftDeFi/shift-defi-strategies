// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {Script} from "forge-std/Script.sol";

struct Roles {
    address deployer;
    address proxyAdminOwner;
}

abstract contract DeployBase is Script {
    Roles public roles;

    function _readRolesFromEnv() internal {
        roles.deployer = vm.envAddress("DEPLOYER");
        roles.proxyAdminOwner = vm.envAddress("PROXY_ADMIN_OWNER");
    }

    function _proxifyWithSalt(address implementation, bytes memory data) internal returns (address) {
        bytes32 saltHash = keccak256(abi.encodePacked(implementation, block.timestamp, block.chainid));
        return address(new TransparentUpgradeableProxy{salt: saltHash}(implementation, roles.proxyAdminOwner, data));
    }
}
