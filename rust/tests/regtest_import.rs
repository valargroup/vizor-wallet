mod common;

use common::{
    create_wallet, current_tip_height, ensure_regtest_up, exclusive_regtest, fund_wallet,
    get_balance, get_transaction_history, import_wallet_with_birthday, list_accounts, mine_blocks,
    sync_wallet,
};

#[test]
#[ignore = "requires Dockerized zcashd/lightwalletd regtest services"]
fn import_wallet_with_historical_birthday_recovers_existing_funds() {
    let _guard = exclusive_regtest();
    ensure_regtest_up();

    let historical_birthday = current_tip_height();
    let (_source_dir, source_wallet) = create_wallet("Import Source");

    fund_wallet(&source_wallet.unified_address, "1.4");
    mine_blocks(15);

    let (imported_dir, imported_wallet) = import_wallet_with_birthday(
        &source_wallet.mnemonic,
        "Imported Account",
        Some(historical_birthday),
    );
    let imported_db = imported_dir.path().join("zcash_wallet.db");

    sync_wallet(&imported_db);

    let balance = get_balance(&imported_db, &imported_wallet.account_uuid);
    assert!(
        balance.spendable >= 140_000_000,
        "imported wallet should recover historical funds, got {}",
        balance.spendable
    );

    let accounts = list_accounts(&imported_db);
    assert_eq!(accounts.len(), 1, "imported wallet should expose one account");
    assert_eq!(accounts[0].uuid, imported_wallet.account_uuid);

    let history = get_transaction_history(&imported_db, &imported_wallet.account_uuid);
    assert!(
        history.iter().any(|tx| tx.account_balance_delta > 0),
        "imported wallet should show an inbound historical transaction"
    );
}
