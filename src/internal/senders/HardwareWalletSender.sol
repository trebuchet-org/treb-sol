// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {PrivateKeySender} from "./PrivateKeySender.sol";

/**
 * @title HardwareWalletSender
 * @author @treb-sol
 * @notice Sender for hardware wallets
 * Right now this a no-op because foundry handles loading of hardware wallets by passing the derivation path to the script.
 * However, the limitation is that we can't have both trezeor and ledger hardware wallets in the same script. 
 * Potential workaround is to use `cast sign` via FFI for that, but it's probably not worth the effort.
 */

abstract contract HardwareWalletSender is PrivateKeySender {
    string public derivationPath;

    constructor(address _sender, uint256 _mnemonicIndex, string memory _derivationPath) PrivateKeySender(_sender, _mnemonicIndex) {
        isHardwareWallet = true;
        derivationPath = _derivationPath;
    }
}

contract LedgerSender is HardwareWalletSender {
    constructor(address _sender, uint256 _mnemonicIndex, string memory _derivationPath) HardwareWalletSender(_sender, _mnemonicIndex, _derivationPath) {
        isLedger = true;
    }
}

contract TrezorSender is HardwareWalletSender {
    constructor(address _sender, uint256 _mnemonicIndex, string memory _derivationPath) HardwareWalletSender(_sender, _mnemonicIndex, _derivationPath) {
        isTrezor = true;
    }
}