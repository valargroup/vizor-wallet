import 'package:flutter/widgets.dart';

import 'app_icon.dart';
import 'app_text_field.dart';

class PasswordTextField extends StatefulWidget {
  const PasswordTextField({
    super.key,
    required this.label,
    this.controller,
    this.focusNode,
    this.messageText,
    this.tone = AppTextFieldTone.neutral,
    this.onChanged,
    this.onSubmitted,
    this.autofocus = false,
    this.enabled = true,
    this.showVisibilityToggle = true,
  });

  final String label;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String? messageText;
  final AppTextFieldTone tone;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;
  final bool enabled;
  final bool showVisibilityToggle;

  @override
  State<PasswordTextField> createState() => _PasswordTextFieldState();
}

class _PasswordTextFieldState extends State<PasswordTextField> {
  bool _obscureText = true;

  void _toggleVisibility() {
    setState(() {
      _obscureText = !_obscureText;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AppTextField(
      label: widget.label,
      controller: widget.controller,
      focusNode: widget.focusNode,
      messageText: widget.messageText,
      tone: widget.tone,
      leading: const AppIcon(AppIcons.lock),
      trailing: widget.showVisibilityToggle
          ? GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _toggleVisibility,
              child: AppIcon(
                _obscureText ? AppIcons.eyeClosed : AppIcons.eye,
                size: 20,
              ),
            )
          : null,
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
      keyboardType: TextInputType.visiblePassword,
      obscureText: _obscureText,
      enableSuggestions: false,
      autocorrect: false,
      enabled: widget.enabled,
      autofocus: widget.autofocus,
    );
  }
}
