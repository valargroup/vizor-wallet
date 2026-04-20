import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';

import '../../../../main.dart' show log;
import '../../../core/config/network_config.dart';
import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_layout.dart';
import '../../../core/layout/app_main_sidebar.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_decorative_divider.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/sync_provider.dart';
import '../../../providers/wallet_provider.dart';
import '../../../rust/api/sync.dart' as rust_sync;
import '../../../rust/api/wallet.dart' as rust_wallet;
import '../../../services/keystone_transport.dart';

const _saplingSpendHash = 'a15ab54c2888880e53c823a3063820c728444126';
const _saplingOutputHash = '0ebc5a1ef3653948e1c46cf7a16071eac4b7e352';
const _saplingParamBaseUrl = 'https://download.z.cash/downloads/';

class SendScreen extends ConsumerStatefulWidget {
  const SendScreen({super.key});

  @override
  ConsumerState<SendScreen> createState() => _SendScreenState();
}

class _SendScreenState extends ConsumerState<SendScreen> {
  final _addressController = TextEditingController();
  final _amountController = TextEditingController();
  final _memoController = TextEditingController();
  final _addressFocusNode = FocusNode();
  final _amountFocusNode = FocusNode();
  final _memoFocusNode = FocusNode();
  final _memoScrollController = ScrollController();
  bool _isSending = false;
  bool _messageExpanded = false;
  String? _error;
  String _addressType = '';
  String?
  _amountError; // null = no error, empty string = silent invalid (empty/dot)
  int _validateSeq = 0;

  @override
  void initState() {
    super.initState();
    _memoController.addListener(_handleMemoChanged);
    _addressFocusNode.addListener(_handleFieldVisualStateChanged);
    _amountFocusNode.addListener(_handleFieldVisualStateChanged);
    _memoFocusNode.addListener(_handleMemoFocusChanged);
    _memoFocusNode.addListener(_handleFieldVisualStateChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(appLayoutProvider.notifier).setMode(AppLayoutMode.large);
    });
  }

  @override
  void dispose() {
    _memoController.removeListener(_handleMemoChanged);
    _addressFocusNode.removeListener(_handleFieldVisualStateChanged);
    _amountFocusNode.removeListener(_handleFieldVisualStateChanged);
    _memoFocusNode.removeListener(_handleMemoFocusChanged);
    _memoFocusNode.removeListener(_handleFieldVisualStateChanged);
    _addressController.dispose();
    _amountController.dispose();
    _memoController.dispose();
    _addressFocusNode.dispose();
    _amountFocusNode.dispose();
    _memoFocusNode.dispose();
    _memoScrollController.dispose();
    super.dispose();
  }

  void _handleMemoChanged() {
    if (_memoController.text.isNotEmpty && !_messageExpanded) {
      _messageExpanded = true;
    }
    if (mounted) setState(() {});
  }

  void _handleFieldVisualStateChanged() {
    if (mounted) setState(() {});
  }

  void _handleMemoFocusChanged() {
    if (!_memoFocusNode.hasFocus && _memoController.text.isEmpty) {
      _messageExpanded = false;
    }
    if (mounted) setState(() {});
  }

  Future<void> _validateAddress() async {
    final addr = _addressController.text.trim();
    if (addr.isEmpty) {
      setState(() => _addressType = '');
      return;
    }
    try {
      final result = await rust_sync.validateAddress(address: addr);
      setState(
        () => _addressType = result.isValid ? result.addressType : 'invalid',
      );
    } catch (e) {
      log('Send: address validation error: $e');
      setState(() => _addressType = 'error');
    }
  }

  BigInt _getSpendableBalance() {
    final syncState = ref.read(syncProvider).value;
    return syncState?.spendableBalance ?? BigInt.zero;
  }

  bool get _hasValidAddress =>
      _addressController.text.trim().isNotEmpty &&
      _addressType.isNotEmpty &&
      _addressType != 'invalid' &&
      _addressType != 'error';

  bool get _isShieldedAddress =>
      _addressType == 'unified' || _addressType == 'sapling';

  bool get _showAmountError =>
      _amountError != null && _amountError!.trim().isNotEmpty;

  int get _memoLength => utf8.encode(_memoController.text).length;

  String? get _memoError {
    if (_memoLength > 512) return 'Message is too long';
    if (_memoController.text.trim().isNotEmpty && !_isShieldedAddress) {
      return 'Message is only available for shielded addresses';
    }
    return null;
  }

  bool get _canReview =>
      !_isSending &&
      _hasValidAddress &&
      _isAmountValid &&
      _memoError == null &&
      (_isShieldedAddress || _memoController.text.trim().isEmpty);

  String _formatSpendableLabel(BigInt zatoshi) {
    final whole = zatoshi ~/ BigInt.from(100000000);
    final frac = (zatoshi % BigInt.from(100000000)).toString().padLeft(8, '0');

    if (frac == '00000000') return whole.toString();
    if (whole == BigInt.zero && int.parse(frac) < 1000000) {
      return '0.${frac.replaceFirst(RegExp(r'0+$'), '')}';
    }

    final short = frac.substring(0, 2).replaceFirst(RegExp(r'0+$'), '');
    return short.isEmpty ? whole.toString() : '$whole.$short';
  }

  Future<void> _resetWallet(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset Wallet'),
        content: const Text(
          'Delete all wallet data (DB + keychain)? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Reset',
              style: TextStyle(color: Color(0xFFFF3B30)),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    ref.read(syncProvider.notifier).stopSync();
    var waited = 0;
    while (rust_sync.isSyncRunning() && waited < 5000) {
      await Future.delayed(const Duration(milliseconds: 100));
      waited += 100;
    }

    await ref.read(accountProvider.notifier).resetWallet();
    exit(0);
  }

  Future<void> _validateAmount() async {
    final seq = ++_validateSeq;
    final text = _amountController.text.trim();

    // Empty or just "." — silently invalid (no error shown, button disabled)
    if (text.isEmpty || text == '.') {
      setState(() => _amountError = '');
      return;
    }

    final zatoshi = _parseZecToZatoshi(text);
    if (zatoshi == null || zatoshi <= 0) {
      setState(() => _amountError = 'Invalid amount');
      return;
    }

    // Quick balance pre-check
    final spendable = _getSpendableBalance();
    if (BigInt.from(zatoshi) > spendable) {
      setState(() => _amountError = 'Insufficient balance');
      return;
    }

    // Need valid address to estimate fee
    final address = _addressController.text.trim();
    if (address.isEmpty ||
        _addressType == 'invalid' ||
        _addressType == 'error' ||
        _addressType.isEmpty) {
      setState(() => _amountError = null);
      return;
    }

    try {
      final dir = await getApplicationDocumentsDirectory();
      final dbPath = '${dir.path}${Platform.pathSeparator}zcash_wallet.db';
      final memo = _memoController.text.trim();
      final accountUuid = ref.read(accountProvider).value?.activeAccountUuid;
      if (accountUuid == null) {
        setState(() => _amountError = null);
        return;
      }
      final fee = await rust_sync.estimateFee(
        dbPath: dbPath,
        network: 'main',
        accountUuid: accountUuid,
        toAddress: address,
        amountZatoshi: BigInt.from(zatoshi),
        memo: memo.isNotEmpty ? memo : null,
      );

      // Stale check — new input arrived while awaiting
      if (seq != _validateSeq) return;

      final totalNeeded = BigInt.from(zatoshi) + fee;
      if (totalNeeded > spendable) {
        final feeZec = _formatZec(fee);
        setState(
          () => _amountError = 'Insufficient balance (fee: $feeZec ZEC)',
        );
      } else {
        setState(() => _amountError = null);
      }
    } catch (e) {
      if (seq != _validateSeq) return;
      final msg = e.toString();
      if (msg.contains('InsufficientFunds') || msg.contains('insufficient')) {
        setState(() => _amountError = 'Insufficient balance including fee');
      } else {
        log('Send: fee estimation failed (non-blocking): $e');
        setState(() => _amountError = null);
      }
    }
  }

  bool get _isAmountValid => _amountError == null;

  String _friendlyError(String raw) {
    final lower = raw.toLowerCase();
    if (lower.contains('insufficientfunds') || lower.contains('insufficient')) {
      return 'Insufficient balance to cover amount and fee.';
    }
    if (lower.contains('grpc connect failed') ||
        lower.contains('connection refused') ||
        lower.contains('dns error') ||
        lower.contains('tls error')) {
      return 'Network error. Please check your connection and try again.';
    }
    // Partial broadcast must be checked before generic "broadcast rejected"
    if (lower.contains('broadcast failed after') &&
        lower.contains('txs sent')) {
      return 'Some transactions were broadcast but not all. '
          'Please check your transaction history before retrying.';
    }
    if (lower.contains('broadcast rejected')) {
      return 'Transaction was rejected by the network. Please try again.';
    }
    if (lower.contains('proposal not found')) {
      return 'Transaction expired. Please try again.';
    }
    return 'Send failed. Please try again.';
  }

  String _formatZec(BigInt zatoshi) {
    final abs = zatoshi.abs();
    final whole = abs ~/ BigInt.from(100000000);
    final frac = (abs % BigInt.from(100000000)).toString().padLeft(8, '0');
    final sign = zatoshi < BigInt.zero ? '-' : '';
    return '$sign$whole.$frac';
  }

  /// Parse a ZEC string to zatoshi without floating-point.
  /// Handles: "1.5", ".01", "100", "0.00000001"
  int? _parseZecToZatoshi(String input) {
    var s = input.trim();
    if (s.isEmpty) return null;
    if (s.startsWith('.')) s = '0$s';

    final parts = s.split('.');
    if (parts.length > 2) return null;

    final whole = int.tryParse(parts[0].isEmpty ? '0' : parts[0]);
    if (whole == null || whole < 0) return null;

    String frac = parts.length > 1 ? parts[1] : '';
    if (frac.length > 8) frac = frac.substring(0, 8);
    frac = frac.padRight(8, '0');

    final fracInt = int.tryParse(frac);
    if (fracInt == null) return null;

    return whole * 100000000 + fracInt;
  }

  Future<void> _send() async {
    setState(() {
      _isSending = true;
      _error = null;
    });

    // Tracks the active proposal so we can release it on any cancel or
    // error path that happens before it has been consumed by a create /
    // execute call. `proposalConsumed` flips to true once we hand the
    // proposal ID to a function that takes ownership of it; after that
    // the finally block is a no-op. Rust's discardProposal is idempotent.
    BigInt? activeProposalId;
    var proposalConsumed = false;

    try {
      final address = _addressController.text.trim();
      final amountZatoshi = _parseZecToZatoshi(_amountController.text.trim());

      if (!_hasValidAddress) {
        setState(() {
          _error = 'Enter a valid address';
          _isSending = false;
        });
        return;
      }

      if (amountZatoshi == null || amountZatoshi <= 0) {
        setState(() {
          _error = 'Invalid amount';
          _isSending = false;
        });
        return;
      }

      if (_memoError != null) {
        setState(() {
          _error = _memoError;
          _isSending = false;
        });
        return;
      }

      // Check balance before proposing
      final spendable = _getSpendableBalance();
      if (BigInt.from(amountZatoshi) > spendable) {
        setState(() {
          _error =
              'Insufficient balance. Available: ${_formatZec(spendable)} ZEC';
          _isSending = false;
        });
        return;
      }

      final memo = _memoController.text.trim();
      final dir = await getApplicationDocumentsDirectory();
      final dbPath = '${dir.path}${Platform.pathSeparator}zcash_wallet.db';

      // Step 1: Propose transfer
      log('Send: proposing transfer');
      final accountUuid = ref.read(accountProvider).value?.activeAccountUuid;
      if (accountUuid == null) {
        setState(() {
          _error = 'No active account';
          _isSending = false;
        });
        return;
      }
      final proposal = await rust_sync.proposeSend(
        dbPath: dbPath,
        network: 'main',
        accountUuid: accountUuid,
        toAddress: address,
        amountZatoshi: BigInt.from(amountZatoshi),
        memo: memo.isNotEmpty ? memo : null,
      );
      activeProposalId = proposal.proposalId;

      log(
        'Send: proposal_id=${proposal.proposalId}, needs_sapling=${proposal.needsSaplingParams}, fee=${proposal.feeZatoshi}',
      );

      // Step 2: Show confirmation with fee
      if (!mounted) return;
      final confirmed = await _showConfirmationDialog(
        address: address,
        amountZatoshi: BigInt.from(amountZatoshi),
        feeZatoshi: proposal.feeZatoshi,
        memo: memo.isNotEmpty ? memo : null,
      );
      if (!confirmed) {
        setState(() => _isSending = false);
        return;
      }

      // Step 3: Check Sapling params if needed
      final paramsDir = '${dir.path}${Platform.pathSeparator}sapling_params';
      final spendPath =
          '$paramsDir${Platform.pathSeparator}sapling-spend.params';
      final outputPath =
          '$paramsDir${Platform.pathSeparator}sapling-output.params';

      if (proposal.needsSaplingParams) {
        final spendExists = File(spendPath).existsSync();
        final outputExists = File(outputPath).existsSync();

        if (!spendExists || !outputExists) {
          if (!mounted) return;
          final downloadConfirmed = await _showSaplingParamsDialog();
          if (!downloadConfirmed) {
            setState(() => _isSending = false);
            return;
          }

          await Directory(paramsDir).create(recursive: true);
          if (!spendExists) {
            log('Send: downloading sapling-spend.params (~47MB)');
            setState(() => _error = 'Downloading sapling-spend.params...');
            await _downloadAndVerify(
              '${_saplingParamBaseUrl}sapling-spend.params',
              spendPath,
              _saplingSpendHash,
            );
          }
          if (!outputExists) {
            log('Send: downloading sapling-output.params (~3.5MB)');
            setState(() => _error = 'Downloading sapling-output.params...');
            await _downloadAndVerify(
              '${_saplingParamBaseUrl}sapling-output.params',
              outputPath,
              _saplingOutputHash,
            );
          }
          setState(() => _error = null);
        }
      }

      // Step 4: Sign and execute
      final isHardware = ref
          .read(accountProvider.notifier)
          .isActiveAccountHardware;

      String txidResult;
      if (isHardware) {
        // Hardware wallet (Keystone): three-PCZT flow (matches zcash-android-wallet-sdk)
        //   1. createPcztFromProposal → base PCZT
        //   2. clone → addProofsToPczt → pcztWithProofs (local Orchard proofs)
        //   3. clone → redactPcztForSigner → send to Keystone → pcztWithSignatures
        //   4. extractAndBroadcastPczt(pcztWithProofs, pcztWithSignatures) → combines + broadcasts
        log('Send: creating PCZT from proposal ${proposal.proposalId}');
        final pcztBytes = await rust_sync.createPcztFromProposal(
          dbPath: dbPath,
          network: ZcashNetwork.mainnet.name,
          proposalId: proposal.proposalId,
        );
        // createPcztFromProposal removes the proposal from PROPOSAL_STORE
        // on entry, so once this returns the proposal is no longer ours.
        proposalConsumed = true;

        log(
          'Send: adding proofs to PCZT locally (sapling=${proposal.needsSaplingParams})',
        );
        // Hand Sapling params paths to Rust only when the proposal actually
        // needs them. They were downloaded above in the `needsSaplingParams`
        // block, so the files are already on disk by the time we get here.
        final pcztWithProofs = await rust_sync.addProofsToPczt(
          pcztBytes: pcztBytes,
          spendParamsPath: proposal.needsSaplingParams ? spendPath : null,
          outputParamsPath: proposal.needsSaplingParams ? outputPath : null,
        );

        log('Send: redacting PCZT for hardware signer');
        final redactedPczt = await rust_sync.redactPcztForSigner(
          pcztBytes: pcztBytes,
        );

        // Select transport and sign
        if (!mounted) return;
        final transport = await KeystoneTransport.select(context);
        if (transport == null || !mounted) {
          setState(() {
            _isSending = false;
          });
          return;
        }

        log('Send: signing PCZT via ${transport.name}');
        final pcztWithSignatures = await transport.signPczt(
          context,
          redactedPczt,
        );

        // Combine, extract, and broadcast. Pass Sapling params paths in the
        // same conditions as addProofsToPczt above: the extractor and the
        // storage function both need Sapling verifying keys whenever the
        // PCZT has a Sapling bundle, otherwise librustzcash rejects the
        // extraction with `SaplingRequired`.
        log('Send: combining PCZTs and broadcasting');
        txidResult = await rust_sync.extractAndBroadcastPczt(
          dbPath: dbPath,
          lightwalletdUrl: ZcashNetwork.mainnet.lightwalletdUrl,
          network: ZcashNetwork.mainnet.name,
          pcztWithProofsBytes: pcztWithProofs,
          pcztWithSignaturesBytes: pcztWithSignatures,
          spendParamsPath: proposal.needsSaplingParams ? spendPath : null,
          outputParamsPath: proposal.needsSaplingParams ? outputPath : null,
        );
      } else {
        // Software wallet: mnemonic-based signing
        final mnemonic = await ref
            .read(accountProvider.notifier)
            .getActiveMnemonic();
        if (mnemonic == null) {
          setState(() {
            _error = 'Mnemonic not found for active account';
            _isSending = false;
          });
          return;
        }

        final seedBytes = await rust_wallet.deriveSeed(mnemonic: mnemonic);

        log('Send: executing proposal ${proposal.proposalId}');
        txidResult = await rust_sync.executeProposal(
          dbPath: dbPath,
          lightwalletdUrl: ZcashNetwork.mainnet.lightwalletdUrl,
          proposalId: proposal.proposalId,
          seed: seedBytes,
          spendParamsPath: proposal.needsSaplingParams ? spendPath : null,
          outputParamsPath: proposal.needsSaplingParams ? outputPath : null,
        );
        // executeProposal removes the proposal from PROPOSAL_STORE on entry.
        proposalConsumed = true;
      }

      log('Send: success, txids=$txidResult');

      // === Send confirmed at this point — all below is non-critical ===

      try {
        await ref.read(syncProvider.notifier).refreshAfterSend();
      } catch (e) {
        log('Send: refreshAfterSend failed (non-critical): $e');
      }

      if (Platform.isIOS) {
        try {
          const channel = MethodChannel('com.zcash.wallet/background_sync');
          final available =
              await channel.invokeMethod<bool>('isAvailable') ?? false;
          if (available) {
            await channel.invokeMethod('startTxTracking');
            log('Send: iOS TX tracking started');
          }
        } catch (e) {
          log('Send: iOS TX tracking failed (non-critical): $e');
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Transaction sent successfully'),
          backgroundColor: Theme.of(context).colorScheme.tertiary,
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.of(context).pop();
    } catch (e) {
      log('Send: ERROR: $e');
      setState(() {
        _error = _friendlyError(e.toString());
        _isSending = false;
      });
    } finally {
      // Release any proposal that wasn't handed off to a create/execute call.
      // This covers: confirmation dialog cancel, Sapling params dialog cancel,
      // exceptions during Sapling download, and errors thrown before the
      // consume call itself. Rust-side discardProposal is idempotent so a
      // spurious call after a successful consume is harmless.
      if (activeProposalId != null && !proposalConsumed) {
        try {
          await rust_sync.discardProposal(proposalId: activeProposalId);
          log('Send: released proposal $activeProposalId (not consumed)');
        } catch (e) {
          log('Send: discardProposal cleanup failed (non-critical): $e');
        }
      }
    }
  }

  Future<bool> _showConfirmationDialog({
    required String address,
    required BigInt amountZatoshi,
    required BigInt feeZatoshi,
    String? memo,
  }) async {
    final theme = Theme.of(context);
    final totalZatoshi = amountZatoshi + feeZatoshi;

    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Confirm Transaction'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'To',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${address.substring(0, 16)}...${address.substring(address.length - 8)}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(height: 16),
                _buildConfirmRow(
                  theme,
                  'Amount',
                  '${_formatZec(amountZatoshi)} ZEC',
                ),
                const SizedBox(height: 8),
                _buildConfirmRow(theme, 'Fee', '${_formatZec(feeZatoshi)} ZEC'),
                Divider(height: 24, color: theme.colorScheme.outlineVariant),
                _buildConfirmRow(
                  theme,
                  'Total',
                  '${_formatZec(totalZatoshi)} ZEC',
                  bold: true,
                ),
                if (memo != null && memo.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    'Memo',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(memo, style: theme.textTheme.bodySmall),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Confirm & Send'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Widget _buildConfirmRow(
    ThemeData theme,
    String label,
    String value, {
    bool bold = false,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        Text(
          value,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
          ),
        ),
      ],
    );
  }

  Future<bool> _showSaplingParamsDialog() async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Download Required'),
            content: const Text(
              'This transaction uses Sapling shielded notes, which require '
              'proving parameters (~50MB) to generate zero-knowledge proofs.\n\n'
              'This is a one-time download. Network data charges may apply.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Download'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _downloadAndVerify(
    String url,
    String destPath,
    String expectedSha1,
  ) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();
      if (response.statusCode != 200) {
        throw Exception(
          'Download failed: HTTP ${response.statusCode} for $url',
        );
      }
      final tempPath = '${destPath}_tmp';
      final file = File(tempPath);
      final sink = file.openWrite();
      await response.pipe(sink);

      // Verify SHA-1
      final bytes = await File(tempPath).readAsBytes();
      final digest = sha1.convert(bytes);
      if (digest.toString() != expectedSha1) {
        await File(tempPath).delete();
        throw Exception('SHA-1 mismatch: expected $expectedSha1, got $digest');
      }

      // Atomic rename
      await File(tempPath).rename(destPath);
      log('Send: downloaded and verified $destPath');
    } finally {
      client.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    final walletAsync = ref.watch(walletProvider);
    final accountAsync = ref.watch(accountProvider);
    final matchedLocation = GoRouterState.of(context).matchedLocation;
    final accountName = accountAsync.value?.activeAccount?.name ?? 'Username';
    final spendable = _getSpendableBalance();
    final colors = context.colors;

    final addressTone = switch (_addressType) {
      'unified' || 'sapling' => _SendFieldTone.brandPurple,
      'invalid' || 'error' => _SendFieldTone.destructive,
      _ => _SendFieldTone.neutral,
    };
    final addressMessage = switch (_addressType) {
      'unified' || 'sapling' => 'Shielded Address',
      'invalid' => 'Invalid address',
      'error' => 'Address validation failed',
      _ => null,
    };
    final addressMessageIcon = switch (_addressType) {
      'unified' || 'sapling' => AppIcon(
        AppIcons.shieldKeyhole,
        size: 16,
        color: colors.text.brandPurple,
      ),
      'invalid' || 'error' => AppIcon(
        AppIcons.warning,
        size: 16,
        color: colors.text.warning,
      ),
      _ => null,
    };

    return AppDesktopShell(
      sidebar: AppMainSidebar(
        accountName: accountName,
        matchedLocation: matchedLocation,
        onResetWallet: () => _resetWallet(context),
      ),
      pane: AppDesktopPane(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: SizedBox.expand(
          child: walletAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, _) => Center(
              child: Text(
                'Error: $err',
                style: AppTypography.bodyMedium.copyWith(
                  color: context.colors.text.warning,
                ),
              ),
            ),
            data: (_) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SendBackRow(
                  onTap: () {
                    if (context.canPop()) {
                      context.pop();
                    } else {
                      context.go('/home');
                    }
                  },
                ),
                const SizedBox(height: AppSpacing.sm),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return SingleChildScrollView(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: constraints.maxHeight,
                          ),
                          child: Center(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: AppSpacing.sm,
                              ),
                              child: SizedBox(
                                width: 352,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    _SendInputField(
                                      label: 'Send to',
                                      tone: addressTone,
                                      focusNode: _addressFocusNode,
                                      controller: _addressController,
                                      hintText: 'zCash Address',
                                      leading: AppIcon(
                                        AppIcons.users,
                                        size: 20,
                                        color:
                                            _addressController.text
                                                .trim()
                                                .isNotEmpty
                                            ? colors.icon.accent
                                            : colors.icon.regular,
                                      ),
                                      trailingLabel: _SendTrailingLabel(
                                        label: 'Contacts',
                                        icon: AppIcon(
                                          AppIcons.chevronForward,
                                          size: 16,
                                          color: colors.text.secondary,
                                        ),
                                      ),
                                      messageText: addressMessage,
                                      messageIcon: addressMessageIcon,
                                      onChanged: (_) {
                                        _validateAddress();
                                        _validateAmount();
                                      },
                                      keyboardType: TextInputType.text,
                                      trailing:
                                          _addressFocusNode.hasFocus &&
                                              _addressController.text
                                                  .trim()
                                                  .isNotEmpty
                                          ? _ClearFieldButton(
                                              onTap: () {
                                                _addressController.clear();
                                                setState(() {
                                                  _addressType = '';
                                                  _error = null;
                                                });
                                                _validateAmount();
                                              },
                                            )
                                          : null,
                                    ),
                                    const SizedBox(height: AppSpacing.xs),
                                    _SendInputField(
                                      label: 'Amount',
                                      tone: _showAmountError
                                          ? _SendFieldTone.destructive
                                          : _SendFieldTone.neutral,
                                      focusNode: _amountFocusNode,
                                      controller: _amountController,
                                      hintText: '0.00',
                                      leading: AppIcon(
                                        AppIcons.zcash,
                                        size: 20,
                                        color:
                                            _amountController.text
                                                .trim()
                                                .isNotEmpty
                                            ? colors.icon.accent
                                            : colors.icon.regular,
                                      ),
                                      trailingLabel: Text(
                                        'Max: ${_formatSpendableLabel(spendable)} ZEC',
                                        style: AppTypography.labelMedium
                                            .copyWith(
                                              color: colors.text.secondary,
                                            ),
                                      ),
                                      messageText: _showAmountError
                                          ? _amountError
                                          : null,
                                      messageIcon: _showAmountError
                                          ? AppIcon(
                                              AppIcons.warning,
                                              size: 16,
                                              color: colors.text.warning,
                                            )
                                          : null,
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                            decimal: true,
                                          ),
                                      inputFormatters: [
                                        FilteringTextInputFormatter.allow(
                                          RegExp(r'[\d.]'),
                                        ),
                                        _ZecAmountFormatter(),
                                      ],
                                      onChanged: (_) => _validateAmount(),
                                      trailing:
                                          _amountFocusNode.hasFocus &&
                                              _amountController.text
                                                  .trim()
                                                  .isNotEmpty
                                          ? _ClearFieldButton(
                                              onTap: () {
                                                _amountController.clear();
                                                setState(() {
                                                  _amountError = '';
                                                  _error = null;
                                                });
                                              },
                                            )
                                          : null,
                                    ),
                                    const SizedBox(height: AppSpacing.sm),
                                    if (!_messageExpanded &&
                                        _memoController.text.isEmpty) ...[
                                      AppDecorativeDivider(
                                        width: 256,
                                        middleWidth: 53.553,
                                        middleHeight: 14,
                                      ),
                                      const SizedBox(height: AppSpacing.sm),
                                      _SendAddMessageCard(
                                        enabled: _isShieldedAddress,
                                        onTap: _isShieldedAddress
                                            ? () {
                                                setState(() {
                                                  _messageExpanded = true;
                                                });
                                                _memoFocusNode.requestFocus();
                                              }
                                            : null,
                                      ),
                                    ] else ...[
                                      _SendInputField(
                                        label: 'Message',
                                        tone: _memoError != null
                                            ? _SendFieldTone.destructive
                                            : _SendFieldTone.neutral,
                                        focusNode: _memoFocusNode,
                                        controller: _memoController,
                                        hintText: 'Add a message',
                                        leading: AppIcon(
                                          AppIcons.scroll,
                                          size: 20,
                                          color: colors.icon.regular,
                                        ),
                                        trailingLabel: Text(
                                          '$_memoLength/512',
                                          style: AppTypography.labelMedium
                                              .copyWith(
                                                color: colors.text.secondary,
                                              ),
                                        ),
                                        messageText: _memoError,
                                        messageIcon: _memoError != null
                                            ? AppIcon(
                                                AppIcons.warning,
                                                size: 16,
                                                color: colors.text.warning,
                                              )
                                            : null,
                                        minLines: 6,
                                        maxLines: 6,
                                        scrollController: _memoScrollController,
                                        onChanged: (_) => setState(() {
                                          _error = null;
                                        }),
                                        trailing:
                                            _memoController.text
                                                .trim()
                                                .isNotEmpty
                                            ? _ClearFieldButton(
                                                onTap: () {
                                                  _memoController.clear();
                                                  setState(() {
                                                    _messageExpanded = false;
                                                    _error = null;
                                                  });
                                                },
                                              )
                                            : null,
                                      ),
                                    ],
                                    if (_error != null) ...[
                                      const SizedBox(height: AppSpacing.xs),
                                      _SendGlobalError(message: _error!),
                                    ],
                                    const SizedBox(height: AppSpacing.sm),
                                    SizedBox(
                                      width: 256,
                                      child: AppButton(
                                        onPressed: _canReview ? _send : null,
                                        variant: AppButtonVariant.primary,
                                        minWidth: 256,
                                        trailing: _isSending
                                            ? null
                                            : const AppIcon(
                                                AppIcons.chevronForward,
                                              ),
                                        child: _isSending
                                            ? const SizedBox(
                                                width: 18,
                                                height: 18,
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                    ),
                                              )
                                            : const Text('Review'),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum _SendFieldTone { neutral, destructive, brandPurple }

class _SendBackRow extends StatelessWidget {
  const _SendBackRow({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          height: 32,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIcon(
                AppIcons.chevronBackward,
                size: 16,
                color: colors.icon.accent,
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

class _SendTrailingLabel extends StatelessWidget {
  const _SendTrailingLabel({required this.label, this.icon});

  final String label;
  final Widget? icon;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: AppTypography.labelMedium.copyWith(
            color: colors.text.secondary,
          ),
        ),
        if (icon != null) ...[const SizedBox(width: AppSpacing.xxs), icon!],
      ],
    );
  }
}

class _ClearFieldButton extends StatelessWidget {
  const _ClearFieldButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: 20,
          height: 20,
          child: Center(
            child: AppIcon(AppIcons.cross, size: 20, color: colors.icon.accent),
          ),
        ),
      ),
    );
  }
}

class _SendInputField extends StatelessWidget {
  const _SendInputField({
    required this.label,
    required this.tone,
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    this.hintText,
    this.leading,
    this.trailing,
    this.trailingLabel,
    this.messageText,
    this.messageIcon,
    this.keyboardType,
    this.inputFormatters,
    this.minLines = 1,
    this.maxLines = 1,
    this.scrollController,
  });

  final String label;
  final _SendFieldTone tone;
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final String? hintText;
  final Widget? leading;
  final Widget? trailing;
  final Widget? trailingLabel;
  final String? messageText;
  final Widget? messageIcon;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final int minLines;
  final int maxLines;
  final ScrollController? scrollController;

  bool get _isMultiline => maxLines > 1 || minLines > 1;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final borderColor = switch (tone) {
      _SendFieldTone.neutral when focusNode.hasFocus => colors.border.strong,
      _SendFieldTone.neutral => colors.border.subtle,
      _SendFieldTone.destructive => colors.border.utilityDestructive,
      _SendFieldTone.brandPurple => colors.border.brandPurpleStrong,
    };
    final focusRingColor = switch (tone) {
      _SendFieldTone.neutral => colors.state.focusRing,
      _SendFieldTone.destructive => colors.border.utilityDestructive,
      _SendFieldTone.brandPurple => colors.border.brandPurpleStrong,
    };
    final messageColor = switch (tone) {
      _SendFieldTone.neutral => colors.text.secondary,
      _SendFieldTone.destructive => colors.text.warning,
      _SendFieldTone.brandPurple => colors.text.brandPurple,
    };
    final shellHeight = _isMultiline ? 148.0 : 46.0;

    final input = TextField(
      controller: controller,
      focusNode: focusNode,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      onChanged: onChanged,
      maxLines: _isMultiline ? null : 1,
      minLines: _isMultiline ? null : 1,
      expands: _isMultiline,
      scrollController: scrollController,
      textAlignVertical: _isMultiline
          ? TextAlignVertical.top
          : TextAlignVertical.center,
      style: _isMultiline
          ? AppTypography.bodyMedium.copyWith(color: colors.text.accent)
          : AppTypography.labelLarge.copyWith(color: colors.text.accent),
      cursorColor: colors.text.accent,
      decoration: InputDecoration.collapsed(
        hintText: hintText,
        hintStyle: AppTypography.labelLarge.copyWith(color: colors.text.muted),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: AppTypography.labelMedium.copyWith(
                  color: colors.text.secondary,
                ),
              ),
            ),
            if (trailingLabel != null) ...[trailingLabel!],
          ],
        ),
        const SizedBox(height: AppSpacing.xxs),
        SizedBox(
          height: shellHeight,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.background.base,
                    borderRadius: BorderRadius.circular(AppRadii.small),
                    border: Border.all(color: borderColor, width: 1.5),
                  ),
                ),
              ),
              if (focusNode.hasFocus)
                Positioned(
                  left: -2.5,
                  right: -2.5,
                  top: -2.5,
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
                child: Row(
                  crossAxisAlignment: _isMultiline
                      ? CrossAxisAlignment.start
                      : CrossAxisAlignment.center,
                  children: [
                    if (leading != null && !_isMultiline)
                      SizedBox(
                        width: 32,
                        height: shellHeight,
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: leading,
                          ),
                        ),
                      ),
                    if (leading != null && _isMultiline)
                      Padding(
                        padding: const EdgeInsets.only(left: AppSpacing.xs),
                        child: SizedBox(
                          width: 20,
                          height: 48,
                          child: Align(
                            alignment: Alignment.center,
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: leading,
                            ),
                          ),
                        ),
                      ),
                    Expanded(
                      child: Padding(
                        padding: _isMultiline
                            ? const EdgeInsets.fromLTRB(
                                AppSpacing.sm,
                                AppSpacing.sm,
                                AppSpacing.sm,
                                AppSpacing.sm,
                              )
                            : const EdgeInsets.symmetric(
                                horizontal: AppSpacing.sm,
                              ),
                        child: _isMultiline
                            ? ScrollbarTheme(
                                data: ScrollbarThemeData(
                                  thumbColor: WidgetStatePropertyAll(
                                    colors.background.overlay.withValues(
                                      alpha: 0.5,
                                    ),
                                  ),
                                  radius: const Radius.circular(AppRadii.full),
                                  thickness: const WidgetStatePropertyAll(6),
                                  thumbVisibility: const WidgetStatePropertyAll(
                                    true,
                                  ),
                                  trackVisibility: const WidgetStatePropertyAll(
                                    false,
                                  ),
                                ),
                                child: Scrollbar(
                                  controller: scrollController,
                                  child: input,
                                ),
                              )
                            : input,
                      ),
                    ),
                    if (!_isMultiline)
                      SizedBox(
                        width: 40,
                        height: shellHeight,
                        child: Center(child: trailing),
                      ),
                    if (_isMultiline)
                      SizedBox(
                        width: 40,
                        height: shellHeight,
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: Padding(
                            padding: const EdgeInsets.only(
                              top: 14,
                              left: 10,
                              right: 10,
                            ),
                            child: trailing,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xxs),
        SizedBox(
          height: 16,
          child: messageText == null
              ? const SizedBox.shrink()
              : Row(
                  children: [
                    if (messageIcon != null) ...[
                      messageIcon!,
                      const SizedBox(width: AppSpacing.xxs),
                    ],
                    Text(
                      messageText!,
                      style: AppTypography.labelMedium.copyWith(
                        color: messageColor,
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _SendAddMessageCard extends StatelessWidget {
  const _SendAddMessageCard({required this.enabled, this.onTap});

  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final card = Container(
      width: 352,
      height: 96,
      decoration: BoxDecoration(
        color: colors.background.base,
        borderRadius: BorderRadius.circular(AppRadii.medium),
      ),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIcon(
                AppIcons.scroll,
                size: 16,
                color: enabled ? colors.icon.accent : colors.icon.regular,
              ),
              const SizedBox(width: AppSpacing.xxs),
              Text(
                'Add a Message',
                style: AppTypography.labelMedium.copyWith(
                  color: enabled ? colors.text.accent : colors.text.secondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Encrypted, for Shielded Addresses only.',
            style: AppTypography.labelMedium.copyWith(color: colors.text.muted),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );

    if (onTap == null) return card;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: card,
      ),
    );
  }
}

class _SendGlobalError extends StatelessWidget {
  const _SendGlobalError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        AppIcon(AppIcons.warning, size: 16, color: context.colors.text.warning),
        const SizedBox(width: AppSpacing.xxs),
        Expanded(
          child: Text(
            message,
            style: AppTypography.labelMedium.copyWith(
              color: context.colors.text.warning,
            ),
          ),
        ),
      ],
    );
  }
}

/// Enforces: one decimal point max, up to 8 fractional digits.
class _ZecAmountFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text;

    // Allow empty
    if (text.isEmpty) return newValue;

    // Only one decimal point
    if ('.'.allMatches(text).length > 1) return oldValue;

    // Limit fractional digits to 8
    final dotIndex = text.indexOf('.');
    if (dotIndex != -1 && text.length - dotIndex - 1 > 8) return oldValue;

    return newValue;
  }
}
