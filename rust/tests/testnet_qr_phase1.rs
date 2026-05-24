use std::path::{Path, PathBuf};
use std::time::{Duration, Instant};

use rust_lib_zcash_wallet::api::{sync as sync_api, wallet as wallet_api};

const NETWORK: &str = "test";
const DEFAULT_LIGHTWALLETD_URL: &str = "https://testnet.zec.rocks:443";
const TESTNET_QR_SEED: &str = "powder bronze skirt because truly bonus link gloom cluster quantum birth mutual limit veteran garden almost trophy potato twelve win crush surface decline uphold";
const TESTNET_QR_BIRTHDAY: u64 = 4_000_000;
const FIRST_SEND_ZATOSHI: u64 = 50_000;
const SECOND_SEND_ZATOSHI: u64 = 20_000;
const MIN_POST_FIRST_CHANGE_ZATOSHI: u64 = 30_000;

fn path_str(path: &Path) -> String {
    path.to_str().expect("utf-8 path").to_string()
}

fn lightwalletd_url() -> String {
    std::env::var("VIZOR_QR_TESTNET_LIGHTWALLETD_URL")
        .unwrap_or_else(|_| DEFAULT_LIGHTWALLETD_URL.to_string())
}

fn env_u64(name: &str, default: u64) -> u64 {
    std::env::var(name)
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(default)
}

fn sync_wallet(db_path: &Path, lightwalletd_url: &str) {
    sync_api::run_full_sync_blocking(
        path_str(db_path),
        lightwalletd_url.to_string(),
        NETWORK.to_string(),
        1,
    )
    .expect("sync wallet");
}

fn balance(db_path: &Path, account_uuid: &str) -> sync_api::WalletBalance {
    sync_api::get_balance(
        path_str(db_path),
        NETWORK.to_string(),
        account_uuid.to_string(),
    )
    .expect("get balance")
}

fn orchard_note_versions(db_path: &Path, is_change: bool) -> Vec<i64> {
    let conn = rusqlite::Connection::open(db_path).expect("open wallet db");
    let mut stmt = conn
        .prepare(
            "SELECT note_version
             FROM orchard_received_notes
             WHERE is_change = ?1
             ORDER BY id",
        )
        .expect("prepare note version query");
    stmt.query_map([if is_change { 1 } else { 0 }], |row| row.get(0))
        .expect("query note versions")
        .map(|row| row.expect("note version row"))
        .collect()
}

fn qr_change_count(db_path: &Path) -> i64 {
    let conn = rusqlite::Connection::open(db_path).expect("open wallet db");
    conn.query_row(
        "SELECT COUNT(*)
         FROM orchard_received_notes
         WHERE note_version = 3
           AND is_change = 1",
        [],
        |row| row.get(0),
    )
    .expect("query QR change")
}

fn unspent_qr_change_count(db_path: &Path) -> i64 {
    let conn = rusqlite::Connection::open(db_path).expect("open wallet db");
    conn.query_row(
        "SELECT COUNT(*)
         FROM orchard_received_notes rn
         LEFT JOIN orchard_received_note_spends s
           ON s.orchard_received_note_id = rn.id
         WHERE rn.note_version = 3
           AND rn.is_change = 1
           AND s.transaction_id IS NULL",
        [],
        |row| row.get(0),
    )
    .expect("query unspent QR change")
}

fn spent_qr_change_count(db_path: &Path) -> i64 {
    let conn = rusqlite::Connection::open(db_path).expect("open wallet db");
    conn.query_row(
        "SELECT COUNT(DISTINCT rn.id)
         FROM orchard_received_notes rn
         JOIN orchard_received_note_spends s
           ON s.orchard_received_note_id = rn.id
         WHERE rn.note_version = 3
           AND rn.is_change = 1",
        [],
        |row| row.get(0),
    )
    .expect("query spent QR change")
}

fn execute_send(
    db_path: &Path,
    lightwalletd_url: &str,
    account_uuid: &str,
    to_address: &str,
    amount_zatoshi: u64,
    flow_id: &str,
) -> String {
    let proposal = sync_api::propose_send(
        path_str(db_path),
        NETWORK.to_string(),
        account_uuid.to_string(),
        flow_id.to_string(),
        to_address.to_string(),
        amount_zatoshi,
        None,
    )
    .expect("propose send");
    assert!(
        !proposal.needs_sapling_params,
        "testnet QR test should use Orchard-only recipients"
    );

    let result = sync_api::execute_proposal(
        path_str(db_path),
        lightwalletd_url.to_string(),
        proposal.proposal_id,
        flow_id.to_string(),
        TESTNET_QR_SEED.as_bytes().to_vec(),
        None,
        None,
    )
    .expect("execute proposal");
    assert_eq!(result.status, "broadcasted", "{:?}", result.message);
    result
        .txids
        .split(',')
        .next()
        .expect("at least one txid")
        .to_string()
}

fn reversed_txid_hex(txid: &str) -> String {
    let mut bytes = hex::decode(txid).expect("txid hex");
    bytes.reverse();
    hex::encode(bytes)
}

fn wait_for_mined_tx(
    db_path: &Path,
    lightwalletd_url: &str,
    account_uuid: &str,
    txid: &str,
    timeout: Duration,
    poll: Duration,
) {
    let start = Instant::now();
    let reversed_txid = reversed_txid_hex(txid);
    loop {
        sync_wallet(db_path, lightwalletd_url);
        let history = sync_api::get_transaction_history(
            path_str(db_path),
            NETWORK.to_string(),
            Some(50),
            account_uuid.to_string(),
        )
        .expect("transaction history");
        if let Some(tx) = history.iter().find(|tx| {
            (tx.txid_hex == txid || tx.txid_hex == reversed_txid)
                && tx.mined_height > 0
                && !tx.expired_unmined
        }) {
            eprintln!(
                "mined tx {txid} matched history {} at height {}",
                tx.txid_hex, tx.mined_height
            );
            return;
        }

        let recent: Vec<String> = history
            .iter()
            .take(5)
            .map(|tx| {
                format!(
                    "{}:height={}:expired={}",
                    tx.txid_hex, tx.mined_height, tx.expired_unmined
                )
            })
            .collect();
        eprintln!(
            "waiting for mined tx {txid} or {reversed_txid}; elapsed={}s recent=[{}]",
            start.elapsed().as_secs(),
            recent.join(", ")
        );

        assert!(
            start.elapsed() < timeout,
            "timed out waiting for testnet tx {txid} to mine"
        );
        std::thread::sleep(poll);
    }
}

fn assert_receiver_outputs_are_v2(receiver_db: &Path) {
    let receiver_external_versions = orchard_note_versions(receiver_db, false);
    assert!(
        !receiver_external_versions.is_empty(),
        "receiver should decrypt the external Orchard output"
    );
    assert!(
        receiver_external_versions.iter().all(|v| *v == 2),
        "external recipient Orchard outputs should remain ordinary V2, got {:?}",
        receiver_external_versions
    );
}

fn create_receiver(lightwalletd_url: &str) -> (tempfile::TempDir, PathBuf, String) {
    let receiver_birthday =
        wallet_api::get_latest_block_height(lightwalletd_url.to_string()).expect("testnet tip");
    let receiver_dir = tempfile::tempdir().expect("receiver tempdir");
    let receiver_db = receiver_dir.path().join("zcash_wallet.db");
    let receiver = wallet_api::create_wallet(
        NETWORK.to_string(),
        path_str(&receiver_db),
        Some(receiver_birthday),
        Some("QR receiver".to_string()),
    )
    .expect("create receiver");
    let receiver_orchard_address = sync_api::get_next_available_address(
        path_str(&receiver_db),
        NETWORK.to_string(),
        receiver.account_uuid,
        "orchard".to_string(),
    )
    .expect("receiver Orchard address");

    (receiver_dir, receiver_db, receiver_orchard_address)
}

#[test]
#[ignore = "requires the funded testnet QR seed and waits for public testnet confirmations"]
fn funded_testnet_seed_can_create_reopen_and_spend_qr_change() {
    if std::env::var("VIZOR_QR_TESTNET_LIVE").as_deref() != Ok("1") {
        eprintln!("set VIZOR_QR_TESTNET_LIVE=1 to run the live QR Phase 1 test");
        return;
    }

    let lightwalletd_url = lightwalletd_url();
    let timeout = Duration::from_secs(env_u64("VIZOR_QR_TESTNET_CONFIRM_TIMEOUT_SECS", 3600));
    let poll = Duration::from_secs(env_u64("VIZOR_QR_TESTNET_CONFIRM_POLL_SECS", 75));
    eprintln!("using testnet lightwalletd endpoint {lightwalletd_url}");
    assert_eq!(
        wallet_api::get_lightwalletd_chain_name(lightwalletd_url.clone()).expect("chain name"),
        "test"
    );

    let sender_dir = tempfile::tempdir().expect("sender tempdir");
    let sender_db = sender_dir.path().join("zcash_wallet.db");
    let sender = wallet_api::import_wallet(
        TESTNET_QR_SEED.to_string(),
        Some(TESTNET_QR_BIRTHDAY),
        NETWORK.to_string(),
        path_str(&sender_db),
        Some("QR funded testnet seed".to_string()),
    )
    .expect("import funded sender");
    let (_receiver_dir, receiver_db, receiver_orchard_address) = create_receiver(&lightwalletd_url);

    sync_wallet(&sender_db, &lightwalletd_url);
    let starting_balance = balance(&sender_db, &sender.account_uuid);
    eprintln!(
        "starting spendable balance: {} zatoshi",
        starting_balance.spendable
    );
    assert!(
        starting_balance.spendable
            > FIRST_SEND_ZATOSHI + SECOND_SEND_ZATOSHI + MIN_POST_FIRST_CHANGE_ZATOSHI,
        "funded testnet seed needs more spendable balance, got {} zatoshi",
        starting_balance.spendable
    );

    let send_max = sync_api::estimate_send_max(
        path_str(&sender_db),
        NETWORK.to_string(),
        sender.account_uuid.clone(),
        receiver_orchard_address.clone(),
        None,
    )
    .expect("estimate send max");
    assert!(
        send_max.amount_zatoshi
            > FIRST_SEND_ZATOSHI + SECOND_SEND_ZATOSHI + MIN_POST_FIRST_CHANGE_ZATOSHI,
        "send-max amount too small for QR change test: {}",
        send_max.amount_zatoshi
    );

    let qr_change_before = qr_change_count(&sender_db);
    let first_txid = execute_send(
        &sender_db,
        &lightwalletd_url,
        &sender.account_uuid,
        &receiver_orchard_address,
        FIRST_SEND_ZATOSHI,
        "testnet-qr-first-send",
    );
    eprintln!("first send broadcast: {first_txid}");
    assert!(
        qr_change_count(&sender_db) > qr_change_before,
        "first send did not persist a new QR Orchard change note"
    );
    assert!(
        unspent_qr_change_count(&sender_db) > 0,
        "first send did not leave an unspent QR Orchard change note"
    );

    wait_for_mined_tx(
        &sender_db,
        &lightwalletd_url,
        &sender.account_uuid,
        &first_txid,
        timeout,
        poll,
    );
    sync_wallet(&receiver_db, &lightwalletd_url);
    assert_receiver_outputs_are_v2(&receiver_db);

    let reopened_balance = balance(&sender_db, &sender.account_uuid);
    eprintln!(
        "reopened spendable balance after first send: {} zatoshi",
        reopened_balance.spendable
    );
    assert!(
        reopened_balance.spendable >= SECOND_SEND_ZATOSHI + 20_000,
        "reopened sender should have spendable QR change, got {}",
        reopened_balance.spendable
    );

    let spent_qr_before = spent_qr_change_count(&sender_db);
    let second_txid = execute_send(
        &sender_db,
        &lightwalletd_url,
        &sender.account_uuid,
        &receiver_orchard_address,
        SECOND_SEND_ZATOSHI,
        "testnet-qr-second-send",
    );
    eprintln!("second send broadcast: {second_txid}");
    assert!(
        spent_qr_change_count(&sender_db) > spent_qr_before,
        "second send did not spend a persisted QR Orchard change note"
    );

    wait_for_mined_tx(
        &sender_db,
        &lightwalletd_url,
        &sender.account_uuid,
        &second_txid,
        timeout,
        poll,
    );
    sync_wallet(&receiver_db, &lightwalletd_url);
    assert_receiver_outputs_are_v2(&receiver_db);
}

#[test]
#[ignore = "requires an existing sender DB with unspent QR change and waits for public testnet confirmations"]
fn existing_testnet_db_can_spend_qr_change() {
    if std::env::var("VIZOR_QR_TESTNET_LIVE").as_deref() != Ok("1") {
        eprintln!("set VIZOR_QR_TESTNET_LIVE=1 to run the live QR Phase 1 test");
        return;
    }

    let sender_db = match std::env::var("VIZOR_QR_TESTNET_EXISTING_SENDER_DB") {
        Ok(path) => PathBuf::from(path),
        Err(_) => {
            eprintln!("set VIZOR_QR_TESTNET_EXISTING_SENDER_DB to run existing DB QR spend");
            return;
        }
    };
    let lightwalletd_url = lightwalletd_url();
    let timeout = Duration::from_secs(env_u64("VIZOR_QR_TESTNET_CONFIRM_TIMEOUT_SECS", 3600));
    let poll = Duration::from_secs(env_u64("VIZOR_QR_TESTNET_CONFIRM_POLL_SECS", 75));
    let accounts = wallet_api::list_accounts(path_str(&sender_db), NETWORK.to_string())
        .expect("list sender accounts");
    let sender_account = accounts.first().expect("sender account");
    let (_receiver_dir, receiver_db, receiver_orchard_address) = create_receiver(&lightwalletd_url);

    sync_wallet(&sender_db, &lightwalletd_url);
    assert!(
        unspent_qr_change_count(&sender_db) > 0,
        "existing sender DB should contain unspent QR change"
    );
    let spent_qr_before = spent_qr_change_count(&sender_db);
    let txid = execute_send(
        &sender_db,
        &lightwalletd_url,
        &sender_account.uuid,
        &receiver_orchard_address,
        SECOND_SEND_ZATOSHI,
        "testnet-qr-existing-db-send",
    );
    eprintln!("existing DB QR spend broadcast: {txid}");
    assert!(
        spent_qr_change_count(&sender_db) > spent_qr_before,
        "existing DB send did not spend a persisted QR Orchard change note"
    );
    wait_for_mined_tx(
        &sender_db,
        &lightwalletd_url,
        &sender_account.uuid,
        &txid,
        timeout,
        poll,
    );
    sync_wallet(&receiver_db, &lightwalletd_url);
    assert_receiver_outputs_are_v2(&receiver_db);
}
