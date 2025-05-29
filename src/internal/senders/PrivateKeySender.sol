// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Sender} from "../Sender.sol";
import {Transaction, BundleStatus} from "../types.sol";

contract PrivateKeySender is Sender {
    uint256 private immutable key;

    constructor(address _sender, uint256 _privateKey) Sender(_sender) {
        key = _privateKey;
        vm.rememberKey(key);
    }
    
    function senderType() public pure virtual override returns (bytes4) {
        return bytes4(keccak256("PrivateKey"));
    }

    function _execute(Transaction[] memory _transactions) internal override returns (BundleStatus status, bytes[] memory returnData) {
        vm.startBroadcast(senderAddress);
        returnData = new bytes[](_transactions.length);
        for (uint256 i = 0; i < _transactions.length; i++) {
            (bool _success, bytes memory data) = _transactions[i].to.call{value: _transactions[i].value}(_transactions[i].data);
            if (!_success) {
                revert TransactionFailed(_transactions[i].label);
            }
            returnData[i] = data;
        }
        vm.stopBroadcast();
        return (BundleStatus.EXECUTED, returnData);
    }
}
