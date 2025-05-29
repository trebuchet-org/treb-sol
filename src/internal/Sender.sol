// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {CommonBase} from "forge-std/Base.sol";
import {Deployer} from "./Deployer.sol";
import {Harness} from "./Harness.sol";
import {Transaction, BundleStatus, BundleTransaction} from "./types.sol";


abstract contract Sender is CommonBase {
    error TransactionFailed(string label);
    error TransactionExecutionMismatch(string label, bytes returnData);

    event BundleSent(
        address indexed sender,
        bytes32 indexed bundleId,
        BundleStatus status,
        BundleTransaction[] transactions
    );

    address public immutable senderAddress;
    Deployer public immutable deployer;

    BundleTransaction[] private currentBundle;
    uint256 private bundleIndex;
    mapping(address => address) private harnesses;
    uint256 private simulationForkId;
    uint256 private executionForkId;

    constructor(address _sender) {
        senderAddress = _sender;
        deployer = new Deployer(this);
        vm.allowCheatcodes(address(deployer));
        vm.makePersistent(address(deployer));
    }

    function initialize(uint256 _simulationForkId, uint256 _executionForkId) public {
        simulationForkId = _simulationForkId;
        executionForkId = _executionForkId;
    }

    function senderType() public virtual pure returns (bytes4);

    function isType(string memory _type) public virtual pure returns (bool) {
        return senderType() == bytes4(keccak256(abi.encodePacked(_type)));
    }

    function harness(address _target) public returns (address) {
        if (harnesses[_target] == address(0)) {
            harnesses[_target] = address(new Harness(_target, this));
            vm.makePersistent(harnesses[_target]);
            vm.allowCheatcodes(harnesses[_target]);
        }
        return harnesses[_target];
    }

    function _execute(Transaction[] memory _simulatedTransactions) internal virtual returns (BundleStatus status, bytes[] memory returnDatas);

    function execute(Transaction[] memory _transactions) public returns (BundleTransaction[] memory bundleTransactions) {
        bundleTransactions = _simulate(_transactions);
        _queue(bundleTransactions);
        return bundleTransactions;
    }

    function execute(Transaction memory _transaction) public virtual returns (BundleTransaction memory bundleTransaction) {
        Transaction[] memory transactions = new Transaction[](1);
        transactions[0] = _transaction;
        BundleTransaction[] memory bundleTransactions = execute(transactions);
        return bundleTransactions[0];
    }

    function _queue(BundleTransaction[] memory _bundleTransactions) internal {
        for (uint256 i = 0; i < _bundleTransactions.length; i++) {
            currentBundle.push(_bundleTransactions[i]);
        }
    }

    function flushBundle() public returns (bytes32 bundleId) {
        require(vm.activeFork() == executionForkId, "Sender: Not in execution fork");
        bundleId = currentBundleId();

        Transaction[] memory transactions = new Transaction[](currentBundle.length);
        for (uint256 i = 0; i < currentBundle.length; i++) {
            transactions[i] = currentBundle[i].transaction;
        }

        (BundleStatus status, bytes[] memory returnData) = _execute(transactions);
        if (status == BundleStatus.EXECUTED) {
            for (uint256 i = 0; i < returnData.length; i++) {
                if (keccak256(currentBundle[i].simulatedReturnData) != keccak256(returnData[i])) {
                    revert TransactionExecutionMismatch(currentBundle[i].transaction.label, returnData[i]);
                }
                currentBundle[i].executedReturnData = returnData[i];
            }
        }

        emit BundleSent(
            senderAddress,
            bundleId,
            status,
            currentBundle
        );

        delete currentBundle;
        bundleIndex++;
        return bundleId;
    }

    function _simulate(Transaction[] memory _transactions) internal returns (BundleTransaction[] memory bundleTransactions) {
        require(vm.activeFork() == simulationForkId, "Sender: Not in simulation fork");
        bundleTransactions = new BundleTransaction[](_transactions.length);
        for (uint256 i = 0; i < _transactions.length; i++) {
            vm.prank(senderAddress);
            (bool success, bytes memory returnData) = _transactions[i].to.call{value: _transactions[i].value}(_transactions[i].data);
            if (!success) {
                revert TransactionFailed(_transactions[i].label);
            }
            bundleTransactions[i] = BundleTransaction({
                txId: txId(i),
                bundleId: currentBundleId(),
                transaction: _transactions[i],
                simulatedReturnData: returnData,
                executedReturnData: new bytes(0)
            });
        }
        return bundleTransactions;
    }

    function currentBundleId() public view returns (bytes32) {
        return keccak256(abi.encode(block.chainid, block.timestamp, senderAddress, bundleIndex));
    }

    function txId(uint256 _index) public view returns (bytes32) {
        return keccak256(abi.encode(currentBundleId(), currentBundle.length + _index));
    }
}
