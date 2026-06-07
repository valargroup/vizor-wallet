import 'dart:math';

import 'migration_demo_state.dart';

/// Builds a believable, staggered transfer schedule for the migration demo.
///
/// Transfer 1 "fires" immediately (offset 0); transfers 2 and 3 fire at random
/// points inside the window so the in-progress UI looks naturally spaced.
/// [now] and [random] are injected for deterministic tests.
MigrationDemoState buildMigrationDemoState({
  required String accountUuid,
  required BigInt displayAmountZatoshi,
  required List<String> txids,
  required DateTime now,
  required Random random,
  int totalDurationMs = MigrationDemoState.defaultDurationMs,
}) {
  final second = _randomInRange(
    random,
    (totalDurationMs * 0.15).round(),
    (totalDurationMs * 0.55).round(),
  );
  final third = _randomInRange(
    random,
    (totalDurationMs * 0.55).round(),
    (totalDurationMs * 0.92).round(),
  );
  final offsets = <int>[0, second, third]..sort();

  return MigrationDemoState(
    accountUuid: accountUuid,
    startedAtEpochMs: now.millisecondsSinceEpoch,
    totalDurationMs: totalDurationMs,
    displayAmountZatoshi: displayAmountZatoshi,
    transferOffsetsMs: offsets,
    txids: txids,
  );
}

int _randomInRange(Random random, int minMs, int maxMs) {
  final span = (maxMs - minMs).clamp(1, 1 << 31);
  return minMs + random.nextInt(span);
}
