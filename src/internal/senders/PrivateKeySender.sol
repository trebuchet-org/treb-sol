// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Sender} from "./Sender.sol";
import {Transaction, OperationResult, OperationStatus} from "../types.sol";

contract PrivateKeySender is Sender {
    uint256 private immutable key;

    constructor(address _sender, uint256 _privateKey) {
        isPrivateKey = true;
        sender = _sender;
        key = _privateKey;
        vm.rememberKey(key);
    }

    function execute(bytes32 operationId, Transaction[] memory _transactions) public override returns (OperationResult memory result) {
        vm.startBroadcast(sender);
        bytes[] memory returnData = new bytes[](_transactions.length);
        for (uint256 i = 0; i < _transactions.length; i++) {
            (bool _success, bytes memory data) = _transactions[i].to.call{value: _transactions[i].value}(_transactions[i].data);
            if (!_success) {
                revert TransactionFailed(_transactions[i].label);
            }
            returnData[i] = data;
        }
        vm.stopBroadcast();

        return OperationResult({
            operationId: operationId,
            status: OperationStatus.EXECUTED,
            returnData: returnData
        });
    }
}
