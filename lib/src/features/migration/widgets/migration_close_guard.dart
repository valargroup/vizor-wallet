import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../../../core/layout/app_layout.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../rust/api/sync.dart' as rust_sync;
import '../models/migration_view_state.dart';
import '../providers/orchard_migration_status_provider.dart';

class MigrationCloseGuard extends ConsumerStatefulWidget {
  const MigrationCloseGuard({
    required this.child,
    required this.navigatorKey,
    super.key,
  });

  final Widget child;
  final GlobalKey<NavigatorState> navigatorKey;

  @override
  ConsumerState<MigrationCloseGuard> createState() =>
      _MigrationCloseGuardState();
}

class _MigrationCloseGuardState extends ConsumerState<MigrationCloseGuard>
    with WindowListener {
  bool _dialogVisible = false;

  @override
  void initState() {
    super.initState();
    if (!isDesktopLayoutPlatform) return;
    windowManager.addListener(this);
    unawaited(windowManager.setPreventClose(true));
  }

  @override
  void dispose() {
    if (isDesktopLayoutPlatform) {
      windowManager.removeListener(this);
      unawaited(windowManager.setPreventClose(false));
    }
    super.dispose();
  }

  @override
  void onWindowClose() {
    unawaited(_handleCloseRequest());
  }

  Future<void> _handleCloseRequest() async {
    if (_dialogVisible) return;

    final status = await _readMigrationStatus();
    if (!mounted) return;

    if (!migrationShouldWarnBeforeClose(status)) {
      await _closeWindow();
      return;
    }

    final remaining = migrationRemainingScheduledSubmissionTime(
      status,
      DateTime.now(),
    );
    final dialogContext = _dialogContext();
    if (dialogContext == null) {
      debugPrint('MigrationCloseGuard: no navigator context for close warning');
      await _closeWindow();
      return;
    }
    if (!dialogContext.mounted) return;

    bool shouldClose = false;
    _dialogVisible = true;
    try {
      shouldClose =
          await showDialog<bool>(
            context: dialogContext,
            barrierDismissible: false,
            builder: (_) => _MigrationCloseWarningDialog(remaining: remaining),
          ) ??
          false;
    } finally {
      _dialogVisible = false;
    }
    if (!mounted || shouldClose != true) return;

    await _closeWindow();
  }

  BuildContext? _dialogContext() {
    final navigatorContext = widget.navigatorKey.currentContext;
    if (navigatorContext != null) return navigatorContext;

    final overlayContext = widget.navigatorKey.currentState?.overlay?.context;
    if (overlayContext != null) return overlayContext;

    return Navigator.maybeOf(context, rootNavigator: true) == null
        ? null
        : context;
  }

  Future<void> _closeWindow() async {
    await windowManager.setPreventClose(false);
    await windowManager.close();
  }

  Future<rust_sync.MigrationStatus?> _readMigrationStatus() async {
    final current = ref.read(activeOrchardMigrationStatusProvider).value;
    if (current != null) return current;

    try {
      return await ref
          .read(activeOrchardMigrationStatusProvider.future)
          .timeout(const Duration(seconds: 1));
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _MigrationCloseWarningDialog extends StatelessWidget {
  const _MigrationCloseWarningDialog({required this.remaining});

  final Duration? remaining;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final remaining = this.remaining;
    final remainingLine = remaining == null
        ? 'Vizor is still submitting or confirming migration transactions.'
        : remaining > Duration.zero
        ? 'About ${migrationCountdownLabel(remaining)} remaining until the final scheduled submission.'
        : 'The final scheduled submission is due now.';

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.medium),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  AppIcon(
                    AppIcons.warning,
                    size: AppIconSize.medium,
                    color: colors.icon.warning,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      'Migration is still in progress',
                      style: AppTypography.bodyMediumStrong.copyWith(
                        color: colors.text.accent,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                remainingLine,
                style: AppTypography.bodyMedium.copyWith(
                  color: colors.text.secondary,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'If you close Vizor now, remaining scheduled submissions will not happen on their own, and confirmation progress will not update until Vizor is reopened.',
                style: AppTypography.bodySmall.copyWith(
                  color: colors.text.warning,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: [
                  AppButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    variant: AppButtonVariant.secondary,
                    child: const Text('Keep Vizor open'),
                  ),
                  AppButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    variant: AppButtonVariant.destructive,
                    child: const Text('Close anyway'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
