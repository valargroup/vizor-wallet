import 'package:flutter/material.dart' show MaterialApp;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';
import 'package:zcash_wallet/src/features/activity/models/activity_row_data.dart';
import 'package:zcash_wallet/src/features/activity/swap_activity_row_mapper.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_prototype_models.dart';

void main() {
  testWidgets('maps swap records to shared activity table rows', (
    tester,
  ) async {
    ActivityRowData? row;

    await tester.pumpWidget(
      MaterialApp(
        home: AppTheme(
          data: AppThemeData.light,
          child: Builder(
            builder: (context) {
              row = buildSwapActivityRow(
                context: context,
                record: const SwapIntentRecord(
                  id: 'swap-1',
                  providerLabel: 'NEAR Intents',
                  pairText: 'ZEC -> USDC',
                  sellAmountText: '0.0030 ZEC',
                  receiveEstimateText: '0.21 USDC',
                  status: SwapIntentStatus.processing,
                  nextAction: 'Swap is processing',
                  direction: SwapDirection.zecToExternal,
                  externalAsset: SwapAsset.usdc,
                  createdAt: null,
                  updatedAt: null,
                ),
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    expect(row!.title, 'Swap ZEC to USDC');
    expect(row!.subtitle, 'NEAR Intents');
    expect(row!.subtitleIconName, AppIcons.link);
    expect(row!.amountText, '-0.0030 ZEC');
    expect(row!.statusText, 'In progress');
    expect(row!.statusIconName, AppIcons.loader);
    expect(row!.timestampText, '--');
  });

  testWidgets('maps receive-ZEC swaps as inbound activity rows', (
    tester,
  ) async {
    ActivityRowData? row;

    await tester.pumpWidget(
      MaterialApp(
        home: AppTheme(
          data: AppThemeData.light,
          child: Builder(
            builder: (context) {
              row = buildSwapActivityRow(
                context: context,
                record: SwapIntentRecord(
                  id: 'swap-2',
                  providerLabel: 'NEAR Intents',
                  pairText: 'USDC -> ZEC',
                  sellAmountText: '0.21 USDC',
                  receiveEstimateText: '0.0030 ZEC',
                  status: SwapIntentStatus.awaitingExternalDeposit,
                  nextAction: 'Send USDC to the deposit address',
                  direction: SwapDirection.externalToZec,
                  externalAsset: SwapAsset.usdc,
                  updatedAt: DateTime.utc(2026, 5, 7, 10, 30),
                ),
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    expect(row!.title, 'Swap USDC to ZEC');
    expect(row!.amountText, '+0.0030 ZEC');
    expect(row!.statusText, 'Action needed');
    expect(row!.statusIconName, AppIcons.warning);
    expect(row!.timestampText, isNot('--'));
  });

  testWidgets('masks swap row amounts in privacy mode', (tester) async {
    ActivityRowData? row;

    await tester.pumpWidget(
      MaterialApp(
        home: AppTheme(
          data: AppThemeData.light,
          child: Builder(
            builder: (context) {
              row = buildSwapActivityRow(
                context: context,
                privacyModeEnabled: true,
                record: const SwapIntentRecord(
                  id: 'swap-private',
                  providerLabel: 'NEAR Intents',
                  pairText: 'ZEC -> USDC',
                  sellAmountText: '0.0030 ZEC',
                  receiveEstimateText: '0.21 USDC',
                  status: SwapIntentStatus.complete,
                  nextAction: 'Complete',
                  direction: SwapDirection.zecToExternal,
                  externalAsset: SwapAsset.usdc,
                ),
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    expect(row!.amountText, isNot(contains('0.0030')));
    expect(row!.amountText, contains('***'));
  });
}
