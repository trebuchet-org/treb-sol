// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {TrebForkScript} from "../src/TrebForkScript.sol";
import {Senders} from "../src/internal/sender/Senders.sol";
import {Transaction, SimulatedTransaction, SenderTypes} from "../src/internal/types.sol";
import {AnvilForkNode} from "./helpers/AnvilForkNode.sol";

contract TrebForkScriptBroadcastTarget {
    uint256 public value;

    function setValue(uint256 newValue) external returns (uint256) {
        value = newValue;
        return newValue;
    }
}

contract TrebForkScriptBroadcastHarness is TrebForkScript {
    using Senders for Senders.Sender;

    function executeAs(address account, Transaction memory txn) external returns (SimulatedTransaction memory) {
        return prankSender(account).execute(txn);
    }

    function dealNative(address to, uint256 amount) external {
        dealFork(to, amount);
    }

    function etchCode(address target, bytes memory code) external {
        etchFork(target, code);
    }

    function broadcastAll() external {
        _broadcast();
    }
}

contract TrebForkScriptBroadcastTest is Test {
    uint256 private constant PORT = 19545;

    function test_prankSender_broadcastsAgainstLiveAnvilFork() public {
        string memory localRpcUrl = AnvilForkNode.start(
            AnvilForkNode.Config({
                name: "fork-prank-broadcast", forkUrlOrAlias: "sepolia", port: PORT, chainId: 31337, forkBlockNumber: 0
            })
        );

        Senders.SenderInitConfig[] memory configs = new Senders.SenderInitConfig[](1);
        configs[0] = Senders.SenderInitConfig({
            name: "bootstrap",
            account: vm.addr(0xB00757A),
            senderType: SenderTypes.InMemory,
            canBroadcast: true,
            config: abi.encode(uint256(0xB00757A))
        });

        vm.setEnv("SENDER_CONFIGS", vm.toString(abi.encode(configs)));
        vm.setEnv("NAMESPACE", "default");
        vm.setEnv("NETWORK", localRpcUrl);
        vm.setEnv("REGISTRY_FILE", ".treb/registry.json");
        vm.setEnv("ADDRESSBOOK_FILE", ".treb/addressbook.json");
        vm.setEnv("DRYRUN", "false");
        vm.setEnv("QUIET", "true");
        vm.setEnv("TREB_FORK_MODE", "true");

        TrebForkScriptBroadcastHarness script = new TrebForkScriptBroadcastHarness();

        address prankAccount = makeAddr("fork-prank");
        address target = makeAddr("etched-target");

        script.etchCode(target, type(TrebForkScriptBroadcastTarget).runtimeCode);
        script.dealNative(prankAccount, 1 ether);
        script.executeAs(
            prankAccount,
            Transaction({to: target, data: abi.encodeCall(TrebForkScriptBroadcastTarget.setValue, (42)), value: 0})
        );

        script.broadcastAll();
        uint256 persistedValue = uint256(AnvilForkNode.storageAt(localRpcUrl, target, bytes32(0)));
        assertEq(persistedValue, 42);
    }
}
