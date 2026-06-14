import 'package:flutter/material.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge.dart' show Uint64List;
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/migration/migration_copy.dart';
import 'package:zcash_wallet/src/features/migration/models/migration_timeline_model.dart';
import 'package:zcash_wallet/src/features/migration/models/migration_view_state.dart';
import 'package:zcash_wallet/src/features/migration/widgets/migration_timeline.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

Future<void> _pump(
  WidgetTester tester,
  MigrationTimelineModel model, {
  rust_sync.MigrationStatus? status,
  int totalShares = 3,
  DateTime? now,
  VoidCallback? onScanSends,
  VoidCallback? onRetry,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: AppTheme(
        data: AppThemeData.light,
        child: Scaffold(
          body: SingleChildScrollView(
            child: MigrationTimeline(
              model: model,
              status: status,
              shares: const [],
              amountZatoshi: BigInt.from(120000000),
              totalShares: totalShares,
              now: now ?? DateTime.fromMillisecondsSinceEpoch(0),
              onScanSends: onScanSends,
              onRetry: onRetry,
            ),
          ),
        ),
      ),
    ),
  );
}

rust_sync.MigrationStatus _status({
  required List<rust_sync.MigrationScheduledBroadcast> scheduledBroadcasts,
}) {
  return rust_sync.MigrationStatus(
    phase: 'broadcast_scheduled',
    targetValuesZatoshi: Uint64List(0),
    preparedNoteCount: 0,
    denominationConfirmationCount: 3,
    denominationConfirmationTarget: 3,
    pendingTxCount: scheduledBroadcasts.length,
    signedChildPcztCount: 0,
    pendingPrepTxCount: 0,
    broadcastedTxCount: 0,
    confirmedTxCount: 0,
    totalCount: scheduledBroadcasts.length,
    canAbandon: false,
    signingBatchLimit: 8,
    broadcastWindowSeconds: BigInt.from(180),
    maxPreparedNotesPerRun: 64,
    scheduledBroadcasts: scheduledBroadcasts,
  );
}

void main() {
  testWidgets('renders the three node titles', (tester) async {
    await _pump(
      tester,
      const MigrationTimelineModel(
        split: MigrationNodeStatus.done,
        confirm: MigrationNodeStatus.done,
        send: MigrationNodeStatus.active,
      ),
    );
    expect(find.text(MigrationCopy.splitTitle), findsOneWidget);
    expect(find.text(MigrationCopy.confirmTitle), findsOneWidget);
    expect(find.text(MigrationCopy.sendTitle), findsOneWidget);
  });

  testWidgets('staged fallback shows the scan action', (tester) async {
    await _pump(
      tester,
      const MigrationTimelineModel(
        split: MigrationNodeStatus.done,
        confirm: MigrationNodeStatus.done,
        send: MigrationNodeStatus.active,
        sendNeedsScan: true,
      ),
      onScanSends: () {},
    );
    expect(find.text(MigrationCopy.sendScanCta), findsOneWidget);
  });

  testWidgets('paused migration shows the resume action', (tester) async {
    await _pump(
      tester,
      const MigrationTimelineModel(
        split: MigrationNodeStatus.done,
        confirm: MigrationNodeStatus.done,
        send: MigrationNodeStatus.active,
        sendCanResume: true,
      ),
      onRetry: () {},
    );
    expect(find.text(MigrationCopy.sendResumeCta), findsOneWidget);
  });

  testWidgets('only the next scheduled share row shows a countdown', (
    tester,
  ) async {
    final now = DateTime.fromMillisecondsSinceEpoch(1000);
    await _pump(
      tester,
      const MigrationTimelineModel(
        split: MigrationNodeStatus.done,
        confirm: MigrationNodeStatus.done,
        send: MigrationNodeStatus.active,
      ),
      status: _status(
        scheduledBroadcasts: const [
          rust_sync.MigrationScheduledBroadcast(
            txidHex:
                'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
            scheduledAtMs: 61000,
            status: 'scheduled',
          ),
          rust_sync.MigrationScheduledBroadcast(
            txidHex:
                'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
            scheduledAtMs: 121000,
            status: 'scheduled',
          ),
        ],
      ),
      totalShares: 2,
      now: now,
    );

    expect(
      find.text(
        MigrationCopy.shareScheduledIn(
          migrationCountdownLabel(const Duration(seconds: 60)),
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        MigrationCopy.shareScheduledIn(
          migrationCountdownLabel(const Duration(seconds: 120)),
        ),
      ),
      findsNothing,
    );
    expect(find.text(MigrationCopy.shareScheduled), findsOneWidget);
  });
}
