# treb-sol

Solidity library for deterministic smart contract deployments using CreateX with structured logging and registry integration.

## Overview

This library provides base contracts and utilities for creating deterministic deployments using CreateX, with comprehensive deployment tracking and verification capabilities. It's designed to work seamlessly with the `treb` CLI tool.

## Features

- 🎯 **Deterministic Deployments**: CreateX-based deployments with predictable addresses across chains
- 📊 **Console Output Parsing**: Structured console.log output for treb CLI parsing
- 🔍 **Address Prediction**: Predict addresses before deployment
- 🛠️ **Multiple Strategies**: Support for CREATE2, CREATE3, and proxy deployment patterns
- 📚 **Library Support**: Base contracts for library deployments
- 🏭 **Proxy Support**: ERC1967 proxy deployment with upgrade capabilities

## Installation

```bash
forge install trebuchet-org/treb-sol
```

## Usage

### Basic Implementation Deployment

**Note:** You don't write these scripts manually. Use `treb gen deploy <contract>` to generate them automatically.

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Deployment, DeployStrategy} from "treb-sol/Deployment.sol";

/**
 * @title DeployMyToken
 * @notice Deployment script for MyToken contract
 * @dev Generated automatically by treb
 */
contract DeployMyToken is Deployment {
    constructor() Deployment(
        "src/tokens/MyToken.sol:MyToken",
        DeployStrategy.CREATE3
    ) {}

    /// @notice Get constructor arguments
    function _getConstructorArgs() internal pure override returns (bytes memory) {
        // Constructor arguments detected from ABI
        string memory _name = "";
        string memory _symbol = "";
        uint256 _totalSupply = 0;
        return abi.encode(_name, _symbol, _totalSupply);
    }
}
```

Generated with:
```bash
treb gen deploy MyToken
```

### Proxy Deployment

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ProxyDeployment, DeployStrategy} from "treb-sol/ProxyDeployment.sol";
import {UpgradeableCounter} from "../../src/UpgradeableCounter.sol";

contract DeployUpgradeableCounterProxy is ProxyDeployment {
    constructor() ProxyDeployment(
        "UpgradeableCounter",
        DeployStrategy.CREATE3
    ) {}

    function deployImplementation() internal override returns (address) {
        return address(new UpgradeableCounter());
    }

    function getInitializationData() internal pure override returns (bytes memory) {
        return abi.encodeWithSignature("initialize()");
    }
}
```

### Library Deployment

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {LibraryDeployment} from "treb-sol/LibraryDeployment.sol";
import {StringUtils} from "../../src/StringUtils.sol";

contract DeployStringUtils is LibraryDeployment {
    constructor() LibraryDeployment() {}

    function deployLibrary() internal override returns (address) {
        return address(new StringUtils());
    }
}
```

## Base Contracts

### Deployment

The core base contract for standard implementation deployments:
- Handles salt generation from contract name, environment, and label
- Integrates with CreateX for deterministic addresses
- Provides structured console output for treb CLI parsing
- Supports both CREATE2 and CREATE3 strategies

### ProxyDeployment

Extended deployment contract for proxy patterns:
- Deploys implementation contracts
- Deploys and initializes ERC1967 proxies
- Handles upgrade scenarios with existing implementations
- Links proxy to implementation in registry

### LibraryDeployment

Specialized deployment for libraries:
- Simplified deployment flow for libraries
- No environment-specific deployment (libraries are global per chain)
- Optimized for library linking and reuse

## Core Features

### Salt Generation

Deterministic addresses are generated using:
```solidity
bytes32 salt = keccak256(abi.encodePacked(contractName, environment, label));
```

- **Contract Name**: Ensures different contracts get different addresses
- **Environment**: Separates staging/production deployments (default: "default")
- **Label**: Optional versioning for same contract/environment (default: "")

### Output Parsing

treb parses the forge script output to extract deployment information. The base contracts use `console.log` statements with structured formats that treb can parse to update the deployment registry.

### CreateX Integration

Built on top of CreateX factory for deterministic deployments:
- CREATE2: Traditional deterministic deployment
- CREATE3: Proxy-based deployment with more flexibility

## Environment Variables

The contracts expect certain environment variables to be set by treb:

- `DEPLOYMENT_NAMESPACE`: Deployment namespace (default, staging, production, etc.)
- `DEPLOYMENT_LABEL`: Optional label for versioning
- `DEPLOYER_ADDRESS`: Address of the deployer for access control

## Integration with treb CLI

This library is designed to work with the [treb CLI](https://github.com/trebuchet-org/treb-cli):

1. **Script Generation**: treb generates deployment scripts using these base contracts via `treb gen deploy`
2. **Output Parsing**: treb parses the forge script console output to update the deployment registry
3. **Library Resolution**: treb automatically detects and deploys required libraries
4. **Address Prediction**: treb uses the same salt generation for address prediction

## Development

### Testing

```bash
# Run tests
forge test

# Run tests with gas reporting
forge test --gas-report

# Run specific test
forge test --match-test testDeployCounter
```

### Address Prediction

```bash
# Predict address using treb CLI
treb deploy Counter --predict

# Or use forge script directly
forge script script/deploy/DeployCounter.s.sol --sig "predictAddress()"
```

## Examples

See the test contracts in `test/` for complete examples of:
- Basic contract deployment
- Proxy deployment with upgrades
- Library deployment and linking
- Multi-contract deployment scenarios

## License

MIT