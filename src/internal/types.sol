// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

struct Transaction {
    string label;
    address to;
    bytes data;
    uint256 value;
}

enum BundleStatus {
    QUEUED,
    EXECUTED
}

struct BundleTransaction {
    bytes32 txId;
    bytes32 bundleId;
    Transaction transaction;
    bytes simulatedReturnData;
    bytes executedReturnData;
}
