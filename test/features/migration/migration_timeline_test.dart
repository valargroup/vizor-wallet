import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/migration/migration_copy.dart';
import 'package:zcash_wallet/src/features/migration/models/migration_timeline_model.dart';
import 'package:zcash_wallet/src/features/migration/widgets/migration_timeline.dart';

Future<void> _pump(
  WidgetTester tester,
  MigrationTimelineModel model, {
  int totalShares = 3,
  VoidCallback? onScanSends,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: AppTheme(
        data: AppThemeData.light,
        child: Scaffold(
          body: SingleChildScrollView(
            child: MigrationTimeline(
              model: model,
              status: null,
              shares: const [],
              amountZatoshi: BigInt.from(120000000),
              totalShares: totalShares,
              now: DateTime.fromMillisecondsSinceEpoch(0),
              onScanSends: onScanSends,
            ),
          ),
        ),
      ),
    ),
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
}
