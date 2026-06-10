import 'package:flutter/material.dart'
    show
        CircularProgressIndicator,
        LinearProgressIndicator,
        MaterialApp,
        Scaffold;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';
import 'package:zcash_wallet/src/features/migration/widgets/migration_step_card.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    home: AppTheme(
      data: AppThemeData.light,
      child: Scaffold(body: child),
    ),
  );
}

void main() {
  testWidgets('renders number badge, title, status and enabled CTA', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      _wrap(
        MigrationStepCard(
          stepNumber: 1,
          title: 'Prepare denominations',
          statusLine: 'Ready.',
          ctaLabel: 'Prepare denominations',
          onCta: () => taps += 1,
        ),
      ),
    );

    expect(find.text('1'), findsOneWidget);
    expect(find.text('Prepare denominations'), findsNWidgets(2));
    expect(find.text('Ready.'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('migration_step1_cta')));
    await tester.pump();
    expect(taps, 1);
  });

  testWidgets('disabled CTA does not fire and dimmed card is wrapped in '
      'reduced opacity', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      _wrap(
        MigrationStepCard(
          stepNumber: 2,
          title: 'Migrate to Ironwood',
          isDimmed: true,
          statusLine: 'Available once the prepared notes confirm.',
          ctaLabel: 'Start migration',
          onCta: null,
        ),
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey('migration_step2_cta')),
      warnIfMissed: false,
    );
    await tester.pump();
    expect(taps, 0);

    final opacity = tester.widget<Opacity>(
      find.ancestor(
        of: find.text('Migrate to Ironwood'),
        matching: find.byType(Opacity),
      ),
    );
    expect(opacity.opacity, lessThan(1));
  });

  testWidgets('done shows check icon instead of number; spinner and '
      'progress render when requested', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const MigrationStepCard(
          stepNumber: 1,
          title: 'Prepare denominations',
          isDone: true,
        ),
      ),
    );
    expect(find.text('1'), findsNothing);
    expect(find.byType(AppIcon), findsOneWidget);

    await tester.pumpWidget(
      _wrap(
        const MigrationStepCard(
          stepNumber: 2,
          title: 'Migrate to Ironwood',
          showSpinner: true,
          progress: 0.5,
        ),
      ),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('error banner renders', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const MigrationStepCard(
          stepNumber: 2,
          title: 'Migrate to Ironwood',
          errorBanner: 'Migration broadcast failed.',
        ),
      ),
    );
    expect(find.text('Migration broadcast failed.'), findsOneWidget);
  });
}
