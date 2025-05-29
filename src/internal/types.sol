// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

struct Transaction {
    string label;
    address to;
    bytes data;
    uint256 value;
}

enum OperationStatus {
    QUEUED,
    EXECUTED
}

struct OperationResult {
    OperationStatus status;
    bytes[] returnData;
}
