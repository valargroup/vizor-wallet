import 'package:flutter_rust_bridge/flutter_rust_bridge.dart' show Uint64List;
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/migration/models/migration_view_state.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

void main() {
  test('account with Orchard funds plans denominations', () {
    expect(
      migrationViewState(
        rustPhase: null,
        hasPendingMigration: false,
        hasCompletedMigration: false,
        orchardBalance: BigInt.from(1),
        ironwoodBalance: BigInt.zero,
      ),
      MigrationViewState.planningDenominations,
    );
  });

  test('account with a pending migration shows confirmation wait', () {
    expect(
      migrationViewState(
        rustPhase: null,
        hasPendingMigration: true,
        hasCompletedMigration: false,
        orchardBalance: BigInt.zero,
        ironwoodBalance: BigInt.zero,
      ),
      MigrationViewState.waitingMigrationConfirmations,
    );
  });

  test('account with a mined migration shows complete', () {
    expect(
      migrationViewState(
        rustPhase: null,
        hasPendingMigration: false,
        hasCompletedMigration: true,
        orchardBalance: BigInt.zero,
        ironwoodBalance: BigInt.from(1),
      ),
      MigrationViewState.complete,
    );
  });

  test('account with migrated ironwood balance shows complete', () {
    expect(
      migrationViewState(
        rustPhase: null,
        hasPendingMigration: false,
        hasCompletedMigration: false,
        orchardBalance: BigInt.zero,
        ironwoodBalance: BigInt.from(1),
      ),
      MigrationViewState.complete,
    );
  });

  test('account with remaining orchard funds stays idle after completion', () {
    expect(
      migrationViewState(
        rustPhase: null,
        hasPendingMigration: false,
        hasCompletedMigration: true,
        orchardBalance: BigInt.from(1),
        ironwoodBalance: BigInt.from(1),
      ),
      MigrationViewState.planningDenominations,
    );
  });

  test('account with no orchard or ironwood funds shows no-op', () {
    expect(
      migrationViewState(
        rustPhase: null,
        hasPendingMigration: false,
        hasCompletedMigration: false,
        orchardBalance: BigInt.zero,
        ironwoodBalance: BigInt.zero,
      ),
      MigrationViewState.noOrchardFunds,
    );
  });

  test('rust phase mapping covers explicit migration phases', () {
    expect(
      migrationViewStateFromRustPhase('waiting_for_spendable_orchard'),
      MigrationViewState.waitingForSpendableOrchard,
    );
    expect(
      migrationViewStateFromRustPhase('ready_to_prepare'),
      MigrationViewState.planningDenominations,
    );
    expect(
      migrationViewStateFromRustPhase('broadcast_scheduled'),
      MigrationViewState.broadcastScheduled,
    );
    expect(
      migrationViewStateFromRustPhase('failed_terminal'),
      MigrationViewState.failedTerminal,
    );
  });

  test('migration txid matching accepts reversed byte order', () {
    const broadcastOrder =
        '24fccdf39b619967ac5904743cb0f4a33b0b4d4b67b84dcee0f4ba0dc2887725';
    const historyOrder =
        '257788c20dbaf4e0ce4db8674b4d0b3ba3f4b03c740459ac6799619bf3cdfc24';

    expect(migrationTxidsMatch(historyOrder, broadcastOrder), isTrue);
  });

  test('migration first transaction index accepts reversed txid order', () {
    const firstBroadcastTxid =
        '24fccdf39b619967ac5904743cb0f4a33b0b4d4b67b84dcee0f4ba0dc2887725';
    const firstHistoryTxid =
        '257788c20dbaf4e0ce4db8674b4d0b3ba3f4b03c740459ac6799619bf3cdfc24';

    expect(
      migrationFirstTransactionIndex(
        transactionTxids: [
          '617b461a369552df0cda9c1764dadb542e240acc433de17660fc20bc0328bf81',
          firstHistoryTxid,
        ],
        firstTxid: firstBroadcastTxid,
      ),
      1,
    );
  });

  test('migration txid matching rejects invalid and unrelated txids', () {
    const txid =
        '24fccdf39b619967ac5904743cb0f4a33b0b4d4b67b84dcee0f4ba0dc2887725';
    const unrelated =
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

    expect(migrationTxidsMatch(txid, 'not-a-txid'), isFalse);
    expect(migrationTxidsMatch(txid, unrelated), isFalse);
  });

  test('software auto-advance fires only at ready_to_migrate, software, idle', () {
    rust_sync.MigrationStatus ready({int signedChildren = 0}) =>
        rust_sync.MigrationStatus(
          phase: 'ready_to_migrate',
          targetValuesZatoshi: Uint64List(0),
          preparedNoteCount: 0,
          denominationConfirmationCount: 3,
          denominationConfirmationTarget: 3,
          pendingTxCount: 0,
          signedChildPcztCount: signedChildren,
          pendingPrepTxCount: 0,
          broadcastedTxCount: 0,
          confirmedTxCount: 0,
          totalCount: 4,
          canAbandon: false,
          signingBatchLimit: 8,
          broadcastWindowSeconds: BigInt.from(180),
          maxPreparedNotesPerRun: 64,
          scheduledBroadcasts: const [],
        );

    expect(
      migrationShouldAutoAdvanceSoftware(
        status: ready(),
        isHardware: false,
        runInFlight: false,
        alreadyAttempted: false,
      ),
      isTrue,
    );
    // hardware excluded
    expect(
      migrationShouldAutoAdvanceSoftware(
        status: ready(),
        isHardware: true,
        runInFlight: false,
        alreadyAttempted: false,
      ),
      isFalse,
    );
    // presigned children present -> not the software path
    expect(
      migrationShouldAutoAdvanceSoftware(
        status: ready(signedChildren: 4),
        isHardware: false,
        runInFlight: false,
        alreadyAttempted: false,
      ),
      isFalse,
    );
    // already attempted / in flight -> no re-fire
    expect(
      migrationShouldAutoAdvanceSoftware(
        status: ready(),
        isHardware: false,
        runInFlight: true,
        alreadyAttempted: false,
      ),
      isFalse,
    );
    expect(
      migrationShouldAutoAdvanceSoftware(
        status: ready(),
        isHardware: false,
        runInFlight: false,
        alreadyAttempted: true,
      ),
      isFalse,
    );
  });
}
