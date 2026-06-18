// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {MorphoVaultBase} from "./MorphoVaultBase.t.sol";
import {MorphoVaultEmergencyExitTest} from "./MorphoVault.EmergencyExit.t.sol";

contract MorphoVaultPyusdTest is MorphoVaultBase, MorphoVaultEmergencyExitTest {
    function setUp() public override {
        morphoVault = MORPHO_SENTORA_PYUSD;
        super.setUp();
    }
}
