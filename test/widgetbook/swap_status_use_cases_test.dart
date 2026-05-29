import 'package:flutter/material.dart' show MaterialApp;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/widgetbook/swap_use_cases.dart';

void main() {
  testWidgets('swap status use case switches tabs and toggles details', (
    tester,
  ) async {
    await _pumpSwapUseCase(tester, buildSwapStatusIncompleteDepositUseCase);

    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey('swap_transaction_details_collapsed')),
      findsOneWidget,
    );
    expect(find.text('Deposit USDC to'), findsOneWidget);
    expect(find.text('Refund fee'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('swap_status_tab_progress')));
    await tester.pump();

    expect(find.byKey(const ValueKey('swap_progress_route')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('swap_status_tab_details')));
    await tester.pump();

    expect(
      find.byKey(const ValueKey('swap_transaction_details_collapsed')),
      findsOneWidget,
    );

    await tester.tap(find.text('More details'));
    await tester.pump();

    expect(
      find.byKey(const ValueKey('swap_transaction_details_expanded')),
      findsOneWidget,
    );
    expect(find.text('Less details'), findsOneWidget);
    expect(find.text('Refund fee'), findsOneWidget);

    await tester.tap(find.text('Less details'));
    await tester.pump();

    expect(
      find.byKey(const ValueKey('swap_transaction_details_collapsed')),
      findsOneWidget,
    );
    expect(find.text('Refund fee'), findsNothing);
  });
}

Future<void> _pumpSwapUseCase(
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
