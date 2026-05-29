import 'swap_models.dart';

SwapIntent _swapIntentFromRecord(SwapIntentRecord record) {
  return SwapIntent(
    id: record.id,
    title: _swapIntentTitle(record),
    pair: record.pairText,
    sellAmount: record.sellAmountText,
    receiveEstimate: record.receiveEstimateText,
    provider: record.providerLabel,
    status: record.status,
    nextAction: record.nextAction,
    steps: _swapStepsForRecord(record),
    exposure: _swapExposureForRecord(record),
    receipt: _swapReceiptForRecord(record),
    sellAmountBaseUnits: record.sellAmountBaseUnits,
    direction: record.direction,
    externalAsset: record.externalAsset,
    depositAddress: record.depositAddress,
    depositMemo: record.depositMemo,
    depositTxHash: record.depositTxHash,
    providerQuoteId: record.providerQuoteId,
    swapFeeText: record.swapFeeText,
    totalFeesText: record.totalFeesText,
    realisedSlippageText: record.realisedSlippageText,
    slippageToleranceText: record.slippageToleranceText,
    minimumReceiveText: record.minimumReceiveText,
    providerStatusRaw: record.providerStatusRaw,
    nearIntentHash: record.nearIntentHash,
    originChainTxHash: record.originChainTxHash,
    destinationChainTxHash: record.destinationChainTxHash,
    providerRefundInfo: record.providerRefundInfo,
    fiatValueBasis: record.fiatValueBasis,
    lastStatusCheckedAt: record.lastStatusCheckedAt,
    statusError: record.statusError,
    broadcastNotice: record.broadcastNotice,
    oneClickRecipient: record.oneClickRecipient,
    oneClickRefundTo: record.oneClickRefundTo,
    depositDeadline: record.depositDeadline,
    accountUuid: record.accountUuid,
    createdAt: record.createdAt,
    updatedAt: record.updatedAt,
    completedAt: record.completedAt,
  );
}

List<SwapIntent> swapIntentsFromRecords(Iterable<SwapIntentRecord> records) {
  return [for (final record in records) _swapIntentFromRecord(record)];
}

SwapIntentRecord swapIntentRecordForPersistence(
  SwapIntent intent, {
  required String accountUuid,
}) {
  return SwapIntentRecord.fromIntent(intent.copyWith(accountUuid: accountUuid));
}

SwapIntent swapIntentFromSnapshot({
  required SwapIntentSnapshot snapshot,
  required SwapQuote quote,
  required SwapAddressPlan addressPlan,
  required String accountUuid,
  required DateTime now,
}) {
  final depositDeadline =
      snapshot.depositInstruction.deadline ?? quote.depositInstruction.deadline;
  final status = _resolveDepositDeadlineStatus(
    providerStatus: snapshot.status,
    deadline: depositDeadline,
    hasDepositEvidence: _hasText(snapshot.originChainTxHash),
    now: now,
  );
  final nextAction = _nextActionForResolvedStatus(status, snapshot);
  final record = SwapIntentRecord(
    id: snapshot.id,
    providerLabel: snapshot.providerLabel,
    pairText: snapshot.pairText,
    sellAmountText: snapshot.sellAmountText,
    receiveEstimateText: snapshot.receiveEstimateText,
    status: status,
    nextAction: nextAction,
    sellAmountBaseUnits:
        snapshot.sellAmountBaseUnits ?? quote.sellAmountBaseUnits,
    direction: quote.direction,
    externalAsset: quote.externalAsset,
    depositAddress: quote.depositInstruction.address,
    depositMemo: quote.depositInstruction.memo,
    providerQuoteId: quote.providerQuoteId,
    swapFeeText: snapshot.swapFeeText ?? quote.feeLabel,
    totalFeesText: snapshot.totalFeesText ?? quote.totalFeesText,
    realisedSlippageText: snapshot.realisedSlippageText,
    slippageToleranceText:
        snapshot.slippageToleranceText ?? quote.slippageToleranceText,
    minimumReceiveText: snapshot.minimumReceiveText ?? quote.minimumReceiveText,
    providerStatusRaw: snapshot.providerStatusRaw,
    nearIntentHash: snapshot.nearIntentHash,
    originChainTxHash: snapshot.originChainTxHash,
    destinationChainTxHash: snapshot.destinationChainTxHash,
    providerRefundInfo: snapshot.providerRefundInfo ?? quote.providerRefundInfo,
    fiatValueBasis: snapshot.fiatValueBasis ?? quote.fiatValueBasis,
    oneClickRecipient: addressPlan.oneClickRecipient,
    oneClickRefundTo: addressPlan.oneClickRefundTo,
    depositDeadline: depositDeadline,
    accountUuid: accountUuid,
    createdAt: now,
    updatedAt: now,
    completedAt: status.isTerminal ? now : null,
  );
  return _swapIntentFromRecord(record);
}

SwapIntent swapIntentWithBroadcastNotice(
  SwapIntent intent, {
  required String notice,
  DateTime? updatedAt,
}) {
  return _swapIntentFromRecord(
    SwapIntentRecord.fromIntent(intent).copyWith(
      statusError: notice,
      broadcastNotice: notice,
      updatedAt: updatedAt ?? DateTime.now().toUtc(),
    ),
  );
}

SwapIntent swapIntentWithDepositCheckpoint(
  SwapIntent intent, {
  required String txHash,
  String? statusError,
  String? broadcastNotice,
  required bool clearStatusError,
  required bool clearBroadcastNotice,
  DateTime? updatedAt,
}) {
  return _swapIntentFromRecord(
    SwapIntentRecord.fromIntent(intent).copyWith(
      depositTxHash: txHash,
      statusError: statusError ?? broadcastNotice,
      broadcastNotice: broadcastNotice,
      clearStatusError: clearStatusError,
      clearBroadcastNotice: clearBroadcastNotice,
      updatedAt: updatedAt ?? DateTime.now().toUtc(),
    ),
  );
}

SwapIntent swapIntentWithDepositSnapshot(
  SwapIntent intent,
  SwapIntentSnapshot snapshot, {
  required String txHash,
  String? broadcastNotice,
  DateTime? updatedAt,
}) {
  final timestamp = updatedAt ?? DateTime.now().toUtc();
  final effectiveBroadcastNotice = broadcastNotice ?? intent.broadcastNotice;
  final updated = updateSwapIntentFromSnapshot(
    intent,
    snapshot,
    updatedAt: timestamp,
  );
  return _swapIntentFromRecord(
    SwapIntentRecord.fromIntent(updated).copyWith(
      depositTxHash: txHash,
      statusError: effectiveBroadcastNotice,
      broadcastNotice: effectiveBroadcastNotice,
      clearStatusError: effectiveBroadcastNotice == null,
      clearBroadcastNotice: effectiveBroadcastNotice == null,
      updatedAt: timestamp,
    ),
  );
}

SwapIntent updateSwapIntentFromSnapshot(
  SwapIntent intent,
  SwapIntentSnapshot snapshot, {
  DateTime? updatedAt,
  DateTime? lastStatusCheckedAt,
}) {
  final timestamp = updatedAt ?? DateTime.now().toUtc();
  final providerRefundInfo =
      intent.providerRefundInfo?.merge(snapshot.providerRefundInfo) ??
      snapshot.providerRefundInfo;
  final depositDeadline =
      snapshot.depositInstruction.deadline ?? intent.depositDeadline;
  final status = _resolveDepositDeadlineStatus(
    providerStatus: snapshot.status,
    deadline: depositDeadline,
    hasDepositEvidence:
        _hasText(intent.depositTxHash) ||
        _hasText(intent.originChainTxHash) ||
        _hasText(snapshot.originChainTxHash),
    now: timestamp,
  );
  final nextAction = _nextActionForResolvedStatus(status, snapshot);
  final record = SwapIntentRecord.fromIntent(intent).copyWith(
    providerLabel: snapshot.providerLabel,
    pairText: snapshot.pairText,
    sellAmountText: snapshot.sellAmountText,
    receiveEstimateText: snapshot.receiveEstimateText,
    status: status,
    nextAction: nextAction,
    sellAmountBaseUnits: snapshot.sellAmountBaseUnits,
    swapFeeText: snapshot.swapFeeText,
    totalFeesText: snapshot.totalFeesText,
    realisedSlippageText: snapshot.realisedSlippageText,
    slippageToleranceText: snapshot.slippageToleranceText,
    minimumReceiveText: snapshot.minimumReceiveText,
    providerStatusRaw: snapshot.providerStatusRaw,
    nearIntentHash: snapshot.nearIntentHash,
    originChainTxHash: snapshot.originChainTxHash,
    destinationChainTxHash: snapshot.destinationChainTxHash,
    providerRefundInfo: providerRefundInfo,
    fiatValueBasis: intent.fiatValueBasis ?? snapshot.fiatValueBasis,
    lastStatusCheckedAt: lastStatusCheckedAt,
    depositAddress:
        intent.depositAddress ?? snapshot.depositInstruction.address,
    depositMemo: intent.depositMemo ?? snapshot.depositInstruction.memo,
    depositDeadline: depositDeadline,
    updatedAt: timestamp,
    completedAt: intent.completedAt ?? (status.isTerminal ? timestamp : null),
  );
  return _swapIntentFromRecord(record);
}

SwapIntentStatus _resolveDepositDeadlineStatus({
  required SwapIntentStatus providerStatus,
  required DateTime? deadline,
  required bool hasDepositEvidence,
  required DateTime now,
}) {
  if (!_isAwaitingDepositStatus(providerStatus) ||
      deadline == null ||
      hasDepositEvidence ||
      now.toUtc().isBefore(deadline.toUtc())) {
    return providerStatus;
  }
  return SwapIntentStatus.expired;
}

bool _isAwaitingDepositStatus(SwapIntentStatus status) {
  return status == SwapIntentStatus.awaitingDeposit ||
      status == SwapIntentStatus.awaitingExternalDeposit;
}

String _nextActionForResolvedStatus(
  SwapIntentStatus status,
  SwapIntentSnapshot snapshot,
) {
  if (status == SwapIntentStatus.expired &&
      snapshot.status != SwapIntentStatus.expired) {
    return 'Start a fresh quote';
  }
  return snapshot.nextAction;
}

bool _hasText(String? value) => value?.trim().isNotEmpty ?? false;

String _swapIntentTitle(SwapIntentRecord record) {
  final direction = record.direction;
  final externalAsset = record.externalAsset;
  if (direction != null && externalAsset != null) {
    return direction.sendsZec
        ? 'ZEC to ${externalAsset.symbol}'
        : '${externalAsset.symbol} to ZEC';
  }
  return record.pairText.replaceAll(' -> ', ' to ');
}

List<SwapStep> _swapStepsForRecord(SwapIntentRecord record) {
  final direction = record.direction;
  final externalAsset = record.externalAsset;
  final useInitialSteps =
      record.lastStatusCheckedAt == null &&
      record.depositTxHash == null &&
      (record.status == SwapIntentStatus.awaitingDeposit ||
          record.status == SwapIntentStatus.awaitingExternalDeposit) &&
      !record.nextAction.toLowerCase().contains('keystone');
  if (!useInitialSteps || direction == null || externalAsset == null) {
    return swapStepsForStatus(record.status, record.nextAction);
  }

  final sendsZec = direction.sendsZec;
  return [
    const SwapStep(
      label: 'Quote locked',
      state: SwapStepState.done,
      evidence: 'Quote saved locally',
    ),
    SwapStep(
      label: sendsZec
          ? 'One-time transparent address prepared'
          : 'One-time ${externalAsset.chainLabel} address prepared for ${externalAsset.symbol}',
      state: SwapStepState.active,
      evidence: '0 previous uses',
    ),
    SwapStep(
      label: sendsZec
          ? 'Awaiting ZEC deposit'
          : 'Awaiting ${externalAsset.symbol} deposit',
      state: SwapStepState.pending,
      evidence: 'Do not reuse this address',
    ),
    SwapStep(
      label: sendsZec ? 'Deposit observed' : 'External deposit observed',
      state: SwapStepState.pending,
      evidence: 'Waiting for chain observation',
    ),
    SwapStep(
      label: sendsZec ? 'Refund path monitored' : 'Shielded receive',
      state: SwapStepState.pending,
      evidence: sendsZec
          ? 'Wallet unified address is used only if a refund arrives'
          : _deliverySummary(record),
    ),
  ];
}

List<SwapStep> swapStepsForStatus(SwapIntentStatus status, String nextAction) {
  final doneBeforeProcessing = switch (status) {
    SwapIntentStatus.awaitingDeposit ||
    SwapIntentStatus.awaitingExternalDeposit ||
    SwapIntentStatus.providerStatusUnknown ||
    SwapIntentStatus.expired => false,
    _ => true,
  };
  final complete = status == SwapIntentStatus.complete;
  final failed =
      status == SwapIntentStatus.failed ||
      status == SwapIntentStatus.expired ||
      status == SwapIntentStatus.refunded;
  return [
    const SwapStep(
      label: 'Quote locked',
      state: SwapStepState.done,
      evidence: 'Stored locally',
    ),
    SwapStep(
      label: 'Deposit observed',
      state: doneBeforeProcessing ? SwapStepState.done : SwapStepState.active,
      evidence: doneBeforeProcessing ? 'Deposit confirmed' : nextAction,
    ),
    SwapStep(
      label: status.label,
      state: failed
          ? SwapStepState.warning
          : complete
          ? SwapStepState.done
          : SwapStepState.active,
      evidence: nextAction,
    ),
  ];
}

List<SwapDetailField> _swapExposureForRecord(SwapIntentRecord record) {
  final direction = record.direction;
  final externalAsset = record.externalAsset;
  if (direction == null || externalAsset == null) return const [];
  final sendsZec = direction.sendsZec;
  if (!sendsZec) {
    return [
      SwapDetailField(
        label: '${externalAsset.symbol} source deposit',
        value: 'one-time ${externalAsset.symbol} address',
      ),
      SwapDetailField(
        label: 'ZEC destination',
        value: _deliverySummary(record),
      ),
      SwapDetailField(
        label: 'Third-party data',
        value: 'solver sees ${externalAsset.symbol} deposit and ZEC route',
      ),
      const SwapDetailField(
        label: 'Network disclosure',
        value: 'direct connection; Tor not enabled',
      ),
    ];
  }
  return [
    const SwapDetailField(
      label: 'ZEC deposit',
      value: 'one-time transparent address',
    ),
    const SwapDetailField(label: 'Address reuse', value: '0 previous uses'),
    const SwapDetailField(
      label: 'Refund path',
      value: 'wallet unified address',
    ),
    SwapDetailField(
      label: 'Third-party data',
      value: 'solver sees ZEC deposit and ${externalAsset.symbol} route',
    ),
    const SwapDetailField(
      label: 'Network disclosure',
      value: 'direct connection; Tor not enabled',
    ),
  ];
}

List<SwapDetailField> _swapReceiptForRecord(SwapIntentRecord record) {
  final direction = record.direction;
  final externalAsset = record.externalAsset;
  final sendsZec = direction?.sendsZec ?? true;
  final fields = <SwapDetailField>[
    SwapDetailField(label: 'Pair', value: record.pairText),
    if (record.providerQuoteId != null)
      SwapDetailField(label: 'Provider quote', value: record.providerQuoteId!),
    if (record.oneClickRecipient != null)
      SwapDetailField(
        label: sendsZec
            ? '${externalAsset?.symbol ?? 'External'} recipient'
            : 'ZEC recipient',
        value: record.oneClickRecipient!,
      ),
    if (record.depositAddress != null)
      SwapDetailField(
        label: sendsZec
            ? 'ZEC deposit'
            : '${externalAsset?.symbol ?? 'External'} source deposit',
        value: record.depositAddress!,
      ),
    if (record.depositMemo != null)
      SwapDetailField(label: 'Memo', value: record.depositMemo!),
    if (record.oneClickRefundTo != null)
      SwapDetailField(label: 'Refund to', value: record.oneClickRefundTo!),
    ..._swapProviderRefundFields(record.providerRefundInfo),
    if (record.providerStatusRaw != null)
      SwapDetailField(
        label: 'Provider status',
        value: record.providerStatusRaw!,
      ),
    if (record.depositTxHash != null)
      SwapDetailField(label: 'Deposit tx', value: record.depositTxHash!),
    if (record.broadcastNotice != null &&
        record.broadcastNotice!.trim().isNotEmpty)
      SwapDetailField(
        label: 'Broadcast status',
        value: record.broadcastNotice!,
      ),
  ];
  return fields;
}

List<SwapDetailField> _swapProviderRefundFields(SwapProviderRefundInfo? info) {
  if (info == null || !info.hasAny) return const [];
  return [
    if (info.minimumDepositText != null)
      SwapDetailField(
        label: 'Minimum deposit',
        value: info.minimumDepositText!,
      ),
    if (info.refundFeeText != null)
      SwapDetailField(label: 'Refund fee', value: info.refundFeeText!),
    if (info.depositedAmountText != null)
      SwapDetailField(
        label: 'Provider deposited',
        value: info.depositedAmountText!,
      ),
    if (info.refundedAmountText != null)
      SwapDetailField(
        label: 'Provider refunded',
        value: info.refundedAmountText!,
      ),
    if (info.refundReason != null)
      SwapDetailField(label: 'Refund reason', value: info.refundReason!),
  ];
}

String _deliverySummary(SwapIntentRecord record) {
  final direction = record.direction;
  final externalAsset = record.externalAsset;
  if (direction == null || externalAsset == null) return 'prepared destination';
  if (!direction.sendsZec) {
    return 'ZEC arrives at your shielded address';
  }
  return '${externalAsset.symbol} is delivered to the external destination';
}
