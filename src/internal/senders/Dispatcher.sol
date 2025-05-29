// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script, console} from "forge-std/Script.sol";
import {Sender} from "./Sender.sol";

contract Dispatcher is Script {
    error MissingSenderConfigs();

    struct SenderConfigs {
        string[] ids;
        string[] artifacts;
        bytes[] constructorArgs;
    }

    mapping(bytes32 => Sender) public senders;
    SenderConfigs private configs;

    constructor() {
        try vm.envBytes("SENDER_CONFIGS") returns (bytes memory rawConfigs) {
            configs = abi.decode(rawConfigs, (SenderConfigs));
        } catch {
            revert MissingSenderConfigs();
        }

        for (uint256 i = 0; i < configs.ids.length; i++) {
            bytes32 id = keccak256(abi.encodePacked(configs.ids[i]));
            Sender _sender = Sender(vm.deployCode(configs.artifacts[i], configs.constructorArgs[i]));
            senders[id] = _sender;
        }

    }

    function sender(string memory _id) public view returns (Sender) {
        return senders[keccak256(abi.encodePacked(_id))];
    }
}