import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../main.dart' show log;
import '../../core/formatting/zec_amount.dart';
import '../../core/layout/app_desktop_shell.dart';
import '../../core/layout/app_main_sidebar.dart';
import '../../core/storage/wallet_paths.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_back_link.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_icon.dart';
import '../../providers/account_provider.dart';
import '../../providers/rpc_endpoint_provider.dart';
import '../../providers/sync_provider.dart';
import '../../rust/api/keystone.dart' as rust_keystone;
import '../../rust/api/sync.dart' as rust_sync;
import '../../rust/wallet/keystone.dart';
import '../../services/qr_scanner.dart';
import '../keystone/widgets/keystone_pczt_qr_stage.dart';
import '../keystone/widgets/keystone_qr_scanner_card.dart';

class KeystoneBatchDebugScreen extends ConsumerStatefulWidget {
  const KeystoneBatchDebugScreen({super.key});

  @override
  ConsumerState<KeystoneBatchDebugScreen> createState() =>
      _KeystoneBatchDebugScreenState();
}

enum _BatchDebugPhase {
  idle,
  preparing,
  ready,
  verifying,
  verified,
  broadcasting,
  broadcasted,
  failed,
}

class _KeystoneBatchDebugScreenState
    extends ConsumerState<KeystoneBatchDebugScreen> {
  static const _messageCount = 3;
  static const _signResultUrType = 'zcash-sign-result';

  final _recipientController = TextEditingController();
  final _amountController = TextEditingController(text: '0.0001');
  final _resultPartsController = TextEditingController();

  _BatchDebugPhase _phase = _BatchDebugPhase.idle;
  bool _recipientPrimed = false;
  bool _cameraScanActive = false;
  int _scanResetToken = 0;
  int _scanProgress = 0;
  String? _requestId;
  String? _error;
  String? _verificationSummary;
  String? _broadcastSummary;
  List<String> _batchUrParts = const [];
  List<ZcashBatchMessageInput> _batchMessages = const [];
  List<ZcashBatchSignedMessage> _signedMessages = const [];
  Map<String, List<int>> _pcztsWithProofsById = const {};

  @override
  void dispose() {
    _recipientController.dispose();
    _amountController.dispose();
    _resultPartsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accountState = ref.watch(accountProvider).value;
    final activeAddress = accountState?.activeAddress;
    if (!_recipientPrimed &&
        activeAddress != null &&
        activeAddress.isNotEmpty) {
      _recipientController.text = activeAddress;
      _recipientPrimed = true;
    }

    final colors = context.colors;
    final activeAccount = accountState?.activeAccount;
    final endpoint = ref.watch(rpcEndpointProvider);
    final canGenerate =
        _phase != _BatchDebugPhase.preparing &&
        _phase != _BatchDebugPhase.verifying &&
        _phase != _BatchDebugPhase.broadcasting;
    final canVerify =
        _phase != _BatchDebugPhase.preparing &&
        _phase != _BatchDebugPhase.verifying &&
        _phase != _BatchDebugPhase.broadcasting;
    final canBroadcast =
        _phase == _BatchDebugPhase.verified &&
        _signedMessages.length == _messageCount &&
        _pcztsWithProofsById.length == _messageCount;

    return AppDesktopShell(
      sidebar: const AppMainSidebar(),
      pane: AppDesktopPane(
        padding: EdgeInsets.zero,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const AppRouteBackLink(),
              const SizedBox(height: AppSpacing.s),
              Text(
                'Keystone batch debug',
                style: AppTypography.displaySmall.copyWith(
                  color: colors.text.accent,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Build three Orchard PCZTs, sign them in one Keystone action, then verify the signed result.',
                style: AppTypography.bodyMedium.copyWith(
                  color: colors.text.secondary,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.s,
                runSpacing: AppSpacing.s,
                children: [
                  _InfoPill(
                    label: 'Account',
                    value: activeAccount?.name ?? 'None',
                  ),
                  _InfoPill(
                    label: 'Hardware',
                    value: activeAccount?.isHardware == true ? 'Yes' : 'No',
                  ),
                  _InfoPill(label: 'Network', value: endpoint.networkName),
                  _InfoPill(
                    label: 'Request',
                    value: _requestId ?? 'Not generated',
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              _DebugSurface(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SectionTitle('Batch draft'),
                    const SizedBox(height: AppSpacing.s),
                    _DebugTextField(
                      controller: _recipientController,
                      label: 'Recipient UA',
                    ),
                    const SizedBox(height: AppSpacing.s),
                    SizedBox(
                      width: 180,
                      child: _DebugTextField(
                        controller: _amountController,
                        label: 'Amount per tx',
                      ),
                    ),
                    const SizedBox(height: AppSpacing.s),
                    Row(
                      children: [
                        AppButton(
                          onPressed: canGenerate ? _generateBatch : null,
                          leading: const AppIcon(AppIcons.qr),
                          child: const Text('Generate 3-PCZT batch'),
                        ),
                        const SizedBox(width: AppSpacing.s),
                        AppButton(
                          onPressed: _batchUrParts.isEmpty
                              ? null
                              : _copyAllUrParts,
                          variant: AppButtonVariant.secondary,
                          size: AppButtonSize.medium,
                          child: const Text('Copy all parts'),
                        ),
                      ],
                    ),
                    if (_batchUrParts.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.s),
                      Text(
                        '${_batchUrParts.length} QR part${_batchUrParts.length == 1 ? '' : 's'} ready',
                        style: AppTypography.bodyMedium.copyWith(
                          color: colors.text.secondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _DebugSurface(
                    width: 310,
                    child: Column(
                      children: [
                        _SectionTitle('Scan with Keystone'),
                        const SizedBox(height: AppSpacing.s),
                        KeystonePcztQrStage(
                          phase: switch (_phase) {
                            _BatchDebugPhase.ready ||
                            _BatchDebugPhase.verified ||
                            _BatchDebugPhase.broadcasting ||
                            _BatchDebugPhase.broadcasted =>
                              KeystonePcztQrStagePhase.ready,
                            _BatchDebugPhase.failed =>
                              KeystonePcztQrStagePhase.failed,
                            _BatchDebugPhase.idle ||
                            _BatchDebugPhase.preparing ||
                            _BatchDebugPhase.verifying =>
                              KeystonePcztQrStagePhase.preparing,
                          },
                          urParts: _batchUrParts,
                          error: _error,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: _DebugSurface(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _SectionTitle('Verify result'),
                          const SizedBox(height: AppSpacing.s),
                          AppButton(
                            onPressed: _cameraScanActive
                                ? _stopCameraScan
                                : canVerify
                                ? _startCameraScan
                                : null,
                            variant: _cameraScanActive
                                ? AppButtonVariant.secondary
                                : AppButtonVariant.primary,
                            size: AppButtonSize.medium,
                            leading: AppIcon(
                              _cameraScanActive
                                  ? AppIcons.cross
                                  : AppIcons.camera,
                            ),
                            child: Text(
                              _cameraScanActive
                                  ? 'Stop camera scan'
                                  : 'Start camera scan',
                            ),
                          ),
                          const SizedBox(height: AppSpacing.s),
                          if (_cameraScanActive)
                            Center(
                              child: KeystoneQrScannerCard(
                                key: ValueKey(_scanResetToken),
                                expectedUrType: _signResultUrType,
                                decoding: _phase == _BatchDebugPhase.verifying,
                                error: _error,
                                onProgress: (progress) {
                                  if (!mounted) return;
                                  setState(() {
                                    _scanProgress = progress;
                                    if (progress > 0) _error = null;
                                  });
                                },
                                onDecodeError: _handleCameraDecodeError,
                                onComplete: _handleScannedResult,
                                decodingLabel: 'Reading batch result...',
                                unavailableMessage:
                                    'Keystone batch result scanning uses camera QR scanning only. Connect a camera and try again.',
                              ),
                            )
                          else
                            SizedBox(
                              height: 220,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(
                                  AppRadii.xSmall,
                                ),
                                child: ColoredBox(
                                  color: colors.background.neutralSubtleOpacity,
                                  child: Center(
                                    child: AppButton(
                                      onPressed: canVerify
                                          ? _startCameraScan
                                          : null,
                                      size: AppButtonSize.medium,
                                      leading: const AppIcon(AppIcons.camera),
                                      child: const Text('Start camera scan'),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          const SizedBox(height: AppSpacing.s),
                          Text(
                            'Scan progress $_scanProgress%',
                            style: AppTypography.bodyMedium.copyWith(
                              color: colors.text.secondary,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.s),
                          _DebugTextField(
                            controller: _resultPartsController,
                            label: 'Paste result UR part(s)',
                            maxLines: 4,
                          ),
                          const SizedBox(height: AppSpacing.s),
                          Wrap(
                            spacing: AppSpacing.s,
                            runSpacing: AppSpacing.s,
                            children: [
                              AppButton(
                                onPressed: canVerify
                                    ? _decodePastedResult
                                    : null,
                                size: AppButtonSize.medium,
                                child: const Text('Decode pasted result'),
                              ),
                              AppButton(
                                onPressed: canBroadcast
                                    ? _broadcastSignedBatch
                                    : null,
                                variant: AppButtonVariant.destructive,
                                size: AppButtonSize.medium,
                                child: const Text('Broadcast signed batch'),
                              ),
                              AppButton(
                                onPressed: _resetResultScan,
                                variant: AppButtonVariant.ghost,
                                size: AppButtonSize.medium,
                                child: const Text('Reset scan'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              _DebugSurface(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SectionTitle('Status'),
                    const SizedBox(height: AppSpacing.s),
                    _StatusLine(label: 'Phase', value: _phase.name),
                    _StatusLine(
                      label: 'Unsigned messages',
                      value: _batchMessages.length.toString(),
                    ),
                    _StatusLine(
                      label: 'Signed messages',
                      value: _signedMessages.length.toString(),
                    ),
                    if (_verificationSummary != null)
                      _StatusLine(
                        label: 'Verification',
                        value: _verificationSummary!,
                      ),
                    if (_broadcastSummary != null)
                      _StatusLine(
                        label: 'Broadcast',
                        value: _broadcastSummary!,
                      ),
                    if (_error != null)
                      _StatusLine(label: 'Error', value: _error!),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _generateBatch() async {
    final accountState = ref.read(accountProvider).value;
    final activeAccount = accountState?.activeAccount;
    final accountUuid = accountState?.activeAccountUuid;
    final recipient = _recipientController.text.trim();
    final amount = parseZecAmount(_amountController.text.trim());
    final endpoint = ref.read(rpcEndpointProvider);

    if (activeAccount == null || accountUuid == null) {
      _fail('No active account.');
      return;
    }
    if (!activeAccount.isHardware) {
      _fail('Active account is not a Keystone hardware account.');
      return;
    }
    if (endpoint.networkName != 'main') {
      _fail('The firmware batch PR currently accepts mainnet only.');
      return;
    }
    if (recipient.isEmpty) {
      _fail('Recipient address is required.');
      return;
    }
    if (amount == null || amount <= BigInt.zero) {
      _fail('Enter a positive ZEC amount.');
      return;
    }

    final requestId = 'vizor-${DateTime.now().millisecondsSinceEpoch}';
    setState(() {
      _phase = _BatchDebugPhase.preparing;
      _requestId = requestId;
      _error = null;
      _verificationSummary = null;
      _broadcastSummary = null;
      _batchUrParts = const [];
      _batchMessages = const [];
      _signedMessages = const [];
      _pcztsWithProofsById = const {};
      _cameraScanActive = false;
      _scanProgress = 0;
    });

    try {
      final dbPath = await getWalletDbPath();
      final messages = <ZcashBatchMessageInput>[];
      final pcztsWithProofsById = <String, List<int>>{};
      final inputOwners = <String, String>{};

      final batchItems = await rust_sync.createReservedPcztBatch(
        dbPath: dbPath,
        network: endpoint.networkName,
        accountUuid: accountUuid,
        requests: [
          for (var i = 0; i < _messageCount; i++)
            rust_sync.ReservedPcztBatchRequest(
              id: 'tx-${i + 1}',
              sendFlowId: '$requestId-${i + 1}',
              toAddress: recipient,
              amountZatoshi: amount,
              memo:
                  'Vizor Keystone batch sim ${i + 1}/$_messageCount $requestId',
            ),
        ],
      );
      if (batchItems.length != _messageCount) {
        throw StateError(
          'Reserved planner returned ${batchItems.length} messages, expected $_messageCount.',
        );
      }

      for (final item in batchItems) {
        for (final spendNullifier in item.spendNullifiers) {
          final previousOwner = inputOwners[spendNullifier];
          if (previousOwner != null) {
            throw StateError(
              'Generated ${item.id} reuses ${_inputPoolLabel(spendNullifier)} input already selected by $previousOwner. '
              'Split funds into separate mined notes, resync, or generate fewer transactions.',
            );
          }
          inputOwners[spendNullifier] = item.id;
        }

        pcztsWithProofsById[item.id] = item.pcztWithProofs;
        messages.add(
          ZcashBatchMessageInput(id: item.id, pcztBytes: item.redactedPczt),
        );
      }

      final urParts = await rust_keystone.encodeZcashSignBatchUrParts(
        requestId: requestId,
        messages: messages,
        maxFragmentLen: BigInt.from(200),
      );

      if (!mounted) return;
      setState(() {
        _phase = _BatchDebugPhase.ready;
        _batchMessages = messages;
        _pcztsWithProofsById = pcztsWithProofsById;
        _batchUrParts = urParts;
        _scanResetToken++;
      });
    } catch (e, st) {
      log('KeystoneBatchDebug.generate: ERROR: $e\n$st');
      if (!mounted) return;
      _fail(e.toString());
    }
  }

  String _inputPoolLabel(String spendNullifier) {
    final separator = spendNullifier.indexOf(':');
    if (separator <= 0) return 'shielded';
    return spendNullifier.substring(0, separator);
  }

  Future<void> _handleScannedResult(ScanResult result) async {
    await _verifyResultCbor(result.data);
  }

  void _handleCameraDecodeError(Object error) {
    if (!mounted || _phase == _BatchDebugPhase.verifying) return;
    final message = error.toString().contains('Unexpected UR type')
        ? 'Open the zcash-sign-result QR on Keystone, then scan again.'
        : 'Keep the QR code steady and fully visible.';
    if (_error == message) return;
    setState(() {
      _error = message;
    });
  }

  Future<void> _decodePastedResult() async {
    final parts = _resultPartsController.text
        .split(RegExp(r'\s+'))
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) {
      _fail('Paste at least one zcash-sign-result UR part.');
      return;
    }

    setState(() {
      _phase = _BatchDebugPhase.verifying;
      _error = null;
      _cameraScanActive = false;
      _scanProgress = 0;
    });

    try {
      rust_keystone.resetUrSession();
      for (final part in parts) {
        final result = await rust_keystone.decodeUrPart(
          part_: part,
          expectedUrType: _signResultUrType,
        );
        if (!mounted) return;
        setState(() {
          _scanProgress = result.progress;
        });
        final cbor = result.data;
        if (result.complete && cbor != null) {
          await _verifyResultCbor(cbor);
          return;
        }
      }
      _fail('Pasted UR parts did not complete the result.');
    } catch (e, st) {
      log('KeystoneBatchDebug.decodePastedResult: ERROR: $e\n$st');
      if (!mounted) return;
      _fail(e.toString());
    }
  }

  Future<void> _verifyResultCbor(List<int> cbor) async {
    if (_requestId == null || _batchMessages.isEmpty) {
      _fail('Generate a batch before verifying a result.');
      return;
    }

    setState(() {
      _phase = _BatchDebugPhase.verifying;
      _error = null;
    });

    try {
      final result = await rust_keystone.decodeZcashSignResultCbor(cbor: cbor);
      if (result.requestId != _requestId) {
        throw StateError(
          'Result request id ${result.requestId} does not match $_requestId.',
        );
      }

      final expectedIds = _batchMessages.map((message) => message.id).toSet();
      final resultIds = result.results.map((message) => message.id).toSet();
      if (result.results.length != _batchMessages.length ||
          resultIds.length != expectedIds.length ||
          !resultIds.containsAll(expectedIds)) {
        throw StateError(
          'Result IDs $resultIds do not match expected IDs $expectedIds.',
        );
      }

      if (!mounted) return;
      setState(() {
        _phase = _BatchDebugPhase.verified;
        _cameraScanActive = false;
        _signedMessages = result.results;
        _verificationSummary =
            'Verified ${result.results.length} signed PCZT payloads for ${result.requestId}.';
        _broadcastSummary = null;
      });
    } catch (e, st) {
      log('KeystoneBatchDebug.verifyResult: ERROR: $e\n$st');
      if (!mounted) return;
      _fail(e.toString());
    }
  }

  Future<void> _broadcastSignedBatch() async {
    if (_signedMessages.length != _messageCount ||
        _pcztsWithProofsById.length != _messageCount) {
      _fail('Verify a complete signed batch before broadcasting.');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Broadcast signed batch?'),
        content: const Text(
          'This will broadcast three mainnet transactions immediately.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Broadcast'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;

    setState(() {
      _phase = _BatchDebugPhase.broadcasting;
      _error = null;
      _broadcastSummary = null;
    });

    try {
      final dbPath = await getWalletDbPath();
      final endpoint = ref.read(rpcEndpointProvider);
      final txids = <String>[];

      for (final signedMessage in _signedMessages) {
        final pcztWithProofs = _pcztsWithProofsById[signedMessage.id];
        if (pcztWithProofs == null) {
          throw StateError(
            'Missing proof PCZT for signed message ${signedMessage.id}.',
          );
        }

        final result = await rust_sync.extractAndBroadcastPczt(
          dbPath: dbPath,
          lightwalletdUrl: endpoint.normalizedLightwalletdUrl,
          network: endpoint.networkName,
          pcztWithProofsBytes: pcztWithProofs,
          pcztWithSignaturesBytes: signedMessage.signedPcztBytes,
        );
        if (result.status != 'broadcasted') {
          throw StateError(
            'Broadcast for ${signedMessage.id} returned ${result.status}: ${result.message ?? 'no message'}',
          );
        }
        txids.add(result.txid);
      }

      try {
        await ref.read(syncProvider.notifier).refreshAfterSend();
      } catch (e) {
        log('KeystoneBatchDebug.broadcast: refreshAfterSend failed: $e');
      }

      if (!mounted) return;
      setState(() {
        _phase = _BatchDebugPhase.broadcasted;
        _broadcastSummary =
            'Broadcasted ${txids.length} txs: ${txids.join(', ')}';
      });
    } catch (e, st) {
      log('KeystoneBatchDebug.broadcast: ERROR: $e\n$st');
      if (!mounted) return;
      _fail(e.toString());
    }
  }

  Future<void> _copyAllUrParts() async {
    if (_batchUrParts.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: _batchUrParts.join('\n')));
  }

  void _startCameraScan() {
    rust_keystone.resetUrSession();
    setState(() {
      _cameraScanActive = true;
      _scanResetToken++;
      _scanProgress = 0;
      _error = null;
    });
  }

  void _stopCameraScan() {
    rust_keystone.resetUrSession();
    setState(() {
      _cameraScanActive = false;
      _scanResetToken++;
      _scanProgress = 0;
    });
  }

  void _resetResultScan() {
    rust_keystone.resetUrSession();
    setState(() {
      _cameraScanActive = false;
      _scanResetToken++;
      _scanProgress = 0;
      _resultPartsController.clear();
      if (_phase == _BatchDebugPhase.failed) {
        _phase = _batchUrParts.isEmpty
            ? _BatchDebugPhase.idle
            : _BatchDebugPhase.ready;
      }
      _error = null;
    });
  }

  void _fail(String message) {
    setState(() {
      _phase = _BatchDebugPhase.failed;
      _error = message;
    });
  }
}

class _DebugSurface extends StatelessWidget {
  const _DebugSurface({required this.child, this.width});

  final Widget child;
  final double? width;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: context.colors.background.neutralSubtleOpacity,
        borderRadius: BorderRadius.circular(AppRadii.xSmall),
      ),
      child: child,
    );
  }
}

class _DebugTextField extends StatelessWidget {
  const _DebugTextField({
    required this.controller,
    required this.label,
    this.maxLines = 1,
  });

  final TextEditingController controller;
  final String label;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return TextField(
      controller: controller,
      maxLines: maxLines,
      style: AppTypography.bodyMedium.copyWith(color: colors.text.accent),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: AppTypography.bodyMedium.copyWith(
          color: colors.text.secondary,
        ),
        border: const OutlineInputBorder(),
        isDense: true,
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: colors.background.neutralSubtleOpacity,
        borderRadius: BorderRadius.circular(AppRadii.xSmall),
      ),
      child: Text(
        '$label: $value',
        style: AppTypography.bodyMedium.copyWith(color: colors.text.accent),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: AppTypography.bodyLarge.copyWith(
        color: context.colors.text.accent,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
      child: Text(
        '$label: $value',
        style: AppTypography.bodyMedium.copyWith(color: colors.text.secondary),
      ),
    );
  }
}
