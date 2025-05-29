// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script, console} from "forge-std/Script.sol";
import {Sender} from "./Sender.sol";

contract Dispatcher is Script {
    error MissingSenderConfigs();
    error SenderNotFound(string id);

    struct SenderConfigs {
        string[] ids;
        string[] artifacts;
        bytes[] constructorArgs;
    }

    modifier flush() {
        _;
        _flush();
    }

    mapping(bytes32 => Sender) public senders;

    uint256 immutable simulationForkId;
    uint256 immutable executionForkId;


    SenderConfigs private configs;

    constructor() {
        simulationForkId = vm.createFork(vm.envString("NETWORK"));
        executionForkId = vm.createFork(vm.envString("NETWORK"));
        vm.selectFork(simulationForkId);

        try vm.envBytes("SENDER_CONFIGS") returns (bytes memory rawConfigs) {
            configs = abi.decode(rawConfigs, (SenderConfigs));
        } catch {
            revert MissingSenderConfigs();
        }

        for (uint256 i = 0; i < configs.ids.length; i++) {
            bytes32 id = keccak256(abi.encodePacked(configs.ids[i]));
            Sender _sender = Sender(vm.deployCode(configs.artifacts[i], configs.constructorArgs[i]));
            senders[id] = _sender;
            vm.allowCheatcodes(address(_sender));
            vm.makePersistent(address(_sender));
        }
    }

    function sender(string memory _id) public view returns (Sender) {
        Sender _sender = senders[keccak256(abi.encodePacked(_id))];
        if (address(_sender) == address(0)) {
            revert SenderNotFound(_id);
        }
        return _sender;
    }

    function _flush() internal {
        if (vm.envOr("DRYRUN", false) == true) {
            return;
        }

        vm.selectFork(executionForkId);
        for (uint256 i = 0; i < configs.ids.length; i++) {
            senders[keccak256(abi.encodePacked(configs.ids[i]))].flushBundle();
        }
    }
}