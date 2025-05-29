// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {CreateXScript} from "createx-forge/script/CreateXScript.sol";
import {Dispatcher} from "./internal/senders/Dispatcher.sol";
import {Registry} from "./internal/Registry.sol";

abstract contract Script is Dispatcher, Registry {

}