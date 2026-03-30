// Phase 2: Sync engine — individual steps exposed to Dart
// Dart manages the sync loop, Rust handles each step.
// TODO: implement individual sync step functions

use rand::rngs::OsRng;
use zcash_client_backend::data_api::{
    WalletRead,
    wallet::ConfirmationsPolicy,
};
use zcash_client_sqlite::{WalletDb, util::SystemClock};
use zcash_protocol::consensus::Network;

/// Progress information for the sync operation.
pub struct SyncProgress {
    pub scanned_height: u64,
    pub chain_tip_height: u64,
    pub is_syncing: bool,
}

/// Get sync progress from the wallet database.
pub fn get_sync_progress(db_data_path: &str, network: Network) -> Result<SyncProgress, String> {
    let db = WalletDb::for_path(db_data_path, network, SystemClock, OsRng)
        .map_err(|e| format!("Failed to open wallet DB: {e}"))?;

    let summary = db
        .get_wallet_summary(ConfirmationsPolicy::default())
        .map_err(|e| format!("Failed to get wallet summary: {e}"))?;

    match summary {
        Some(s) => Ok(SyncProgress {
            scanned_height: u32::from(s.fully_scanned_height()) as u64,
            chain_tip_height: u32::from(s.chain_tip_height()) as u64,
            is_syncing: s.fully_scanned_height() < s.chain_tip_height(),
        }),
        None => Ok(SyncProgress {
            scanned_height: 0,
            chain_tip_height: 0,
            is_syncing: false,
        }),
    }
}

/// Get wallet balance (transparent, sapling, orchard) in zatoshi.
pub fn get_wallet_balance(
    db_data_path: &str,
    network: Network,
) -> Result<(u64, u64, u64), String> {
    let db = WalletDb::for_path(db_data_path, network, SystemClock, OsRng)
        .map_err(|e| format!("Failed to open wallet DB: {e}"))?;

    let summary = db
        .get_wallet_summary(ConfirmationsPolicy::default())
        .map_err(|e| format!("Failed to get wallet summary: {e}"))?;

    match summary {
        Some(s) => {
            let mut sapling: u64 = 0;
            let mut orchard: u64 = 0;
            let mut transparent: u64 = 0;

            for (_account_id, balance) in s.account_balances() {
                sapling += u64::from(balance.sapling_balance().spendable_value());
                orchard += u64::from(balance.orchard_balance().spendable_value());
                transparent += u64::from(balance.unshielded_balance().spendable_value());
            }

            Ok((transparent, sapling, orchard))
        }
        None => Ok((0, 0, 0)),
    }
}
