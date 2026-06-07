import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/migration/models/migration_demo_state.dart';

void main() {
  // 24h window; transfer offsets at 0, 4h, 15h.
  const fourH = 4 * 60 * 60 * 1000;
  const fifteenH = 15 * 60 * 60 * 1000;
  final state = MigrationDemoState(
    accountUuid: 'acc-1',
    startedAtEpochMs: 1000000,
    totalDurationMs: MigrationDemoState.defaultDurationMs,
    displayAmountZatoshi: BigInt.from(123450000),
    transferOffsetsMs: const [0, fourH, fifteenH],
    txids: const ['tx1', 'tx2', 'tx3'],
  );

  DateTime at(int offsetMs) =>
      DateTime.fromMillisecondsSinceEpoch(1000000 + offsetMs);

  test('json round-trips including BigInt amount', () {
    final decoded = MigrationDemoState.decode(state.encode());
    expect(decoded.accountUuid, 'acc-1');
    expect(decoded.displayAmountZatoshi, BigInt.from(123450000));
    expect(decoded.transferOffsetsMs, const [0, fourH, fifteenH]);
    expect(decoded.txids, const ['tx1', 'tx2', 'tx3']);
  });

  test('progress and remaining derive from now', () {
    expect(state.progressFraction(at(0)), 0.0);
    expect(state.isComplete(at(0)), isFalse);
    final mid = MigrationDemoState.defaultDurationMs ~/ 2;
    expect(state.progressFraction(at(mid)), closeTo(0.5, 0.001));
    expect(state.isComplete(at(MigrationDemoState.defaultDurationMs)), isTrue);
    expect(
        state.progressFraction(at(MigrationDemoState.defaultDurationMs * 2)),
        1.0);
  });

  test('transfersSent flips per offset; eta counts down', () {
    expect(state.transfersSent(at(0)), const [true, false, false]);
    expect(state.transfersSent(at(fourH)), const [true, true, false]);
    expect(state.transfersSent(at(fifteenH)), const [true, true, true]);
    expect(state.transferEta(1, at(0)).inHours, 4);
    expect(state.transferEta(1, at(fourH)), Duration.zero);
  });
}
