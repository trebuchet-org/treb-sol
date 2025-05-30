# INTEGRATION.md - Transaction Ordering and Event Architecture

## Overview

The treb-sol library has been refactored to provide a clear separation between synchronous and asynchronous transaction execution, with proper ordering guarantees and a unified event system based on transaction IDs rather than bundle IDs.

## Key Architectural Changes

### 1. Global Transaction Queue

All transactions are now queued globally in the order they are simulated:

```solidity
struct Registry {
    // ... other fields ...
    RichTransaction[] globalQueue;
    uint256 transactionCounter;
    bytes32 currentTransactionId;
}
```

This ensures that transaction ordering is preserved across all senders during broadcast.

### 2. Transaction ID System

Each transaction now gets a unique ID when simulated:

```solidity
struct RichTransaction {
    Transaction transaction;
    bytes32 transactionId;      // Unique ID for this transaction
    bytes32 senderId;           // Which sender will execute this
    TransactionStatus status;    // PENDING -> EXECUTED/QUEUED
    bytes simulatedReturnData;
    bytes executedReturnData;
}
```

Transaction IDs are generated using:
```solidity
keccak256(abi.encodePacked(block.chainid, block.timestamp, transactionCounter))
```

### 3. Transaction Flow

#### Simulation Phase
1. Transactions are simulated in the order they are called
2. Each transaction gets a unique `transactionId` 
3. Status is set to `PENDING`
4. Transaction is added to the global queue
5. `TransactionSimulated` event is emitted with the transaction ID

#### Broadcast Phase
1. The global queue is processed in order
2. For each transaction:
   - **Synchronous senders (PrivateKey)**: Execute immediately, emit `TransactionBroadcast`, status -> `EXECUTED`
   - **Asynchronous senders (GnosisSafe)**: Queue for batch, status -> `QUEUED`
3. After all sync transactions, async senders broadcast their batches and emit `SafeTransactionQueued`

### 4. Event Structure

#### During Simulation

```solidity
event TransactionSimulated(
    bytes32 indexed transactionId,
    address indexed sender,
    address indexed to,
    uint256 value,
    bytes data,
    string label,
    bytes returnData
);

event TransactionFailed(
    bytes32 indexed transactionId,
    address indexed sender,
    address indexed to,
    uint256 value,
    bytes data,
    string label
);
```

#### During Broadcast

For synchronous execution:
```solidity
event TransactionBroadcast(
    bytes32 indexed transactionId,
    address indexed sender,
    address indexed to,
    uint256 value,
    bytes data,
    string label,
    bytes returnData
);
```

For asynchronous queuing:
```solidity
event SafeTransactionQueued(
    bytes32 indexed safeTxHash,
    address indexed safe,
    address indexed proposer,
    RichTransaction[] transactions
);
```

#### Contract Deployments

```solidity
event ContractDeployed(
    address indexed deployer,
    address indexed location,
    bytes32 indexed transactionId,  // Links to the transaction that deployed
    EventDeployment deployment
);
```

### 5. Key Benefits

1. **Order Preservation**: Transactions execute in the exact order they were simulated
2. **Transaction Traceability**: Every operation can be traced back to its transaction ID
3. **Clear Sync/Async Separation**: Different event types for different execution models
4. **No Bundle ID Confusion**: Bundle IDs are removed in favor of transaction IDs and Safe transaction hashes

### 6. CLI Integration Points

The CLI should:

1. **Listen for Events**:
   - `TransactionSimulated`: Track all simulated transactions
   - `TransactionBroadcast`: Mark sync transactions as executed
   - `SafeTransactionQueued`: Track async transactions and their Safe tx hash
   - `ContractDeployed`: Link deployments to their transaction IDs

2. **Transaction Tracking**:
   ```go
   type Transaction struct {
       ID            string // bytes32 as hex
       Status        string // PENDING, EXECUTED, QUEUED
       Sender        string
       To            string
       Data          string
       Value         string
       Label         string
       ReturnData    string
       SafeTxHash    string // Only for QUEUED transactions
   }
   ```

3. **Deployment Registry**:
   - Store transaction ID with each deployment
   - Can trace back to see the exact transaction that deployed a contract

### 7. Example Flow

```solidity
// Simulation phase
deployer.deployCounter();     // txId: 0x123..., status: PENDING
safe.deployToken();          // txId: 0x456..., status: PENDING  
deployer.deployFactory();    // txId: 0x789..., status: PENDING

// Broadcast phase (in order)
// 1. Process txId 0x123... (deployer/sync) -> EXECUTED, emit TransactionBroadcast
// 2. Process txId 0x456... (safe/async) -> QUEUED, accumulate
// 3. Process txId 0x789... (deployer/sync) -> EXECUTED, emit TransactionBroadcast
// 4. Broadcast safe batch -> emit SafeTransactionQueued with [txId: 0x456...]
```

### 8. Migration Notes

- Remove any references to `bundleId` in favor of `transactionId`
- Update event listeners to handle new event signatures
- Transaction status tracking is now critical for understanding execution state
- Safe transactions will have both a `transactionId` and a `safeTxHash`