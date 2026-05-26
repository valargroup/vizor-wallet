import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_context_menu.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';

void main() {
  testWidgets('AppContextMenu uses semantic menu surface tokens', (
    tester,
  ) async {
    await tester.pumpWidget(
      _ThemedHarness(
        theme: AppThemeData.light,
        child: AppContextMenu(
          children: [
            AppContextMenuItem(
              iconName: AppIcons.trash,
              label: 'Remove Contact',
              destructive: true,
              onTap: () {},
            ),
          ],
        ),
      ),
    );

    final decoration = _menuDecoration(tester);
    final border = decoration.border as Border?;

    expect(decoration.color, AppThemeData.light.colors.background.inverse);
    expect(border?.top.color, AppThemeData.light.colors.border.subtleOpacity);
    expect(decoration.boxShadow?.map((shadow) => shadow.color), [
      AppThemeData.light.colors.background.neutralScrim,
      AppThemeData.light.colors.background.neutralScrim,
    ]);

    final text = tester.widget<Text>(find.text('Remove Contact'));
    expect(text.style?.color, AppThemeData.light.colors.text.destructive);
  });

  testWidgets('AppContextMenuItem applies the hover state token', (
    tester,
  ) async {
    await tester.pumpWidget(
      _ThemedHarness(
        theme: AppThemeData.dark,
        child: AppContextMenu(
          children: [
            AppContextMenuItem(
              iconName: AppIcons.scroll,
              label: 'Edit Contact',
              onTap: () {},
            ),
          ],
        ),
      ),
    );

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    await gesture.moveTo(tester.getCenter(find.text('Edit Contact')));
    await tester.pumpAndSettle();

    final decoration = _itemDecoration(tester);
    expect(decoration.color, AppThemeData.dark.colors.state.hover);

    await gesture.removePointer();
  });

  testWidgets('AppContextMenuItem can be removed while hovered', (
    tester,
  ) async {
    var showMenu = true;

    await tester.pumpWidget(
      _ThemedHarness(
        theme: AppThemeData.dark,
        child: StatefulBuilder(
          builder: (context, setState) {
            return SizedBox(
              width: 420,
              height: 220,
              child: Stack(
                children: [
                  if (showMenu)
                    AppContextMenu(
                      children: [
                        AppContextMenuItem(
                          iconName: AppIcons.scroll,
                          label: 'Edit Contact',
                          onTap: () {},
                        ),
                      ],
                    ),
                  Positioned(
                    left: 240,
                    top: 0,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => setState(() => showMenu = false),
                      child: const SizedBox(
                        width: 120,
                        height: 40,
                        child: Text('Hide menu'),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    await gesture.moveTo(tester.getCenter(find.text('Edit Contact')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Hide menu'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Edit Contact'), findsNothing);

    await gesture.removePointer();
  });
}

BoxDecoration _menuDecoration(WidgetTester tester) {
  return tester
          .widget<DecoratedBox>(
            find
                .descendant(
                  of: find.byType(AppContextMenu),
                  matching: find.byType(DecoratedBox),
                )
                .first,
          )
          .decoration
      as BoxDecoration;
}

BoxDecoration _itemDecoration(WidgetTester tester) {
  return tester
          .widget<AnimatedContainer>(
            find.descendant(
              of: find.byType(AppContextMenuItem),
              matching: find.byType(AnimatedContainer),
            ),
          )
          .decoration!
      as BoxDecoration;
}

class _ThemedHarness extends StatelessWidget {
  const _ThemedHarness({required this.theme, required this.child});

  final AppThemeData theme;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AppTheme(
      data: theme,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Center(child: child),
      ),
    );
  }
}
