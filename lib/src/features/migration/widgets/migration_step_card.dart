import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';

/// Presentational shell for one migration step. State semantics live in the
/// screen; this widget only renders what it is given.
class MigrationStepCard extends StatelessWidget {
  const MigrationStepCard({
    required this.stepNumber,
    required this.title,
    this.isDone = false,
    this.isDimmed = false,
    this.showSpinner = false,
    this.statusLine,
    this.statusIsError = false,
    this.errorBanner,
    this.progress,
    this.body = const <Widget>[],
    this.ctaLabel,
    this.onCta,
    super.key,
  });

  final int stepNumber;
  final String title;
  final bool isDone;
  final bool isDimmed;
  final bool showSpinner;
  final String? statusLine;
  final bool statusIsError;
  final String? errorBanner;

  /// 0..1 bar shown when non-null.
  final double? progress;
  final List<Widget> body;
  final String? ctaLabel;

  /// Null with a non-null [ctaLabel] renders the disabled button state.
  final VoidCallback? onCta;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Opacity(
      opacity: isDimmed ? 0.5 : 1,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: colors.background.neutralSubtleOpacity,
          borderRadius: BorderRadius.circular(AppRadii.xSmall),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (isDone)
                  AppIcon(
                    AppIcons.checkCircle,
                    size: AppIconSize.medium,
                    color: colors.icon.success,
                  )
                else
                  Container(
                    width: 24,
                    height: 24,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: colors.border.subtle),
                    ),
                    child: Text(
                      '$stepNumber',
                      style: AppTypography.bodyExtraSmall.copyWith(
                        color: colors.text.secondary,
                      ),
                    ),
                  ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    title,
                    style: AppTypography.bodyLarge.copyWith(
                      color: colors.text.accent,
                    ),
                  ),
                ),
                if (showSpinner)
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colors.icon.success,
                    ),
                  ),
              ],
            ),
            if (statusLine != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                statusLine!,
                style: AppTypography.bodyMedium.copyWith(
                  color: statusIsError
                      ? colors.text.destructive
                      : colors.text.secondary,
                ),
              ),
            ],
            if (progress != null) ...[
              const SizedBox(height: AppSpacing.s),
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadii.full),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 8,
                  backgroundColor: colors.background.neutralSubtleOpacity,
                  color: colors.icon.success,
                ),
              ),
            ],
            ...body.map(
              (child) => Padding(
                padding: const EdgeInsets.only(top: AppSpacing.s),
                child: child,
              ),
            ),
            if (errorBanner != null) ...[
              const SizedBox(height: AppSpacing.s),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppIcon(
                    AppIcons.warning,
                    size: AppIconSize.medium,
                    color: colors.icon.destructive,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      errorBanner!,
                      style: AppTypography.bodyExtraSmall.copyWith(
                        color: colors.text.destructive,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            if (ctaLabel != null) ...[
              const SizedBox(height: AppSpacing.md),
              AppButton(
                key: ValueKey('migration_step${stepNumber}_cta'),
                onPressed: onCta,
                leading: const AppIcon(AppIcons.doubleArrowVertical),
                child: Text(ctaLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
