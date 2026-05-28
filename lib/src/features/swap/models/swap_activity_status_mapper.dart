import '../../../core/profile_pictures.dart';
import '../../../core/widgets/app_icon.dart';
import '../widgets/swap_status_page_content.dart';
import 'swap_detail_tooltips.dart';
import 'swap_models.dart';

class SwapActivityAccountDetail {
  const SwapActivityAccountDetail({required this.name, this.profilePictureId});

  final String name;
  final String? profilePictureId;
}

class SwapActivityStatusPresentation {
  const SwapActivityStatusPresentation({
    required this.title,
    required this.payAsset,
    required this.receiveAsset,
    required this.payFiatText,
    required this.receiveFiatText,
    required this.payAmountText,
    required this.receiveAmountText,
    required this.badgeKind,
    required this.progressIndex,
    required this.steps,
    required this.details,
    required this.showTabs,
  });

  final String title;
  final SwapAsset payAsset;
  final SwapAsset receiveAsset;
  final String payFiatText;
  final String receiveFiatText;
  final String payAmountText;
  final String receiveAmountText;
  final SwapStatusBadgeKind badgeKind;
  final int progressIndex;
  final List<SwapStatusStepData> steps;
  final List<SwapStatusDetailRowData> details;
  final bool showTabs;
}

SwapActivityStatusPresentation swapActivityStatusPresentationForIntent(
  SwapState state,
  SwapIntent intent, {
  SwapActivityAccountDetail? accountDetail,
}) {
  final sellAsset = swapActivitySellAsset(intent) ?? SwapAsset.zec;
  final receiveAsset = swapActivityReceiveAsset(intent) ?? SwapAsset.usdc;
  return SwapActivityStatusPresentation(
    title: _swapActivityStatusTitle(intent),
    payAsset: sellAsset,
    receiveAsset: receiveAsset,
    payFiatText: _swapActivityFiatTextForAsset(
      state,
      intent: intent,
      asset: sellAsset,
      amountText: intent.sellAmount,
    ),
    receiveFiatText: _swapActivityFiatTextForAsset(
      state,
      intent: intent,
      asset: receiveAsset,
      amountText: intent.receiveEstimate,
    ),
    payAmountText: intent.sellAmount,
    receiveAmountText: intent.receiveEstimate,
    badgeKind: _swapActivityStatusBadgeKind(intent.status),
    progressIndex: _swapActivityStatusProgressIndex(intent),
    steps: _swapActivityProgressSteps(intent),
    details: _swapActivityStatusDetails(intent, accountDetail: accountDetail),
    showTabs: !intent.status.isTerminal,
  );
}

String _swapActivityStatusTitle(SwapIntent intent) {
  return switch (intent.status) {
    SwapIntentStatus.complete => 'Swap completed',
    SwapIntentStatus.failed ||
    SwapIntentStatus.refunded ||
    SwapIntentStatus.incompleteDeposit => 'Swap failed',
    _ => 'Swapping ...',
  };
}

SwapStatusBadgeKind _swapActivityStatusBadgeKind(SwapIntentStatus status) {
  return switch (status) {
    SwapIntentStatus.complete => SwapStatusBadgeKind.completed,
    SwapIntentStatus.failed ||
    SwapIntentStatus.refunded ||
    SwapIntentStatus.expired ||
    SwapIntentStatus.incompleteDeposit => SwapStatusBadgeKind.failed,
    _ => SwapStatusBadgeKind.liveQuote,
  };
}

int _swapActivityStatusProgressIndex(SwapIntent intent) {
  final hasDepositTx = intent.depositTxHash?.trim().isNotEmpty ?? false;
  return switch (intent.status) {
    SwapIntentStatus.awaitingDeposit ||
    SwapIntentStatus.awaitingExternalDeposit => hasDepositTx ? 1 : 0,
    SwapIntentStatus.depositObserved => 1,
    SwapIntentStatus.processing ||
    SwapIntentStatus.providerStatusUnknown ||
    SwapIntentStatus.incompleteDeposit => 2,
    SwapIntentStatus.complete ||
    SwapIntentStatus.refunded ||
    SwapIntentStatus.expired ||
    SwapIntentStatus.failed => 3,
  };
}

List<SwapStatusStepData> _swapActivityProgressSteps(SwapIntent intent) {
  final sourceSymbol = swapActivityPairSymbol(intent.pair, 0);
  final receiveSymbol = swapActivityPairSymbol(intent.pair, 1);
  final sourceVerb = intent.direction == SwapDirection.zecToExternal
      ? 'Sending'
      : 'Depositing';
  final sourceDone = intent.direction == SwapDirection.zecToExternal
      ? '$sourceSymbol sent'
      : '$sourceSymbol Deposited';
  final deliveryTitle = intent.direction == SwapDirection.zecToExternal
      ? 'Deliver $receiveSymbol'
      : 'Send $receiveSymbol';

  final lastCheckedLabel =
      _swapActivityLastRelativeStatusCheckedLabel(intent.lastStatusCheckedAt) ??
      'Last check: just now';

  return [
    SwapStatusStepData(
      title: sourceSymbol,
      state: SwapStatusStepState.pending,
      completeTitle: sourceDone,
      activeTitle: '$sourceVerb $sourceSymbol...',
      pendingTitle: intent.direction == SwapDirection.zecToExternal
          ? 'Send $sourceSymbol'
          : 'Deposit $sourceSymbol',
      lastCheckedLabel: lastCheckedLabel,
      description:
          'Confirm waiting for the source chain and provider to recognise the deposit',
    ),
    SwapStatusStepData(
      title: 'Deposit confirmation',
      state: SwapStatusStepState.pending,
      activeTitle: 'Deposit confirmation...',
      lastCheckedLabel: lastCheckedLabel,
      description: 'Confirming the deposit before the swap route starts.',
    ),
    SwapStatusStepData(
      title: 'Swap',
      state: SwapStatusStepState.pending,
      activeTitle: 'Swap...',
      lastCheckedLabel: lastCheckedLabel,
      description: 'The provider is executing the swap route.',
    ),
    SwapStatusStepData(
      title: deliveryTitle,
      state: SwapStatusStepState.pending,
      activeTitle: '$deliveryTitle...',
      lastCheckedLabel: lastCheckedLabel,
      description: 'Delivering the output asset to the recipient address.',
    ),
  ];
}

List<SwapStatusDetailRowData> _swapActivityStatusDetails(
  SwapIntent intent, {
  SwapActivityAccountDetail? accountDetail,
}) {
  final sourceSymbol = swapActivityPairSymbol(intent.pair, 0);
  final receiveSymbol = swapActivityPairSymbol(intent.pair, 1);
  final refundAddress = intent.oneClickRefundTo?.trim();
  final recipientAddress = intent.oneClickRecipient?.trim();
  final depositAddress = intent.depositAddress?.trim();
  final localDepositTxHash = intent.depositTxHash?.trim();
  final originChainTxHash = intent.originChainTxHash?.trim();
  final destinationChainTxHash = intent.destinationChainTxHash?.trim();
  final depositTxHash = _firstNonEmpty([localDepositTxHash, originChainTxHash]);
  final timestamp = _swapActivityTimestampLabel(
    intent.completedAt ?? intent.updatedAt ?? intent.createdAt,
  );
  final terminal = intent.status.isTerminal;
  final failed =
      _swapActivityStatusBadgeKind(intent.status) == SwapStatusBadgeKind.failed;
  final sendsZec = intent.direction != SwapDirection.externalToZec;

  if (terminal) {
    return [
      _accountDetailRow(accountDetail),
      if (failed && refundAddress != null && refundAddress.isNotEmpty)
        SwapStatusDetailRowData(
          label: '$sourceSymbol refunded to',
          value: _compactSwapActivityAddress(refundAddress),
        )
      else if (!failed && depositAddress != null && depositAddress.isNotEmpty)
        SwapStatusDetailRowData(
          label: '$sourceSymbol deposit to',
          value: _compactSwapActivityAddress(depositAddress),
          copyable: true,
          copyText: depositAddress,
        ),
      SwapStatusDetailRowData(
        label: 'Total fees',
        value:
            intent.totalFeesText ??
            intent.swapFeeText ??
            intent.providerRefundInfo?.refundFeeText ??
            'Included',
        help: true,
        helpTooltip: swapTotalFeesTooltip,
      ),
      if (!failed)
        SwapStatusDetailRowData(
          label: 'Realized slippage',
          value: intent.realisedSlippageText ?? 'Not reported',
        ),
      if (timestamp != null)
        SwapStatusDetailRowData(label: 'Timestamp', value: timestamp),
    ];
  }

  return [
    _accountDetailRow(accountDetail),
    if (sendsZec && recipientAddress != null && recipientAddress.isNotEmpty)
      SwapStatusDetailRowData(
        label: '$receiveSymbol recipient',
        value: _compactSwapActivityAddress(recipientAddress),
        copyable: true,
        copyText: recipientAddress,
      ),
    if (!sendsZec && refundAddress != null && refundAddress.isNotEmpty)
      SwapStatusDetailRowData(
        label: '$sourceSymbol refund address',
        value: _compactSwapActivityAddress(refundAddress),
      ),
    if (depositAddress != null && depositAddress.isNotEmpty)
      SwapStatusDetailRowData(
        label: 'Deposit $sourceSymbol to',
        value: _compactSwapActivityAddress(depositAddress),
        copyable: true,
        copyText: depositAddress,
      ),
    SwapStatusDetailRowData(
      label: 'Swap fee',
      value: intent.swapFeeText ?? 'Included in shown rate',
      help: true,
      helpTooltip: swapFeeTooltip,
    ),
    SwapStatusDetailRowData(
      label: 'Slippage tolerance',
      value: intent.slippageToleranceText ?? 'Configured quote',
    ),
    SwapStatusDetailRowData(
      label: 'Guaranteed minimum',
      value: intent.minimumReceiveText ?? intent.receiveEstimate,
      help: true,
      helpTooltip: swapMinimumReceiveTooltip(receiveSymbol),
    ),
    if (sendsZec && refundAddress != null && refundAddress.isNotEmpty)
      SwapStatusDetailRowData(
        label: '$sourceSymbol refund address',
        value: _compactSwapActivityAddress(refundAddress),
      ),
    if (!sendsZec && recipientAddress != null && recipientAddress.isNotEmpty)
      SwapStatusDetailRowData(
        label: '$receiveSymbol recipient',
        value: _compactSwapActivityAddress(recipientAddress),
        copyable: true,
        copyText: recipientAddress,
      ),
    if (depositTxHash != null && depositTxHash.isNotEmpty)
      SwapStatusDetailRowData(
        label: '$sourceSymbol deposit tx',
        value: _compactSwapActivityAddress(depositTxHash),
        copyable: true,
        copyText: depositTxHash,
      ),
    if (destinationChainTxHash != null && destinationChainTxHash.isNotEmpty)
      SwapStatusDetailRowData(
        label: '$receiveSymbol delivery tx',
        value: _compactSwapActivityAddress(destinationChainTxHash),
        copyable: true,
        copyText: destinationChainTxHash,
      ),
  ];
}

SwapAsset? swapActivitySellAsset(SwapIntent intent) {
  final direction = intent.direction;
  final externalAsset = intent.externalAsset;
  if (direction == null || externalAsset == null) {
    return _swapActivityAssetFromPair(intent.pair, 0);
  }
  return direction.fromAsset(externalAsset);
}

SwapAsset? swapActivityReceiveAsset(SwapIntent intent) {
  final direction = intent.direction;
  final externalAsset = intent.externalAsset;
  if (direction == null || externalAsset == null) {
    return _swapActivityAssetFromPair(intent.pair, 1);
  }
  return direction.toAsset(externalAsset);
}

SwapAsset? _swapActivityAssetFromPair(String pair, int index) {
  final parts = pair.split('->');
  if (index < 0 || index >= parts.length) return null;
  final tokens = parts[index].trim().split(RegExp(r'\s+'));
  final symbol = tokens.isEmpty ? '' : tokens.first;
  if (symbol.isEmpty) return null;
  return SwapAsset.byName(symbol.toLowerCase());
}

String swapActivityPairSymbol(String pair, int index) {
  final parts = pair.split(' -> ');
  if (parts.length > index && parts[index].trim().isNotEmpty) {
    return parts[index].trim();
  }
  return index == 0 ? 'deposit asset' : 'receive asset';
}

String _swapActivityFiatTextForAsset(
  SwapState state, {
  required SwapIntent intent,
  required SwapAsset asset,
  required String amountText,
}) {
  final amount = _numericAmount(amountText);
  if (amount == null || amount <= 0) return r'$--';
  if (_isUsdLikeSwapAsset(asset)) return _formatActivityUsd(amount);
  final externalAsset = intent.externalAsset ?? state.externalAsset;
  if (asset.isNativeZec && _isUsdLikeSwapAsset(externalAsset)) {
    final zecUsd =
        state.indicativeExternalPerZec[externalAsset] ??
        externalAsset.fallbackExternalPerZec;
    if (zecUsd.isFinite && zecUsd > 0) {
      return _formatActivityUsd(amount * zecUsd);
    }
  }
  return r'$--';
}

String? swapDepositDeadlineLabel(SwapIntent intent) {
  final deadline = intent.depositDeadline;
  if (deadline == null) return null;
  final remaining = deadline.difference(DateTime.now());
  if (remaining.isNegative) return '00:00';
  if (remaining.inHours >= 1) {
    final hours = (remaining.inSeconds / Duration.secondsPerHour).ceil();
    return hours == 1 ? '1hr' : '${hours}hrs';
  }
  if (remaining.inMinutes >= 15) {
    final minutes = remaining.inMinutes;
    return minutes == 1 ? '1min' : '${minutes}mins';
  }
  final minutes = remaining.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = remaining.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}

String? _swapActivityLastRelativeStatusCheckedLabel(DateTime? checkedAt) {
  if (checkedAt == null) return null;
  final elapsed = DateTime.now().difference(checkedAt.toLocal());
  if (elapsed.inMinutes <= 0) return 'Last check: just now';
  return 'Last check: ${elapsed.inMinutes}m ago';
}

String? _swapActivityTimestampLabel(DateTime? timestamp) {
  if (timestamp == null) return null;
  final local = timestamp.toLocal();
  final month = _monthNames[local.month - 1];
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$month ${local.day}, ${local.year} $hour:$minute';
}

String _compactSwapActivityAddress(String address) {
  final trimmed = address.trim();
  if (trimmed.length <= 18) return trimmed;
  return '${trimmed.substring(0, 9)} ... ${trimmed.substring(trimmed.length - 7)}';
}

class SwapActivityStatusPlan {
  const SwapActivityStatusPlan({
    required this.title,
    required this.detail,
    required this.iconName,
    required this.tone,
  });

  static SwapActivityStatusPlan fromIntent(SwapIntent intent) {
    final sourceSymbol = swapActivityPairSymbol(intent.pair, 0);
    final receiveSymbol = swapActivityPairSymbol(intent.pair, 1);
    final hasDepositTx = intent.depositTxHash?.trim().isNotEmpty ?? false;

    return switch (intent.status) {
      SwapIntentStatus.awaitingDeposit => SwapActivityStatusPlan(
        title: hasDepositTx ? '$sourceSymbol sent' : 'Send $sourceSymbol',
        detail: hasDepositTx
            ? 'Waiting for the deposit to confirm.'
            : 'Send once to the deposit address below.',
        iconName: hasDepositTx ? AppIcons.eye : AppIcons.link,
        tone: SwapActivityStatusPlanTone.action,
      ),
      SwapIntentStatus.awaitingExternalDeposit => SwapActivityStatusPlan(
        title: hasDepositTx ? '$sourceSymbol sent' : 'Send $sourceSymbol',
        detail: hasDepositTx
            ? 'Waiting for the source-chain deposit to confirm.'
            : 'Send once to the source-chain deposit address below.',
        iconName: hasDepositTx ? AppIcons.eye : AppIcons.link,
        tone: SwapActivityStatusPlanTone.action,
      ),
      SwapIntentStatus.depositObserved => SwapActivityStatusPlan(
        title: '$sourceSymbol deposit confirmed',
        detail: 'Preparing the $receiveSymbol delivery.',
        iconName: AppIcons.eye,
        tone: SwapActivityStatusPlanTone.action,
      ),
      SwapIntentStatus.processing => SwapActivityStatusPlan(
        title: '$receiveSymbol delivery in progress',
        detail: 'No new approval is needed.',
        iconName: AppIcons.renew,
        tone: SwapActivityStatusPlanTone.action,
      ),
      SwapIntentStatus.providerStatusUnknown => SwapActivityStatusPlan(
        title: 'Checking provider status',
        detail: intent.providerStatusRaw == null
            ? 'Refresh once. Keep the swap record open if it does not update.'
            : 'Provider returned ${intent.providerStatusRaw}. Keep this record open.',
        iconName: AppIcons.warning,
        tone: SwapActivityStatusPlanTone.warning,
      ),
      SwapIntentStatus.incompleteDeposit => const SwapActivityStatusPlan(
        title: 'Deposit needs attention',
        detail: 'Top up the missing amount or wait for refund.',
        iconName: AppIcons.warning,
        tone: SwapActivityStatusPlanTone.warning,
      ),
      SwapIntentStatus.complete => SwapActivityStatusPlan(
        title: receiveSymbol == 'ZEC'
            ? 'ZEC ready'
            : '$receiveSymbol delivered',
        detail: 'The swap is complete.',
        iconName: AppIcons.checkCircle,
        tone: SwapActivityStatusPlanTone.success,
      ),
      SwapIntentStatus.refunded => const SwapActivityStatusPlan(
        title: 'Funds refunded',
        detail: 'Check the refund transaction before retrying.',
        iconName: AppIcons.checkCircle,
        tone: SwapActivityStatusPlanTone.success,
      ),
      SwapIntentStatus.expired => const SwapActivityStatusPlan(
        title: 'Deposit window closed',
        detail: 'No funds moved if no deposit was sent.',
        iconName: AppIcons.block,
        tone: SwapActivityStatusPlanTone.destructive,
      ),
      SwapIntentStatus.failed => const SwapActivityStatusPlan(
        title: 'Swap failed',
        detail: 'Start a fresh quote when ready.',
        iconName: AppIcons.block,
        tone: SwapActivityStatusPlanTone.destructive,
      ),
    };
  }

  final String title;
  final String detail;
  final String iconName;
  final SwapActivityStatusPlanTone tone;
}

enum SwapActivityStatusPlanTone { action, warning, success, destructive }

class SwapActivityRoutePlan {
  const SwapActivityRoutePlan({required this.steps});

  factory SwapActivityRoutePlan.fromIntent(SwapIntent intent) {
    final sourceSymbol = swapActivityPairSymbol(intent.pair, 0);
    final receiveSymbol = swapActivityPairSymbol(intent.pair, 1);
    final receivesZec = receiveSymbol == 'ZEC';
    final deliverLabel = receivesZec ? 'Receive ZEC' : 'Deliver';
    final deliverDetail = receivesZec
        ? 'Provider is sending ZEC directly to this wallet shielded address.'
        : 'Provider is sending funds to your destination address.';
    final hasDepositTx = intent.depositTxHash?.trim().isNotEmpty ?? false;

    final labels = ['Send $sourceSymbol', 'Confirm', 'Swap', deliverLabel];
    final details = [
      'Send the quoted amount to the one-time deposit address.',
      'Waiting for the source chain and provider to recognize the deposit.',
      'Provider is converting funds and preparing delivery.',
      deliverDetail,
    ];
    final icons = [
      AppIcons.link,
      AppIcons.eye,
      AppIcons.renew,
      receivesZec ? AppIcons.shieldKeyhole : AppIcons.checkCircle,
    ];
    final states = switch (intent.status) {
      SwapIntentStatus.awaitingDeposit ||
      SwapIntentStatus.awaitingExternalDeposit =>
        hasDepositTx
            ? const [
                SwapActivityRouteStepState.done,
                SwapActivityRouteStepState.active,
                SwapActivityRouteStepState.pending,
                SwapActivityRouteStepState.pending,
              ]
            : const [
                SwapActivityRouteStepState.active,
                SwapActivityRouteStepState.pending,
                SwapActivityRouteStepState.pending,
                SwapActivityRouteStepState.pending,
              ],
      SwapIntentStatus.depositObserved || SwapIntentStatus.processing => const [
        SwapActivityRouteStepState.done,
        SwapActivityRouteStepState.done,
        SwapActivityRouteStepState.active,
        SwapActivityRouteStepState.pending,
      ],
      SwapIntentStatus.providerStatusUnknown => const [
        SwapActivityRouteStepState.done,
        SwapActivityRouteStepState.warning,
        SwapActivityRouteStepState.active,
        SwapActivityRouteStepState.pending,
      ],
      SwapIntentStatus.incompleteDeposit =>
        hasDepositTx
            ? const [
                SwapActivityRouteStepState.done,
                SwapActivityRouteStepState.warning,
                SwapActivityRouteStepState.pending,
                SwapActivityRouteStepState.pending,
              ]
            : const [
                SwapActivityRouteStepState.warning,
                SwapActivityRouteStepState.pending,
                SwapActivityRouteStepState.pending,
                SwapActivityRouteStepState.pending,
              ],
      SwapIntentStatus.complete => const [
        SwapActivityRouteStepState.done,
        SwapActivityRouteStepState.done,
        SwapActivityRouteStepState.done,
        SwapActivityRouteStepState.done,
      ],
      SwapIntentStatus.refunded => const [
        SwapActivityRouteStepState.done,
        SwapActivityRouteStepState.warning,
        SwapActivityRouteStepState.pending,
        SwapActivityRouteStepState.pending,
      ],
      SwapIntentStatus.expired => const [
        SwapActivityRouteStepState.failed,
        SwapActivityRouteStepState.pending,
        SwapActivityRouteStepState.pending,
        SwapActivityRouteStepState.pending,
      ],
      SwapIntentStatus.failed =>
        hasDepositTx
            ? const [
                SwapActivityRouteStepState.done,
                SwapActivityRouteStepState.done,
                SwapActivityRouteStepState.failed,
                SwapActivityRouteStepState.pending,
              ]
            : const [
                SwapActivityRouteStepState.failed,
                SwapActivityRouteStepState.pending,
                SwapActivityRouteStepState.pending,
                SwapActivityRouteStepState.pending,
              ],
    };
    return SwapActivityRoutePlan(
      steps: [
        for (var index = 0; index < labels.length; index++)
          SwapActivityRouteStep(
            label: labels[index],
            detail: details[index],
            state: states[index],
            iconName: icons[index],
          ),
      ],
    );
  }

  int get _activeStepIndex {
    final failedOrWarningIndex = steps.indexWhere(
      (step) =>
          step.state == SwapActivityRouteStepState.failed ||
          step.state == SwapActivityRouteStepState.warning,
    );
    if (failedOrWarningIndex != -1) return failedOrWarningIndex;
    final activeIndex = steps.indexWhere(
      (step) => step.state == SwapActivityRouteStepState.active,
    );
    if (activeIndex != -1) return activeIndex;
    final lastDoneIndex = steps.lastIndexWhere(
      (step) => step.state == SwapActivityRouteStepState.done,
    );
    return lastDoneIndex == -1 ? 0 : lastDoneIndex;
  }

  SwapActivityRouteStep get _activeStep => steps[_activeStepIndex];

  bool get hasActiveStep =>
      steps.any((step) => step.state == SwapActivityRouteStepState.active);

  bool get _hasAlertStep => steps.any(
    (step) =>
        step.state == SwapActivityRouteStepState.failed ||
        step.state == SwapActivityRouteStepState.warning,
  );

  bool get canAnimateProgress =>
      !_hasAlertStep && (hasActiveStep || _isComplete);

  int get progressIndex {
    if (_isComplete) return steps.length;
    final activeIndex = steps.indexWhere(
      (step) => step.state == SwapActivityRouteStepState.active,
    );
    if (activeIndex != -1) return activeIndex;
    return _activeStepIndex;
  }

  SwapActivityRoutePlan displayedAtProgress(int progressIndex) {
    if (!canAnimateProgress || progressIndex >= this.progressIndex) {
      return this;
    }
    final clampedIndex = progressIndex.clamp(0, steps.length).toInt();
    if (clampedIndex >= steps.length) return this;
    return SwapActivityRoutePlan(
      steps: [
        for (var index = 0; index < steps.length; index++)
          steps[index]._copyWith(
            state: index < clampedIndex
                ? SwapActivityRouteStepState.done
                : index == clampedIndex
                ? SwapActivityRouteStepState.active
                : SwapActivityRouteStepState.pending,
          ),
      ],
    );
  }

  int get _completedStepCount => steps
      .where((step) => step.state == SwapActivityRouteStepState.done)
      .length;

  String get _phaseLabel {
    if (_isComplete) return 'Funds delivered';
    final step = _activeStep;
    return step.state == SwapActivityRouteStepState.active
        ? 'Now: ${step.label}'
        : step.state.label;
  }

  String get semanticLabel =>
      '$_phaseLabel, ${_activeStep.detail}, $_completedStepCount of ${steps.length} steps done';

  bool get _isComplete =>
      steps.every((step) => step.state == SwapActivityRouteStepState.done);

  final List<SwapActivityRouteStep> steps;
}

class SwapActivityRouteStep {
  const SwapActivityRouteStep({
    required this.label,
    required this.detail,
    required this.state,
    required this.iconName,
  });

  final String label;
  final String detail;
  final SwapActivityRouteStepState state;
  final String iconName;

  SwapActivityRouteStep _copyWith({SwapActivityRouteStepState? state}) {
    return SwapActivityRouteStep(
      label: label,
      detail: detail,
      state: state ?? this.state,
      iconName: iconName,
    );
  }
}

enum SwapActivityRouteStepState { pending, active, done, warning, failed }

extension _SwapActivityRouteStepStateLabel on SwapActivityRouteStepState {
  String get label => switch (this) {
    SwapActivityRouteStepState.pending => 'Waiting',
    SwapActivityRouteStepState.active => 'Now',
    SwapActivityRouteStepState.done => 'Done',
    SwapActivityRouteStepState.warning => 'Check',
    SwapActivityRouteStepState.failed => 'Stopped',
  };
}

class SwapActivityResolution {
  const SwapActivityResolution({
    required this.title,
    required this.message,
    required this.detail,
    required this.iconName,
    required this.tone,
    this.primaryAction,
  });

  static SwapActivityResolution? fromIntent(SwapIntent intent) {
    return switch (intent.status) {
      SwapIntentStatus.incompleteDeposit => SwapActivityResolution(
        title: 'Resolve incomplete deposit',
        message: 'The deposit is below the quoted amount.',
        detail:
            'Send only the missing amount with the same one-time deposit details, or wait for the refund path.',
        iconName: AppIcons.warning,
        tone: SwapActivityResolutionTone.warning,
        primaryAction: SwapActivityResolutionAction.copyTopUpDetails,
      ),
      SwapIntentStatus.providerStatusUnknown => SwapActivityResolution(
        title: 'Status needs your attention',
        message: intent.providerStatusRaw == null
            ? 'The provider status could not be interpreted.'
            : 'The provider returned ${intent.providerStatusRaw}.',
        detail:
            'Do not resend funds. Refresh once and keep this activity item for support if the status does not move forward.',
        iconName: AppIcons.warning,
        tone: SwapActivityResolutionTone.warning,
      ),
      SwapIntentStatus.refunded => SwapActivityResolution(
        title: 'Refund complete',
        message: 'The swap is closed and the refund has been submitted.',
        detail:
            'Check the origin-chain refund transaction before starting a fresh quote.',
        iconName: AppIcons.checkCircle,
        tone: SwapActivityResolutionTone.success,
        primaryAction: SwapActivityResolutionAction.reviewFreshQuote,
      ),
      SwapIntentStatus.failed => SwapActivityResolution(
        title: 'Route failed',
        message: 'The swap could not complete this route.',
        detail:
            'No funds moved according to status. Review the receipt, then start a new quote.',
        iconName: AppIcons.block,
        tone: SwapActivityResolutionTone.destructive,
        primaryAction: SwapActivityResolutionAction.reviewFreshQuote,
      ),
      SwapIntentStatus.expired => SwapActivityResolution(
        title: 'Deposit window closed',
        message: 'The deposit window for this quote has closed.',
        detail:
            'If you did not send funds, no action is needed. If you sent funds near expiry, refresh once and keep this deposit address for support.',
        iconName: AppIcons.block,
        tone: SwapActivityResolutionTone.destructive,
        primaryAction: SwapActivityResolutionAction.reviewFreshQuote,
      ),
      _ => null,
    };
  }

  final String title;
  final String message;
  final String detail;
  final String iconName;
  final SwapActivityResolutionTone tone;
  final SwapActivityResolutionAction? primaryAction;
}

enum SwapActivityResolutionTone { warning, success, destructive }

enum SwapActivityResolutionAction { copyTopUpDetails, reviewFreshQuote }

class SwapActivityDepositInstruction {
  const SwapActivityDepositInstruction({
    required this.sendLabel,
    required this.depositSymbol,
    required this.depositAddressLabel,
    required this.address,
    required this.txHashLabel,
    required this.txHashHint,
    required this.submitLabel,
    this.memo,
    this.qr,
  });

  static SwapActivityDepositInstruction? fromIntent(SwapIntent intent) {
    final direction = intent.direction;
    final externalAsset = intent.externalAsset;
    final depositAddress = intent.depositAddress;
    if (direction == null || externalAsset == null || depositAddress == null) {
      return null;
    }

    final depositSymbol = direction.fromSymbol(externalAsset);
    final depositAddressLabel = direction.sendsZec
        ? '$depositSymbol deposit'
        : '$depositSymbol source deposit';

    return SwapActivityDepositInstruction(
      sendLabel: direction.sendsZec
          ? 'Send $depositSymbol'
          : 'Send $depositSymbol from source chain',
      depositSymbol: depositSymbol,
      depositAddressLabel: depositAddressLabel,
      address: depositAddress,
      memo: intent.depositMemo,
      txHashLabel: '$depositSymbol deposit tx hash',
      txHashHint: '$depositSymbol source-chain transaction hash',
      submitLabel: 'Submit $depositSymbol deposit',
      qr: direction.sendsZec
          ? null
          : SwapActivityDepositQrInstruction(
              railLabel: externalAsset.railLabel,
              reuseWarning: 'Do not reuse this address',
            ),
    );
  }

  final String sendLabel;
  final String depositSymbol;
  final String depositAddressLabel;
  final String address;
  final String? memo;
  final String txHashLabel;
  final String txHashHint;
  final String submitLabel;
  final SwapActivityDepositQrInstruction? qr;
}

class SwapActivityDepositQrInstruction {
  const SwapActivityDepositQrInstruction({
    required this.railLabel,
    required this.reuseWarning,
  });

  final String railLabel;
  final String reuseWarning;
}

bool swapActivityShowDepositControls(SwapIntentStatus status) {
  return switch (status) {
    SwapIntentStatus.complete ||
    SwapIntentStatus.refunded ||
    SwapIntentStatus.expired ||
    SwapIntentStatus.providerStatusUnknown ||
    SwapIntentStatus.failed => false,
    _ => true,
  };
}

bool canRefreshSwapIntentStatus(SwapIntentStatus status) {
  return status != SwapIntentStatus.complete;
}

bool swapActivityShowsExternalDepositPage(SwapIntent intent) {
  return intent.direction == SwapDirection.externalToZec &&
      intent.status == SwapIntentStatus.awaitingExternalDeposit &&
      SwapActivityDepositInstruction.fromIntent(intent) != null;
}

bool swapActivityShowsHardwareZecDepositPage(
  SwapIntent intent, {
  required bool intentIsHardware,
}) {
  return intentIsHardware &&
      intent.direction == SwapDirection.zecToExternal &&
      intent.status == SwapIntentStatus.awaitingDeposit &&
      !(intent.depositTxHash?.trim().isNotEmpty ?? false) &&
      SwapActivityDepositInstruction.fromIntent(intent) != null;
}

bool swapActivityShowsDepositPage(
  SwapIntent intent, {
  required bool intentIsHardware,
}) {
  if (intent.status == SwapIntentStatus.expired) return true;
  return swapActivityShowsExternalDepositPage(intent) ||
      swapActivityShowsHardwareZecDepositPage(
        intent,
        intentIsHardware: intentIsHardware,
      );
}

SwapStatusDetailRowData _accountDetailRow(
  SwapActivityAccountDetail? accountDetail,
) {
  return SwapStatusDetailRowData(
    label: 'Account',
    value: accountDetail?.name ?? 'Unknown account',
    accountProfilePictureId:
        accountDetail?.profilePictureId ?? kDefaultProfilePictureId,
  );
}

String? _firstNonEmpty(Iterable<String?> values) {
  for (final value in values) {
    final trimmed = value?.trim();
    if (trimmed != null && trimmed.isNotEmpty) return trimmed;
  }
  return null;
}

bool _isUsdLikeSwapAsset(SwapAsset asset) {
  final symbol = asset.symbol.toUpperCase();
  return symbol == 'USDC' || symbol == 'USDT' || symbol == 'DAI';
}

double? _numericAmount(String amountText) {
  final raw = amountText.split(RegExp(r'\s+')).first.replaceAll(',', '').trim();
  final amount = double.tryParse(raw);
  return amount == null || !amount.isFinite ? null : amount;
}

String _formatActivityUsd(double value) {
  if (!value.isFinite || value <= 0) return r'$0.00';
  if (value >= 1000000) return '\$${(value / 1000000).toStringAsFixed(2)}M';
  if (value >= 1000) return '\$${(value / 1000).toStringAsFixed(2)}K';
  return '\$${value.toStringAsFixed(2)}';
}

const _monthNames = <String>[
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];
