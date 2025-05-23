# forge-deploy-lib

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
forge install your-org/forge-deploy-lib
```

## Usage

### Basic Deployment Script

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-deploy-lib/base/CreateXDeployment.sol";
import "../src/MyContract.sol";

contract DeployMyContract is CreateXDeployment {
    constructor() CreateXDeployment(
        "MyContract",
        "v1.0.0",
        _buildSaltComponents()
    ) {}
    
    function _buildSaltComponents() private view returns (string[] memory) {
        string[] memory components = new string[](3);
        components[0] = "MyContract";
        components[1] = "v1.0.0";
        components[2] = vm.envString("DEPLOYMENT_ENV");
        return components;
    }
    
    function getInitCode() internal pure override returns (bytes memory) {
        return abi.encodePacked(
            type(MyContract).creationCode,
            abi.encode("constructor", "args")
        );
    }
}
```

### Address Prediction

```solidity
// Use the PredictAddress script
forge script script/PredictAddress.s.sol \
    --sig "predict(string,string)" "MyContract" "staging"
```

## Base Contracts

### Operation

Base contract providing common deployment functionality:
- Environment setup
- Deployment file management  
- Private key handling

### CreateXDeployment

Enhanced deployment contract with CREATE2 support:
- Salt generation from components
- Address prediction
- Deployment verification
- Metadata recording

## Integration with fdeploy

This library is designed to work seamlessly with the `fdeploy` CLI tool for enhanced deployment orchestration and management.

## License

MIT