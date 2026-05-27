import 'swap_prototype_models.dart';

SwapPrototypeIntent swapPrototypeIntentFromRecord(SwapIntentRecord record) {
  return SwapPrototypeIntent(
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
    direction: record.direction,
    externalAsset: record.externalAsset,
    depositAddress: record.depositAddress,
    depositMemo: record.depositMemo,
    depositTxHash: record.depositTxHash,
    providerQuoteId: record.providerQuoteId,
    providerSignature: record.providerSignature,
    swapFeeText: record.swapFeeText,
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

SwapPrototypeIntent swapIntentFromSnapshot({
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
    direction: quote.direction,
    externalAsset: quote.externalAsset,
    depositAddress: quote.depositInstruction.address,
    depositMemo: quote.depositInstruction.memo,
    providerQuoteId: quote.providerQuoteId,
    providerSignature: quote.providerSignature,
    swapFeeText: snapshot.swapFeeText ?? quote.feeLabel,
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
  return swapPrototypeIntentFromRecord(record);
}

SwapPrototypeIntent updateSwapIntentFromSnapshot(
  SwapPrototypeIntent intent,
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
    swapFeeText: snapshot.swapFeeText,
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
  return swapPrototypeIntentFromRecord(record);
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

List<SwapPrototypeStep> swapStepsForRecord(SwapIntentRecord record) {
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
    const SwapPrototypeStep(
      label: 'Quote locked',
      state: SwapPrototypeStepState.done,
      evidence: 'Quote saved locally',
    ),
    SwapPrototypeStep(
      label: sendsZec
          ? 'One-time transparent address prepared'
          : 'One-time ${externalAsset.symbol} source address prepared',
      state: SwapPrototypeStepState.active,
      evidence: '0 previous uses',
    ),
    SwapPrototypeStep(
      label: sendsZec
          ? 'Awaiting ZEC deposit'
          : 'Awaiting ${externalAsset.symbol} deposit',
      state: SwapPrototypeStepState.pending,
      evidence: 'Do not reuse this address',
    ),
    SwapPrototypeStep(
      label: sendsZec ? 'Deposit observed' : 'External deposit observed',
      state: SwapPrototypeStepState.pending,
      evidence: 'Waiting for chain observation',
    ),
    SwapPrototypeStep(
      label: sendsZec ? 'Refund path monitored' : 'Shielded receive',
      state: SwapPrototypeStepState.pending,
      evidence: sendsZec
          ? 'Wallet unified address is used only if a refund arrives'
          : _deliverySummary(record),
    ),
  ];
}

List<SwapPrototypeStep> swapStepsForStatus(
  SwapIntentStatus status,
  String nextAction,
) {
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
    const SwapPrototypeStep(
      label: 'Quote locked',
      state: SwapPrototypeStepState.done,
      evidence: 'Stored locally',
    ),
    SwapPrototypeStep(
      label: 'Deposit observed',
      state: doneBeforeProcessing
          ? SwapPrototypeStepState.done
          : SwapPrototypeStepState.active,
      evidence: doneBeforeProcessing ? 'Deposit confirmed' : nextAction,
    ),
    SwapPrototypeStep(
      label: status.label,
      state: failed
          ? SwapPrototypeStepState.warning
          : complete
          ? SwapPrototypeStepState.done
          : SwapPrototypeStepState.active,
      evidence: nextAction,
    ),
  ];
}

List<SwapPrototypeField> swapExposureForRecord(SwapIntentRecord record) {
  final direction = record.direction;
  final externalAsset = record.externalAsset;
  if (direction == null || externalAsset == null) return const [];
  final sendsZec = direction.sendsZec;
  if (!sendsZec) {
    return [
      SwapPrototypeField(
        label: '${externalAsset.symbol} source deposit',
        value: 'one-time ${externalAsset.symbol} address',
      ),
      SwapPrototypeField(
        label: 'ZEC destination',
        value: _deliverySummary(record),
      ),
      SwapPrototypeField(
        label: 'Third-party data',
        value: 'solver sees ${externalAsset.symbol} deposit and ZEC route',
      ),
      const SwapPrototypeField(
        label: 'Network disclosure',
        value: 'direct connection; Tor not enabled',
      ),
    ];
  }
  return [
    const SwapPrototypeField(
      label: 'ZEC deposit',
      value: 'one-time transparent address',
    ),
    const SwapPrototypeField(label: 'Address reuse', value: '0 previous uses'),
    const SwapPrototypeField(
      label: 'Refund path',
      value: 'wallet unified address',
    ),
    SwapPrototypeField(
      label: 'Third-party data',
      value: 'solver sees ZEC deposit and ${externalAsset.symbol} route',
    ),
    const SwapPrototypeField(
      label: 'Network disclosure',
      value: 'direct connection; Tor not enabled',
    ),
  ];
}

List<SwapPrototypeField> swapReceiptForRecord(SwapIntentRecord record) {
  final direction = record.direction;
  final externalAsset = record.externalAsset;
  final sendsZec = direction?.sendsZec ?? true;
  final fields = <SwapPrototypeField>[
    SwapPrototypeField(label: 'Pair', value: record.pairText),
    if (record.providerQuoteId != null)
      SwapPrototypeField(
        label: 'Provider quote',
        value: record.providerQuoteId!,
      ),
    if (record.oneClickRecipient != null)
      SwapPrototypeField(
        label: sendsZec
            ? '${externalAsset?.symbol ?? 'External'} recipient'
            : 'ZEC recipient',
        value: record.oneClickRecipient!,
      ),
    if (record.depositAddress != null)
      SwapPrototypeField(
        label: sendsZec
            ? 'ZEC deposit'
            : '${externalAsset?.symbol ?? 'External'} source deposit',
        value: record.depositAddress!,
      ),
    if (record.depositMemo != null)
      SwapPrototypeField(label: 'Memo', value: record.depositMemo!),
    if (record.oneClickRefundTo != null)
      SwapPrototypeField(label: 'Refund to', value: record.oneClickRefundTo!),
    ...swapProviderRefundFields(record.providerRefundInfo),
    if (record.providerStatusRaw != null)
      SwapPrototypeField(
        label: 'Provider status',
        value: record.providerStatusRaw!,
      ),
    if (record.depositTxHash != null)
      SwapPrototypeField(label: 'Deposit tx', value: record.depositTxHash!),
    if (record.broadcastNotice != null &&
        record.broadcastNotice!.trim().isNotEmpty)
      SwapPrototypeField(
        label: 'Broadcast status',
        value: record.broadcastNotice!,
      ),
  ];
  return fields;
}

List<SwapPrototypeField> swapProviderRefundFields(
  SwapProviderRefundInfo? info,
) {
  if (info == null || !info.hasAny) return const [];
  return [
    if (info.minimumDepositText != null)
      SwapPrototypeField(
        label: 'Minimum deposit',
        value: info.minimumDepositText!,
      ),
    if (info.refundFeeText != null)
      SwapPrototypeField(label: 'Refund fee', value: info.refundFeeText!),
    if (info.depositedAmountText != null)
      SwapPrototypeField(
        label: 'Provider deposited',
        value: info.depositedAmountText!,
      ),
    if (info.refundedAmountText != null)
      SwapPrototypeField(
        label: 'Provider refunded',
        value: info.refundedAmountText!,
      ),
    if (info.refundReason != null)
      SwapPrototypeField(label: 'Refund reason', value: info.refundReason!),
  ];
}

String _deliverySummary(SwapIntentRecord record) {
  final direction = record.direction;
  final externalAsset = record.externalAsset;
  if (direction == null || externalAsset == null) return 'prepared destination';
  if (!direction.sendsZec) {
    return 'ZEC arrives directly at the shielded wallet address';
  }
  return '${externalAsset.symbol} is delivered to the external destination';
}
