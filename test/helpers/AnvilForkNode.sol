// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Vm} from "forge-std/Vm.sol";

library AnvilForkNode {
    Vm private constant vm = Vm(address(bytes20(uint160(uint256(keccak256("hevm cheat code"))))));

    struct Config {
        string name;
        string forkUrlOrAlias;
        uint256 port;
        uint256 chainId;
        uint256 forkBlockNumber;
    }

    function start(Config memory config) internal returns (string memory localRpcUrl) {
        string memory root = vm.projectRoot();
        string memory scriptPath = string.concat(root, "/test/ffi/anvil_node.sh");
        string memory runtimeDir = string.concat(root, "/test/fixtures/anvil");
        string memory forkUrl = _resolveRpcUrl(config.forkUrlOrAlias);

        string[] memory cmd = new string[](9);
        cmd[0] = "bash";
        cmd[1] = scriptPath;
        cmd[2] = "start";
        cmd[3] = config.name;
        cmd[4] = vm.toString(config.port);
        cmd[5] = runtimeDir;
        cmd[6] = forkUrl;
        cmd[7] = vm.toString(config.chainId);
        cmd[8] = vm.toString(config.forkBlockNumber);

        vm.ffi(cmd);
        return rpcUrl(config.port);
    }

    function stop(string memory name, uint256 port) internal {
        string memory root = vm.projectRoot();
        string memory scriptPath = string.concat(root, "/test/ffi/anvil_node.sh");
        string memory runtimeDir = string.concat(root, "/test/fixtures/anvil");

        string[] memory cmd = new string[](6);
        cmd[0] = "bash";
        cmd[1] = scriptPath;
        cmd[2] = "stop";
        cmd[3] = name;
        cmd[4] = vm.toString(port);
        cmd[5] = runtimeDir;

        vm.ffi(cmd);
    }

    function rpcUrl(uint256 port) internal view returns (string memory) {
        return string.concat("http://127.0.0.1:", vm.toString(port));
    }

    function storageAt(string memory rpcUrl_, address target, bytes32 slot) internal returns (bytes32 value) {
        string[] memory cmd = new string[](6);
        cmd[0] = "cast";
        cmd[1] = "storage";
        cmd[2] = vm.toString(target);
        cmd[3] = vm.toString(slot);
        cmd[4] = "--rpc-url";
        cmd[5] = rpcUrl_;

        bytes memory raw = vm.ffi(cmd);
        if (raw.length == 32) {
            assembly {
                value := mload(add(raw, 0x20))
            }
            return value;
        }

        return vm.parseBytes32(vm.trim(string(raw)));
    }

    function _resolveRpcUrl(string memory forkUrlOrAlias) private view returns (string memory) {
        try vm.rpcUrl(forkUrlOrAlias) returns (string memory resolved) {
            return resolved;
        } catch {
            return forkUrlOrAlias;
        }
    }
}
