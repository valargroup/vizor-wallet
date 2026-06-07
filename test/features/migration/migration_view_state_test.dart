import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/migration/models/migration_demo_state.dart';
import 'package:zcash_wallet/src/features/migration/models/migration_view_state.dart';

void main() {
  final now = DateTime.fromMillisecondsSinceEpoch(1000000);

  MigrationDemoState demoStartedAt(int startMs, {int durationMs = 10000}) =>
      MigrationDemoState(
        accountUuid: 'acc',
        startedAtEpochMs: startMs,
        totalDurationMs: durationMs,
        displayAmountZatoshi: BigInt.zero,
        transferOffsetsMs: const [0, 1, 2],
        txids: const [],
      );

  test('software account always shows keystoneRequired', () {
    expect(
      migrationViewState(isHardware: false, demo: null, now: now),
      MigrationViewState.keystoneRequired,
    );
    expect(
      migrationViewState(
          isHardware: false, demo: demoStartedAt(1000000), now: now),
      MigrationViewState.keystoneRequired,
    );
  });

  test('keystone account with no demo shows idle', () {
    expect(
      migrationViewState(isHardware: true, demo: null, now: now),
      MigrationViewState.idle,
    );
  });

  test('keystone account with an active demo shows inProgress', () {
    // started now, 10s window -> not complete.
    expect(
      migrationViewState(
          isHardware: true, demo: demoStartedAt(now.millisecondsSinceEpoch),
          now: now),
      MigrationViewState.inProgress,
    );
  });

  test('keystone account past the window shows complete', () {
    // started 20s before now, 10s window -> complete.
    expect(
      migrationViewState(
        isHardware: true,
        demo: demoStartedAt(now.millisecondsSinceEpoch - 20000,
            durationMs: 10000),
        now: now,
      ),
      MigrationViewState.complete,
    );
  });
}
