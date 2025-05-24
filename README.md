# treb-sol

Foundry library for deterministic smart contract deployments with enhanced tracking and verification.

## Overview

This library provides base contracts and utilities for creating deterministic deployments using CREATE2, with comprehensive deployment tracking and verification capabilities.

## Features

- 🎯 **Deterministic Deployments**: CREATE2-based deployments with predictable addresses
- 📊 **Enhanced Tracking**: Comprehensive deployment metadata recording
- 🔍 **Address Prediction**: Predict addresses before deployment
- 🛠️ **Base Contracts**: Extensible base contracts for custom deployment scripts
- 📝 **JSON Registry**: Structured deployment information storage

## Installation

```bash
forge install trebuchet-org/treb-sol
```

## Usage

### Basic Deployment Script

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "treb-sol/CreateXDeployment.sol";
import "src/Counter.sol";

/**
 * @title DeployCounter
 * @notice Deployment script for Counter contract
 * @dev Generated automatically by treb
 */
contract DeployCounter is CreateXDeployment {
    constructor() CreateXDeployment(
        "Counter",
        DeploymentType.IMPLEMENTATION,
        DeployStrategy.CREATE3
    ) {}

    /// @notice Get contract bytecode using type().creationCode
    function getContractBytecode() internal pure override returns (bytes memory) {
        return type(Counter).creationCode;
    }
}
```

### Address Prediction

```solidity
// Use the PredictAddress script
forge script script/deploy/DeployCounter.s.sol --sig "predictAddress()"
```

## Base Contracts

### CreateXDeployment

Enhanced deployment contract with CREATE2 support:
- Salt generation from components
- Address prediction
- Deployment verification
- Metadata recording

### Executor



## Integration with `treb`

This library is designed to work seamlessly with the `treb` CLI tool for enhanced deployment orchestration and management.
See [treb-cli](https://github.com/trebuchet-org/treb-cli).

## License

MIT