import 'package:flutter/material.dart' show Colors, Scaffold;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../main.dart' show log;
import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_decorative_divider.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/password_text_field.dart';
import '../../../providers/app_security_provider.dart';

class UnlockScreen extends ConsumerStatefulWidget {
  const UnlockScreen({super.key});

  @override
  ConsumerState<UnlockScreen> createState() => _UnlockScreenState();
}

class _UnlockScreenState extends ConsumerState<UnlockScreen> {
  final _passwordController = TextEditingController();
  bool _isSubmitting = false;
  String? _errorText;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSubmitting || _passwordController.text.isEmpty) return;

    setState(() {
      _isSubmitting = true;
      _errorText = null;
    });

    final isValid = await ref
        .read(appSecurityProvider.notifier)
        .unlock(_passwordController.text);
    if (!mounted) return;
    if (!isValid) {
      log('UnlockScreen._submit: invalid password');
      setState(() {
        _isSubmitting = false;
        _errorText = 'Incorrect password. Please try again.';
      });
      return;
    }

    context.go('/home');
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xs),
          child: AppDesktopPane(
            child: Center(
              child: SizedBox(
                width: 432,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: colors.background.overlay.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(AppRadii.full),
                      ),
                      child: const Center(
                        child: AppIcon(AppIcons.unlock, size: 24),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.s),
                    Text(
                      'Unlock Wallet',
                      style: AppTypography.displaySmall.copyWith(
                        color: colors.text.accent,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.s),
                    Text(
                      'Enter your password to access your wallet.',
                      style: AppTypography.bodyMedium.copyWith(
                        color: colors.text.accent,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.s),
                    const AppDecorativeDivider(),
                    const SizedBox(height: AppSpacing.s),
                    PasswordTextField(
                      label: 'Password',
                      controller: _passwordController,
                      autofocus: true,
                      messageText: _errorText,
                      tone: _errorText == null
                          ? AppTextFieldTone.neutral
                          : AppTextFieldTone.destructive,
                      onChanged: (_) {
                        setState(() {
                          _errorText = null;
                        });
                      },
                      onSubmitted: (_) => _submit(),
                    ),
                    const SizedBox(height: AppSpacing.s),
                    AppButton(
                      onPressed:
                          _isSubmitting || _passwordController.text.isEmpty
                          ? null
                          : _submit,
                      variant: AppButtonVariant.primary,
                      minWidth: 256,
                      trailing: const AppIcon(AppIcons.chevronForward),
                      child: Text(_isSubmitting ? 'Unlocking...' : 'Unlock'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
