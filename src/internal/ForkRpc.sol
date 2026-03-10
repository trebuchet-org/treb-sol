// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
// solhint-disable quotes
// solhint-disable ordering

import {Vm} from "forge-std/Vm.sol";

/// @title ForkRpc
/// @notice Small helper around Anvil JSON-RPC methods used by fork-mode scripts.
library ForkRpc {
    Vm private constant vm = Vm(address(bytes20(uint160(uint256(keccak256("hevm cheat code"))))));

    error RpcCallFailed(string method);
    error TransactionBroadcastFailed();

    function setStorageAt(address target, bytes32 slot, bytes32 value) internal {
        _rpcOrRevert(
            "anvil_setStorageAt",
            string(
                abi.encodePacked('["', vm.toString(target), '","', vm.toString(slot), '","', vm.toString(value), '"]')
            )
        );
    }

    function setCode(address target, bytes memory code) internal {
        _rpcOrRevert(
            "anvil_setCode", string(abi.encodePacked('["', vm.toString(target), '","', vm.toString(code), '"]'))
        );
    }

    function setBalance(address account, uint256 amount) internal {
        _rpcOrRevert(
            "anvil_setBalance",
            string(abi.encodePacked('["', vm.toString(account), '","', vm.toString(bytes32(amount)), '"]'))
        );
    }

    function impersonateAccount(address account) internal {
        _rpcOrRevert("anvil_impersonateAccount", string(abi.encodePacked('["', vm.toString(account), '"]')));
    }

    function stopImpersonatingAccount(address account) internal {
        _rpcOrRevert("anvil_stopImpersonatingAccount", string(abi.encodePacked('["', vm.toString(account), '"]')));
    }

    function sendTransactionAs(address from, address to, bytes memory data, uint256 value)
        internal
        returns (bytes memory response)
    {
        impersonateAccount(from);
        response = sendTransaction(from, to, data, value);
        stopImpersonatingAccount(from);
    }

    function sendTransaction(address from, address to, bytes memory data, uint256 value)
        internal
        returns (bytes memory response)
    {
        string memory params = _txParams(from, to, data, value);

        (bool success, bytes memory result) = _tryRpc("anvil_sendTransaction", params);
        if (!success) {
            (success, result) = _tryRpc("eth_sendTransaction", params);
        }
        if (!success) {
            revert TransactionBroadcastFailed();
        }

        return result;
    }

    function _txParams(address from, address to, bytes memory data, uint256 value)
        private
        view
        returns (string memory params)
    {
        params = string(
            abi.encodePacked(
                '[{"from":"', vm.toString(from), '","to":"', vm.toString(to), '","data":"', vm.toString(data), '"'
            )
        );

        if (value > 0) {
            params = string.concat(params, ',"value":"', vm.toString(bytes32(value)), '"');
        }

        return string.concat(params, "}]");
    }

    function _rpcOrRevert(string memory method, string memory params) private returns (bytes memory result) {
        (bool success, bytes memory data) = _tryRpc(method, params);
        if (!success) {
            revert RpcCallFailed(method);
        }
        return data;
    }

    function _tryRpc(string memory method, string memory params) private returns (bool success, bytes memory result) {
        bytes memory raw;
        (success, raw) = address(vm).call(abi.encodeWithSignature("rpc(string,string)", method, params));
        if (!success) {
            return (false, bytes(""));
        }

        return (true, abi.decode(raw, (bytes)));
    }
}
