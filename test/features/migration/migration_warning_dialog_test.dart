import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/migration/migration_copy.dart';
import 'package:zcash_wallet/src/features/migration/widgets/migration_warning_dialog.dart';

Future<void> _open(WidgetTester tester, {bool oversized = false}) async {
  await tester.pumpWidget(
    MaterialApp(
      // Wrap every route (including the dialog overlay, which renders outside
      // `home`) with AppTheme so `context.colors` resolves inside the dialog.
      builder: (context, child) =>
          AppTheme(data: AppThemeData.light, child: child!),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => MigrationWarningDialog.show(
                context,
                windowSeconds: 180,
                oversized: oversized,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows keep-open copy and the window', (tester) async {
    await _open(tester);
    expect(find.text(MigrationCopy.warningTitle), findsOneWidget);
    expect(find.textContaining('about 3 minutes'), findsOneWidget);
    expect(find.text(MigrationCopy.warningOversizedLine), findsNothing);
  });

  testWidgets('oversized adds the extra-scan line', (tester) async {
    await _open(tester, oversized: true);
    expect(find.text(MigrationCopy.warningOversizedLine), findsOneWidget);
  });
}
