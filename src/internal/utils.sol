// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {console} from "forge-std/console.sol";
import {Vm} from "forge-std/Vm.sol";

/// @notice Get init code from compiler artifacts (cross-version compatibility)
/// @dev Might struggle when libraries are used and need to be linked
function getInitCodeFromArtifacts(Vm vm, string memory artifactPath) view returns (bytes memory) {
    try vm.readFile(artifactPath) returns (string memory artifactJson) {
        // Parse the JSON to extract bytecode string
        try vm.parseJsonString(artifactJson, ".bytecode.object") returns (string memory bytecodeStr) {
            if (bytes(bytecodeStr).length > 0) {
                // Add 0x prefix if not present
                if (bytes(bytecodeStr).length >= 2 && bytes(bytecodeStr)[0] == "0" && bytes(bytecodeStr)[1] == "x")
                {
                    return vm.parseBytes(bytecodeStr);
                } else {
                    return vm.parseBytes(string.concat("0x", bytecodeStr));
                }
            }
        } catch {
            console.log("Failed to parse bytecode from artifact: ", artifactPath);
        }
    } catch {
        console.log("Warning: Could not read artifact from: ", artifactPath);
    }

    return "";
}
