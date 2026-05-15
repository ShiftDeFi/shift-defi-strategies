// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

abstract contract BaseConfig is Test {
    bytes32 internal constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 internal constant CONTAINER_MANAGER_ROLE = keccak256("CONTAINER_MANAGER_ROLE");
    bytes32 internal constant CONFIGURATOR_ROLE = keccak256("CONFIGURATOR_ROLE");
    bytes32 internal constant TOKEN_MANAGER_ROLE = keccak256("TOKEN_MANAGER_ROLE");
    bytes32 internal constant HARVEST_MANAGER_ROLE = keccak256("HARVEST_MANAGER_ROLE");
    bytes32 internal constant RESHUFFLING_MANAGER_ROLE = keccak256("RESHUFFLING_MANAGER_ROLE");
    bytes32 internal constant RESHUFFLING_EXECUTOR_ROLE = keccak256("RESHUFFLING_EXECUTOR_ROLE");
    bytes32 internal constant EMERGENCY_PAUSER_ROLE = keccak256("EMERGENCY_PAUSER_ROLE");
    bytes32 internal constant EMERGENCY_MANAGER_ROLE = keccak256("EMERGENCY_MANAGER_ROLE");
    bytes32 internal constant EMERGENCY_EXECUTOR_ROLE = keccak256("EMERGENCY_EXECUTOR_ROLE");
    bytes32 internal constant ORACLE_MANAGER_ROLE = keccak256("ORACLE_MANAGER_ROLE");

    struct Roles {
        address deployer;
        address defaultAdmin;
        address operator;
        address containerManager;
        address configurator;
        address tokenManager;
        address harvestManager;
        address reshufflingManager;
        address reshufflingExecutor;
        address emergencyPauser;
        address emergencyManager;
        address emergencyExecutor;
        address oracleManager;
        address merkleClaimer;
    }

    struct Users {
        address alice;
        address bob;
    }

    Roles public roles;

    Users public users;

    function setUp() public virtual {
        roles.deployer = makeAddr("DEPLOYER");
        roles.defaultAdmin = makeAddr("DEFAULT_ADMIN");
        roles.operator = makeAddr("OPERATOR");
        roles.containerManager = makeAddr("CONTAINER_MANAGER");
        roles.configurator = makeAddr("CONFIGURATOR");
        roles.tokenManager = makeAddr("TOKEN_MANAGER");
        roles.harvestManager = makeAddr("HARVEST_MANAGER");
        roles.reshufflingManager = makeAddr("RESHUFFLING_MANAGER");
        roles.reshufflingExecutor = makeAddr("RESHUFFLING_EXECUTOR");
        roles.emergencyPauser = makeAddr("EMERGENCY_PAUSER");
        roles.emergencyManager = makeAddr("EMERGENCY_MANAGER");
        roles.emergencyExecutor = makeAddr("EMERGENCY_EXECUTOR");
        roles.oracleManager = makeAddr("ORACLE_MANAGER");
        roles.merkleClaimer = makeAddr("MERKLE_CLAIMER");

        users.alice = makeAddr("ALICE");
        users.bob = makeAddr("BOB");
    }
}
