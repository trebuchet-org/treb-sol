# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is **treb-sol** - a Solidity library for deterministic smart contract deployments using CreateX. The library provides base contracts and utilities for creating deterministic deployments with comprehensive deployment tracking and registry integration. It's designed to work seamlessly with the `treb` CLI tool.

## Architecture

### Core Components

1. **Script Base Contract** (`src/Script.sol`): Combines CreateX functionality with deployment dispatch and registry capabilities
2. **Deployer** (`src/internal/Deployer.sol`): Handles CREATE2/CREATE3 deployments via CreateX with salt generation
3. **Registry** (`src/internal/Registry.sol`): Reads deployment addresses from `deployments.json` for cross-contract lookups
4. **Sender System** (`src/internal/senders/`): Modular transaction execution supporting multiple sender types (private key, hardware wallet, Safe multisig)
5. **LibraryDeployment** (`src/LibraryDeployment.sol`): Simplified deployment for Solidity libraries

### Key Patterns

- **Deterministic Addresses**: Uses CreateX factory with salt generation from contract name + namespace + optional label
- **Namespace-Aware**: Supports deployment namespaces (default, staging, production) for environment separation
- **Sender Abstraction**: Unified interface for different transaction execution methods (EOA, hardware wallet, Safe)
- **Registry Integration**: Automatic loading of deployment addresses from JSON registry

## Development Commands

### Building
```bash
forge build
```

### Testing
```bash
# Run all tests
forge test

# Run tests with gas reporting
forge test --gas-report

# Run specific test
forge test --match-test testDeployCounter

# Run tests with verbose output
forge test -vvv
```

### Deployment Scripts
```bash
# Deploy a contract (requires environment variables)
forge script script/deploy/DeployMyContract.s.sol --rpc-url $RPC_URL --broadcast

# Predict deployment address
forge script script/deploy/DeployMyContract.s.sol --sig "predictAddress()"
```

## Core Contracts

### Script.sol
Base contract that deployment scripts inherit from. Provides:
- Dispatcher for sender management
- Registry for deployment lookups
- Integration with CreateX

### Deployer.sol
Handles deployment logic:
- `deployCreate3(string what)`: Deploy using artifact path
- `deployCreate3(string what, bytes args)`: Deploy with constructor args
- `deployCreate2(...)`: CREATE2 variant methods
- `predictCreate3(bytes32 salt)`: Predict deployment address
- Salt generation with sender-specific encoding

### Registry.sol
Simplified on-chain registry for deployment lookups:
- `lookup(string identifier)`: Get deployment by identifier from current namespace
- `lookup(string identifier, string env)`: Get deployment from specific environment
- `lookup(string identifier, string env, string chainId)`: Full lookup with explicit chain ID
- Loads from `.treb/registry.json` at construction with flattened JSON structure

### Sender Types
- **PrivateKeySender**: Direct execution with private key
- **HardwareWalletSender**: Ledger/Trezor integration
- **SafeSender**: Safe multisig transaction batching
- All inherit from base `Sender` contract with unified interface

## Environment Variables

The library expects these environment variables:

```bash
# Required by Dispatcher
SENDER_CONFIGS=<encoded configs>  # ABI-encoded sender configurations

# Required by Registry
NAMESPACE=default                 # Deployment namespace (default/staging/production)

# Required by LibraryDeployment
LIBRARY_ARTIFACT_PATH=<path>      # Path to library artifact for deployment

# Used by deployment scripts
DEPLOYMENT_NAMESPACE=<namespace>  # Override namespace for deployment
DEPLOYMENT_LABEL=<label>          # Optional label for salt generation
```

## Salt Generation

Deterministic addresses use salt encoding:
```solidity
// Basic salt from entropy string
bytes32 salt = keccak256(abi.encodePacked(entropy));

// Sender-specific salt encoding (adds sender address + flags)
bytes32 derivedSalt = _derivedSalt(salt);
```

Salt includes:
- Sender address (20 bytes)
- Salt flag (1 byte: 0x00 or 0x01)
- Entropy hash (11 bytes)

## Registry Format

The `deployments.json` file structure:
```json
{
  "networks": {
    "31337": {
      "deployments": {
        "0x...": {
          "fqid": "31337/default/Counter",
          "sid": "Counter"
        }
      }
    }
  }
}
```

## Integration Notes

1. **No Direct Deployment**: This library is meant to be used through the treb CLI, not directly
2. **Structured Output**: Uses `console.log` for treb CLI parsing - do not modify log formats
3. **CreateX Dependency**: All deployments go through CreateX factory at `0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed`
4. **Registry Loading**: Registry loads at construction - ensure `.treb/registry.json` exists
5. **Sender Configuration**: Sender configs must be ABI-encoded and passed via environment variable

## Common Usage Patterns

### Inheriting from Script
```solidity
contract DeployMyContract is Script {
    function run() public {
        // Use sender() to get configured sender
        address deployed = sender("default").deployCreate3("MyContract");
        
        // Use registry to lookup dependencies
        address dependency = lookup("MyDependency");
    }
}
```

### Library Deployment
```solidity
contract DeployMyLibrary is LibraryDeployment {
    // LibraryDeployment handles everything
    // Just set LIBRARY_ARTIFACT_PATH environment variable
}
```

### Predictable Addresses
```solidity
// Predict before deployment
bytes32 salt = _salt("MyContract:v1");
address predicted = predictCreate3(salt);

// Deploy to predicted address
address actual = deployCreate3(salt, initCode);
require(predicted == actual);
```