import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_decorative_divider.dart';
import '../../../core/widgets/app_icon.dart';
import 'onboarding_split_view.dart';

class AddressTypesScreen extends StatelessWidget {
  const AddressTypesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const OnboardingTrailingPane(child: _Content());
  }
}

class _Content extends StatelessWidget {
  const _Content();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        _BackRow(),
        Expanded(
          child: Center(child: SizedBox(width: 588, child: _HeroLayout())),
        ),
      ],
    );
  }
}

class _BackRow extends StatelessWidget {
  const _BackRow();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Align(
      alignment: Alignment.centerLeft,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => context.go(OnboardingStep.intro.routePath),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIcon(
                AppIcons.chevronBackward,
                size: AppIconSize.medium,
                color: colors.text.accent,
              ),
              const SizedBox(width: AppSpacing.xxs),
              Text(
                'Back',
                style: AppTypography.labelLarge.copyWith(
                  color: colors.text.accent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeroLayout extends StatelessWidget {
  const _HeroLayout();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        Expanded(child: Center(child: _HeroBlock())),
        _ActionRow(),
        SizedBox(height: AppSpacing.s),
      ],
    );
  }
}

class _HeroBlock extends StatelessWidget {
  const _HeroBlock();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final bodyStyle = AppTypography.bodyMedium.copyWith(
      color: colors.text.accent,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Zcash Address Types',
          style: AppTypography.displaySmall.copyWith(color: colors.text.accent),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.s),
        Text.rich(
          TextSpan(
            style: bodyStyle,
            children: [
              const TextSpan(text: 'Zcash has two addresses types.\nOne for '),
              TextSpan(
                text: 'Privacy',
                style: bodyStyle.copyWith(
                  color: colors.text.brandPurple,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const TextSpan(text: ', one for '),
              TextSpan(
                text: 'Transparency',
                style: bodyStyle.copyWith(fontWeight: FontWeight.w500),
              ),
            ],
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.s),
        const AppDecorativeDivider(),
        const SizedBox(height: AppSpacing.s),
        const _CardsRow(),
      ],
    );
  }
}

class _CardsRow extends StatelessWidget {
  const _CardsRow();

  @override
  Widget build(BuildContext context) {
    return const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: _ShieldedAddressCard()),
        SizedBox(width: AppSpacing.s),
        Expanded(child: _TransparentAddressCard()),
      ],
    );
  }
}

class _ShieldedAddressCard extends StatelessWidget {
  const _ShieldedAddressCard();

  String _patternAsset(BuildContext context) {
    final isDark = AppTheme.of(context) == AppThemeData.dark;
    return isDark
        ? 'assets/illustrations/onboarding_address_types_card_pattern_dark.png'
        : 'assets/illustrations/onboarding_address_types_card_pattern_light.png';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isDark = AppTheme.of(context) == AppThemeData.dark;
    final addressColor = isDark ? colors.text.inverse : colors.text.primary;
    final badgeBg = isDark ? colors.background.base : colors.background.ground;
    final badgeText = isDark ? colors.text.accent : colors.text.inverse;
    return _AddressTypeCard(
      top: _ShieldedPreview(
        patternAsset: _patternAsset(context),
        badgeBackgroundColor: badgeBg,
        badgeTextColor: badgeText,
        valueColor: addressColor,
      ),
      title: 'Shielded Address',
      description: Text.rich(
        TextSpan(
          style: AppTypography.bodyMedium.copyWith(color: colors.text.primary),
          children: [
            const TextSpan(text: 'Address starts with '),
            TextSpan(
              text: 'u1',
              style: AppTypography.bodyMediumStrong.copyWith(
                color: colors.text.brandPurple,
              ),
            ),
            const TextSpan(text: ' (or '),
            TextSpan(
              text: 'zs',
              style: AppTypography.bodyMediumStrong.copyWith(
                color: colors.text.brandPurple,
              ),
            ),
            const TextSpan(text: ' for legacy).\n'),
            const TextSpan(
              text:
                  'Only you can see your account balance and transaction history.',
            ),
          ],
        ),
      ),
    );
  }
}

class _TransparentAddressCard extends StatelessWidget {
  const _TransparentAddressCard();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return _AddressTypeCard(
      top: _TransparentPreview(
        badgeBackgroundColor: colors.background.overlay.withValues(alpha: 0.5),
        badgeTextColor: colors.text.accent,
        valueColor: colors.text.secondary,
      ),
      title: 'Transparent Address',
      description: Text(
        "Address starts with t, similar to Bitcoin, your address' balance and "
        'transaction history are publicly visible.',
        style: AppTypography.bodyMedium.copyWith(color: colors.text.primary),
      ),
    );
  }
}

class _AddressTypeCard extends StatelessWidget {
  const _AddressTypeCard({
    required this.top,
    required this.title,
    required this.description,
  });

  final Widget top;
  final String title;
  final Widget description;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xxs,
        vertical: AppSpacing.xs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          top,
          const SizedBox(height: AppSpacing.sm),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTypography.bodyMediumStrong.copyWith(
                    color: colors.text.accent,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                SizedBox(width: 256, child: description),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ShieldedPreview extends StatelessWidget {
  const _ShieldedPreview({
    required this.patternAsset,
    required this.badgeBackgroundColor,
    required this.badgeTextColor,
    required this.valueColor,
  });

  final String patternAsset;
  final Color badgeBackgroundColor;
  final Color badgeTextColor;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 96,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadii.small),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(patternAsset, fit: BoxFit.cover),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.xs),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 38),
                _AddressBadgeRow(
                  badge: 'u1',
                  badgeWidth: 21,
                  badgeBackgroundColor: badgeBackgroundColor,
                  badgeTextColor: badgeTextColor,
                  valueColor: valueColor,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TransparentPreview extends StatelessWidget {
  const _TransparentPreview({
    required this.badgeBackgroundColor,
    required this.badgeTextColor,
    required this.valueColor,
  });

  final Color badgeBackgroundColor;
  final Color badgeTextColor;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      height: 96,
      decoration: BoxDecoration(
        color: colors.background.base,
        borderRadius: BorderRadius.circular(AppRadii.small),
      ),
      padding: const EdgeInsets.all(AppSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Align(
            alignment: Alignment.topRight,
            child: AppIcon(
              AppIcons.eye,
              size: AppIconSize.large,
              color: colors.icon.disabled,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          _AddressBadgeRow(
            badge: 't',
            badgeWidth: 21,
            badgeBackgroundColor: badgeBackgroundColor,
            badgeTextColor: badgeTextColor,
            valueColor: valueColor,
          ),
        ],
      ),
    );
  }
}

class _AddressBadgeRow extends StatelessWidget {
  const _AddressBadgeRow({
    required this.badge,
    required this.badgeWidth,
    this.badgeBackgroundColor,
    this.badgeTextColor,
    this.valueColor,
  });

  final String badge;
  final double badgeWidth;
  final Color? badgeBackgroundColor;
  final Color? badgeTextColor;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      children: [
        Container(
          width: badgeWidth,
          height: 21,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: badgeBackgroundColor ?? colors.background.base,
            borderRadius: BorderRadius.circular(AppSpacing.xxs),
          ),
          child: Text(
            badge,
            style: AppTypography.codeMedium.copyWith(
              color: badgeTextColor ?? colors.text.accent,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.xxs),
        Text(
          'vtr241aaf13 ... jFJxxTmd3FwF',
          style: AppTypography.codeMedium.copyWith(
            color: valueColor ?? colors.text.primary,
          ),
        ),
      ],
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow();

  static const double _buttonWidth = 256;

  @override
  Widget build(BuildContext context) {
    return AppButton(
      onPressed: () => context.go(OnboardingStep.thingsToKnow.routePath),
      variant: AppButtonVariant.primary,
      minWidth: _buttonWidth,
      trailing: const AppIcon(AppIcons.chevronForward),
      child: const Text('Continue'),
    );
  }
}
