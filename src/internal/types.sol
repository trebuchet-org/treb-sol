// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

struct Transaction {
    string label;
    address to;
    bytes data;
    uint256 value;
}

struct SimulatedTransaction {
    bytes32 transactionId;
    bytes32 senderId;
    address sender;
    bytes returnData;
    Transaction transaction;
}

library SenderTypes {
    bytes8 internal constant Custom = bytes8(keccak256("custom"));
    bytes8 internal constant PrivateKey = bytes8(keccak256("private-key"));
    bytes8 internal constant InMemory = bytes8(keccak256("in-memory")) | PrivateKey;
    bytes8 internal constant Multisig = bytes8(keccak256("multisig"));
    bytes8 internal constant GnosisSafe = Multisig | bytes8(keccak256("gnosis-safe"));
    bytes8 internal constant HardwareWallet = bytes8(keccak256("hardware-wallet")) | PrivateKey;
    bytes8 internal constant Ledger = bytes8(keccak256("ledger")) | HardwareWallet;
    bytes8 internal constant Trezor = bytes8(keccak256("trezor")) | HardwareWallet;
}
