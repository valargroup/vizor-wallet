import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../theme/app_theme.dart';
import '../widgets/app_icon.dart';
import 'app_desktop_shell.dart';

class AppMainSidebar extends StatelessWidget {
  const AppMainSidebar({
    super.key,
    required this.accountName,
    required this.matchedLocation,
    this.onResetWallet,
  });

  final String accountName;
  final String matchedLocation;
  final VoidCallback? onResetWallet;

  bool _matches(String routePath) =>
      matchedLocation == routePath || matchedLocation.startsWith('$routePath/');

  @override
  Widget build(BuildContext context) {
    return AppDesktopSidebarSurface(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xs),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: AppSidebarUserButton(
                    label: accountName,
                    onTap: () => context.push('/accounts'),
                  ),
                ),
                if (onResetWallet != null &&
                    kDebugMode &&
                    Platform.isMacOS) ...[
                  const SizedBox(width: AppSpacing.xs),
                  _DebugResetButton(onPressed: onResetWallet!),
                ],
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.xs),
              child: Column(
                children: [
                  AppSidebarItem(
                    label: 'Wallet',
                    iconName: AppIcons.wallet,
                    active: _matches('/home'),
                    onTap: _matches('/home') ? null : () => context.go('/home'),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  AppSidebarItem(
                    label: 'Send',
                    iconName: AppIcons.plane,
                    active: _matches('/send'),
                    onTap: _matches('/send') ? null : () => context.go('/send'),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  AppSidebarItem(
                    label: 'Receive',
                    iconName: AppIcons.arrowDownCircle,
                    active: _matches('/receive'),
                    onTap: _matches('/receive')
                        ? null
                        : () => context.go('/receive'),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  const AppSidebarItem(
                    label: 'Address Book',
                    iconName: AppIcons.users,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  AppSidebarItem(
                    label: 'Activity',
                    iconName: AppIcons.history,
                    active: _matches('/history'),
                    onTap: _matches('/history')
                        ? null
                        : () => context.go('/history'),
                  ),
                ],
              ),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.xs),
              child: Column(
                children: [
                  AppSidebarItem(
                    label: 'Settings',
                    iconName: AppIcons.cog,
                    active: _matches('/settings'),
                    onTap: _matches('/settings')
                        ? null
                        : () => context.go('/settings'),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  const AppSidebarItem(
                    label: 'About Vizor',
                    iconName: AppIcons.crystalBall,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  const AppSidebarItem(
                    label: 'Sign Out',
                    iconName: AppIcons.logOut,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DebugResetButton extends StatelessWidget {
  const _DebugResetButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: Container(
          width: 40,
          height: 40,
          padding: const EdgeInsets.all(AppSpacing.xs),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.small),
            color: colors.background.overlay.withValues(alpha: 0.12),
          ),
          child: AppIcon(AppIcons.block, size: 20, color: colors.text.warning),
        ),
      ),
    );
  }
}
