import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import 'app_icon.dart';

enum AppTextFieldTone { neutral, destructive, brandPurple }

class AppTextField extends StatefulWidget {
  const AppTextField({
    super.key,
    required this.label,
    this.rightLabel,
    this.controller,
    this.focusNode,
    this.initialValue,
    this.hintText,
    this.leading,
    this.trailing,
    this.messageText,
    this.messageIcon,
    this.tone = AppTextFieldTone.neutral,
    this.showClearButton = false,
    this.onClear,
    this.onChanged,
    this.onSubmitted,
    this.onTap,
    this.keyboardType,
    this.textInputAction,
    this.inputFormatters,
    this.minLines = 1,
    this.maxLines = 1,
    this.enabled = true,
    this.readOnly = false,
    this.autofocus = false,
  }) : assert(
         controller == null || initialValue == null,
         'Provide either controller or initialValue, not both.',
       );

  final String label;
  final String? rightLabel;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String? initialValue;
  final String? hintText;
  final Widget? leading;
  final Widget? trailing;
  final String? messageText;
  final Widget? messageIcon;
  final AppTextFieldTone tone;
  final bool showClearButton;
  final VoidCallback? onClear;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onTap;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final List<TextInputFormatter>? inputFormatters;
  final int minLines;
  final int maxLines;
  final bool enabled;
  final bool readOnly;
  final bool autofocus;

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  late final TextEditingController _internalController;
  late final FocusNode _internalFocusNode;
  bool _hovered = false;

  TextEditingController get _controller =>
      widget.controller ?? _internalController;
  FocusNode get _focusNode => widget.focusNode ?? _internalFocusNode;
  bool get _multiline => widget.maxLines > 1 || widget.minLines > 1;
  bool get _hasText => _controller.text.isNotEmpty;
  bool get _isFocused => _focusNode.hasFocus;
  bool get _showMessage =>
      widget.messageText != null && widget.messageText!.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _internalController = TextEditingController(text: widget.initialValue);
    _internalFocusNode = FocusNode();
    _controller.addListener(_handleTextChanged);
    _focusNode.addListener(_handleFocusChanged);
  }

  @override
  void didUpdateWidget(covariant AppTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.removeListener(_handleTextChanged);
      widget.controller?.addListener(_handleTextChanged);
    }
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode?.removeListener(_handleFocusChanged);
      widget.focusNode?.addListener(_handleFocusChanged);
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_handleTextChanged);
    _focusNode.removeListener(_handleFocusChanged);
    if (widget.controller == null) _internalController.dispose();
    if (widget.focusNode == null) _internalFocusNode.dispose();
    super.dispose();
  }

  void _handleTextChanged() => setState(() {});

  void _handleFocusChanged() => setState(() {});

  void _setHovered(bool value) {
    if (_hovered != value) setState(() => _hovered = value);
  }

  void _clear() {
    _controller.clear();
    widget.onChanged?.call('');
    widget.onClear?.call();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final titleStyle = AppTypography.labelMedium.copyWith(
      color: colors.text.secondary,
    );
    final hintStyle = AppTypography.labelLarge.copyWith(
      color: colors.text.muted,
    );
    final valueStyle = AppTypography.labelLarge.copyWith(
      color: colors.text.accent,
    );
    final iconColor = _hasText || _isFocused
        ? colors.icon.accent
        : colors.icon.regular;
    final gap = _multiline ? AppSpacing.xs : AppSpacing.xxs;
    final shellHeight = _multiline ? 148.0 : 46.0;
    final titleHeight = 16.0;
    final messageTop = titleHeight + gap + shellHeight + gap;

    final isNeutralTone = widget.tone == AppTextFieldTone.neutral;
    final borderColor = switch (widget.tone) {
      AppTextFieldTone.neutral when _isFocused => colors.border.strong,
      AppTextFieldTone.neutral => colors.border.subtle,
      AppTextFieldTone.destructive => colors.border.utilityDestructive,
      AppTextFieldTone.brandPurple => colors.border.brandPurpleStrong,
    };
    final focusRingColor = switch (widget.tone) {
      AppTextFieldTone.neutral => colors.state.focusRing,
      AppTextFieldTone.destructive => colors.border.utilityDestructive,
      AppTextFieldTone.brandPurple => colors.border.brandPurpleStrong,
    };
    final messageColor = switch (widget.tone) {
      AppTextFieldTone.neutral => colors.text.secondary,
      AppTextFieldTone.destructive => colors.text.warning,
      AppTextFieldTone.brandPurple => colors.text.brandPurple,
    };
    final defaultMessageIcon = switch (widget.tone) {
      AppTextFieldTone.neutral => null,
      AppTextFieldTone.destructive => AppIcon(
        AppIcons.warning,
        size: AppIconSize.medium,
        color: messageColor,
      ),
      AppTextFieldTone.brandPurple => AppIcon(
        AppIcons.shieldKeyhole,
        size: AppIconSize.medium,
        color: messageColor,
      ),
    };

    final textField = TextField(
      controller: _controller,
      focusNode: _focusNode,
      enabled: widget.enabled,
      readOnly: widget.readOnly,
      autofocus: widget.autofocus,
      keyboardType: widget.keyboardType,
      textInputAction: widget.textInputAction,
      inputFormatters: widget.inputFormatters,
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
      onTap: widget.onTap,
      maxLines: _multiline ? null : 1,
      minLines: _multiline ? null : 1,
      expands: _multiline,
      textAlignVertical: _multiline
          ? TextAlignVertical.top
          : TextAlignVertical.center,
      style: valueStyle,
      cursorColor: colors.text.accent,
      decoration: InputDecoration.collapsed(
        hintText: widget.hintText,
        hintStyle: hintStyle,
      ),
    );

    final shell = SizedBox(
      height: shellHeight,
      child: MouseRegion(
        cursor: widget.enabled && !widget.readOnly
            ? SystemMouseCursors.text
            : SystemMouseCursors.basic,
        onEnter: (_) => _setHovered(true),
        onExit: (_) => _setHovered(false),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.surface.input,
                  borderRadius: BorderRadius.circular(AppRadii.small),
                  border: Border.all(color: borderColor, width: 1.5),
                ),
              ),
            ),
            if (_hovered && !_isFocused && isNeutralTone)
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.state.hover,
                    borderRadius: BorderRadius.circular(AppRadii.small),
                  ),
                ),
              ),
            if (_isFocused)
              Positioned(
                left: -2.5,
                top: -2.5,
                right: -2.5,
                bottom: -2.5,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(AppRadii.small),
                      border: Border.all(color: focusRingColor, width: 2),
                    ),
                  ),
                ),
              ),
            Positioned.fill(
              child: IconTheme.merge(
                data: IconThemeData(color: iconColor, size: AppIconSize.large),
                child: Row(
                  crossAxisAlignment: _multiline
                      ? CrossAxisAlignment.start
                      : CrossAxisAlignment.center,
                  children: [
                    if (widget.leading != null && !_multiline)
                      SizedBox(
                        width: 32,
                        height: shellHeight,
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: SizedBox(
                            width: AppIconSize.large,
                            height: AppIconSize.large,
                            child: widget.leading,
                          ),
                        ),
                      ),
                    if (widget.leading != null && _multiline)
                      Padding(
                        padding: const EdgeInsets.only(left: AppSpacing.xs),
                        child: SizedBox(
                          width: 20,
                          height: 48,
                          child: Align(
                            alignment: Alignment.center,
                            child: SizedBox(
                              width: AppIconSize.large,
                              height: AppIconSize.large,
                              child: widget.leading,
                            ),
                          ),
                        ),
                      ),
                    Expanded(
                      child: Padding(
                        padding: _multiline
                            ? const EdgeInsets.fromLTRB(
                                AppSpacing.sm,
                                AppSpacing.sm,
                                AppSpacing.sm,
                                AppSpacing.sm,
                              )
                            : const EdgeInsets.symmetric(
                                horizontal: AppSpacing.sm,
                              ),
                        child: textField,
                      ),
                    ),
                    if (!_multiline)
                      SizedBox(
                        width: 40,
                        height: shellHeight,
                        child: Center(
                          child:
                              widget.showClearButton &&
                                  _isFocused &&
                                  _hasText &&
                                  widget.enabled &&
                                  !widget.readOnly
                              ? GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: _clear,
                                  child: AppIcon(
                                    AppIcons.cross,
                                    size: 20,
                                    color: iconColor,
                                  ),
                                )
                              : widget.trailing,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(child: Text(widget.label, style: titleStyle)),
                if (widget.rightLabel != null)
                  Text(widget.rightLabel!, style: titleStyle),
              ],
            ),
            SizedBox(height: gap),
            shell,
          ],
        ),
        if (_showMessage)
          Positioned(
            top: messageTop,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Row(
                children: [
                  widget.messageIcon ?? defaultMessageIcon ?? const SizedBox(),
                  if (widget.messageIcon != null || defaultMessageIcon != null)
                    const SizedBox(width: AppSpacing.xxs),
                  Text(
                    widget.messageText!,
                    style: AppTypography.labelMedium.copyWith(
                      color: messageColor,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
