// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface ICampaignTokenMint {
    function mint(address to, uint256 amount) external;
}

/// @title  SubmissionManager
/// @notice Handles record assignment and submission for a single Crowdvouched
///         campaign. Records are assigned deterministically to callers, they
///         cannot pick which record they receive — this is the primary Sybil
///         defense (a rogue operator cannot coordinate two wallets onto the
///         same record).
///
///         Records validate when `requiredMatches` distinct submitters have
///         all submitted the same `dataHash`. On validation, the campaign is
///         notified via event; token minting and NFT minting happen in the
///         reward-flow contracts that watch these events.
///
///         Actual submission payload lives off-chain (IPFS). Only its keccak256
///         hash is compared on-chain — matches are computed cheaply.
contract SubmissionManager {
    /// -----------------------------------------------------------------------
    /// Types
    /// -----------------------------------------------------------------------

    struct Submission {
        address submitter;
        bytes32 dataHash;    // keccak256 of the canonical submission payload
        string ipfsCid;      // IPFS content id of the raw submission
        uint64 submittedAt;
    }

    struct Record {
        address assignee;    // 0 if unassigned or timed out
        uint64 assignedAt;
        bool validated;
        bytes32 validatedHash;
        Submission[] submissions;
    }

    /// -----------------------------------------------------------------------
    /// Immutable config
    /// -----------------------------------------------------------------------

    address public campaign;
    uint256 public immutable totalRecords;
    uint32  public assignmentTimeout; // seconds, set by the campaign
    uint8   public immutable requiredMatches;   // matching submissions to validate

    /// -----------------------------------------------------------------------
    /// State
    /// -----------------------------------------------------------------------

    /// recordId => Record. Record ids are 1..totalRecords.
    mapping(uint256 => Record) private _records;

    /// caller => recordId currently assigned to them (0 if none).
    mapping(address => uint256) public assignedTo;

    /// caller => recordId => has already submitted for this record.
    mapping(address => mapping(uint256 => bool)) public hasSubmitted;

    /// Reward credited to each matching submitter when a record validates.
    /// One whole token (18 decimals), per the whitepaper.
    uint256 public constant REWARD_PER_VALIDATION = 1e18;

    /// Reward tokens the user has earned via validation but not yet claimed.
    /// Filled in _tryValidate; drained by claim().
    mapping(address => uint256) public unclaimedRewards;

    /// The CampaignToken this manager mints rewards from. Set once by the
    /// campaign after deployment via `setToken`.
    address public token;

    /// Number of records that have been validated. Campaign is complete when
    /// this equals totalRecords.
    uint256 public validatedCount;

    /// Next unallocated recordId. Starts at 1. Once it exceeds totalRecords,
    /// no more fresh records are created — later assignBounty calls only pick
    /// up freed (timed-out or awaiting-second) records.
    uint256 public nextRecordId = 1;

    /// Records still in play: created but not yet validated. assignBounty only
    /// ever walks this list, so its cost tracks work-in-progress rather than
    /// campaign progress — validated records are removed and never scanned again.
    uint256[] public activeRecordIds;

    /// recordId => (position in activeRecordIds) + 1. Zero means "not active",
    /// which lets removal skip the linear search for the record's slot.
    mapping(uint256 => uint256) private _activeIndex;

    /// -----------------------------------------------------------------------
    /// Errors
    /// -----------------------------------------------------------------------

    error ZeroAddress();
    error InvalidConfig();
    error NoRecordAvailable();
    error NotAssigned();
    error NotYourAssignment();
    error AlreadySubmitted();
    error AlreadyValidated();
    error EmptyIpfsCid();
    error EmptyDataHash();
    error NotCampaign();
    error AlreadySet();
    error TokenNotSet();
    error NothingToClaim();
    error SubmissionWindowClosed();

    /// -----------------------------------------------------------------------
    /// Events
    /// -----------------------------------------------------------------------

    event RecordAssigned(uint256 indexed recordId, address indexed assignee);
    event SubmissionReceived(uint256 indexed recordId, address indexed submitter, bytes32 dataHash, string ipfsCid);
    event RecordValidated(uint256 indexed recordId, bytes32 dataHash, address[] validators);
    event CampaignCompleted(uint256 totalValidated);
    event TokenSet(address indexed token);
    event CampaignUpdated(address indexed campaign);
    event AssignmentTimeoutUpdated(uint32 assignmentTimeout);
    event RewardClaimed(address indexed claimant, uint256 amount);
    event AssignmentExpired(uint256 indexed recordId, address indexed assignee);

    /// -----------------------------------------------------------------------
    /// Construction
    /// -----------------------------------------------------------------------

    constructor(
        address _campaign,
        uint256 _totalRecords,
        uint32  _assignmentTimeout,
        uint8   _requiredMatches
    ) {
        if (_campaign == address(0)) revert ZeroAddress();
        if (_totalRecords == 0 || _assignmentTimeout == 0 || _requiredMatches < 2) {
            revert InvalidConfig();
        }
        campaign = _campaign;
        totalRecords = _totalRecords;
        assignmentTimeout = _assignmentTimeout;
        requiredMatches = _requiredMatches;
    }

    /// -----------------------------------------------------------------------
    /// Campaign-only setup
    /// -----------------------------------------------------------------------

    /// @notice Hand campaign control to the real Campaign contract. Deployment
    ///         is a cycle — Campaign needs this address, this needs Campaign's —
    ///         so the deployer holds the role until Campaign exists, then hands
    ///         it over. One-shot in practice: only the current holder can move it.
    function setCampaign(address _campaign) external {
        if (msg.sender != campaign) revert NotCampaign();
        if (_campaign == address(0)) revert ZeroAddress();
        campaign = _campaign;
        emit CampaignUpdated(_campaign);
    }

    /// @notice How long a caller has to submit before their assignment lapses.
    /// @dev    Applies to in-flight assignments too: shortening it can cause
    ///         records currently held to lapse immediately.
    function setAssignmentTimeout(uint32 _assignmentTimeout) external {
        if (msg.sender != campaign) revert NotCampaign();
        if (_assignmentTimeout == 0) revert InvalidConfig();
        assignmentTimeout = _assignmentTimeout;
        emit AssignmentTimeoutUpdated(_assignmentTimeout);
    }

    /// @notice Wire in the CampaignToken. One-shot; only the campaign can set.
    function setToken(address _token) external {
        if (msg.sender != campaign) revert NotCampaign();
        if (token != address(0)) revert AlreadySet();
        if (_token == address(0)) revert ZeroAddress();
        token = _token;
        emit TokenSet(_token);
    }

    /// -----------------------------------------------------------------------
    /// External: rewards
    /// -----------------------------------------------------------------------

    /// @notice Mint the caller their earned-but-not-yet-claimed reward tokens.
    function claim() external {
        if (token == address(0)) revert TokenNotSet();
        uint256 amount = unclaimedRewards[msg.sender];
        if (amount == 0) revert NothingToClaim();
        unclaimedRewards[msg.sender] = 0;
        ICampaignTokenMint(token).mint(msg.sender, amount);
        emit RewardClaimed(msg.sender, amount);
    }

    /// -----------------------------------------------------------------------
    /// External: assignment
    /// -----------------------------------------------------------------------

    /// @notice Assign the caller to an available record. Callers cannot pick;
    ///         this scans records in-order and takes the first one that is
    ///         (a) not validated, (b) not currently assigned (or timed out),
    ///         and (c) the caller has not already submitted for.
    /// @return recordId The record the caller has been assigned.
    function assignBounty() external returns (uint256 recordId) {
        // If the caller still holds a live assignment, hand it back (idempotent).
        // If their window has closed, release it here rather than letting them
        // hold it indefinitely just because nobody else has asked for work yet.
        // They can be assigned it again below, on a fresh window.
        uint256 current = assignedTo[msg.sender];
        if (current != 0) {
            Record storage cur = _records[current];
            if (cur.assignee == msg.sender && !cur.validated) {
                if (block.timestamp <= uint256(cur.assignedAt) + assignmentTimeout) {
                    return current;
                }
                _release(current, msg.sender);
            } else {
                // Reassigned away, or validated while they held it.
                assignedTo[msg.sender] = 0;
            }
        }

        // Scan records still in play. Validated records have been removed from
        // activeRecordIds, so finished work is never walked.
        uint256 n = activeRecordIds.length;
        for (uint256 i = 0; i < n; ++i) {
            uint256 id = activeRecordIds[i];
            if (hasSubmitted[msg.sender][id]) continue;
            Record storage r = _records[id];
            address holder = r.assignee;
            if (holder == address(0)) {
                _assign(id);
                return id;
            }
            if (block.timestamp > uint256(r.assignedAt) + assignmentTimeout) {
                // Holder let their window lapse: the record is up for grabs.
                _release(id, holder);
                _assign(id);
                return id;
            }
        }

        // Otherwise mint a fresh record if we haven't hit totalRecords yet.
        if (nextRecordId <= totalRecords) {
            uint256 fresh = nextRecordId++;
            _addActive(fresh);
            _assign(fresh);
            return fresh;
        }

        revert NoRecordAvailable();
    }

    /// -----------------------------------------------------------------------
    /// External: submission
    /// -----------------------------------------------------------------------

    /// @notice Submit the caller's transcription for the record they are
    ///         currently assigned. Validation runs automatically once enough
    ///         matching submissions have arrived.
    function submit(uint256 recordId, bytes32 dataHash, string calldata ipfsCid) external {
        Record storage r = _records[recordId];
        if (r.validated) revert AlreadyValidated();
        if (assignedTo[msg.sender] != recordId) revert NotYourAssignment();
        if (r.assignee != msg.sender) revert NotAssigned();
        if (block.timestamp > uint256(r.assignedAt) + assignmentTimeout) {
            revert SubmissionWindowClosed();
        }
        if (hasSubmitted[msg.sender][recordId]) revert AlreadySubmitted();
        if (dataHash == bytes32(0)) revert EmptyDataHash();
        if (bytes(ipfsCid).length == 0) revert EmptyIpfsCid();

        r.submissions.push(Submission({
            submitter: msg.sender,
            dataHash: dataHash,
            ipfsCid: ipfsCid,
            submittedAt: uint64(block.timestamp)
        }));
        hasSubmitted[msg.sender][recordId] = true;

        emit SubmissionReceived(recordId, msg.sender, dataHash, ipfsCid);

        // Free the record so someone else can pick up the next required submission.
        r.assignee = address(0);
        assignedTo[msg.sender] = 0;

        _tryValidate(recordId);
    }

    /// -----------------------------------------------------------------------
    /// External views
    /// -----------------------------------------------------------------------

    function record(uint256 recordId) external view returns (
        address assignee,
        uint64 assignedAt,
        bool validated,
        bytes32 validatedHash,
        uint256 submissionCount
    ) {
        Record storage r = _records[recordId];
        return (r.assignee, r.assignedAt, r.validated, r.validatedHash, r.submissions.length);
    }

    /// @notice How many records are currently in play (created, not validated).
    function activeRecordCount() external view returns (uint256) {
        return activeRecordIds.length;
    }

    function submissionAt(uint256 recordId, uint256 idx) external view returns (Submission memory) {
        return _records[recordId].submissions[idx];
    }

    /// -----------------------------------------------------------------------
    /// Internals
    /// -----------------------------------------------------------------------

    /// @dev Release a record whose holder let the assignment window close, so
    ///      it is available again. No penalty attaches to the holder: they may
    ///      request it again like anyone else, on a fresh window.
    function _release(uint256 recordId, address holder) private {
        _records[recordId].assignee = address(0);
        assignedTo[holder] = 0;
        emit AssignmentExpired(recordId, holder);
    }

    /// @dev Append a newly created record to the active list.
    function _addActive(uint256 recordId) private {
        activeRecordIds.push(recordId);
        _activeIndex[recordId] = activeRecordIds.length; // position + 1
    }

    /// @dev Remove a record from the active list by swapping the last element
    ///      into its slot and popping. Order is not meaningful here, so this
    ///      avoids shifting the tail.
    function _removeActive(uint256 recordId) private {
        uint256 pos = _activeIndex[recordId];
        if (pos == 0) return; // not active; nothing to do
        uint256 idx = pos - 1;
        uint256 lastIdx = activeRecordIds.length - 1;
        if (idx != lastIdx) {
            uint256 lastId = activeRecordIds[lastIdx];
            activeRecordIds[idx] = lastId;
            _activeIndex[lastId] = idx + 1;
        }
        activeRecordIds.pop();
        _activeIndex[recordId] = 0;
    }

    function _assign(uint256 recordId) private {
        _records[recordId].assignee = msg.sender;
        _records[recordId].assignedAt = uint64(block.timestamp);
        assignedTo[msg.sender] = recordId;
        emit RecordAssigned(recordId, msg.sender);
    }

    /// @dev Runs after every new submission. If `requiredMatches` distinct
    ///      submissions with the same dataHash exist for this record, mark it
    ///      validated and emit the event.
    function _tryValidate(uint256 recordId) private {
        Record storage r = _records[recordId];
        uint256 n = r.submissions.length;
        if (n < requiredMatches) return;

        // Check the newest submission against earlier ones (an existing match
        // set can only grow by the newest addition).
        Submission storage latest = r.submissions[n - 1];
        bytes32 target = latest.dataHash;

        uint8 count;
        // Collect matching submitters
        address[] memory matchers = new address[](requiredMatches);
        for (uint256 i = 0; i < n; ++i) {
            if (r.submissions[i].dataHash == target) {
                if (count < requiredMatches) {
                    matchers[count] = r.submissions[i].submitter;
                }
                count++;
                if (count == requiredMatches) break;
            }
        }
        if (count < requiredMatches) return;

        r.validated = true;
        r.validatedHash = target;
        ++validatedCount;
        _removeActive(recordId);

        // Credit each matcher one reward token; they claim it later via claim().
        for (uint8 j = 0; j < requiredMatches; ++j) {
            unclaimedRewards[matchers[j]] += REWARD_PER_VALIDATION;
        }

        emit RecordValidated(recordId, target, matchers);
        if (validatedCount == totalRecords) {
            emit CampaignCompleted(validatedCount);
        }
    }
}
