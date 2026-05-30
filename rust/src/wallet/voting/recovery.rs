use super::state::open_voting_db;

/// Stored commitment bundle recovery data for one `(bundle_index, proposal_id)`.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct CommitmentBundleRecovery {
    pub bundle_index: u32,
    pub proposal_id: u32,
    pub commitment_bundle_json: String,
    pub vc_tree_position: u64,
}

/// Stored delegation transaction hash for one voting note bundle.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct DelegationTxRecovery {
    pub bundle_index: u32,
    pub tx_hash: String,
}

/// Stored vote transaction hash for one `(bundle_index, proposal_id)`.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct VoteTxRecovery {
    pub bundle_index: u32,
    pub proposal_id: u32,
    pub tx_hash: String,
}

/// Stored helper-server share delegation state for retry/resume.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ShareDelegationRecord {
    pub round_id: String,
    pub bundle_index: u32,
    pub proposal_id: u32,
    pub share_index: u32,
    pub sent_to_urls: Vec<String>,
    pub nullifier: Vec<u8>,
    pub phase: String,
    pub confirmed: bool,
    pub submit_at: u64,
    pub created_at: u64,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct DelegationWorkflowRecovery {
    pub bundle_index: u32,
    pub phase: String,
    pub tx_hash: Option<String>,
    pub van_leaf_position: Option<u32>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct VoteWorkflowRecovery {
    pub bundle_index: u32,
    pub proposal_id: u32,
    pub phase: String,
    pub tx_hash: Option<String>,
    pub vc_tree_position: Option<u64>,
    pub has_commitment_bundle: bool,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ShareWorkflowRecovery {
    pub bundle_index: u32,
    pub proposal_id: u32,
    pub share_index: u32,
    pub phase: String,
}

/// Stored vote row keyed by `(round_id, wallet_id, bundle_index, proposal_id)`.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct VoteRecord {
    pub proposal_id: u32,
    pub bundle_index: u32,
    pub choice: u32,
}

/// Recovery summary for one round.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct RoundRecoveryState {
    pub round_id: String,
    pub bundle_count: u32,
    pub delegation_workflows: Vec<DelegationWorkflowRecovery>,
    pub delegation_tx_hashes: Vec<DelegationTxRecovery>,
    pub votes: Vec<VoteRecord>,
    pub vote_workflows: Vec<VoteWorkflowRecovery>,
    pub vote_tx_hashes: Vec<VoteTxRecovery>,
    pub commitment_bundles: Vec<CommitmentBundleRecovery>,
    pub share_workflows: Vec<ShareWorkflowRecovery>,
    pub share_delegations: Vec<ShareDelegationRecord>,
    pub unconfirmed_share_delegations: Vec<ShareDelegationRecord>,
}

/// Loads the persisted recovery snapshot for a voting round.
pub fn get_round_recovery_state(
    db_path: &str,
    wallet_id: &str,
    round_id: &str,
) -> Result<RoundRecoveryState, String> {
    let voting_db = open_voting_db(db_path, wallet_id)?;
    let snapshot = zcash_voting::recovery::round_snapshot(&voting_db, round_id)
        .map_err(|e| format!("round_snapshot failed: {e}"))?;

    let delegation_workflows = snapshot
        .delegation
        .iter()
        .map(|record| DelegationWorkflowRecovery {
            bundle_index: record.bundle_index,
            phase: delegation_workflow_phase(record.phase).to_string(),
            tx_hash: record.tx_hash.clone(),
            van_leaf_position: record.van_leaf_position,
        })
        .collect::<Vec<_>>();
    let delegation_tx_hashes = snapshot
        .delegation
        .iter()
        .filter_map(|record| {
            record
                .tx_hash
                .as_ref()
                .map(|tx_hash| DelegationTxRecovery {
                    bundle_index: record.bundle_index,
                    tx_hash: tx_hash.clone(),
                })
        })
        .collect::<Vec<_>>();
    let votes = snapshot
        .votes
        .iter()
        .map(|record| VoteRecord {
            proposal_id: record.proposal_id,
            bundle_index: record.bundle_index,
            choice: record.choice,
        })
        .collect::<Vec<_>>();
    let vote_workflows = snapshot
        .votes
        .iter()
        .map(|record| VoteWorkflowRecovery {
            bundle_index: record.bundle_index,
            proposal_id: record.proposal_id,
            phase: vote_workflow_phase(record.phase).to_string(),
            tx_hash: record.tx_hash.clone(),
            vc_tree_position: record.vc_tree_position,
            has_commitment_bundle: record.has_commitment_bundle,
        })
        .collect::<Vec<_>>();
    let vote_tx_hashes = snapshot
        .votes
        .iter()
        .filter_map(|record| {
            record.tx_hash.as_ref().map(|tx_hash| VoteTxRecovery {
                bundle_index: record.bundle_index,
                proposal_id: record.proposal_id,
                tx_hash: tx_hash.clone(),
            })
        })
        .collect::<Vec<_>>();
    let commitment_bundles = snapshot
        .commitment_bundles
        .into_iter()
        .map(|record| CommitmentBundleRecovery {
            bundle_index: record.bundle_index,
            proposal_id: record.proposal_id,
            commitment_bundle_json: record.commitment_bundle_json,
            vc_tree_position: record.vc_tree_position,
        })
        .collect::<Vec<_>>();
    let share_workflows = snapshot
        .shares
        .into_iter()
        .map(|record| ShareWorkflowRecovery {
            bundle_index: record.bundle_index,
            proposal_id: record.proposal_id,
            share_index: record.share_index,
            phase: share_workflow_phase(record.phase).to_string(),
        })
        .collect::<Vec<_>>();
    let share_delegations = snapshot
        .share_delegations
        .into_iter()
        .map(share_record_from_upstream)
        .collect::<Vec<_>>();
    let unconfirmed_share_delegations = snapshot
        .unconfirmed_share_delegations
        .into_iter()
        .map(share_record_from_upstream)
        .collect::<Vec<_>>();

    Ok(RoundRecoveryState {
        round_id: snapshot.round_id,
        bundle_count: snapshot.bundle_count,
        delegation_workflows,
        delegation_tx_hashes,
        votes,
        vote_workflows,
        vote_tx_hashes,
        commitment_bundles,
        share_workflows,
        share_delegations,
        unconfirmed_share_delegations,
    })
}

/// Returns the stored vote transaction hash for one vote, when present.
pub fn get_vote_tx_hash(
    db_path: &str,
    wallet_id: &str,
    round_id: &str,
    bundle_index: u32,
    proposal_id: u32,
) -> Result<Option<String>, String> {
    let voting_db = open_voting_db(db_path, wallet_id)?;
    voting_db
        .get_vote_tx_hash(round_id, bundle_index, proposal_id)
        .map_err(|e| format!("get_vote_tx_hash failed: {e}"))
}

/// Returns the stored commitment bundle recovery payload for one vote.
pub fn get_commitment_bundle(
    db_path: &str,
    wallet_id: &str,
    round_id: &str,
    bundle_index: u32,
    proposal_id: u32,
) -> Result<Option<CommitmentBundleRecovery>, String> {
    let voting_db = open_voting_db(db_path, wallet_id)?;
    zcash_voting::recovery::recoverable_commitment_bundle(
        &voting_db,
        round_id,
        bundle_index,
        proposal_id,
    )
    .map_err(|e| format!("recoverable_commitment_bundle failed: {e}"))
    .map(|record| {
        record.map(|record| CommitmentBundleRecovery {
            bundle_index: record.bundle_index,
            proposal_id: record.proposal_id,
            commitment_bundle_json: record.commitment_bundle_json,
            vc_tree_position: record.vc_tree_position,
        })
    })
}

/// Lists all stored share delegation records for a round.
pub fn get_share_delegations(
    db_path: &str,
    wallet_id: &str,
    round_id: &str,
) -> Result<Vec<ShareDelegationRecord>, String> {
    let voting_db = open_voting_db(db_path, wallet_id)?;
    zcash_voting::share::list(&voting_db, round_id)
        .map_err(|e| format!("get_share_delegations failed: {e}"))
        .map(|records| records.into_iter().map(share_record_from_upstream).collect())
}

/// Lists share delegation records that still need confirmation.
pub fn get_unconfirmed_share_delegations(
    db_path: &str,
    wallet_id: &str,
    round_id: &str,
) -> Result<Vec<ShareDelegationRecord>, String> {
    let voting_db = open_voting_db(db_path, wallet_id)?;
    zcash_voting::share::unconfirmed(&voting_db, round_id)
        .map_err(|e| format!("get_unconfirmed_delegations failed: {e}"))
        .map(|records| records.into_iter().map(share_record_from_upstream).collect())
}

/// Adds helper-server URLs to the sent history for one share delegation.
pub fn add_sent_servers(
    db_path: &str,
    wallet_id: &str,
    round_id: &str,
    bundle_index: u32,
    proposal_id: u32,
    share_index: u32,
    new_urls: &[String],
) -> Result<(), String> {
    let voting_db = open_voting_db(db_path, wallet_id)?;
    zcash_voting::share::add_sent_servers(
        &voting_db,
        round_id,
        bundle_index,
        proposal_id,
        share_index,
        new_urls,
    )
    .map_err(|e| format!("add_sent_servers failed: {e}"))
}

/// Clears retry/recovery artifacts for a voting round.
pub fn clear_recovery_state(db_path: &str, wallet_id: &str, round_id: &str) -> Result<(), String> {
    let voting_db = open_voting_db(db_path, wallet_id)?;
    zcash_voting::recovery::clear(&voting_db, round_id)
        .map_err(|e| format!("clear_recovery_state failed: {e}"))
}

/// Converts the upstream share record into the flat API-facing recovery type.
fn share_record_from_upstream(record: zcash_voting::ShareDelegationRecord) -> ShareDelegationRecord {
    ShareDelegationRecord {
        round_id: record.round_id,
        bundle_index: record.bundle_index,
        proposal_id: record.proposal_id,
        share_index: record.share_index,
        sent_to_urls: record.sent_to_urls,
        nullifier: record.nullifier,
        phase: if record.confirmed {
            "confirmed".to_string()
        } else {
            "submitted_share".to_string()
        },
        confirmed: record.confirmed,
        submit_at: record.submit_at,
        created_at: record.created_at,
    }
}

fn delegation_workflow_phase(phase: zcash_voting::phases::DelegationPhase) -> &'static str {
    match phase {
        zcash_voting::phases::DelegationPhase::Prepared => "prepared",
        zcash_voting::phases::DelegationPhase::PcztBuilt
        | zcash_voting::phases::DelegationPhase::Proved => "signed",
        zcash_voting::phases::DelegationPhase::Submitted => "submitted_delegation",
        zcash_voting::phases::DelegationPhase::Confirmed => "confirmed",
        _ => "prepared",
    }
}

fn vote_workflow_phase(phase: zcash_voting::phases::VotePhase) -> &'static str {
    match phase {
        zcash_voting::phases::VotePhase::Prepared => "prepared",
        zcash_voting::phases::VotePhase::Committed => "signed",
        zcash_voting::phases::VotePhase::Submitted => "submitted_vote",
        zcash_voting::phases::VotePhase::Confirmed => "confirmed",
        _ => "prepared",
    }
}

fn share_workflow_phase(phase: zcash_voting::phases::SharePhase) -> &'static str {
    match phase {
        zcash_voting::phases::SharePhase::Submitted => "submitted_share",
        zcash_voting::phases::SharePhase::Confirmed => "confirmed",
        _ => "submitted_share",
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::wallet::voting::state;

    const WALLET_ID: &str = "wallet-recovery";
    const ROUND_ID: &str = "round-recovery";

    #[test]
    fn round_recovery_state_maps_typed_phases_to_ffi_strings() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("voting.sqlite");
        let db = state::open_voting_db(db_path.to_str().unwrap(), WALLET_ID).unwrap();
        state::init_voting_round(&db, &test_round_params(), None).unwrap();
        let notes: Vec<_> = (0..6).map(test_note_info).collect();
        db.ensure_bundles(ROUND_ID, &notes).unwrap();

        let state = get_round_recovery_state(db_path.to_str().unwrap(), WALLET_ID, ROUND_ID).unwrap();

        assert_eq!(state.bundle_count, 2);
        assert!(state
            .delegation_workflows
            .iter()
            .all(|record| record.phase == "prepared"));
        assert!(state.votes.is_empty());
        assert!(state.vote_workflows.is_empty());
    }

    #[test]
    fn commitment_bundle_placeholder_requires_submitted_vote_tx_hash() {
        let temp_dir = tempfile::tempdir().unwrap();
        let db_path = temp_dir.path().join("voting.sqlite");
        let db = state::open_voting_db(db_path.to_str().unwrap(), WALLET_ID).unwrap();
        state::init_voting_round(&db, &test_round_params(), None).unwrap();
        let notes: Vec<_> = (0..6).map(test_note_info).collect();
        db.ensure_bundles(ROUND_ID, &notes).unwrap();
        zcash_voting::storage::queries::store_vote(
            &db.conn(),
            ROUND_ID,
            WALLET_ID,
            0,
            1,
            0,
            b"vote-0-1",
        )
        .unwrap();
        db.conn()
            .execute(
                "UPDATE votes SET commitment_bundle_json = :json, vc_tree_position = NULL
                 WHERE round_id = :round_id AND wallet_id = :wallet_id
                 AND bundle_index = 0 AND proposal_id = 1",
                rusqlite::named_params! {
                    ":json": r#"{"bundle":"pending"}"#,
                    ":round_id": ROUND_ID,
                    ":wallet_id": WALLET_ID,
                },
            )
            .unwrap();

        assert!(
            get_commitment_bundle(db_path.to_str().unwrap(), WALLET_ID, ROUND_ID, 0, 1)
                .unwrap()
                .is_none()
        );

        db.mark_vote_submitted(ROUND_ID, 0, 1, "vote-tx-0-1").unwrap();
        let recovered = get_commitment_bundle(db_path.to_str().unwrap(), WALLET_ID, ROUND_ID, 0, 1)
            .unwrap()
            .unwrap();
        assert_eq!(recovered.vc_tree_position, 0);
    }

    fn test_round_params() -> zcash_voting::VotingRoundParams {
        zcash_voting::VotingRoundParams {
            vote_round_id: ROUND_ID.to_string(),
            snapshot_height: 100,
            ea_pk: vec![1; 32],
            nc_root: vec![2; 32],
            nullifier_imt_root: vec![3; 32],
        }
    }

    fn test_note_info(position: u64) -> zcash_voting::NoteInfo {
        zcash_voting::NoteInfo {
            commitment: vec![1; 32],
            nullifier: vec![2; 32],
            value: zcash_voting::governance::BALLOT_DIVISOR,
            position,
            diversifier: vec![3; 11],
            rho: vec![4; 32],
            rseed: vec![5; 32],
            scope: 0,
            ufvk_str: "uviewtest".to_string(),
        }
    }
}
