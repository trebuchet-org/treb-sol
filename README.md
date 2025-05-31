# treb-sol

A powerful Solidity library for deterministic smart contract deployments with multi-sender coordination, hardware wallet support, and Safe multisig integration.

## Overview

**treb-sol** provides a sophisticated framework for writing deployment scripts that can execute transactions through different wallet types while maintaining deterministic addresses across chains. Unlike traditional deployment tools, treb-sol allows you to write arbitrary scripts with automatic transaction coordination and broadcasting.

## Key Features

- 🎯 **Deterministic Deployments**: CreateX-based deployments with predictable addresses
- 🔄 **Multi-Sender Coordination**: Unified interface for EOA, hardware wallets, and Safe multisig
- 🛡️ **Transaction Batching**: Automatic batching for Safe multisig efficiency
- 🔍 **Address Prediction**: Predict deployment addresses before execution
- 📚 **Registry Integration**: Lookup previously deployed contracts across environments
- 🧪 **Harness System**: Secure proxy-based contract interaction
- 🏗️ **Flexible Scripting**: Write arbitrary deployment logic with automatic broadcasting

## Installation

```bash
forge install trebuchet-org/treb-sol
```

## Architecture

The library is built around three core concepts:

1. **Sender Abstraction**: Unified interface for different wallet types
2. **Global Transaction Queue**: Maintains execution order across different senders
3. **Harness System**: Secure proxy-based contract interaction

## Quick Start

### Basic Deployment Script (with treb-cli)

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {TrebScript} from "treb-sol/TrebScript.sol";
import {Deployer} from "treb-sol/internal/sender/Deployer.sol";

contract DeployCounter is TrebScript {
    using Deployer for Senders.Sender;
    using Deployer for Deployer.Deployment;
    

    function run() public broadcast {
        // Get default sender
        Senders.Sender storage deployer = sender("default");
        
        // Deploy contract with deterministic address
        address counter = deployer.create3("Counter").deploy();
        
        console.log("Counter deployed at:", counter);
    }
}
```

### Standalone Usage (without treb-cli)

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ConfigurableTrebScript} from "treb-sol/TrebScript.sol";
import {Deployer} from "treb-sol/internal/sender/Deployer.sol";
import {Senders} from "treb-sol/internal/sender/Senders.sol";
import {SenderTypes} from "treb-sol/internal/types.sol";

contract StandaloneDeployment is ConfigurableTrebScript {
    using Deployer for Senders.Sender;

    constructor() ConfigurableTrebScript(
        _getSenderConfigs(),     // Custom sender configuration
        "production",            // Namespace
        "deployments.json",      // Registry file
        false                    // Not dry run
    ) {}

    function _getSenderConfigs() internal pure returns (Senders.SenderInitConfig[] memory) {
        Senders.SenderInitConfig[] memory configs = new Senders.SenderInitConfig[](1);
        
        configs[0] = Senders.SenderInitConfig({
            name: "deployer",
            account: 0xYourDeployerAddress,
            senderType: SenderTypes.InMemory,
            config: abi.encode(0xYourPrivateKey)
        });
        
        return configs;
    }

    function run() public broadcast {
        Senders.Sender storage deployer = sender("deployer");
        address counter = deployer.create3("Counter").deploy();
        console.log("Counter deployed at:", counter);
    }
}
```

### Multi-Contract Deployment

```solidity
contract DeploySystem is TrebScript {
    using Deployer for Senders.Sender;

    function run() public broadcast {
        Senders.Sender storage deployer = sender("default");
        
        // Deploy contracts in order
        address token = deployer.create3("Token").deploy();
        address vault = deployer.create3("Vault").deploy(abi.encode(token));
        address router = deployer.create3("Router").deploy(abi.encode(vault, token));
        
        // All transactions are automatically broadcast at the end
    }
}
```

## Base Contracts

### TrebScript vs ConfigurableTrebScript

**treb-sol** provides two base contracts for different usage scenarios:

#### TrebScript
- **Use case**: Integration with treb-cli
- **Configuration**: Reads from environment variables automatically
- **Best for**: Production deployments managed by treb-cli

#### ConfigurableTrebScript  
- **Use case**: Standalone usage without treb-cli
- **Configuration**: Manual configuration via constructor parameters
- **Best for**: Testing, custom deployment frameworks, standalone usage

```solidity
// With treb-cli (environment variables)
contract MyDeployment is TrebScript {
    // Automatically reads SENDER_CONFIGS, NAMESPACE, etc.
}

// Standalone (manual configuration)
contract MyDeployment is ConfigurableTrebScript {
    constructor() ConfigurableTrebScript(
        _getSenderConfigs(),    // Define your own configs
        "production",          // Explicit namespace
        "registry.json",       // Explicit registry file
        false                  // Explicit dry-run setting
    ) {}
}
```

### Complete Example

See `script/ExampleDeploy.sol` for a comprehensive example demonstrating:
- Safe multisig + proposer configuration
- Contract deployment with ownership transfer
- Safe transaction execution through harness system

## Sender Types

### Development Setup (Private Keys)

```solidity
// Environment variables
SENDER_CONFIGS = <abi-encoded configs>
NAMESPACE = "default"
DRYRUN = false

// Sender config for development
{
    name: "default",
    account: 0x...,
    senderType: "in-memory",
    config: abi.encode(privateKey)
}
```

### Production Setup (Hardware Wallet + Safe)

```solidity
// Hardware wallet as proposer
{
    name: "proposer", 
    account: 0x...,
    senderType: "ledger",
    config: abi.encode("m/44'/60'/0'/0/0")
}

// Safe multisig with hardware wallet proposer
{
    name: "default",
    account: 0x..., // Safe address
    senderType: "gnosis-safe", 
    config: abi.encode("proposer") // references proposer sender
}
```

## Transaction Execution

### Direct Transaction Execution

```solidity
contract CustomDeployment is TrebScript {
    function run() public broadcast {
        Senders.Sender storage deployer = sender("default");
        
        // Execute arbitrary transaction
        Transaction memory tx = Transaction({
            to: someContract,
            data: abi.encodeWithSignature("initialize(address)", owner),
            value: 0,
            label: "initialize-contract"
        });
        
        RichTransaction memory result = deployer.execute(tx);
        console.logBytes(result.simulatedReturnData);
    }
}
```

### Using Contract Harness

```solidity
contract InteractWithContracts is TrebScript {
    function run() public broadcast {
        Senders.Sender storage deployer = sender("default");
        
        // Get harness for existing contract
        address counterAddr = lookup("Counter");
        Counter counter = Counter(deployer.harness(counterAddr));
        
        // Interact through harness - transactions are queued
        counter.increment();
        counter.setName("My Counter");
        
        // All harness calls are broadcast automatically
    }
}
```

## Registry Integration

### Cross-Environment Lookups

```solidity
contract CrossEnvDeployment is TrebScript {
    function run() public broadcast {
        // Reference production token while deploying to staging
        address prodToken = lookup("Token", "production");
        
        // Deploy staging vault that references production token
        address vault = sender("default")
            .create3("Vault")
            .deploy(abi.encode(prodToken));
    }
}
```

### Cross-Chain References

```solidity
contract CrossChainSetup is TrebScript {
    function run() public broadcast {
        // Reference mainnet deployment while on testnet
        address mainnetBridge = lookup("Bridge", "production", "1");
        
        // Deploy testnet side with mainnet reference
        address testnetBridge = sender("default")
            .create3("TestnetBridge") 
            .deploy(abi.encode(mainnetBridge));
    }
}
```

## Advanced Patterns

### Labeled Deployments

```solidity
contract VersionedDeployment is TrebScript {
    function run() public broadcast {
        Senders.Sender storage deployer = sender("default");
        
        // Deploy different versions
        address v1 = deployer.create3("Token").setLabel("v1").deploy();
        address v2 = deployer.create3("Token").setLabel("v2").deploy();
        
        // Each gets a unique address based on label
    }
}
```

### Custom Entropy

```solidity
contract CustomAddresses is TrebScript {
    function run() public broadcast {
        Senders.Sender storage deployer = sender("default");
        
        // Use custom entropy for specific address
        bytes memory bytecode = vm.getCode("SpecialContract");
        address special = deployer
            .create3("SpecialContract"),
            .setEntropy("special-deployment-2024")
            .deploy();
    }
}
```

### Conditional Deployments

```solidity
contract ConditionalDeployment is TrebScript {
    function run() public broadcast {
        Senders.Sender storage deployer = sender("default");
        
        // Check if already deployed
        address existing = lookup("UpgradeableProxy");
        
        if (existing == address(0)) {
            // First time deployment
            address impl = deployer.create3("Implementation").deploy();
            address proxy = deployer.create3("UpgradeableProxy").deploy(abi.encode(impl));
        } else {
            // Upgrade existing
            address newImpl = deployer.create3("Implementation").setLabel("v2").deploy();
            
            UpgradeableProxy(deployer.harness(existing)).upgradeTo(newImpl);
        }
    }
}
```

## Testing and Debugging

### Dry Run Mode

```bash
# Set environment for dry run
export DRYRUN=true

# Run script without executing transactions
forge script script/Deploy.s.sol
```

### Address Prediction

```solidity
contract PredictAddresses is TrebScript {
    function predict() public view {
        // Predict address before deployment
        bytes32 salt = keccak256(abi.encodePacked("default/Counter"));
        address predicted = CREATEX.computeCreate3Address(salt);
        
        console.log("Counter will deploy to:", predicted);
    }
}
```

### Testing with Multiple Senders

```solidity
contract TestMultiSender is TrebScript {
    function run() public broadcast {
        // Use different senders for different operations
        address adminContract = sender("admin").create3("AdminContract").deploy();
        address userContract = sender("user").create3("UserContract").deploy();
        
        // Admin operations through admin sender
        AdminContract(sender("admin").harness(adminContract)).setConfig();
        
        // User operations through user sender  
        UserContract(sender("user").harness(userContract)).interact();
    }
}
```

## Environment Configuration

### Development (.env)

```bash
# Simple development setup
SENDER_CONFIGS=0x0000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000080000000000000000000000000f39fd6e51aad88f6f4ce6ab8827279cfffb92266000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000c0000000000000000000000000000000000000000000000000000000000000000764656661756c7400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000ac18b2c3e86929874e04ba4ac0c3b92ef2a5e6d8c1405c7e86ba3b5b5720d
NAMESPACE=default
```

### Production (.env)

```bash
# Hardware wallet + Safe setup
SENDER_CONFIGS=<complex-abi-encoded-safe-config>
NAMESPACE=production
DEPLOYER_DERIVATION_PATH=m/44'/60'/0'/0/0
SAFE_ADDRESS=0x32CB58b145d3f7e28c45cE4B2Cc31fa94248b23F
```

## Integration with treb CLI

While treb-sol can be used standalone, it's designed to work seamlessly with the [treb CLI](https://github.com/trebuchet-org/treb-cli):

- **Registry Management**: Automatic registry updates from script output
- **Environment Coordination**: Consistent namespace and configuration management  
- **Verification**: Automatic contract verification on block explorers
- **Multi-chain Orchestration**: Deploy to multiple chains with shared configuration

## Best Practices

### 1. Use Descriptive Labels

```solidity
// Good: Clear versioning
address tokenV2 = deployer.create3("Token").setLabel("v2").deploy();

// Bad: Unclear purpose  
address token2 = deployer.create3("Token").setLabel("new").deploy();
```

### 2. Handle Missing Dependencies

```solidity
address dependency = lookup("RequiredContract");
require(dependency != address(0), "Required contract not deployed");
```

### 3. Organize Complex Deployments

```solidity
contract SystemDeployment is TrebScript {
    function run() public broadcast {
        deployCore();
        deployPeripherals(); 
        configureSystem();
    }
    
    function deployCore() internal {
        // Core contract deployments
    }
    
    function deployPeripherals() internal {
        // Peripheral contracts
    }
    
    function configureSystem() internal {
        // System configuration
    }
}
```

### 4. Use Safe Defaults

```solidity
// Use CREATE3 for flexibility (can upgrade later)
address contract = deployer.create3("Contract").deploy();

// Use CREATE2 only when you need deterministic init code
address factory = deployer.create2("Factory").deploy();
```

## API Reference

### Core Contracts

- **TrebScript**: Base contract for treb-cli managed deployment scripts
- **ConfigurableTrebScript**: Base contract for standalone deployment scripts
- **SenderCoordinator**: Manages multiple transaction senders  
- **Registry**: Deployment address lookup system
- **Deployer**: CreateX-based deterministic deployments
- **Senders**: Low-level sender abstraction library

### Key Functions

- `sender(name)`: Get sender by name
- `lookup(identifier)`: Look up deployed contract address
- `harness(target)`: Get harness proxy for contract interaction
- `create3(artifact)`: Create CREATE3 deployment
- `create2(artifact)`: Create CREATE2 deployment
- `broadcast`: Modifier for automatic transaction broadcasting

## License

MIT
