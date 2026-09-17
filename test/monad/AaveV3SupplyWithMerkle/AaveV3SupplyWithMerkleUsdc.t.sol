// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {AaveV3SupplyWithMerkleBase} from "./AaveV3SupplyWithMerkleBase.t.sol";
import {AaveV3SupplyWithMerkleEmergencyExitTest} from "./AaveV3SupplyWithMerkle.EmergencyExit.t.sol";

contract AaveV3SupplyWithMerkleUsdcTest is AaveV3SupplyWithMerkleBase, AaveV3SupplyWithMerkleEmergencyExitTest {
    function setUp() public override {
        merkleDistributor = AAVE_MERKLE_DISTRIBUTOR;
        super.setUp();
    }
}
