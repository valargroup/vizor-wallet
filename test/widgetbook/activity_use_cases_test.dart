import 'package:flutter/material.dart' show MaterialApp;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/widgetbook/activity_use_cases.dart';

void main() {
  testWidgets('swap activity progress use case renders Figma row structure', (
    tester,
  ) async {
    await _pumpActivityUseCase(
      tester,
      buildActivitySwapProgressExternalToZecUseCase,
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Activity'), findsWidgets);
    expect(find.text('Swapping...'), findsOneWidget);
    expect(find.text('USDC on Optimism'), findsOneWidget);
    expect(find.text('-101.23 USDC'), findsOneWidget);
    expect(find.text('3/4 In progress'), findsOneWidget);
    expect(find.text('Receiving ZEC ...'), findsOneWidget);
    expect(find.text('+4.12 ZEC'), findsOneWidget);
    expect(find.text('Send failed'), findsOneWidget);
    expect(find.text('Refunded'), findsOneWidget);
  });

  testWidgets(
    'swap activity sending-ZEC use case stays on first progress step',
    (tester) async {
      await _pumpActivityUseCase(
        tester,
        buildActivitySwapSendingZecToExternalUseCase,
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Swapping...'), findsOneWidget);
      expect(find.text('ZEC Zcash'), findsOneWidget);
      expect(find.text('-4.12 ZEC'), findsWidgets);
      expect(find.text('1/4 In progress'), findsOneWidget);
      expect(find.text('Depositing USDC...'), findsNothing);
    },
  );

  testWidgets(
    'swap activity confirming-ZEC use case moves to second progress step',
    (tester) async {
      await _pumpActivityUseCase(
        tester,
        buildActivitySwapConfirmingZecToExternalUseCase,
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Swapping...'), findsOneWidget);
      expect(find.text('ZEC Zcash'), findsOneWidget);
      expect(find.text('-4.12 ZEC'), findsWidgets);
      expect(find.text('2/4 In progress'), findsOneWidget);
      expect(find.text('Depositing USDC...'), findsNothing);
    },
  );

  testWidgets(
    'swap activity success use cases render received/deposited rows',
    (tester) async {
      await _pumpActivityUseCase(
        tester,
        buildActivitySwapSuccessExternalToZecUseCase,
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Swapped'), findsOneWidget);
      expect(find.text('ZEC Received'), findsOneWidget);
      expect(find.text('Completed'), findsWidgets);

      await _pumpActivityUseCase(
        tester,
        buildActivitySwapSuccessZecToExternalUseCase,
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Swapped'), findsOneWidget);
      expect(find.text('USDC Deposited'), findsOneWidget);
    },
  );

  testWidgets('swap activity failed use case renders failed single row', (
    tester,
  ) async {
    await _pumpActivityUseCase(
      tester,
      buildActivitySwapFailedExternalToZecUseCase,
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Swap failed'), findsOneWidget);
    expect(find.text('-101.23 USDC'), findsOneWidget);
    expect(find.text('Failed'), findsWidgets);
    expect(find.text('Receiving ZEC ...'), findsNothing);
  });
}

Future<void> _pumpActivityUseCase(
  WidgetTester tester,
  WidgetBuilder builder,
) async {
  tester.view.physicalSize = const Size(1080, 720);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      home: AppTheme(
        data: AppThemeData.light,
        child: Center(
          child: SizedBox(
            width: 1080,
            height: 720,
            child: Builder(builder: builder),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}
