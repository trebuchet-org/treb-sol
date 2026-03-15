// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {SenderCoordinator} from "./internal/SenderCoordinator.sol";
import {Registry} from "../internal/Registry.sol";
import {Senders} from "./internal/sender/Senders.sol";

/// @title TrebScript (v2)
/// @notice Base contract for v2 deployment scripts.
/// @dev Same user-facing API as v1 TrebScript. The difference is entirely internal:
///      v2 uses vm.broadcast() instead of vm.prank() + global queue, and the broadcast
///      modifier is a no-op (Rust handles transaction routing after execution).
///
///      To migrate from v1 to v2, change one import:
///      ```diff
///      - import {TrebScript} from "treb-sol/TrebScript.sol";
///      + import {TrebScript} from "treb-sol/v2/TrebScript.sol";
///      ```
///
///      User scripts are UNCHANGED between v1 and v2:
///      ```solidity
///      contract DeployToken is TrebScript {
///          using Deployer for Senders.Sender;
///          using Deployer for Deployer.Deployment;
///
///          function run() public broadcast {
///              Senders.Sender storage deployer = sender("deployer");
///              deployer.create3("GovernanceToken").deploy(
///                  abi.encode("TGT", "TGT", deployer.account, 1e18)
///              );
///          }
///      }
///      ```
abstract contract TrebScript is SenderCoordinator, Registry {
    bool public isForkMode;

    constructor()
        SenderCoordinator(
            abi.decode(vm.envBytes("SENDER_CONFIGS"), (Senders.SenderInitConfig[])),
            vm.envOr("NAMESPACE", string("default")),
            vm.envString("NETWORK"),
            vm.envOr("DRYRUN", false),
            vm.envOr("QUIET", false)
        )
        Registry(
            vm.envOr("NAMESPACE", string("default")),
            vm.envOr("REGISTRY_FILE", string(".treb/registry.json")),
            vm.envOr("ADDRESSBOOK_FILE", string(".treb/addressbook.json"))
        )
    {
        isForkMode = vm.envOr("TREB_FORK_MODE", false);
    }
}
