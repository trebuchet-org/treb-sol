// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title ExampleContract
 * @notice A simple contract for demonstrating treb-sol deployment capabilities
 * @dev This contract includes ownership functionality to demonstrate Safe multisig workflows
 */
contract ExampleContract {
    address public owner;
    string public name;
    uint256 public value;
    
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event NameSet(string newName);
    event ValueSet(uint256 newValue);
    
    modifier onlyOwner() {
        require(msg.sender == owner, "Not the owner");
        _;
    }
    
    constructor(address _owner, string memory _name) {
        owner = _owner;
        name = _name;
        emit OwnershipTransferred(address(0), _owner);
    }
    
    /**
     * @notice Transfer ownership to a new address
     * @param newOwner The address to transfer ownership to
     */
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "New owner cannot be zero address");
        address previousOwner = owner;
        owner = newOwner;
        emit OwnershipTransferred(previousOwner, newOwner);
    }
    
    /**
     * @notice Set the contract name (owner only)
     * @param _name The new name for the contract
     */
    function setName(string memory _name) external onlyOwner {
        name = _name;
        emit NameSet(_name);
    }
    
    /**
     * @notice Set a value (owner only)
     * @param _value The new value to set
     */
    function setValue(uint256 _value) external onlyOwner {
        value = _value;
        emit ValueSet(_value);
    }
    
    /**
     * @notice Get contract information
     * @return The current owner, name, and value
     */
    function getInfo() external view returns (address, string memory, uint256) {
        return (owner, name, value);
    }
}