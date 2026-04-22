import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../main.dart' show log;
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_decorative_divider.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/password_text_field.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/app_security_provider.dart';
import 'onboarding_split_view.dart';

class SetPasswordScreenArgs {
  const SetPasswordScreenArgs({required this.mnemonic});

  final String mnemonic;
}

class SetPasswordScreen extends ConsumerStatefulWidget {
  const SetPasswordScreen({super.key, required this.args});

  final SetPasswordScreenArgs? args;

  @override
  ConsumerState<SetPasswordScreen> createState() => _SetPasswordScreenState();
}

class _SetPasswordScreenState extends ConsumerState<SetPasswordScreen> {
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _isSubmitting = false;
  String? _submitError;

  @override
  void initState() {
    super.initState();
    if (widget.args == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context.go(OnboardingStep.secretPassphrase.routePath);
      });
    }
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  bool get _hasMinLength => _passwordController.text.length >= 8;
  bool get _matches =>
      _confirmController.text.isNotEmpty &&
      _confirmController.text == _passwordController.text;

  bool get _canSubmit =>
      !_isSubmitting && widget.args != null && _hasMinLength && _matches;

  String? get _passwordMessage {
    final value = _passwordController.text;
    if (value.isEmpty || _hasMinLength) return null;
    return 'Password must be at least 8 characters.';
  }

  String? get _confirmMessage {
    final value = _confirmController.text;
    if (value.isEmpty || _matches) return null;
    return 'Passwords do not match.';
  }

  Future<void> _submit() async {
    final args = widget.args;
    if (!_canSubmit || args == null) return;

    setState(() {
      _isSubmitting = true;
      _submitError = null;
    });

    try {
      await ref
          .read(appSecurityProvider.notifier)
          .configurePassword(_passwordController.text);
      await ref
          .read(accountProvider.notifier)
          .createAccountFromMnemonic(mnemonic: args.mnemonic);
    } catch (e, st) {
      log('SetPasswordScreen._submit: ERROR: $e\n$st');
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _submitError = e.toString();
      });
      return;
    }

    if (!mounted) return;
    context.go('/home');
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return OnboardingTrailingPane(
      child: Column(
        children: [
          const _BackRow(),
          Expanded(
            child: Center(
              child: SizedBox(
                width: 432,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Set Password',
                      style: AppTypography.displaySmall.copyWith(
                        color: colors.text.accent,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.s),
                    Text(
                      'Minimum 8 symbols including characters.',
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
                      messageText: _passwordMessage,
                      tone: _passwordMessage == null
                          ? AppTextFieldTone.neutral
                          : AppTextFieldTone.destructive,
                      autofocus: true,
                      onChanged: (_) => setState(() {
                        _submitError = null;
                      }),
                      onSubmitted: (_) => _submit(),
                    ),
                    const SizedBox(height: AppSpacing.s),
                    PasswordTextField(
                      label: 'Confirm Password',
                      controller: _confirmController,
                      messageText: _confirmMessage,
                      tone: _confirmMessage == null
                          ? AppTextFieldTone.neutral
                          : AppTextFieldTone.destructive,
                      onChanged: (_) => setState(() {
                        _submitError = null;
                      }),
                      onSubmitted: (_) => _submit(),
                    ),
                    if (_submitError != null) ...[
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        _submitError!,
                        style: AppTypography.bodyMedium.copyWith(
                          color: colors.text.warning,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                    const SizedBox(height: AppSpacing.s),
                    AppButton(
                      onPressed: _canSubmit ? _submit : null,
                      variant: AppButtonVariant.primary,
                      minWidth: 256,
                      trailing: const AppIcon(AppIcons.chevronForward),
                      child: Text(
                        _isSubmitting ? 'Setting password...' : 'Set Password',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
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
        onTap: () => context.go(OnboardingStep.secretPassphrase.routePath),
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
