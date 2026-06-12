import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../migration_copy.dart';

/// Confirmation shown when the user presses Migrate from idle. Resolves to true
/// if the user chose to start. [oversized] adds the staged-Keystone "you'll
/// scan once more" line.
class MigrationWarningDialog extends StatelessWidget {
  const MigrationWarningDialog({
    required this.windowSeconds,
    this.oversized = false,
    super.key,
  });

  final int windowSeconds;
  final bool oversized;

  static Future<bool> show(
    BuildContext context, {
    required int windowSeconds,
    bool oversized = false,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (_) => MigrationWarningDialog(
        windowSeconds: windowSeconds,
        oversized: oversized,
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
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
                      MigrationCopy.warningTitle,
                      style: AppTypography.bodyMediumStrong.copyWith(
                        color: colors.text.accent,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                MigrationCopy.warningBody(
                  MigrationCopy.migrationWindowText(windowSeconds),
                ),
                style: AppTypography.bodyMedium.copyWith(
                  color: colors.text.secondary,
                ),
              ),
              if (oversized) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  MigrationCopy.warningOversizedLine,
                  style: AppTypography.bodySmall.copyWith(
                    color: colors.text.warning,
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: [
                  AppButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    variant: AppButtonVariant.secondary,
                    child: const Text(MigrationCopy.warningCancelCta),
                  ),
                  AppButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text(MigrationCopy.warningStartCta),
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
