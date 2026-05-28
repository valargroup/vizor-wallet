import 'swap_models.dart';

SwapIntent swapIntentFromRecord(SwapIntentRecord record) {
  return SwapIntent(
    id: record.id,
    title: swapIntentTitle(record),
    pair: record.pairText,
    sellAmount: record.sellAmountText,
    receiveEstimate: record.receiveEstimateText,
    provider: record.providerLabel,
    status: record.status,
    nextAction: record.nextAction,
    steps: swapStepsForRecord(record),
    exposure: swapExposureForRecord(record),
    receipt: swapReceiptForRecord(record),
    sellAmountBaseUnits: record.sellAmountBaseUnits,
    direction: record.direction,
    externalAsset: record.externalAsset,
    depositAddress: record.depositAddress,
    depositMemo: record.depositMemo,
    depositTxHash: record.depositTxHash,
    providerQuoteId: record.providerQuoteId,
    providerSignature: record.providerSignature,
    swapFeeText: record.swapFeeText,
    totalFeesText: record.totalFeesText,
    realisedSlippageText: record.realisedSlippageText,
    slippageToleranceText: record.slippageToleranceText,
    priceProtectionText: record.priceProtectionText,
    minimumReceiveText: record.minimumReceiveText,
    providerStatusRaw: record.providerStatusRaw,
    nearIntentHash: record.nearIntentHash,
    nearTransactionHash: record.nearTransactionHash,
    originChainTxHash: record.originChainTxHash,
    destinationChainTxHash: record.destinationChainTxHash,
    providerRefundInfo: record.providerRefundInfo,
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
  return [for (final record in records) swapIntentFromRecord(record)];
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
  final record = SwapIntentRecord(
    id: snapshot.id,
    providerLabel: snapshot.providerLabel,
    pairText: snapshot.pairText,
    sellAmountText: snapshot.sellAmountText,
    receiveEstimateText: snapshot.receiveEstimateText,
    status: snapshot.status,
    nextAction: snapshot.nextAction,
    sellAmountBaseUnits:
        snapshot.sellAmountBaseUnits ?? quote.sellAmountBaseUnits,
    direction: quote.direction,
    externalAsset: quote.externalAsset,
    depositAddress: quote.depositInstruction.address,
    depositMemo: quote.depositInstruction.memo,
    providerQuoteId: quote.providerQuoteId,
    providerSignature: quote.providerSignature,
    swapFeeText: snapshot.swapFeeText ?? quote.feeLabel,
    totalFeesText: snapshot.totalFeesText ?? quote.totalFeesText,
    realisedSlippageText: snapshot.realisedSlippageText,
    slippageToleranceText:
        snapshot.slippageToleranceText ?? quote.slippageToleranceText,
    priceProtectionText:
        snapshot.priceProtectionText ?? quote.priceProtectionText,
    minimumReceiveText: snapshot.minimumReceiveText ?? quote.minimumReceiveText,
    providerStatusRaw: snapshot.providerStatusRaw,
    nearIntentHash: snapshot.nearIntentHash,
    nearTransactionHash: snapshot.nearTransactionHash,
    originChainTxHash: snapshot.originChainTxHash,
    destinationChainTxHash: snapshot.destinationChainTxHash,
    providerRefundInfo: snapshot.providerRefundInfo ?? quote.providerRefundInfo,
    oneClickRecipient: addressPlan.oneClickRecipient,
    oneClickRefundTo: addressPlan.oneClickRefundTo,
    depositDeadline: quote.depositInstruction.deadline,
    accountUuid: accountUuid,
    createdAt: now,
    updatedAt: now,
    completedAt: snapshot.status.isTerminal ? now : null,
  );
  return swapIntentFromRecord(record);
}

SwapIntent swapIntentWithBroadcastNotice(
  SwapIntent intent, {
  required String notice,
  DateTime? updatedAt,
}) {
  return swapIntentFromRecord(
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
  return swapIntentFromRecord(
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
  return swapIntentFromRecord(
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
  final status = snapshot.status;
  final record = SwapIntentRecord.fromIntent(intent).copyWith(
    providerLabel: snapshot.providerLabel,
    pairText: snapshot.pairText,
    sellAmountText: snapshot.sellAmountText,
    receiveEstimateText: snapshot.receiveEstimateText,
    status: status,
    nextAction: snapshot.nextAction,
    sellAmountBaseUnits: snapshot.sellAmountBaseUnits,
    swapFeeText: snapshot.swapFeeText,
    totalFeesText: snapshot.totalFeesText,
    realisedSlippageText: snapshot.realisedSlippageText,
    slippageToleranceText: snapshot.slippageToleranceText,
    priceProtectionText: snapshot.priceProtectionText,
    minimumReceiveText: snapshot.minimumReceiveText,
    providerStatusRaw: snapshot.providerStatusRaw,
    nearIntentHash: snapshot.nearIntentHash,
    nearTransactionHash: snapshot.nearTransactionHash,
    originChainTxHash: snapshot.originChainTxHash,
    destinationChainTxHash: snapshot.destinationChainTxHash,
    providerRefundInfo: providerRefundInfo,
    lastStatusCheckedAt: lastStatusCheckedAt,
    depositAddress:
        intent.depositAddress ?? snapshot.depositInstruction.address,
    depositMemo: intent.depositMemo ?? snapshot.depositInstruction.memo,
    depositDeadline:
        snapshot.depositInstruction.deadline ?? intent.depositDeadline,
    updatedAt: timestamp,
    completedAt: intent.completedAt ?? (status.isTerminal ? timestamp : null),
  );
  return swapIntentFromRecord(record);
}

String swapIntentTitle(SwapIntentRecord record) {
  final direction = record.direction;
  final externalAsset = record.externalAsset;
  if (direction != null && externalAsset != null) {
    return direction.sendsZec
        ? 'ZEC to ${externalAsset.symbol}'
        : '${externalAsset.symbol} to ZEC';
  }
  return record.pairText.replaceAll(' -> ', ' to ');
}

List<SwapStep> swapStepsForRecord(SwapIntentRecord record) {
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

List<SwapDetailField> swapExposureForRecord(SwapIntentRecord record) {
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

List<SwapDetailField> swapReceiptForRecord(SwapIntentRecord record) {
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
    ...swapProviderRefundFields(record.providerRefundInfo),
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

List<SwapDetailField> swapProviderRefundFields(SwapProviderRefundInfo? info) {
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
