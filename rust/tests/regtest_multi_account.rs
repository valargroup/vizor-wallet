mod common;

use common::{
    add_account_with_birthday, create_wallet, current_tip_height, ensure_regtest_up,
    exclusive_regtest, fund_wallet, get_balance, get_transaction_history, list_accounts,
    mine_blocks, sync_wallet,
};

#[test]
#[ignore = "requires Dockerized zcashd/lightwalletd regtest services"]
fn adding_second_account_after_tip_sync_recovers_historical_and_future_funds() {
    let _guard = exclusive_regtest();
    ensure_regtest_up();

    let (main_dir, first_wallet) = create_wallet("Primary");
    let main_db = main_dir.path().join("zcash_wallet.db");

    fund_wallet(&first_wallet.unified_address, "1.1");
    sync_wallet(&main_db);
    let first_before = get_balance(&main_db, &first_wallet.account_uuid);
    assert!(
        first_before.spendable >= 110_000_000,
        "primary account should have its initial funds, got {}",
        first_before.spendable
    );

    let historical_birthday = current_tip_height();
    let (_external_dir, external_wallet) = create_wallet("Secondary Source");
    fund_wallet(&external_wallet.unified_address, "0.7");
    mine_blocks(20);

    sync_wallet(&main_db);
    let first_after_catchup = get_balance(&main_db, &first_wallet.account_uuid);
    assert_eq!(
        first_after_catchup.spendable, first_before.spendable,
        "syncing past the second account's receive height should not affect the first account"
    );

    let second_account = add_account_with_birthday(
        &main_db,
        "Secondary",
        &external_wallet.mnemonic,
        Some(historical_birthday),
    );
    let accounts = list_accounts(&main_db);
    assert_eq!(accounts.len(), 2, "wallet should now contain two accounts");

    sync_wallet(&main_db);

    let second_after_historical = get_balance(&main_db, &second_account.account_uuid);
    assert!(
        second_after_historical.spendable >= 70_000_000,
        "second account should recover historical funds after being added, got {}",
        second_after_historical.spendable
    );

    let first_after_add = get_balance(&main_db, &first_wallet.account_uuid);
    assert_eq!(
        first_after_add.spendable, first_before.spendable,
        "adding a second account must not disturb the first account balance"
    );

    fund_wallet(&first_wallet.unified_address, "0.4");
    fund_wallet(&second_account.unified_address, "0.6");

    sync_wallet(&main_db);

    let first_final = get_balance(&main_db, &first_wallet.account_uuid);
    let second_final = get_balance(&main_db, &second_account.account_uuid);

    assert!(
        first_final.spendable >= first_before.spendable + 40_000_000,
        "first account should pick up new funds after multi-account sync, got {}",
        first_final.spendable
    );
    assert!(
        second_final.spendable >= second_after_historical.spendable + 60_000_000,
        "second account should pick up both historical and new funds, got {}",
        second_final.spendable
    );

    let second_history = get_transaction_history(&main_db, &second_account.account_uuid);
    let inbound_count = second_history
        .iter()
        .filter(|tx| tx.account_balance_delta > 0)
        .count();
    assert!(
        inbound_count >= 2,
        "second account should show both historical and new inbound transactions, got {}",
        inbound_count
    );
}
