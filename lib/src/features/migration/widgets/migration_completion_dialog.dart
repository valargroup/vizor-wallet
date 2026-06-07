import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../migration_copy.dart';

Future<void> showMigrationCompletionDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => const _MigrationCompletionDialog(),
  );
}

class _MigrationCompletionDialog extends StatelessWidget {
  const _MigrationCompletionDialog();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Dialog(
      backgroundColor: colors.background.ground,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.large),
      ),
      child: Container(
        width: 360,
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: colors.background.neutralSubtleOpacity,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: AppIcon(
                  AppIcons.checkCircle,
                  size: AppIconSize.large,
                  color: colors.icon.success,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.s),
            Text(
              MigrationCopy.completeTitle,
              textAlign: TextAlign.center,
              style: AppTypography.bodyLarge.copyWith(
                color: colors.text.accent,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              MigrationCopy.completeBody,
              textAlign: TextAlign.center,
              style: AppTypography.bodyMedium.copyWith(
                color: colors.text.secondary,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              width: double.infinity,
              child: AppButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text(MigrationCopy.completeButton),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
