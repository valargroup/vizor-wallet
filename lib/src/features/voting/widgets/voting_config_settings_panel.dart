import 'package:flutter/services.dart'
    show SystemMouseCursors, TextInputAction, TextInputType;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../providers/voting/voting_config_provider.dart';
import '../../../providers/voting/voting_config_source_provider.dart';
import '../../../providers/voting/voting_rounds_provider.dart';
import '../../../providers/voting/voting_service_providers.dart';
import '../../../services/voting/voting_config_loader.dart';
import '../../../services/voting/voting_models.dart';

class VotingConfigSettingsPanel extends ConsumerStatefulWidget {
  const VotingConfigSettingsPanel({
    this.onClose,
    this.onUpdated,
    this.width = 520,
    super.key,
  });

  final VoidCallback? onClose;
  final VoidCallback? onUpdated;
  final double width;

  @override
  ConsumerState<VotingConfigSettingsPanel> createState() =>
      _VotingConfigSettingsPanelState();
}

class _VotingConfigSettingsPanelState
    extends ConsumerState<VotingConfigSettingsPanel> {
  final _controller = TextEditingController();
  String? _loadedSourceUrl;
  bool _isSubmitting = false;
  String? _submitError;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool _canUpdate(VotingConfigSourceState source) {
    if (_isSubmitting) return false;
    final trimmed = _controller.text.trim();
    if (trimmed.isEmpty || trimmed == source.sourceUrl) return false;
    try {
      StaticVotingConfigSource.parse(trimmed);
      return true;
    } on StaticVotingConfigSourceMalformed {
      return false;
    }
  }

  String? _fieldMessage() {
    final trimmed = _controller.text.trim();
    if (trimmed.isEmpty) return null;
    try {
      StaticVotingConfigSource.parse(trimmed);
      return null;
    } on StaticVotingConfigSourceMalformed catch (e) {
      return e.message;
    }
  }

  Future<void> _submit() async {
    final source = ref.read(votingConfigSourceProvider).value;
    if (source == null || !_canUpdate(source)) return;
    final input = _controller.text.trim();

    setState(() {
      _isSubmitting = true;
      _submitError = null;
    });

    try {
      final parsed = StaticVotingConfigSource.parse(input);
      await VotingConfigLoader(
        httpClient: ref.read(votingHttpClientProvider),
        staticConfigSource: parsed,
      ).load();
      await ref.read(votingConfigSourceProvider.notifier).setCustom(input);
      await ref.read(votingConfigProvider.notifier).refresh();
      await ref.read(votingRoundsProvider.notifier).refresh();
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
      });
      widget.onUpdated?.call();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _submitError = _messageFromError(error);
        _isSubmitting = false;
      });
    }
  }

  Future<void> _resetDefault() async {
    final source = ref.read(votingConfigSourceProvider).value;
    if (_isSubmitting || source == null || source.isDefault) return;

    setState(() {
      _isSubmitting = true;
      _submitError = null;
    });

    try {
      await ref.read(votingConfigSourceProvider.notifier).resetDefault();
      await ref.read(votingConfigProvider.notifier).refresh();
      await ref.read(votingRoundsProvider.notifier).refresh();
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
      });
      widget.onUpdated?.call();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _submitError = _messageFromError(error);
        _isSubmitting = false;
      });
    }
  }

  String _messageFromError(Object error) {
    if (error is StaticVotingConfigSourceMalformed) return error.message;
    if (error is VotingConfigChecksumMismatch) {
      return 'Static config checksum did not match.';
    }
    if (error is VotingHttpException) {
      return "Couldn't load voting config from that source.";
    }
    final text = error.toString().trim();
    return text.isEmpty ? "Couldn't update voting config." : text;
  }

  void _syncController(VotingConfigSourceState source) {
    if (_loadedSourceUrl == source.sourceUrl) return;
    _loadedSourceUrl = source.sourceUrl;
    _controller.text = source.sourceUrl;
    _controller.selection = TextSelection.collapsed(
      offset: _controller.text.length,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final sourceState = ref.watch(votingConfigSourceProvider);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.background.ground,
        borderRadius: BorderRadius.circular(AppRadii.large),
        border: Border.all(color: colors.border.subtle),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints.tightFor(width: widget.width),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: sourceState.when(
            loading: () => const SizedBox(
              height: 180,
              child: Center(child: AppIcon(AppIcons.loader)),
            ),
            error: (error, _) =>
                _PanelError(message: error.toString(), onClose: widget.onClose),
            data: (source) {
              _syncController(source);
              final message = _submitError ?? _fieldMessage();
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _PanelHeader(onClose: widget.onClose),
                  const SizedBox(height: AppSpacing.xs),
                  _CurrentSourceText(source: source),
                  const SizedBox(height: AppSpacing.sm),
                  AppTextField(
                    label: 'Static Config URL',
                    controller: _controller,
                    autofocus: true,
                    leading: const AppIcon(AppIcons.endpoint),
                    leadingSlotWidth: 32,
                    trailingSlotWidth: 40,
                    inputHorizontalPadding: AppSpacing.s,
                    keyboardType: TextInputType.url,
                    textInputAction: TextInputAction.done,
                    messageText: message,
                    tone: message == null
                        ? AppTextFieldTone.neutral
                        : AppTextFieldTone.destructive,
                    onChanged: (_) => setState(() {
                      _submitError = null;
                    }),
                    onSubmitted: (_) => _submit(),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AppButton(
                        onPressed: _isSubmitting || source.isDefault
                            ? null
                            : _resetDefault,
                        variant: AppButtonVariant.secondary,
                        minWidth: 164,
                        child: const Text('Use Default'),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      AppButton(
                        onPressed: _canUpdate(source) ? _submit : null,
                        variant: AppButtonVariant.primary,
                        minWidth: 164,
                        trailing: const AppIcon(AppIcons.chevronForward),
                        child: Text(_isSubmitting ? 'Updating...' : 'Update'),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _CurrentSourceText extends StatelessWidget {
  const _CurrentSourceText({required this.source});

  final VotingConfigSourceState source;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final uri = Uri.tryParse(source.sourceUrl);
    final label = uri == null || uri.host.isEmpty ? source.sourceUrl : uri.host;
    return Text.rich(
      TextSpan(
        text: 'Current: ',
        children: [
          TextSpan(
            text: label,
            style: TextStyle(color: colors.text.brandCrimson),
          ),
          if (source.isDefault) const TextSpan(text: ' (Default)'),
        ],
      ),
      textAlign: TextAlign.center,
      style: AppTypography.bodyMedium.copyWith(color: colors.text.primary),
    );
  }
}

class _PanelHeader extends StatelessWidget {
  const _PanelHeader({required this.onClose});

  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      height: 32,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Center(
            child: Text(
              'Voting Config',
              style: AppTypography.headlineMedium.copyWith(
                color: colors.text.accent,
              ),
            ),
          ),
          if (onClose != null)
            Positioned(
              right: 0,
              child: _SmallIconButton(
                icon: AppIcons.cross,
                semanticLabel: 'Close voting config settings',
                onTap: onClose!,
              ),
            ),
        ],
      ),
    );
  }
}

class _PanelError extends StatelessWidget {
  const _PanelError({required this.message, this.onClose});

  final String message;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _PanelHeader(onClose: onClose),
        const SizedBox(height: AppSpacing.sm),
        Text(
          message,
          textAlign: TextAlign.center,
          style: AppTypography.bodyMedium.copyWith(
            color: context.colors.text.destructive,
          ),
        ),
      ],
    );
  }
}

class _SmallIconButton extends StatefulWidget {
  const _SmallIconButton({
    required this.icon,
    required this.semanticLabel,
    required this.onTap,
  });

  final String icon;
  final String semanticLabel;
  final VoidCallback onTap;

  @override
  State<_SmallIconButton> createState() => _SmallIconButtonState();
}

class _SmallIconButtonState extends State<_SmallIconButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      button: true,
      label: widget.semanticLabel,
      child: ExcludeSemantics(
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => _setHovered(true),
          onExit: (_) => _setHovered(false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: _hovered
                    ? colors.button.ghost.bgHover
                    : colors.background.ground.withValues(alpha: 0),
                shape: BoxShape.circle,
              ),
              child: SizedBox(
                width: 32,
                height: 32,
                child: Center(
                  child: AppIcon(
                    widget.icon,
                    size: AppIconSize.medium,
                    color: colors.icon.accent,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _setHovered(bool hovered) {
    if (_hovered == hovered) return;
    setState(() {
      _hovered = hovered;
    });
  }
}
