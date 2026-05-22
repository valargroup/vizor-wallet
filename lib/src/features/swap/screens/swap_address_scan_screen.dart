import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../../main.dart' show log;
import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_main_sidebar.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_back_link.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../services/camera_permission_settings.dart';
import '../../../services/qr_scanner.dart';
import '../domain/swap_address_scan_payload.dart';

enum _CameraAccessStatus { active, requesting, denied, unavailable }

class SwapAddressScanScreen extends StatefulWidget {
  const SwapAddressScanScreen({super.key});

  @override
  State<SwapAddressScanScreen> createState() => _SwapAddressScanScreenState();
}

class _SwapAddressScanScreenState extends State<SwapAddressScanScreen>
    with WidgetsBindingObserver {
  late final MobileScannerController _controller;
  bool _completed = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = MobileScannerController(
      facing: defaultQrScannerFacing,
      formats: QrScanner.formats,
      detectionSpeed: QrScanner.detectionSpeed,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    unawaited(_retryCameraStart(openSettingsOnDenied: false));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  _CameraAccessStatus _cameraAccessStatus(MobileScannerState state) {
    if (!QrScanner.isAvailable) return _CameraAccessStatus.unavailable;
    if (state.error?.errorCode == MobileScannerErrorCode.permissionDenied) {
      return _CameraAccessStatus.denied;
    }
    if (state.hasCameraPermission) return _CameraAccessStatus.active;
    return _CameraAccessStatus.requesting;
  }

  Future<void> _retryCameraStart({required bool openSettingsOnDenied}) async {
    if (!QrScanner.isAvailable || _controller.value.isStarting) return;

    try {
      await _controller.start();
    } catch (e, st) {
      log('SwapAddressScan: camera start retry error: $e\n$st');
    }

    if (!mounted || !openSettingsOnDenied) return;
    if (_cameraAccessStatus(_controller.value) != _CameraAccessStatus.denied) {
      return;
    }

    final opened = await CameraPermissionSettings.open();
    if (!opened) {
      log('SwapAddressScan: failed to open camera permission settings');
    }
  }

  void _handleScanComplete(String value) {
    if (_completed) return;
    final normalized = normalizeSwapAddressScanPayload(value);
    if (normalized == null || normalized.isEmpty) {
      setState(() => _error = 'QR code did not include an address.');
      return;
    }
    _completed = true;
    if (context.canPop()) {
      context.pop(normalized);
      return;
    }
    context.go('/swap');
  }

  void _cancel() {
    if (context.canPop()) {
      context.pop();
      return;
    }
    context.go('/swap');
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AppDesktopShell(
      sidebar: const AppMainSidebar(),
      pane: AppDesktopPane(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: AppBackLink(label: 'Swap', onTap: _cancel, minWidth: 60),
            ),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Scan address QR',
                        key: const ValueKey('swap_address_scan_title'),
                        textAlign: TextAlign.center,
                        style: AppTypography.headlineSmall.copyWith(
                          color: colors.text.accent,
                          fontSize: 26,
                          height: 32 / 26,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'Scan a plain address or payment URI.',
                        textAlign: TextAlign.center,
                        style: AppTypography.bodyMediumStrong.copyWith(
                          color: colors.text.secondary,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.base),
                      _ScannerCard(
                        controller: _controller,
                        accessStatusFor: _cameraAccessStatus,
                        onRetry: () => unawaited(
                          _retryCameraStart(openSettingsOnDenied: true),
                        ),
                        onComplete: _handleScanComplete,
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          _error!,
                          key: const ValueKey('swap_address_scan_error'),
                          textAlign: TextAlign.center,
                          style: AppTypography.bodySmall.copyWith(
                            color: colors.text.destructive,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScannerCard extends StatelessWidget {
  const _ScannerCard({
    required this.controller,
    required this.accessStatusFor,
    required this.onRetry,
    required this.onComplete,
  });

  final MobileScannerController controller;
  final _CameraAccessStatus Function(MobileScannerState state) accessStatusFor;
  final VoidCallback onRetry;
  final ValueChanged<String> onComplete;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      key: const ValueKey('swap_address_scan_card'),
      padding: const EdgeInsets.all(AppSpacing.xxs),
      decoration: BoxDecoration(
        color: colors.background.base,
        border: Border.all(color: colors.border.regular),
        borderRadius: BorderRadius.circular(AppRadii.small),
      ),
      child: AspectRatio(
        aspectRatio: 1.45,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadii.small),
          clipBehavior: Clip.antiAliasWithSaveLayer,
          child: DecoratedBox(
            decoration: BoxDecoration(color: colors.background.raised),
            child: ValueListenableBuilder<MobileScannerState>(
              valueListenable: controller,
              builder: (context, scannerState, _) {
                final accessStatus = accessStatusFor(scannerState);
                final active = accessStatus == _CameraAccessStatus.active;
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    if (QrScanner.isAvailable)
                      PlainQrScannerView(
                        controller: controller,
                        onComplete: onComplete,
                      )
                    else
                      _CameraMessage(
                        icon: AppIcons.cameraDenied,
                        title: 'Camera unavailable',
                        message:
                            'Address QR scanning requires a camera on this device.',
                      ),
                    if (active) const _ScanFrame(),
                    if (accessStatus == _CameraAccessStatus.requesting)
                      const _CameraMessage(
                        icon: AppIcons.camera,
                        title: 'Enable camera access',
                        message: 'Camera access is required to scan QR codes.',
                      ),
                    if (accessStatus == _CameraAccessStatus.denied)
                      _CameraMessage(
                        icon: AppIcons.cameraDenied,
                        title: 'Camera access denied',
                        message:
                            'Request access again or enable it in system settings.',
                        action: AppButton(
                          onPressed: onRetry,
                          variant: AppButtonVariant.secondary,
                          size: AppButtonSize.medium,
                          minWidth: 118,
                          leading: const AppIcon(AppIcons.renew),
                          child: const Text('Request again'),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _CameraMessage extends StatelessWidget {
  const _CameraMessage({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final String icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ColoredBox(
      color: colors.background.raised,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIcon(icon, size: 30, color: colors.icon.accent),
              const SizedBox(height: AppSpacing.xs),
              Text(
                title,
                textAlign: TextAlign.center,
                style: AppTypography.labelLarge.copyWith(
                  color: colors.text.accent,
                ),
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                message,
                textAlign: TextAlign.center,
                style: AppTypography.bodySmall.copyWith(
                  color: colors.text.secondary,
                ),
              ),
              if (action != null) ...[
                const SizedBox(height: AppSpacing.sm),
                action!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ScanFrame extends StatelessWidget {
  const _ScanFrame();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return IgnorePointer(
      child: Center(
        child: Container(
          width: 224,
          height: 224,
          decoration: BoxDecoration(
            border: Border.all(color: colors.border.strong, width: 2),
            borderRadius: BorderRadius.circular(AppRadii.small),
          ),
        ),
      ),
    );
  }
}
