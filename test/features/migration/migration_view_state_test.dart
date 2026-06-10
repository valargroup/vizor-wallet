import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/migration/models/migration_view_state.dart';

void main() {
  test('hardware account shows softwareRequired', () {
    expect(
      migrationViewState(
        isHardware: true,
        rustPhase: 'ready_to_prepare',
        hasPendingMigration: true,
        hasCompletedMigration: false,
        orchardBalance: BigInt.from(1),
        ironwoodBalance: BigInt.zero,
      ),
      MigrationViewState.softwareRequired,
    );
  });

  test('software account with Orchard funds plans denominations', () {
    expect(
      migrationViewState(
        isHardware: false,
        rustPhase: null,
        hasPendingMigration: false,
        hasCompletedMigration: false,
        orchardBalance: BigInt.from(1),
        ironwoodBalance: BigInt.zero,
      ),
      MigrationViewState.planningDenominations,
    );
  });

  test('software account with a pending migration shows confirmation wait', () {
    expect(
      migrationViewState(
        isHardware: false,
        rustPhase: null,
        hasPendingMigration: true,
        hasCompletedMigration: false,
        orchardBalance: BigInt.zero,
        ironwoodBalance: BigInt.zero,
      ),
      MigrationViewState.waitingMigrationConfirmations,
    );
  });

  test('software account with a mined migration shows complete', () {
    expect(
      migrationViewState(
        isHardware: false,
        rustPhase: null,
        hasPendingMigration: false,
        hasCompletedMigration: true,
        orchardBalance: BigInt.zero,
        ironwoodBalance: BigInt.from(1),
      ),
      MigrationViewState.complete,
    );
  });

  test('software account with migrated ironwood balance shows complete', () {
    expect(
      migrationViewState(
        isHardware: false,
        rustPhase: null,
        hasPendingMigration: false,
        hasCompletedMigration: false,
        orchardBalance: BigInt.zero,
        ironwoodBalance: BigInt.from(1),
      ),
      MigrationViewState.complete,
    );
  });

  test(
    'software account with remaining orchard funds stays idle after completion',
    () {
      expect(
        migrationViewState(
          isHardware: false,
          rustPhase: null,
          hasPendingMigration: false,
          hasCompletedMigration: true,
          orchardBalance: BigInt.from(1),
          ironwoodBalance: BigInt.from(1),
        ),
        MigrationViewState.planningDenominations,
      );
    },
  );

  test('software account with no orchard or ironwood funds shows no-op', () {
    expect(
      migrationViewState(
        isHardware: false,
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
}
