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

struct RichTransaction {
    Transaction transaction;
    bytes simulatedReturnData;
    bytes executedReturnData;
}

library SenderTypes {
    bytes8 constant Custom = bytes8(keccak256("custom"));
    bytes8 constant PrivateKey = bytes8(keccak256("private-key"));
    bytes8 constant InMemory = bytes8(keccak256("in-memory")) | PrivateKey;
    bytes8 constant Multisig = bytes8(keccak256("multisig"));
    bytes8 constant GnosisSafe = Multisig | bytes8(keccak256("gnosis-safe"));
    bytes8 constant HardwareWallet = bytes8(keccak256("hardware-wallet")) | PrivateKey;
    bytes8 constant Ledger = bytes8(keccak256("ledger")) | HardwareWallet;
    bytes8 constant Trezor = bytes8(keccak256("trezor")) | HardwareWallet;
}

