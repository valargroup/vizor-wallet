import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_layout.dart';
import '../../../core/layout/app_main_sidebar.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_back_link.dart';
import '../../../services/qr_scanner.dart';
import '../../keystone/widgets/keystone_qr_scanner_card.dart';
import '../migration_copy.dart';

class MigrationScanScreen extends ConsumerStatefulWidget {
  const MigrationScanScreen({super.key});

  @override
  ConsumerState<MigrationScanScreen> createState() =>
      _MigrationScanScreenState();
}

class _MigrationScanScreenState extends ConsumerState<MigrationScanScreen> {
  static const _signResultUrType = 'zcash-sign-result';

  bool _decoding = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(appLayoutProvider.notifier).setMode(AppLayoutMode.large);
    });
  }

  void _handleComplete(ScanResult result) {
    if (_decoding) return;
    setState(() => _decoding = true);
    context.pop(Uint8List.fromList(result.data));
  }

  void _handleDecodeError(Object error) {
    if (!mounted || _decoding) return;
    final message = error.toString().contains('Unexpected UR type')
        ? 'Open the signed migration QR on Keystone, then scan again.'
        : 'Keep the QR code steady and fully visible.';
    if (_error == message) return;
    setState(() => _error = message);
  }

  void _goBack() {
    if (context.canPop()) {
      context.pop();
      return;
    }
    context.go('/migration');
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AppDesktopShell(
      sidebar: const AppMainSidebar(),
      pane: AppDesktopPane(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppBackLink(label: 'Back', onTap: _goBack),
            const SizedBox(height: AppSpacing.s),
            Text(
              MigrationCopy.scanTitle,
              style: AppTypography.displaySmall.copyWith(
                color: colors.text.accent,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              MigrationCopy.scanBody,
              style: AppTypography.bodyMedium.copyWith(
                color: colors.text.secondary,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Expanded(
              child: Center(
                child: KeystoneQrScannerCard(
                  expectedUrType: _signResultUrType,
                  decoding: _decoding,
                  error: _error,
                  onProgress: (_) {},
                  onDecodeError: _handleDecodeError,
                  onComplete: _handleComplete,
                  decodingLabel: MigrationCopy.scanDecodingLabel,
                  unavailableMessage: MigrationCopy.scanUnavailable,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
