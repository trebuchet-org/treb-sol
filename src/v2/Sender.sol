// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Re-export Senders so that importing this file brings in the Sender UDVT
// and its globally-attached methods (addr, broadcast, startBroadcast, stopBroadcast).
import {Senders} from "./internal/sender/Senders.sol";
