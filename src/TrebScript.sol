// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {CreateXScript} from "createx-forge/script/CreateXScript.sol";
import {Dispatcher} from "./internal/Dispatcher.sol";
import {Registry} from "./internal/Registry.sol";

import {PrivateKeySender} from "./internal/senders/PrivateKeySender.sol";
import {HardwareWalletSender} from "./internal/senders/HardwareWalletSender.sol";
import {SafeSender} from "./internal/senders/SafeSender.sol";


abstract contract TrebScript is Dispatcher, Registry {}