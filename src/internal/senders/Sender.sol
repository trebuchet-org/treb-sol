// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Deployer} from "../Deployer.sol";
import {Transaction, OperationResult} from "../types.sol";

abstract contract Sender is Deployer {
    bool public immutable isPrivateKey = false;
    bool public immutable isHardwareWallet = false;
    bool public immutable isLedger = false;
    bool public immutable isTrezor = false;
    bool public immutable isSafe = false;

    error TransactionFailed(string label);

    event OperationSent(
        address indexed sender,
        bytes32 indexed operationId,
        Transaction[] transactions,
        OperationResult result
    );

    address public immutable sender;

    function getSender() internal pure virtual returns (address) {
        return sender;
    }

    function execute(bytes32 operationId, Transaction[] memory _transactions) public virtual returns (OperationResult memory result);

    function execute(Transaction[] memory _transactions) public returns (OperationResult memory result) {
        bytes32 operationId = keccak256(abi.encode(block.timestamp, sender, _transactions));
        return execute(operationId, _transactions);
    }

    function execute(Transaction memory _transaction) public returns (OperationResult memory result) {
        Transaction[] memory transactions = new Transaction[](1);
        transactions[0] = _transaction;
        return execute(transactions);
    }
}