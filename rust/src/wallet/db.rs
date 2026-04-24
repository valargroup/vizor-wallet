use std::time::Duration;

use rand::rngs::OsRng;
use zcash_client_sqlite::{util::SystemClock, WalletDb};

use crate::wallet::network::WalletNetwork;

pub(crate) type WalletDatabase = WalletDb<rusqlite::Connection, WalletNetwork, SystemClock, OsRng>;

/// User-driven wallet operations can afford a longer wait for a short sync write.
pub(crate) const WALLET_DB_BUSY_TIMEOUT: Duration = Duration::from_secs(10);
/// Account creation/import runs after sync is paused, so a shorter wait exposes real stalls.
pub(crate) const ACCOUNT_MUTATION_DB_BUSY_TIMEOUT: Duration = Duration::from_secs(5);
/// The sync loop should absorb brief read/write overlap without stretching cancel too far.
pub(crate) const SYNC_DB_BUSY_TIMEOUT: Duration = Duration::from_secs(2);
pub(crate) const READ_DB_BUSY_TIMEOUT: Duration = Duration::from_secs(2);

pub(crate) fn open_wallet_db_with_timeout(
    db_path: &str,
    network: WalletNetwork,
    timeout: Duration,
) -> Result<WalletDatabase, String> {
    let conn = rusqlite::Connection::open(db_path)
        .map_err(|e| format!("Failed to open wallet DB: {e}"))?;
    conn.busy_timeout(timeout)
        .map_err(|e| format!("Failed to configure wallet DB busy timeout: {e}"))?;
    rusqlite::vtab::array::load_module(&conn)
        .map_err(|e| format!("Failed to load SQLite array module: {e}"))?;
    Ok(WalletDb::from_connection(conn, network, SystemClock, OsRng))
}

pub(crate) fn open_readonly_conn_with_timeout(
    db_path: &str,
    timeout: Option<Duration>,
) -> Result<rusqlite::Connection, String> {
    let conn =
        rusqlite::Connection::open_with_flags(db_path, rusqlite::OpenFlags::SQLITE_OPEN_READ_ONLY)
            .map_err(|e| format!("Failed to open DB: {e}"))?;
    if let Some(timeout) = timeout {
        conn.busy_timeout(timeout)
            .map_err(|e| format!("Failed to configure DB busy timeout: {e}"))?;
    }
    Ok(conn)
}
