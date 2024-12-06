// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "@openzeppelin/contracts/access/Ownable.sol";
import "hardhat/console.sol";

contract SubmissionManager is Ownable {

    struct Record {
        uint256 recordId;
        address assignedTo;
        uint256 assignedAt;
        address[] submissions;
    }

    uint256 public nextAvailableRecord = 1;
    uint256[] public activeRecordIds;
    mapping(uint256 => Record) public records;
    address public campaign;

    event RecordAssigned(uint256 indexed recordId, address indexed crowdsourcer);

    constructor(address _campaign) {
        campaign = _campaign;
    }

    modifier onlyCampaign() {
        require(msg.sender == campaign, "Only the Campaign contract can call this");
        _;
    }

    /*
    function getBounty() public {
        console.log("Hello, world!");
        // User can only work on one bounty at a time.
        // Check if user is currently assigned a bounty.
        for (uint256 i = 0; i < activeRecordIds.length; i++) {
            uint256 recordId = activeRecordIds[i];
            Record storage record = records[recordId];

            if (record.assignedTo == address(0) && !hasSubmitted(record, msg.sender)) {
                // Assign this existing record to the crowdsourcer
                record.assignedTo = msg.sender;
                record.assignedAt = block.timestamp;

                emit RecordAssigned(recordId, msg.sender);
                return;
            }
        }

        // Assign new bounty
        uint256 newRecordId = nextAvailableRecord;
        nextAvailableRecord++;

        records[newRecordId] = Record({
            recordId: newRecordId,
            assignedTo: msg.sender,
            assignedAt: block.timestamp,
            submissions: new address[](0)
        });

        activeRecordIds.push(newRecordId);

        emit RecordAssigned(newRecordId, msg.sender);
    }
    */

    function getBounty() public returns (uint256) {
        // Step 1: Check if the user is already assigned a record
        for (uint256 i = 0; i < activeRecordIds.length; i++) {
            uint256 recordId = activeRecordIds[i];
            Record storage record = records[recordId];

            // If the user is already assigned a record, return it
            if (record.assignedTo == msg.sender) {
                return recordId;
            }
        }

        // Step 2: Check for an existing unassigned record
        for (uint256 i = 0; i < activeRecordIds.length; i++) {
            uint256 recordId = activeRecordIds[i];
            Record storage record = records[recordId];

            if (record.assignedTo == address(0) && !hasSubmitted(record, msg.sender)) {
                // Assign this existing record to the crowdsourcer
                record.assignedTo = msg.sender;
                record.assignedAt = block.timestamp;

                emit RecordAssigned(recordId, msg.sender);
                return recordId;
            }
        }

        // Step 3: Assign a new record
        uint256 newRecordId = nextAvailableRecord;
        nextAvailableRecord++;

        records[newRecordId] = Record({
            recordId: newRecordId,
            assignedTo: msg.sender,
            assignedAt: block.timestamp,
            submissions: new address[](0)
        });

        activeRecordIds.push(newRecordId);

        emit RecordAssigned(newRecordId, msg.sender);
        return newRecordId;
    }

    // TODO: Add function that only returns assigned bounty.


    // Internal function to check if a crowdsourcer has already submitted a specific record
    function hasSubmitted(Record storage record, address crowdsourcer) internal view returns (bool) {
        for (uint256 j = 0; j < record.submissions.length; j++) {
            if (record.submissions[j] == crowdsourcer) {
                return true;
            }
        }
        return false;
    }

    // Function to remove a record from active records once it is fully validated
    function removeRecordFromActive(uint256 recordId) internal {
        for (uint256 i = 0; i < activeRecordIds.length; i++) {
            if (activeRecordIds[i] == recordId) {
                activeRecordIds[i] = activeRecordIds[activeRecordIds.length - 1]; // Replace with the last element
                activeRecordIds.pop(); // Remove the last element
                break;
            }
        }
    }

    // Helper functions for console testing
    function getSubmissions(uint256 recordId) external view returns (address[] memory) {
        return records[recordId].submissions;
    }

    function getActiveRecordIdsLength() external view returns (uint256) {
        return activeRecordIds.length;
    }

}
