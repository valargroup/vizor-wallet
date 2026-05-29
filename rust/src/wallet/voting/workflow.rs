use zcash_voting::confirmation::{DelegationConfirmation, TxEvent, VoteConfirmation};

/// Marks a delegation bundle as submitted by storing its transaction hash.
///
/// The write is atomic and idempotent for the same `tx_hash`. A different
/// existing hash for the same `(round_id, wallet_id, bundle_index)` is rejected.
///
/// # Errors
///
/// Returns an error if the voting DB cannot be opened, the transaction cannot
/// be committed, the bundle row is missing, or an existing hash conflicts.
pub fn mark_delegation_submitted(
    db_path: &str,
    wallet_id: &str,
    round_id: &str,
    bundle_index: u32,
    tx_hash: &str,
) -> Result<(), String> {
    let db = super::state::open_voting_db(db_path, wallet_id)?;
    db.store_delegation_tx_hash(round_id, bundle_index, tx_hash)
        .map_err(|e| format!("store_delegation_tx_hash failed: {e}"))?;
    Ok(())
}

/// Marks a delegation bundle as confirmed from chain transaction events.
///
/// # Errors
///
/// Returns an error if the voting DB cannot be opened, the confirmation event is
/// malformed or for a different round, the bundle row is missing, or stored data
/// conflicts.
pub fn mark_delegation_confirmed(
    db_path: &str,
    wallet_id: &str,
    round_id: &str,
    bundle_index: u32,
    tx_hash: &str,
    events: &[TxEvent],
) -> Result<DelegationConfirmation, String> {
    let db = super::state::open_voting_db(db_path, wallet_id)?;
    zcash_voting::confirmation::confirm_delegation_submission(
        &db,
        round_id,
        bundle_index,
        tx_hash,
        events,
    )
    .map_err(|e| format!("confirm_delegation_submission failed: {e}"))
}

/// Marks a vote as submitted by storing its tx hash.
///
/// The write is atomic and idempotent for the same `tx_hash`. A different
/// existing hash for the same vote key is rejected.
///
/// # Errors
///
/// Returns an error if the voting DB cannot be opened, the vote row is missing,
/// the transaction cannot be committed, or an existing hash conflicts.
pub fn mark_vote_submitted(
    db_path: &str,
    wallet_id: &str,
    round_id: &str,
    bundle_index: u32,
    proposal_id: u32,
    tx_hash: &str,
) -> Result<(), String> {
    let db = super::state::open_voting_db(db_path, wallet_id)?;
    db.record_vote_submission(round_id, bundle_index, proposal_id, tx_hash)
        .map_err(|e| format!("record_vote_submission failed: {e}"))?;
    Ok(())
}

/// Marks a vote as confirmed from chain transaction events.
///
/// # Errors
///
/// Returns an error if the voting DB cannot be opened, the confirmation event is
/// malformed or for a different round, the vote row is missing, or stored data
/// conflicts.
pub fn mark_vote_confirmed(
    db_path: &str,
    wallet_id: &str,
    round_id: &str,
    bundle_index: u32,
    proposal_id: u32,
    tx_hash: &str,
    events: &[TxEvent],
) -> Result<VoteConfirmation, String> {
    let db = super::state::open_voting_db(db_path, wallet_id)?;
    zcash_voting::confirmation::confirm_vote_submission(
        &db,
        round_id,
        bundle_index,
        proposal_id,
        tx_hash,
        events,
    )
    .map_err(|e| format!("confirm_vote_submission failed: {e}"))
}

/// Records helper-server share submission state for retry/recovery.
///
/// The shared voting crate reconstructs the share payload and nullifier from the
/// stored vote recovery bundle, so callers only provide helper delivery state.
///
/// # Errors
///
/// Returns an error if the voting DB cannot be opened or the upstream share
/// write fails.
#[allow(clippy::too_many_arguments)]
pub fn record_share_delegation(
    db_path: &str,
    wallet_id: &str,
    round_id: &str,
    bundle_index: u32,
    proposal_id: u32,
    share_index: u32,
    sent_to_urls: &[String],
    submit_at: u64,
) -> Result<(), String> {
    let db = super::state::open_voting_db(db_path, wallet_id)?;
    zcash_voting::share::record(
        &db,
        round_id,
        bundle_index,
        proposal_id,
        share_index,
        sent_to_urls,
        submit_at,
    )
    .map_err(|e| format!("record_share_delegation failed: {e}"))?;
    Ok(())
}

/// Marks a helper-server share delegation as confirmed.
///
/// The write is atomic for the exact `(round_id, wallet_id, bundle_index,
/// proposal_id, share_index)` key.
///
/// # Errors
///
/// Returns an error if the voting DB cannot be opened, the transaction cannot be
/// committed, or the upstream confirmation update fails.
pub fn mark_share_confirmed(
    db_path: &str,
    wallet_id: &str,
    round_id: &str,
    bundle_index: u32,
    proposal_id: u32,
    share_index: u32,
) -> Result<(), String> {
    let db = super::state::open_voting_db(db_path, wallet_id)?;
    zcash_voting::share::confirm(&db, round_id, bundle_index, proposal_id, share_index)
        .map_err(|e| format!("mark_share_confirmed failed: {e}"))?;
    Ok(())
}
