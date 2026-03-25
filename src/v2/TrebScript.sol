// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {SenderCoordinator} from "./internal/SenderCoordinator.sol";
import {Registry} from "../internal/Registry.sol";
import {Senders} from "./internal/sender/Senders.sol";
import {Deployer} from "./internal/sender/Deployer.sol";

/// @title TrebScript (v2)
/// @notice Base contract for v2 deployment scripts.
/// @dev Sender is a user-defined value type (Senders.Sender) wrapping address.
///      Methods are attached via `using ... for Senders.Sender`:
///
///      - SenderLib (global): .addr(), .broadcast(), .startBroadcast(), .stopBroadcast()
///      - Deployer:           .create3(), .create2()
///      - Senders:            .harness()
///
///      Usage:
///      ```solidity
///      contract DeployToken is TrebScript {
///          using Deployer for Senders.Sender;
///          using Deployer for Deployer.Deployment;
///
///          function run() public broadcast {
///              Senders.Sender deployer = sender("deployer");
///
///              // Deploy via sender-attached builder
///              deployer.create3("GovernanceToken").deploy(
///                  abi.encode("TGT", "TGT", deployer.addr(), 1e18)
///              );
///
///              // Or broadcast raw calls
///              deployer.broadcast();
///              IERC20(token).transfer(recipient, amount);
///          }
///      }
///      ```
abstract contract TrebScript is SenderCoordinator, Registry {
    bool public isForkMode;

    constructor()
        SenderCoordinator(
            vm.envBytes("SENDER_CONFIGS"),
            vm.envOr("NAMESPACE", string("default")),
            vm.envString("NETWORK"),
            vm.envOr("DRYRUN", false),
            vm.envOr("QUIET", false)
        )
        Registry(
            vm.envOr("NAMESPACE", string("default")),
            vm.envOr("REGISTRY_FILE", string("deployments/registry.json")),
            vm.envOr("ADDRESSBOOK_FILE", string("deployments/addressbook.json"))
        )
    {
        isForkMode = vm.envOr("TREB_FORK_MODE", false);
    }
}
