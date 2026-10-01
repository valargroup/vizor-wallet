//! Final transparent-input authorization for every hardware broadcast path.
//!
//! Signing can outlive recovery authority. Validate using the library's input
//! selector at the current network target, then keep a SQLite writer reservation
//! through the bounded SendTransaction attempt. This prevents policy changes,
//! rewinds, or evidence withdrawal between validation and submission, including
//! writes from another connection. No transaction is stored here: dropping the
//! connection rolls back the reservation on success, failure, or cancellation.
//! The same reservation withholds a stored retry whose earlier mined
//! observation was rewound and is not yet reconciled.

use std::future::Future;

use voting_crypto_deps::rand::rngs::OsRng;
use zcash_client_backend::data_api::WalletRead;
use zcash_client_sqlite::{util::SystemClock, WalletDb};
use zcash_primitives::transaction::{Transaction, TxId};
use zcash_protocol::consensus::BlockHeight;

use crate::wallet::{
    db::{open_wallet_raw_conn_with_timeout, READ_DB_BUSY_TIMEOUT},
    network::WalletNetwork,
    sync_engine::enhancement::transparent_ledger_mode_for,
};

/// How the wallet accounts for finalized hardware bytes at recovery time.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum StoredSubmission {
    /// These exact bytes are stored with a current mined height.
    Mined,
    /// Scanned as mined, then rewound. Scan or status reconciliation has not yet
    /// established whether it is still mined; a reorg may have removed it.
    AwaitingReconciliation,
    /// An ordinary retry or expiry candidate.
    Unmined,
}

/// Retains the signed operation without classifying expiry or dispatching.
/// Must stay retryable: outbox terminal-failure classifiers match other wording.
pub(crate) fn awaiting_reconciliation_error(txid: &TxId) -> String {
    format!(
        "Hardware broadcast deferred until wallet sync reconciles previously mined transaction {txid}"
    )
}

/// The automatic resubmission guard for one txid: prior mined evidence with
/// pending status work, or with a pending scan range that could restore it.
fn awaiting_reconciliation(
    conn: &rusqlite::Connection,
    db_path: &str,
    network: WalletNetwork,
    txid: &TxId,
) -> Result<bool, String> {
    if crate::wallet::sync::has_recovered_status_work(conn, txid.as_ref())? {
        return Ok(true);
    }
    let pending = crate::wallet::db::wallet_db_on(conn, db_path, network)
        .suggest_scan_ranges()
        .map_err(|e| format!("Recovery scan ranges: {e}"))?
        .into_iter()
        .filter(crate::wallet::sync_engine::is_pending_scan_range)
        .map(|range| range.block_range().clone())
        .collect::<Vec<_>>();
    Ok(
        crate::wallet::sync::unmined_txids_with_mined_output_evidence_on(conn, &pending)?
            .contains(txid.as_ref()),
    )
}

fn is_stored(db_path: &str, txid: &TxId) -> Result<bool, String> {
    open_wallet_raw_conn_with_timeout(db_path, READ_DB_BUSY_TIMEOUT)?
        .query_row(
            "SELECT EXISTS (SELECT 1 FROM transactions WHERE txid = ?1)",
            [txid.as_ref()],
            |row| row.get(0),
        )
        .map_err(|e| format!("Stored transaction lookup: {e}"))
}

/// Authorizes `tx` immediately before polling `send`. Earlier finalized batch
/// transactions may supply local chained inputs (TEX); the output must exist.
/// Unknown, withdrawn, competing-spent, immature, or unauthorized wallet inputs fail
/// before `send` is polled. Exact stored retries may consume their own recorded inputs.
/// A stored retry awaiting rewind reconciliation is deferred under the same
/// reservation. Fresh transactions without transparent inputs need no reservation:
/// only a stored transaction can carry mined evidence.
pub(crate) async fn dispatch<T>(
    db_path: &str,
    network: WalletNetwork,
    tx: &Transaction,
    earlier: &[&Transaction],
    network_tip: u64,
    send: impl Future<Output = T>,
) -> Result<T, String> {
    let txid = tx.txid();
    let inputs = tx.transparent_bundle().map_or(&[][..], |b| &b.vin[..]);
    if inputs.is_empty() && !is_stored(db_path, &txid)? {
        return Ok(send.await);
    }
    let conn = open_wallet_raw_conn_with_timeout(db_path, READ_DB_BUSY_TIMEOUT)?;
    conn.execute_batch("BEGIN IMMEDIATE")
        .map_err(|e| format!("Reserve hardware broadcast authority: {e}"))?;
    if awaiting_reconciliation(&conn, db_path, network, &txid)? {
        return Err(awaiting_reconciliation_error(&txid));
    }
    if inputs.is_empty() {
        let result = send.await;
        drop(conn);
        return Ok(result);
    }
    let target = u32::try_from(network_tip)
        .ok()
        .and_then(|h| h.checked_add(1))
        .map(BlockHeight::from_u32)
        .ok_or_else(|| "Transparent broadcast target exceeds u32".to_string())?;
    let db = WalletDb::from_connection(conn, network, SystemClock, OsRng)
        .with_transparent_ledger_mode(transparent_ledger_mode_for(db_path));
    // Checking the mode also rejects a weaker handle on a durable private wallet.
    use zcash_client_backend::data_api::transparent_ledger::TransparentLedgerRead;
    db.transparent_ledger_mode()
        .map_err(|e| format!("Transparent broadcast authority unavailable: {e}"))?;
    if db.chain_height().map_err(|e| e.to_string())?.is_none() {
        return Err("Transparent broadcast authority unavailable: chain height unknown".into());
    }
    db.check_transparent_transaction_inputs(tx, earlier, target.into())
        .map_err(|e| format!("Transparent broadcast authority unavailable: {e}"))?;
    let result = send.await;
    drop(db);
    Ok(result)
}

/// Reconciles finalized bytes against wallet evidence before considering expiry.
/// The read transaction binds the compatibility check and evidence to one snapshot.
pub(crate) fn stored_status(
    db_path: &str,
    network: WalletNetwork,
    tx: &Transaction,
) -> Result<StoredSubmission, String> {
    use rusqlite::OptionalExtension;
    use zcash_client_backend::data_api::transparent_ledger::TransparentLedgerRead;
    let conn = open_wallet_raw_conn_with_timeout(db_path, READ_DB_BUSY_TIMEOUT)?;
    conn.execute_batch("BEGIN").map_err(|e| e.to_string())?;
    let db = crate::wallet::db::wallet_db_on(&conn, db_path, network);
    db.transparent_ledger_mode()
        .map_err(|e| format!("Stored transaction authority unavailable: {e}"))?;
    let mut raw = Vec::new();
    tx.write(&mut raw).map_err(|e| e.to_string())?;
    let txid = tx.txid();
    let stored: Option<Vec<u8>> = conn
        .query_row(
            "SELECT raw FROM transactions WHERE txid = ?1 AND mined_height IS NOT NULL",
            [txid.as_ref()],
            |row| row.get(0),
        )
        .optional()
        .map_err(|e| e.to_string())?
        .flatten();
    if stored.as_deref() == Some(raw.as_slice()) {
        Ok(StoredSubmission::Mined)
    } else if awaiting_reconciliation(&conn, db_path, network, &txid)? {
        Ok(StoredSubmission::AwaitingReconciliation)
    } else {
        Ok(StoredSubmission::Unmined)
    }
}
