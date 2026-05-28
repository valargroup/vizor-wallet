import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_back_link.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../providers/account_provider.dart';
import '../domain/near_intents_explorer.dart';
import '../models/swap_activity_navigation.dart';
import '../models/swap_activity_status_mapper.dart';
import '../models/swap_models.dart';
import '../providers/swap_state_provider.dart';
import 'swap_amount_text.dart';
import 'swap_asset_icon.dart';
import 'swap_copy_feedback.dart';
import 'swap_deposit_tokens_page_content.dart';
import 'swap_deposit_qr_panel.dart';
import 'swap_keystone_signing_overlay.dart';
import 'swap_near_intents_attribution.dart';
import 'swap_queue_panel.dart';
import 'swap_status_page_content.dart';

class SwapActivityDetailSurface extends ConsumerStatefulWidget {
  const SwapActivityDetailSurface({
    required this.intentId,
    this.returnTarget,
    this.autoSignZecDeposit = false,
    super.key,
  });

  final String intentId;
  final SwapActivityReturnTarget? returnTarget;
  final bool autoSignZecDeposit;

  @override
  ConsumerState<SwapActivityDetailSurface> createState() =>
      _SwapActivityDetailSurfaceState();
}

class _SwapKeystoneSigningRequest {
  const _SwapKeystoneSigningRequest({
    required this.intentId,
    required this.accountUuid,
    this.removeUnsentIntentOnCancel = false,
  });

  final String intentId;
  final String accountUuid;
  final bool removeUnsentIntentOnCancel;
}

class _SwapActivityDetailSurfaceState
    extends ConsumerState<SwapActivityDetailSurface> {
  final _toastOverlayContextKey = GlobalKey(
    debugLabel: 'swap_activity_toast_overlay_context',
  );
  _SwapKeystoneSigningRequest? _keystoneSigningRequest;
  String? _depositCheckWarningIntentId;
  String? _depositCheckingIntentId;
  var _initialIntentApplied = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _applyInitialIntent();
    });
  }

  @override
  void didUpdateWidget(covariant SwapActivityDetailSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.intentId != widget.intentId ||
        oldWidget.autoSignZecDeposit != widget.autoSignZecDeposit) {
      _initialIntentApplied = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _applyInitialIntent();
      });
    }
  }

  void _applyInitialIntent() {
    if (_initialIntentApplied) return;
    final intentId = widget.intentId.trim();
    if (intentId.isEmpty) {
      _initialIntentApplied = true;
      return;
    }
    final intent = _intentById(ref.read(swapStateProvider).intents, intentId);
    if (intent == null) return;
    ref.read(swapStateProvider.notifier).selectIntent(intentId);
    final needsAutoSign =
        widget.autoSignZecDeposit &&
        _isHardwareIntent(intent) &&
        intent.direction == SwapDirection.zecToExternal &&
        !(intent.depositTxHash?.trim().isNotEmpty ?? false);
    setState(() {
      _initialIntentApplied = true;
      if (needsAutoSign) {
        _keystoneSigningRequest = _SwapKeystoneSigningRequest(
          intentId: intent.id,
          accountUuid: intent.accountUuid ?? _activeAccountUuid ?? '',
          removeUnsentIntentOnCancel: true,
        );
      }
    });
  }

  String? get _activeAccountUuid =>
      ref.read(accountProvider).value?.activeAccountUuid;

  BuildContext _toastContext(BuildContext fallback) =>
      _toastOverlayContextKey.currentContext ?? fallback;

  bool _isHardwareIntent(SwapIntent intent) {
    final accountUuid = intent.accountUuid;
    if (accountUuid == null || accountUuid.trim().isEmpty) return false;
    final accountState = ref.read(accountProvider).value;
    final accountHardwareByUuid = {
      for (final account in accountState?.accounts ?? const <AccountInfo>[])
        account.uuid: account.isHardware,
    };
    return accountHardwareByUuid[accountUuid] ?? false;
  }

  void _refreshStatus() {
    unawaited(_refreshStatusForSelectedIntent());
  }

  Future<void> _refreshStatusForSelectedIntent() async {
    final selected = ref.read(swapStateProvider).selectedIntentOrNull;
    if (selected == null || !canRefreshSwapIntentStatus(selected.status)) {
      return;
    }
    if (mounted) {
      setState(() {
        _depositCheckingIntentId = selected.id;
        if (_depositCheckWarningIntentId == selected.id) {
          _depositCheckWarningIntentId = null;
        }
      });
    }
    await ref.read(swapStateProvider.notifier).refreshSelectedIntentStatus();
    if (!mounted) return;

    final state = ref.read(swapStateProvider);
    final refreshed = state.selectedIntentOrNull;
    final shouldWarn =
        swapActivityShowsExternalDepositPage(selected) &&
        refreshed != null &&
        refreshed.id == selected.id &&
        refreshed.status == SwapIntentStatus.awaitingExternalDeposit &&
        refreshed.statusError == null &&
        state.statusError == null;
    setState(() {
      _depositCheckingIntentId = null;
      _depositCheckWarningIntentId = shouldWarn ? selected.id : null;
    });
  }

  void _submitDepositTransaction() {
    unawaited(
      ref.read(swapStateProvider.notifier).submitSelectedDepositTransaction(),
    );
  }

  void _reviewFreshQuote() {
    ref.read(swapStateProvider.notifier).prepareRetryFromSelectedIntent();
    context.go('/swap');
  }

  void _openNearIntentsExplorerLink(SwapIntent intent) {
    unawaited(
      launchNearIntentsExplorer(
        nearIntentHash: intent.nearIntentHash,
        depositTxHash: intent.depositTxHash,
        depositAddress: intent.depositAddress ?? intent.id,
      ),
    );
  }

  void _signZecDeposit(SwapIntent intent) {
    setState(() {
      _keystoneSigningRequest = _SwapKeystoneSigningRequest(
        intentId: intent.id,
        accountUuid: intent.accountUuid ?? _activeAccountUuid ?? '',
      );
    });
  }

  void _closeKeystoneSigning({bool cleanupCancelledRequest = false}) {
    final request = _keystoneSigningRequest;
    setState(() => _keystoneSigningRequest = null);
    if (cleanupCancelledRequest &&
        request != null &&
        request.removeUnsentIntentOnCancel) {
      unawaited(
        ref
            .read(swapStateProvider.notifier)
            .removeUnsentHardwareDepositIntent(request.intentId),
      );
    }
  }

  void _handleKeystoneDepositBroadcast(
    BuildContext context,
    SwapKeystoneBroadcastResult result,
  ) {
    final request = _keystoneSigningRequest;
    if (request == null) return;
    _closeKeystoneSigning();
    unawaited(
      ref
          .read(swapStateProvider.notifier)
          .submitDepositTransactionForIntent(
            intentId: request.intentId,
            accountUuid: request.accountUuid,
            txHash: result.txHash,
            broadcastStatus: result.status,
            broadcastMessage: result.message,
          ),
    );
    showAppToast(
      _toastContext(context),
      result.isCertain ? 'ZEC deposit sent' : 'Checking ZEC deposit',
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<String?>(
      accountProvider.select((value) => value.value?.activeAccountUuid),
      (previous, next) {
        if (previous == next || !mounted) return;
        setState(() {
          _keystoneSigningRequest = null;
        });
        context.go('/activity');
      },
    );

    final state = ref.watch(swapStateProvider);
    final initialIntentId = widget.intentId.trim();
    if (!_initialIntentApplied && initialIntentId.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _applyInitialIntent();
      });
    }
    final activityDetailIntent = _intentById(state.intents, initialIntentId);
    final keystoneSigningRequest = _keystoneSigningRequest;
    final keystoneSigningIntent = _intentById(
      state.intents,
      keystoneSigningRequest?.intentId,
    );

    final Widget pageContent = activityDetailIntent == null
        ? const _SwapActivityMissingPanel()
        : SwapActivityDetailPagePanel(
            state: state,
            intent: activityDetailIntent,
            depositChecking:
                _depositCheckingIntentId == activityDetailIntent.id,
            depositCheckWarning:
                _depositCheckWarningIntentId == activityDetailIntent.id
                ? _depositConfirmationPendingMessage
                : null,
            onRefreshStatus: _refreshStatus,
            onDepositTxHashChanged: ref
                .read(swapStateProvider.notifier)
                .updateDepositTxHash,
            onSubmitDepositTransaction: _submitDepositTransaction,
            onReviewFreshQuote: _reviewFreshQuote,
            onSignZecDeposit: _signZecDeposit,
            onCopyExplorerLink: _openNearIntentsExplorerLink,
            intentIsHardware: _isHardwareIntent(activityDetailIntent),
          );

    return Stack(
      key: const ValueKey('swap_activity_detail_surface'),
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: _SwapActivityDetailPaneContent(
            returnTarget: widget.returnTarget,
            child: pageContent,
          ),
        ),
        if (keystoneSigningRequest != null && keystoneSigningIntent != null)
          Positioned.fill(
            child: SwapKeystoneSigningOverlay(
              intent: keystoneSigningIntent,
              onCancel: () =>
                  _closeKeystoneSigning(cleanupCancelledRequest: true),
              onDepositBroadcast: (result) =>
                  _handleKeystoneDepositBroadcast(context, result),
            ),
          ),
        Positioned.fill(
          child: IgnorePointer(
            child: AppToastHost(
              key: const ValueKey('swap_toast_overlay_host'),
              child: SizedBox.expand(key: _toastOverlayContextKey),
            ),
          ),
        ),
      ],
    );
  }
}

class _SwapActivityDetailPaneContent extends StatelessWidget {
  const _SwapActivityDetailPaneContent({
    required this.child,
    required this.returnTarget,
  });

  final Widget child;
  final SwapActivityReturnTarget? returnTarget;

  @override
  Widget build(BuildContext context) {
    final returnTarget = this.returnTarget;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (returnTarget != null) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: AppBackLink(
                label: returnTarget.label,
                minWidth: 60,
                onTap: () => context.go(returnTarget.path),
              ),
            ),
            const SizedBox(height: AppSpacing.s),
          ],
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Stack(
                  children: [
                    Positioned.fill(child: child),
                    if (constraints.maxHeight >= 520)
                      const Positioned(
                        left: 0,
                        bottom: AppSpacing.md,
                        child: SwapNearIntentsAttribution(),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

SwapIntent? _intentById(List<SwapIntent> intents, String? intentId) {
  if (intentId == null) return null;
  for (final intent in intents) {
    if (intent.id == intentId) return intent;
  }
  return null;
}

class SwapActivityPanel extends StatelessWidget {
  const SwapActivityPanel({
    required this.state,
    required this.onRefreshStatus,
    required this.onIntentSelected,
    super.key,
  });

  final SwapState state;
  final VoidCallback onRefreshStatus;
  final ValueChanged<String> onIntentSelected;

  @override
  Widget build(BuildContext context) {
    final selectedIntent = state.selectedIntentOrNull;
    final hasRefreshableIntents = state.intents.any(
      (intent) => canRefreshSwapIntentStatus(intent.status),
    );
    final queueRefreshAction = hasRefreshableIntents ? onRefreshStatus : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwapQueuePanel(
          intents: state.intents,
          selectedIntentId: selectedIntent?.id,
          onIntentSelected: onIntentSelected,
          statusRefreshing: state.statusRefreshing,
          onRefresh: queueRefreshAction,
        ),
        if (selectedIntent == null) ...[
          const SizedBox(height: AppSpacing.xs),
          const SwapActivityEmptyState(),
        ],
      ],
    );
  }
}

class SwapActivityDetailEntrance extends StatelessWidget {
  const SwapActivityDetailEntrance({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      key: const ValueKey('swap_activity_detail_entrance'),
      tween: Tween<double>(begin: 28, end: 0),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      child: child,
      builder: (context, dx, child) {
        final opacity = 1 - (dx.abs() / 28);
        return Opacity(
          opacity: opacity.clamp(0.0, 1.0).toDouble(),
          child: Transform.translate(offset: Offset(dx, 0), child: child),
        );
      },
    );
  }
}

class SwapActivityEmptyState extends StatelessWidget {
  const SwapActivityEmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      key: const ValueKey('swap_activity_empty_state'),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: colors.background.base,
        border: Border.all(color: colors.border.regular),
        borderRadius: BorderRadius.circular(AppRadii.xSmall),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppIcon(AppIcons.history, size: 20, color: colors.icon.brandCrimson),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'No swap activity yet',
                  style: AppTypography.labelLarge.copyWith(
                    color: colors.text.accent,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  'Review a live quote to create an activity record with deposit, delivery, and recovery details.',
                  style: AppTypography.bodySmall.copyWith(
                    color: colors.text.secondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SwapActivityStack extends StatelessWidget {
  const _SwapActivityStack({
    required this.state,
    required this.selectedIntent,
    required this.onDepositTxHashChanged,
    required this.onSubmitDepositTransaction,
    required this.onReviewFreshQuote,
    required this.onSignZecDeposit,
    required this.intentIsHardware,
  });

  final SwapState state;
  final SwapIntent selectedIntent;
  final ValueChanged<String> onDepositTxHashChanged;
  final VoidCallback onSubmitDepositTransaction;
  final VoidCallback onReviewFreshQuote;
  final ValueChanged<SwapIntent> onSignZecDeposit;
  final bool intentIsHardware;

  @override
  Widget build(BuildContext context) {
    final depositInstruction = SwapActivityDepositInstruction.fromIntent(
      selectedIntent,
    );
    final statusPlan = SwapActivityStatusPlan.fromIntent(selectedIntent);
    final resolution = SwapActivityResolution.fromIntent(selectedIntent);
    final showDepositControls = swapActivityShowDepositControls(
      selectedIntent.status,
    );
    final statusError = selectedIntent.statusError ?? state.statusError;
    final hasDepositTx =
        selectedIntent.depositTxHash?.trim().isNotEmpty ?? false;
    final showHardwareDepositAction =
        intentIsHardware &&
        selectedIntent.direction == SwapDirection.zecToExternal &&
        selectedIntent.status == SwapIntentStatus.awaitingDeposit &&
        !hasDepositTx;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ActiveSwapSummaryPanel(
          intent: selectedIntent,
          plan: statusPlan,
          statusRefreshing: state.statusRefreshing,
        ),
        if (statusError != null) ...[
          const SizedBox(height: AppSpacing.md),
          _ActivityStatusErrorPanel(message: statusError),
        ],
        if (showHardwareDepositAction) ...[
          const SizedBox(height: AppSpacing.md),
          _ActivityHardwareActionPanel(
            key: const ValueKey('swap_hardware_deposit_action_panel'),
            iconName: AppIcons.qr,
            title: 'Deposit ZEC',
            message:
                'Use Keystone to approve one ZEC transaction to the swap deposit address.',
            buttonKey: const ValueKey('swap_hardware_deposit_button'),
            buttonLabel: 'Deposit ZEC',
            onPressed: () => onSignZecDeposit(selectedIntent),
          ),
        ],
        if (resolution != null) ...[
          const SizedBox(height: AppSpacing.md),
          _ActivityResolutionPanel(
            resolution: resolution,
            intent: selectedIntent,
            onReviewFreshQuote: onReviewFreshQuote,
          ),
        ],
        if (showDepositControls &&
            depositInstruction != null &&
            !showHardwareDepositAction) ...[
          const SizedBox(height: AppSpacing.md),
          _ActivityDepositActionPanel(
            state: state,
            instruction: depositInstruction,
            onDepositTxHashChanged: onDepositTxHashChanged,
            onSubmitDepositTransaction: onSubmitDepositTransaction,
          ),
        ],
      ],
    );
  }
}

class SwapActivityDetailPagePanel extends StatelessWidget {
  const SwapActivityDetailPagePanel({
    required this.state,
    required this.intent,
    required this.depositChecking,
    required this.depositCheckWarning,
    required this.onRefreshStatus,
    required this.onDepositTxHashChanged,
    required this.onSubmitDepositTransaction,
    required this.onReviewFreshQuote,
    required this.onSignZecDeposit,
    required this.onCopyExplorerLink,
    required this.intentIsHardware,
    super.key,
  });

  final SwapState state;
  final SwapIntent intent;
  final bool depositChecking;
  final String? depositCheckWarning;
  final VoidCallback onRefreshStatus;
  final ValueChanged<String> onDepositTxHashChanged;
  final VoidCallback onSubmitDepositTransaction;
  final VoidCallback onReviewFreshQuote;
  final ValueChanged<SwapIntent> onSignZecDeposit;
  final ValueChanged<SwapIntent> onCopyExplorerLink;
  final bool intentIsHardware;

  @override
  Widget build(BuildContext context) {
    final flowContent = _SwapActivityFlowContent(
      state: state,
      intent: intent,
      depositChecking: depositChecking,
      depositCheckWarning: depositCheckWarning,
      onRefreshStatus: onRefreshStatus,
      onDepositTxHashChanged: onDepositTxHashChanged,
      onSubmitDepositTransaction: onSubmitDepositTransaction,
      onReviewFreshQuote: onReviewFreshQuote,
      onSignZecDeposit: onSignZecDeposit,
      onCopyExplorerLink: onCopyExplorerLink,
      intentIsHardware: intentIsHardware,
    );
    final isDepositPage = swapActivityShowsDepositPage(
      intent,
      intentIsHardware: intentIsHardware,
    );

    return Container(
      key: const ValueKey('swap_activity_detail_page'),
      padding: EdgeInsets.zero,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return _ActivityDetailScrollArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Align(
                alignment: isDepositPage
                    ? Alignment.center
                    : Alignment.topCenter,
                child: flowContent,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SwapActivityFlowContent extends StatelessWidget {
  const _SwapActivityFlowContent({
    required this.state,
    required this.intent,
    required this.depositChecking,
    required this.depositCheckWarning,
    required this.onRefreshStatus,
    required this.onDepositTxHashChanged,
    required this.onSubmitDepositTransaction,
    required this.onReviewFreshQuote,
    required this.onSignZecDeposit,
    required this.onCopyExplorerLink,
    required this.intentIsHardware,
  });

  final SwapState state;
  final SwapIntent intent;
  final bool depositChecking;
  final String? depositCheckWarning;
  final VoidCallback onRefreshStatus;
  final ValueChanged<String> onDepositTxHashChanged;
  final VoidCallback onSubmitDepositTransaction;
  final VoidCallback onReviewFreshQuote;
  final ValueChanged<SwapIntent> onSignZecDeposit;
  final ValueChanged<SwapIntent> onCopyExplorerLink;
  final bool intentIsHardware;

  @override
  Widget build(BuildContext context) {
    final depositInstruction = SwapActivityDepositInstruction.fromIntent(
      intent,
    );
    final statusError = intent.statusError ?? state.statusError;
    final showExternalDepositPage = swapActivityShowsExternalDepositPage(
      intent,
    );
    final showHardwareDepositPage = swapActivityShowsHardwareZecDepositPage(
      intent,
      intentIsHardware: intentIsHardware,
    );
    final primaryContent = switch (intent.status) {
      SwapIntentStatus.expired => SwapDepositTimeoutPageContent(
        onRestart: onReviewFreshQuote,
      ),
      _ when showExternalDepositPage && depositInstruction != null =>
        SwapDepositTokensPageContent(
          asset: swapActivitySellAsset(intent) ?? SwapAsset.zec,
          amountText: intent.sellAmount,
          depositAddress: depositInstruction.address,
          expiresInLabel: swapDepositDeadlineLabel(intent) ?? '2hrs',
          expiresAt: intent.depositDeadline,
          memo: depositInstruction.memo,
          checking: depositChecking || state.statusRefreshing,
          checkWarning: depositCheckWarning,
          onDeposited: onRefreshStatus,
        ),
      _ when showHardwareDepositPage && depositInstruction != null =>
        SwapHardwareZecDepositPageContent(
          asset: swapActivitySellAsset(intent) ?? SwapAsset.zec,
          amountText: intent.sellAmount,
          depositAddress: depositInstruction.address,
          expiresInLabel: swapDepositDeadlineLabel(intent) ?? '2hrs',
          expiresAt: intent.depositDeadline,
          memo: depositInstruction.memo,
          onDepositZec: () => onSignZecDeposit(intent),
        ),
      _ => _SwapStatusForIntent(
        intent: intent,
        onOpenExplorer: () => onCopyExplorerLink(intent),
      ),
    };

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        primaryContent,
        if (statusError != null) ...[
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            width: 400,
            child: _ActivityStatusErrorPanel(message: statusError),
          ),
        ],
      ],
    );
  }
}

class _SwapStatusForIntent extends ConsumerStatefulWidget {
  const _SwapStatusForIntent({
    required this.intent,
    required this.onOpenExplorer,
  });

  final SwapIntent intent;
  final VoidCallback onOpenExplorer;

  @override
  ConsumerState<_SwapStatusForIntent> createState() =>
      _SwapStatusForIntentState();
}

class _SwapStatusForIntentState extends ConsumerState<_SwapStatusForIntent> {
  SwapStatusTab _activeTab = SwapStatusTab.progress;
  bool _detailsExpanded = false;

  @override
  void didUpdateWidget(covariant _SwapStatusForIntent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.intent.id != widget.intent.id) {
      _activeTab = SwapStatusTab.progress;
      _detailsExpanded = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final intent = widget.intent;
    final state = ref.watch(swapStateProvider);
    final accountInfo = _accountInfoForIntent(
      ref.watch(accountProvider).value,
      intent,
    );
    final presentation = swapActivityStatusPresentationForIntent(
      state,
      intent,
      accountDetail: accountInfo == null
          ? null
          : SwapActivityAccountDetail(
              name: accountInfo.name,
              profilePictureId: accountInfo.profilePictureId,
            ),
    );
    return SwapStatusPageContent(
      title: presentation.title,
      payAsset: presentation.payAsset,
      receiveAsset: presentation.receiveAsset,
      payFiatText: presentation.payFiatText,
      receiveFiatText: presentation.receiveFiatText,
      payAmountText: presentation.payAmountText,
      receiveAmountText: presentation.receiveAmountText,
      badgeKind: presentation.badgeKind,
      progressIndex: presentation.progressIndex,
      activeTab: _activeTab,
      steps: presentation.steps,
      details: presentation.details,
      detailsExpanded: _detailsExpanded,
      showTabs: presentation.showTabs,
      onTabChanged: (tab) {
        setState(() {
          _activeTab = tab;
        });
      },
      onToggleDetails: () {
        setState(() {
          _detailsExpanded = !_detailsExpanded;
        });
      },
      onOpenExplorer: widget.onOpenExplorer,
    );
  }
}

AccountInfo? _accountInfoForIntent(
  AccountState? accountState,
  SwapIntent intent,
) {
  if (accountState == null) return null;
  final accountUuid = intent.accountUuid?.trim();
  if (accountUuid != null && accountUuid.isNotEmpty) {
    for (final account in accountState.accounts) {
      if (account.uuid == accountUuid) return account;
    }
  }
  return accountState.activeAccount;
}

class _SwapActivityMissingPanel extends StatelessWidget {
  const _SwapActivityMissingPanel();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      key: const ValueKey('swap_activity_detail_missing'),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Couldn't load this swap. Try again or pull to refresh.",
            style: AppTypography.headlineSmall.copyWith(
              color: colors.text.accent,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Return to Activity and select a saved swap.',
            style: AppTypography.bodyMedium.copyWith(
              color: colors.text.secondary,
            ),
          ),
        ],
      ),
    );
  }
}

class SwapActivityDetailModal extends StatelessWidget {
  const SwapActivityDetailModal({
    required this.state,
    required this.intent,
    required this.onClose,
    required this.onRefreshStatus,
    required this.onDepositTxHashChanged,
    required this.onSubmitDepositTransaction,
    required this.onReviewFreshQuote,
    required this.onSignZecDeposit,
    required this.onCopyExplorerLink,
    required this.intentIsHardware,
    super.key,
  });

  final SwapState state;
  final SwapIntent intent;
  final VoidCallback onClose;
  final VoidCallback onRefreshStatus;
  final ValueChanged<String> onDepositTxHashChanged;
  final VoidCallback onSubmitDepositTransaction;
  final VoidCallback onReviewFreshQuote;
  final ValueChanged<SwapIntent> onSignZecDeposit;
  final ValueChanged<SwapIntent> onCopyExplorerLink;
  final bool intentIsHardware;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : MediaQuery.sizeOf(context).height;
        return ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: SizedBox(
            height: height,
            child: Container(
              key: const ValueKey('swap_activity_detail_modal'),
              margin: const EdgeInsets.all(AppSpacing.xs),
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: colors.background.base,
                border: Border.all(color: colors.border.regular),
                borderRadius: BorderRadius.circular(AppRadii.small),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _ActivityAssetPair(intent: intent),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Swap progress',
                              key: const ValueKey('swap_activity_detail_title'),
                              style: AppTypography.headlineSmall.copyWith(
                                color: colors.text.accent,
                                fontSize: 24,
                                height: 30 / 24,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              intent.pair,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.labelLarge.copyWith(
                                color: colors.text.secondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      AppButton(
                        key: const ValueKey(
                          'swap_activity_detail_close_button',
                        ),
                        onPressed: onClose,
                        variant: AppButtonVariant.secondary,
                        size: AppButtonSize.large,
                        minWidth: 132,
                        leading: const AppIcon(AppIcons.cross, size: 20),
                        child: const Text('Close'),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Expanded(
                    child: _ActivityDetailScrollArea(
                      child: _SwapActivityStack(
                        state: state,
                        selectedIntent: intent,
                        onDepositTxHashChanged: onDepositTxHashChanged,
                        onSubmitDepositTransaction: onSubmitDepositTransaction,
                        onReviewFreshQuote: onReviewFreshQuote,
                        onSignZecDeposit: onSignZecDeposit,
                        intentIsHardware: intentIsHardware,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ActivityDetailScrollArea extends StatefulWidget {
  const _ActivityDetailScrollArea({required this.child});

  final Widget child;

  @override
  State<_ActivityDetailScrollArea> createState() =>
      _ActivityDetailScrollAreaState();
}

class _ActivityDetailScrollAreaState extends State<_ActivityDetailScrollArea> {
  late final ScrollController _controller;
  bool _hasScrollableExtent = false;

  @override
  void initState() {
    super.initState();
    _controller = ScrollController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool _handleScrollMetrics(ScrollMetricsNotification notification) {
    final hasScrollableExtent = notification.metrics.maxScrollExtent > 0.5;
    if (hasScrollableExtent != _hasScrollableExtent) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _hasScrollableExtent = hasScrollableExtent;
        });
      });
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: NotificationListener<ScrollMetricsNotification>(
        onNotification: _handleScrollMetrics,
        child: RawScrollbar(
          key: const ValueKey('swap_activity_detail_scrollbar'),
          controller: _controller,
          thumbVisibility: _hasScrollableExtent,
          interactive: _hasScrollableExtent,
          thickness: 4,
          radius: const Radius.circular(AppRadii.full),
          thumbColor: colors.border.regular.withValues(alpha: 0.72),
          mainAxisMargin: AppSpacing.xxs,
          crossAxisMargin: AppSpacing.xxs,
          child: SingleChildScrollView(
            key: const ValueKey('swap_activity_detail_scroll_view'),
            controller: _controller,
            child: Padding(
              key: const ValueKey('swap_activity_detail_scroll_gutter'),
              padding: EdgeInsets.only(
                right: _hasScrollableExtent ? AppSpacing.s : 0,
              ),
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}

class _ActivityAssetPair extends StatelessWidget {
  const _ActivityAssetPair({required this.intent});

  final SwapIntent intent;

  @override
  Widget build(BuildContext context) {
    final sellAsset = swapActivitySellAsset(intent);
    final receiveAsset = swapActivityReceiveAsset(intent);
    if (sellAsset == null || receiveAsset == null) {
      return const SizedBox.shrink();
    }

    return SizedBox(
      key: const ValueKey('swap_activity_detail_asset_pair'),
      width: 80,
      height: 48,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            top: 4,
            child: SwapAssetIcon(asset: sellAsset, selected: true, size: 38),
          ),
          Positioned(
            left: 36,
            top: 4,
            child: Container(
              padding: const EdgeInsets.all(1),
              decoration: BoxDecoration(
                color: context.colors.background.base,
                border: Border.all(color: context.colors.border.regular),
                borderRadius: BorderRadius.circular(AppRadii.full),
              ),
              child: SwapAssetIcon(
                asset: receiveAsset,
                selected: true,
                size: 38,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActivityStatusErrorPanel extends StatelessWidget {
  const _ActivityStatusErrorPanel({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xs),
      decoration: BoxDecoration(
        color: colors.text.destructive.withValues(alpha: 0.08),
        border: Border.all(
          color: colors.text.destructive.withValues(alpha: 0.26),
        ),
        borderRadius: BorderRadius.circular(AppRadii.xSmall),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppIcon(AppIcons.warning, size: 16, color: colors.icon.destructive),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              message,
              style: AppTypography.bodySmall.copyWith(
                color: colors.text.destructive,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActivityStatusPlanPanel extends StatelessWidget {
  const _ActivityStatusPlanPanel({
    required this.intent,
    required this.plan,
    required this.statusRefreshing,
  });

  final SwapIntent intent;
  final SwapActivityStatusPlan plan;
  final bool statusRefreshing;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final color = switch (plan.tone) {
      SwapActivityStatusPlanTone.action => colors.text.accent,
      SwapActivityStatusPlanTone.warning => colors.text.warning,
      SwapActivityStatusPlanTone.success => colors.text.success,
      SwapActivityStatusPlanTone.destructive => colors.text.destructive,
    };
    final iconColor = switch (plan.tone) {
      SwapActivityStatusPlanTone.action => colors.icon.accent,
      SwapActivityStatusPlanTone.warning => colors.icon.warning,
      SwapActivityStatusPlanTone.success => colors.icon.success,
      SwapActivityStatusPlanTone.destructive => colors.icon.destructive,
    };
    final live = _shouldAutoRefreshActivityStatus(intent.status);
    return Column(
      key: const ValueKey('swap_activity_status_plan'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 48,
              height: 48,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.08),
                      border: Border.all(color: color.withValues(alpha: 0.22)),
                      borderRadius: BorderRadius.circular(AppRadii.small),
                    ),
                    child: AppIcon(plan.iconName, size: 20, color: iconColor),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.s),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Text(
                          plan.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.headlineSmall.copyWith(
                            color: color,
                            fontSize: 18,
                            height: 23 / 18,
                          ),
                        ),
                      ),
                      if (live) ...[
                        const SizedBox(width: AppSpacing.xs),
                        _ActivityLiveBadge(
                          checking: statusRefreshing,
                          color: color,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    plan.detail,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.bodyExtraSmall.copyWith(
                      color: colors.text.secondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.s),
        _ActivityRouteTracker(intent: intent, tone: plan.tone),
      ],
    );
  }
}

class _ActivityRouteTracker extends StatefulWidget {
  const _ActivityRouteTracker({required this.intent, required this.tone});

  final SwapIntent intent;
  final SwapActivityStatusPlanTone tone;

  @override
  State<_ActivityRouteTracker> createState() => _ActivityRouteTrackerState();
}

class _ActivityRouteTrackerState extends State<_ActivityRouteTracker> {
  Timer? _timer;
  Timer? _advanceTimer;
  var _pulse = 0;
  late int _displayProgressIndex;
  late String _displayIntentId;

  @override
  void initState() {
    super.initState();
    final plan = SwapActivityRoutePlan.fromIntent(widget.intent);
    _displayProgressIndex = plan.progressIndex;
    _displayIntentId = widget.intent.id;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncPulseTimer();
    _syncDisplayProgress();
  }

  @override
  void didUpdateWidget(covariant _ActivityRouteTracker oldWidget) {
    super.didUpdateWidget(oldWidget);
    final changedIntent = _displayIntentId != widget.intent.id;
    if (changedIntent) {
      final plan = SwapActivityRoutePlan.fromIntent(widget.intent);
      _displayProgressIndex = plan.progressIndex;
      _displayIntentId = widget.intent.id;
    }
    _syncPulseTimer();
    if (!changedIntent) {
      _syncDisplayProgress();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _advanceTimer?.cancel();
    super.dispose();
  }

  void _syncPulseTimer() {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final plan = SwapActivityRoutePlan.fromIntent(widget.intent);
    final shouldPulse = !reduceMotion && plan.hasActiveStep;
    if (shouldPulse && _timer == null) {
      _timer = Timer.periodic(_activityStepBlinkTempo, (_) => _triggerPulse());
      return;
    }
    if (!shouldPulse && _timer != null) {
      _timer?.cancel();
      _timer = null;
    }
  }

  void _triggerPulse() {
    if (!mounted) return;
    setState(() => _pulse += 1);
  }

  void _syncDisplayProgress() {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final targetPlan = SwapActivityRoutePlan.fromIntent(widget.intent);
    final targetIndex = targetPlan.progressIndex;
    if (reduceMotion ||
        !targetPlan.canAnimateProgress ||
        targetIndex <= _displayProgressIndex) {
      _advanceTimer?.cancel();
      _advanceTimer = null;
      if (_displayProgressIndex != targetIndex) {
        setState(() => _displayProgressIndex = targetIndex);
      }
      return;
    }

    if (targetIndex == _displayProgressIndex + 1) {
      _advanceTimer?.cancel();
      _advanceTimer = null;
      setState(() => _displayProgressIndex = targetIndex);
      return;
    }

    _advanceDisplayProgress();
    _advanceTimer ??= Timer.periodic(
      _activityRouteAdvanceTempo,
      (_) => _advanceDisplayProgress(),
    );
  }

  void _advanceDisplayProgress() {
    if (!mounted) return;
    final targetPlan = SwapActivityRoutePlan.fromIntent(widget.intent);
    final targetIndex = targetPlan.progressIndex;
    if (!targetPlan.canAnimateProgress ||
        targetIndex <= _displayProgressIndex) {
      _advanceTimer?.cancel();
      _advanceTimer = null;
      if (_displayProgressIndex != targetIndex) {
        setState(() => _displayProgressIndex = targetIndex);
      }
      return;
    }

    final nextIndex = _displayProgressIndex + 1;
    setState(() => _displayProgressIndex = nextIndex);
    if (nextIndex >= targetIndex) {
      _advanceTimer?.cancel();
      _advanceTimer = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final plan = SwapActivityRoutePlan.fromIntent(widget.intent);
    final displayPlan = plan.displayedAtProgress(_displayProgressIndex);
    return Semantics(
      label: 'Swap progress: ${displayPlan.semanticLabel}',
      child: Padding(
        key: const ValueKey('swap_activity_route_tracker'),
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ActivityRouteSegmentStrip(
              plan: displayPlan,
              tone: widget.tone,
              pulse: _pulse,
            ),
            const SizedBox(height: AppSpacing.s),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var index = 0; index < plan.steps.length; index++)
                  Expanded(
                    child: _ActivityRouteStepView(
                      key: ValueKey(
                        'swap_activity_route_step_${index}_${displayPlan.steps[index].state.name}',
                      ),
                      step: displayPlan.steps[index],
                      tone: widget.tone,
                      pulse: _pulse,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ActivityRouteSegmentStrip extends StatelessWidget {
  const _ActivityRouteSegmentStrip({
    required this.plan,
    required this.tone,
    required this.pulse,
  });

  final SwapActivityRoutePlan plan;
  final SwapActivityStatusPlanTone tone;
  final int pulse;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var index = 0; index < plan.steps.length; index++) ...[
          Expanded(
            child: _ActivityRouteSegment(
              index: index,
              state: plan.steps[index].state,
              tone: tone,
              pulse: pulse,
            ),
          ),
          if (index != plan.steps.length - 1)
            const SizedBox(width: AppSpacing.xxs),
        ],
      ],
    );
  }
}

class _ActivityRouteSegment extends StatelessWidget {
  const _ActivityRouteSegment({
    required this.index,
    required this.state,
    required this.tone,
    required this.pulse,
  });

  final int index;
  final SwapActivityRouteStepState state;
  final SwapActivityStatusPlanTone tone;
  final int pulse;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final segment = AnimatedContainer(
      key: ValueKey('swap_activity_route_segment_${index}_${state.name}'),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      height: state == SwapActivityRouteStepState.active ? 7 : 5,
      decoration: BoxDecoration(
        color: _activityRouteSegmentColor(context, state, tone),
        borderRadius: BorderRadius.circular(AppRadii.full),
        border: Border.all(
          color: state == SwapActivityRouteStepState.pending
              ? colors.border.subtle
              : _activityRouteColor(
                  context,
                  state,
                  tone,
                ).withValues(alpha: 0.28),
        ),
      ),
    );
    if (state != SwapActivityRouteStepState.active) return segment;
    return _ActivityStepBlinkOpacity(
      key: ValueKey('swap_activity_route_segment_blink_$index'),
      pulse: pulse,
      minOpacity: 0.62,
      maxOpacity: 1,
      child: segment,
    );
  }
}

class _ActivityStepBlinkOpacity extends StatelessWidget {
  const _ActivityStepBlinkOpacity({
    required this.child,
    required this.pulse,
    this.minOpacity = 0.08,
    this.maxOpacity = 0.32,
    super.key,
  });

  final Widget child;
  final int pulse;
  final double minOpacity;
  final double maxOpacity;

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) return child;
    return TweenAnimationBuilder<double>(
      key: ValueKey(pulse),
      tween: Tween<double>(begin: 0, end: 1),
      duration: _activityStepBlinkDuration,
      curve: Curves.easeInOutCubic,
      builder: (context, value, child) {
        final pulse = math.sin(value * math.pi);
        final opacity = minOpacity + ((maxOpacity - minOpacity) * pulse);
        return Opacity(opacity: opacity, child: child);
      },
      child: child,
    );
  }
}

class _ActivityRouteStepView extends StatelessWidget {
  const _ActivityRouteStepView({
    required this.step,
    required this.tone,
    required this.pulse,
    super.key,
  });

  final SwapActivityRouteStep step;
  final SwapActivityStatusPlanTone tone;
  final int pulse;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final color = _activityRouteColor(context, step.state, tone);
    final pending = step.state == SwapActivityRouteStepState.pending;
    final active = step.state == SwapActivityRouteStepState.active;
    final iconName = switch (step.state) {
      SwapActivityRouteStepState.done => AppIcons.check,
      SwapActivityRouteStepState.warning => AppIcons.warning,
      SwapActivityRouteStepState.failed => AppIcons.block,
      _ => step.iconName,
    };
    return Column(
      children: [
        SizedBox(
          width: 32,
          height: 32,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (active) _ActivityActiveStepHalo(color: color, pulse: pulse),
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: pending
                      ? colors.background.base
                      : color.withValues(alpha: 0.1),
                  border: Border.all(
                    color: pending
                        ? colors.border.subtle
                        : color.withValues(alpha: 0.34),
                  ),
                  borderRadius: BorderRadius.circular(AppRadii.full),
                ),
                child: AppIcon(
                  iconName,
                  size: 14,
                  color: pending ? colors.icon.muted : color,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          step.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: AppTypography.labelSmall.copyWith(
            color: pending ? colors.text.secondary : color,
          ),
        ),
      ],
    );
  }
}

class _ActivityLiveBadge extends StatelessWidget {
  const _ActivityLiveBadge({required this.checking, required this.color});

  final bool checking;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      key: const ValueKey('swap_activity_live_badge'),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        border: Border.all(color: color.withValues(alpha: 0.22)),
        borderRadius: BorderRadius.circular(AppRadii.full),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _LiveDot(color: color),
          const SizedBox(width: AppSpacing.xxs),
          Text(
            checking ? 'Checking' : 'Live',
            style: AppTypography.labelSmall.copyWith(
              color: checking ? color : colors.text.secondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _LiveDot extends StatelessWidget {
  const _LiveDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) {
      return Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(AppRadii.full),
        ),
      );
    }
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.48, end: 1),
      duration: const Duration(milliseconds: 620),
      curve: Curves.easeOutCubic,
      builder: (context, opacity, child) {
        return Opacity(opacity: opacity, child: child);
      },
      child: Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(AppRadii.full),
        ),
      ),
    );
  }
}

const _activityStepBlinkTempo = Duration(milliseconds: 2200);
const _activityStepBlinkDuration = Duration(milliseconds: 1000);
const _activityRouteAdvanceTempo = Duration(milliseconds: 420);

class _ActivityActiveStepHalo extends StatelessWidget {
  const _ActivityActiveStepHalo({required this.color, required this.pulse});

  final Color color;
  final int pulse;

  @override
  Widget build(BuildContext context) {
    const size = 32.0;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(AppRadii.full),
        ),
      );
    }
    return KeyedSubtree(
      key: const ValueKey('swap_activity_active_step_halo'),
      child: TweenAnimationBuilder<double>(
        key: ValueKey(pulse),
        tween: Tween<double>(begin: 0, end: 1),
        duration: _activityStepBlinkDuration,
        curve: Curves.easeInOutCubic,
        builder: (context, value, child) {
          final pulse = math.sin(value * math.pi);
          return Transform.scale(
            key: const ValueKey('swap_activity_active_step_blink_scale'),
            scale: 0.96 + (pulse * 0.1),
            child: Opacity(
              key: const ValueKey('swap_activity_active_step_blink_opacity'),
              opacity: 0.08 + (pulse * 0.24),
              child: child,
            ),
          );
        },
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(AppRadii.full),
          ),
        ),
      ),
    );
  }
}

bool _shouldAutoRefreshActivityStatus(SwapIntentStatus status) {
  return switch (status) {
    SwapIntentStatus.awaitingDeposit ||
    SwapIntentStatus.awaitingExternalDeposit ||
    SwapIntentStatus.depositObserved ||
    SwapIntentStatus.processing ||
    SwapIntentStatus.providerStatusUnknown => true,
    _ => false,
  };
}

Color _activityRouteSegmentColor(
  BuildContext context,
  SwapActivityRouteStepState state,
  SwapActivityStatusPlanTone tone,
) {
  final colors = context.colors;
  return switch (state) {
    SwapActivityRouteStepState.done => colors.text.success,
    SwapActivityRouteStepState.active ||
    SwapActivityRouteStepState.warning ||
    SwapActivityRouteStepState.failed => _activityRouteColor(
      context,
      state,
      tone,
    ).withValues(alpha: 0.72),
    SwapActivityRouteStepState.pending => colors.background.base,
  };
}

Color _activityRouteColor(
  BuildContext context,
  SwapActivityRouteStepState state,
  SwapActivityStatusPlanTone tone,
) {
  final colors = context.colors;
  return switch (state) {
    SwapActivityRouteStepState.done => colors.text.success,
    SwapActivityRouteStepState.warning => colors.text.warning,
    SwapActivityRouteStepState.failed => colors.text.destructive,
    SwapActivityRouteStepState.active => switch (tone) {
      SwapActivityStatusPlanTone.warning => colors.text.warning,
      SwapActivityStatusPlanTone.destructive => colors.text.destructive,
      _ => colors.text.accent,
    },
    SwapActivityRouteStepState.pending => colors.text.secondary,
  };
}

class _ActivityResolutionPanel extends StatelessWidget {
  const _ActivityResolutionPanel({
    required this.resolution,
    required this.intent,
    required this.onReviewFreshQuote,
  });

  final SwapActivityResolution resolution;
  final SwapIntent intent;
  final VoidCallback onReviewFreshQuote;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final color = switch (resolution.tone) {
      SwapActivityResolutionTone.warning => colors.text.warning,
      SwapActivityResolutionTone.success => colors.text.success,
      SwapActivityResolutionTone.destructive => colors.text.destructive,
    };
    final iconColor = switch (resolution.tone) {
      SwapActivityResolutionTone.warning => colors.icon.warning,
      SwapActivityResolutionTone.success => colors.icon.success,
      SwapActivityResolutionTone.destructive => colors.icon.destructive,
    };
    final action = resolution.primaryAction;
    final actionLabel = switch (action) {
      SwapActivityResolutionAction.copyTopUpDetails => 'Copy top-up details',
      SwapActivityResolutionAction.reviewFreshQuote => 'Review fresh quote',
      null => null,
    };
    final actionIcon = switch (action) {
      SwapActivityResolutionAction.copyTopUpDetails => AppIcons.copy,
      SwapActivityResolutionAction.reviewFreshQuote => AppIcons.renew,
      null => null,
    };
    final actionKey = switch (action) {
      SwapActivityResolutionAction.copyTopUpDetails => const ValueKey(
        'swap_resolution_copy_deposit_button',
      ),
      SwapActivityResolutionAction.reviewFreshQuote => const ValueKey(
        'swap_resolution_review_again_button',
      ),
      null => null,
    };
    final depositAddress = intent.depositAddress;
    final actionEnabled =
        action == SwapActivityResolutionAction.reviewFreshQuote ||
        (action == SwapActivityResolutionAction.copyTopUpDetails &&
            depositAddress != null &&
            depositAddress.isNotEmpty);
    return Container(
      key: const ValueKey('swap_resolution_panel'),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppRadii.xSmall),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppIcon(resolution.iconName, size: 18, color: iconColor),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  resolution.title,
                  style: AppTypography.labelLarge.copyWith(color: color),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  resolution.message,
                  style: AppTypography.bodySmall.copyWith(
                    color: colors.text.primary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  resolution.detail,
                  style: AppTypography.bodyExtraSmall.copyWith(
                    color: colors.text.secondary,
                  ),
                ),
                if (actionLabel != null && actionIcon != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: AppButton(
                      key: actionKey,
                      onPressed: actionEnabled
                          ? () {
                              if (action ==
                                      SwapActivityResolutionAction
                                          .copyTopUpDetails &&
                                  depositAddress != null) {
                                copySwapText(
                                  context,
                                  text: _topUpDetailsText(intent),
                                  toastMessage: 'Top-up Details Copied',
                                );
                                return;
                              }
                              if (action ==
                                  SwapActivityResolutionAction
                                      .reviewFreshQuote) {
                                onReviewFreshQuote();
                              }
                            }
                          : null,
                      variant: AppButtonVariant.secondary,
                      size: AppButtonSize.medium,
                      leading: AppIcon(actionIcon),
                      child: Text(actionLabel),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _topUpDetailsText(SwapIntent intent) {
    final lines = [
      if (intent.depositAddress != null)
        'Deposit address: ${intent.depositAddress}',
      if (intent.depositMemo != null) 'Deposit memo: ${intent.depositMemo}',
    ];
    return lines.join('\n');
  }
}

const _depositConfirmationPendingMessage =
    'Deposit confirmation not found yet.\nCheck again in a few minutes.';

class _ActiveSwapSummaryPanel extends StatelessWidget {
  const _ActiveSwapSummaryPanel({
    required this.intent,
    required this.plan,
    required this.statusRefreshing,
  });

  final SwapIntent intent;
  final SwapActivityStatusPlan plan;
  final bool statusRefreshing;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('swap_active_summary_panel'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ActivityStatusPlanPanel(
          intent: intent,
          plan: plan,
          statusRefreshing: statusRefreshing,
        ),
        const SizedBox(height: AppSpacing.md),
        const _ActivityDetailDivider(),
        const SizedBox(height: AppSpacing.md),
        _ActiveSwapTradeLine(intent: intent),
      ],
    );
  }
}

class _ActivityDetailDivider extends StatelessWidget {
  const _ActivityDetailDivider();

  @override
  Widget build(BuildContext context) {
    return Container(height: 1, color: context.colors.border.subtle);
  }
}

class _ActiveSwapTradeLine extends StatelessWidget {
  const _ActiveSwapTradeLine({required this.intent});

  final SwapIntent intent;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final recipient = _externalRecipientSummary(intent);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: _ActiveTradeAmount(
                  label: 'You send',
                  value: intent.sellAmount,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                child: AppIcon(
                  AppIcons.arrowForwardIos,
                  size: 14,
                  color: colors.icon.muted,
                ),
              ),
              Expanded(
                child: _ActiveTradeAmount(
                  label: 'You receive',
                  value: intent.receiveEstimate,
                  alignEnd: true,
                ),
              ),
            ],
          ),
          if (recipient != null) ...[
            const SizedBox(height: AppSpacing.xs),
            _ExternalRecipientLine(recipient: recipient),
          ],
        ],
      ),
    );
  }
}

class _ExternalRecipientSummary {
  const _ExternalRecipientSummary({required this.label, required this.value});

  final String label;
  final String value;
}

_ExternalRecipientSummary? _externalRecipientSummary(SwapIntent intent) {
  if (intent.direction != SwapDirection.zecToExternal) return null;
  final recipient = intent.oneClickRecipient?.trim();
  if (recipient == null || recipient.isEmpty) return null;
  final symbol =
      intent.externalAsset?.symbol ?? swapActivityPairSymbol(intent.pair, 1);
  return _ExternalRecipientSummary(
    label: '$symbol recipient',
    value: recipient,
  );
}

class _ExternalRecipientLine extends StatelessWidget {
  const _ExternalRecipientLine({required this.recipient});

  final _ExternalRecipientSummary recipient;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      key: const ValueKey('swap_activity_external_recipient_line'),
      children: [
        AppIcon(AppIcons.user, size: 14, color: colors.icon.muted),
        const SizedBox(width: AppSpacing.xxs),
        Text(
          recipient.label,
          style: AppTypography.labelMedium.copyWith(
            color: colors.text.secondary,
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Text(
            recipient.value,
            key: const ValueKey('swap_activity_external_recipient_value'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.end,
            style: AppTypography.codeSmall.copyWith(color: colors.text.primary),
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        _CopyValueButton(label: recipient.label, value: recipient.value),
      ],
    );
  }
}

class _ActiveTradeAmount extends StatelessWidget {
  const _ActiveTradeAmount({
    required this.label,
    required this.value,
    this.alignEnd = false,
  });

  final String label;
  final String value;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: alignEnd
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTypography.labelMedium.copyWith(
            color: colors.text.secondary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          compactSwapAmountText(value),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: alignEnd ? TextAlign.end : TextAlign.start,
          style: AppTypography.labelLarge.copyWith(color: colors.text.accent),
        ),
      ],
    );
  }
}

class _ActivityHardwareActionPanel extends StatelessWidget {
  const _ActivityHardwareActionPanel({
    required this.iconName,
    required this.title,
    required this.message,
    required this.buttonKey,
    required this.buttonLabel,
    required this.onPressed,
    super.key,
  });

  final String iconName;
  final String title;
  final String message;
  final Key buttonKey;
  final String buttonLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: colors.background.raised,
        borderRadius: BorderRadius.circular(AppRadii.xSmall),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colors.background.base,
              borderRadius: BorderRadius.circular(AppRadii.xSmall),
            ),
            child: AppIcon(iconName, size: 20, color: colors.icon.regular),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTypography.labelLarge.copyWith(
                    color: colors.text.accent,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  message,
                  style: AppTypography.bodySmall.copyWith(
                    color: colors.text.secondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          AppButton(
            key: buttonKey,
            onPressed: onPressed,
            variant: AppButtonVariant.primary,
            size: AppButtonSize.medium,
            leading: AppIcon(iconName),
            child: Text(buttonLabel),
          ),
        ],
      ),
    );
  }
}

class _ActivityDepositActionPanel extends StatelessWidget {
  const _ActivityDepositActionPanel({
    required this.state,
    required this.instruction,
    required this.onDepositTxHashChanged,
    required this.onSubmitDepositTransaction,
  });

  final SwapState state;
  final SwapActivityDepositInstruction instruction;
  final ValueChanged<String> onDepositTxHashChanged;
  final VoidCallback onSubmitDepositTransaction;

  @override
  Widget build(BuildContext context) {
    final qr = instruction.qr;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (qr != null) ...[
          SwapDepositQrPanel(
            key: const ValueKey('swap_activity_deposit_qr_panel'),
            title: 'Send ${instruction.depositSymbol} to this deposit address',
            qrData: instruction.address,
            addressLabel: instruction.depositAddressLabel,
            address: instruction.address,
            railLabel: qr.railLabel,
            reuseWarning: qr.reuseWarning,
            memo: instruction.memo,
          ),
          const SizedBox(height: AppSpacing.xs),
        ],
        _ActivityDepositInstructionPanel(instruction: instruction),
        const SizedBox(height: AppSpacing.xs),
        _DepositTxHashDisclosure(
          state: state,
          instruction: instruction,
          onDepositTxHashChanged: onDepositTxHashChanged,
          onSubmitDepositTransaction: onSubmitDepositTransaction,
        ),
      ],
    );
  }
}

class _ActivityDepositInstructionPanel extends StatelessWidget {
  const _ActivityDepositInstructionPanel({required this.instruction});

  final SwapActivityDepositInstruction instruction;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            instruction.sendLabel,
            style: AppTypography.labelLarge.copyWith(color: colors.text.accent),
          ),
          const SizedBox(height: AppSpacing.xs),
          _ActivityInstructionRow(
            label: instruction.depositAddressLabel,
            value: instruction.address,
          ),
          if (instruction.memo != null)
            _ActivityInstructionRow(label: 'Memo', value: instruction.memo!),
        ],
      ),
    );
  }
}

class _ActivityInstructionRow extends StatelessWidget {
  const _ActivityInstructionRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
      child: Row(
        children: [
          SizedBox(
            width: 124,
            child: Text(
              label,
              style: AppTypography.labelMedium.copyWith(
                color: colors.text.secondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.bodySmall.copyWith(
                color: colors.text.primary,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.xxs),
          _CopyValueButton(label: label, value: value),
        ],
      ),
    );
  }
}

class _DepositTxHashDisclosure extends StatefulWidget {
  const _DepositTxHashDisclosure({
    required this.state,
    required this.instruction,
    required this.onDepositTxHashChanged,
    required this.onSubmitDepositTransaction,
  });

  final SwapState state;
  final SwapActivityDepositInstruction instruction;
  final ValueChanged<String> onDepositTxHashChanged;
  final VoidCallback onSubmitDepositTransaction;

  @override
  State<_DepositTxHashDisclosure> createState() =>
      _DepositTxHashDisclosureState();
}

class _DepositTxHashDisclosureState extends State<_DepositTxHashDisclosure> {
  late bool _expanded = widget.state.depositTxHashText.trim().isNotEmpty;

  @override
  void didUpdateWidget(covariant _DepositTxHashDisclosure oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.state.depositTxHashText.trim().isNotEmpty && !_expanded) {
      _expanded = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final canSubmit = widget.state.canSubmitDepositTx;
    final submitLabel = widget.state.depositSubmitting
        ? 'Submitting'
        : widget.instruction.submitLabel;
    return Padding(
      key: const ValueKey('swap_deposit_tx_hash_disclosure'),
      padding: const EdgeInsets.all(AppSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                child: AppIcon(
                  AppIcons.link,
                  size: 16,
                  color: colors.icon.muted,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Already sent?',
                      style: AppTypography.labelLarge.copyWith(
                        color: colors.text.accent,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Add the deposit transaction hash to speed up status checks.',
                      style: AppTypography.bodyExtraSmall.copyWith(
                        color: colors.text.secondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              AppButton(
                key: const ValueKey('swap_deposit_tx_hash_toggle'),
                onPressed: () => setState(() => _expanded = !_expanded),
                variant: AppButtonVariant.secondary,
                size: AppButtonSize.small,
                trailing: AppIcon(
                  _expanded ? AppIcons.arrowUpward : AppIcons.arrowDown,
                ),
                child: Text(_expanded ? 'Hide' : 'Add tx hash'),
              ),
            ],
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppTextField(
                    key: const ValueKey('swap_deposit_tx_hash_field'),
                    label: widget.instruction.txHashLabel,
                    initialValue: widget.state.depositTxHashText,
                    hintText: widget.instruction.txHashHint,
                    showClearButton: true,
                    onChanged: widget.onDepositTxHashChanged,
                    onClear: () => widget.onDepositTxHashChanged(''),
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) {
                      if (canSubmit) {
                        widget.onSubmitDepositTransaction();
                      }
                    },
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Align(
                    alignment: Alignment.centerRight,
                    child: AppButton(
                      key: const ValueKey('swap_deposit_submit_button'),
                      onPressed: canSubmit
                          ? widget.onSubmitDepositTransaction
                          : null,
                      variant: AppButtonVariant.secondary,
                      size: AppButtonSize.medium,
                      leading: const AppIcon(AppIcons.link),
                      child: Text(submitLabel),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _CopyValueButton extends StatelessWidget {
  const _CopyValueButton({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final keyLabel = label.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    return Semantics(
      button: true,
      label: 'Copy $label',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          key: ValueKey('swap_copy_$keyLabel'),
          behavior: HitTestBehavior.opaque,
          onTap: () {
            copySwapText(
              context,
              text: value,
              toastMessage: _copyValueToastMessage(label),
            );
          },
          child: Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colors.background.raised,
              border: Border.all(color: colors.border.subtle),
              borderRadius: BorderRadius.circular(AppRadii.xSmall),
            ),
            child: AppIcon(AppIcons.copy, size: 14, color: colors.icon.muted),
          ),
        ),
      ),
    );
  }
}

String _copyValueToastMessage(String label) {
  final normalized = label.trim();
  if (normalized.isEmpty) return 'Copied to Clipboard';
  final lower = normalized.toLowerCase();
  if (lower == 'memo') return 'Memo Copied';
  if (lower.contains('address') ||
      lower.contains('recipient') ||
      lower.contains('deposit')) {
    return 'Address copied';
  }
  return 'Copied to Clipboard';
}
