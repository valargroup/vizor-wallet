import '../domain/swap_contract.dart';
import 'swap_presentation_models.dart';

class SwapIntentRecord {
  const SwapIntentRecord({
    required this.id,
    required this.providerLabel,
    required this.pairText,
    required this.sellAmountText,
    required this.receiveEstimateText,
    required this.status,
    required this.nextAction,
    this.sellAmountBaseUnits,
    this.direction,
    this.externalAsset,
    this.depositAddress,
    this.depositMemo,
    this.depositTxHash,
    this.providerQuoteId,
    this.swapFeeText,
    this.totalFeesText,
    this.realisedSlippageText,
    this.slippageToleranceText,
    this.priceProtectionText,
    this.minimumReceiveText,
    this.providerStatusRaw,
    this.nearIntentHash,
    this.originChainTxHash,
    this.destinationChainTxHash,
    this.providerRefundInfo,
    this.lastStatusCheckedAt,
    this.statusError,
    this.broadcastNotice,
    this.oneClickRecipient,
    this.oneClickRefundTo,
    this.depositDeadline,
    this.accountUuid,
    this.createdAt,
    this.updatedAt,
    this.completedAt,
  });

  factory SwapIntentRecord.fromIntent(SwapIntent intent) {
    return SwapIntentRecord(
      id: intent.id,
      providerLabel: intent.provider,
      pairText: intent.pair,
      sellAmountText: intent.sellAmount,
      receiveEstimateText: intent.receiveEstimate,
      status: intent.status,
      nextAction: intent.nextAction,
      sellAmountBaseUnits: intent.sellAmountBaseUnits,
      direction: intent.direction,
      externalAsset: intent.externalAsset,
      depositAddress: intent.depositAddress,
      depositMemo: intent.depositMemo,
      depositTxHash: intent.depositTxHash,
      providerQuoteId: intent.providerQuoteId,
      swapFeeText: intent.swapFeeText,
      totalFeesText: intent.totalFeesText,
      realisedSlippageText: intent.realisedSlippageText,
      slippageToleranceText: intent.slippageToleranceText,
      priceProtectionText: intent.priceProtectionText,
      minimumReceiveText: intent.minimumReceiveText,
      providerStatusRaw: intent.providerStatusRaw,
      nearIntentHash: intent.nearIntentHash,
      originChainTxHash: intent.originChainTxHash,
      destinationChainTxHash: intent.destinationChainTxHash,
      providerRefundInfo: intent.providerRefundInfo,
      lastStatusCheckedAt: intent.lastStatusCheckedAt,
      statusError: intent.statusError,
      broadcastNotice: intent.broadcastNotice,
      oneClickRecipient: intent.oneClickRecipient,
      oneClickRefundTo: intent.oneClickRefundTo,
      depositDeadline: intent.depositDeadline,
      accountUuid: intent.accountUuid,
      createdAt: intent.createdAt,
      updatedAt: intent.updatedAt,
      completedAt: intent.completedAt,
    );
  }

  final String id;
  final String providerLabel;
  final String pairText;
  final String sellAmountText;
  final String receiveEstimateText;
  final SwapIntentStatus status;
  final String nextAction;
  final BigInt? sellAmountBaseUnits;
  final SwapDirection? direction;
  final SwapAsset? externalAsset;
  final String? depositAddress;
  final String? depositMemo;
  final String? depositTxHash;
  final String? providerQuoteId;
  final String? swapFeeText;
  final String? totalFeesText;
  final String? realisedSlippageText;
  final String? slippageToleranceText;
  final String? priceProtectionText;
  final String? minimumReceiveText;
  final String? providerStatusRaw;
  final String? nearIntentHash;
  final String? originChainTxHash;
  final String? destinationChainTxHash;
  final SwapProviderRefundInfo? providerRefundInfo;
  final DateTime? lastStatusCheckedAt;
  final String? statusError;
  final String? broadcastNotice;
  final String? oneClickRecipient;
  final String? oneClickRefundTo;
  final DateTime? depositDeadline;
  final String? accountUuid;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? completedAt;

  DateTime? get activityTimestamp =>
      updatedAt ?? createdAt ?? lastStatusCheckedAt;

  SwapIntentRecord copyWith({
    String? id,
    String? providerLabel,
    String? pairText,
    String? sellAmountText,
    String? receiveEstimateText,
    SwapIntentStatus? status,
    String? nextAction,
    BigInt? sellAmountBaseUnits,
    SwapDirection? direction,
    SwapAsset? externalAsset,
    String? depositAddress,
    String? depositMemo,
    String? depositTxHash,
    String? providerQuoteId,
    String? swapFeeText,
    String? totalFeesText,
    String? realisedSlippageText,
    String? slippageToleranceText,
    String? priceProtectionText,
    String? minimumReceiveText,
    String? providerStatusRaw,
    String? nearIntentHash,
    String? originChainTxHash,
    String? destinationChainTxHash,
    SwapProviderRefundInfo? providerRefundInfo,
    DateTime? lastStatusCheckedAt,
    String? statusError,
    String? broadcastNotice,
    String? oneClickRecipient,
    String? oneClickRefundTo,
    DateTime? depositDeadline,
    String? accountUuid,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? completedAt,
    bool clearStatusError = false,
    bool clearBroadcastNotice = false,
  }) {
    return SwapIntentRecord(
      id: id ?? this.id,
      providerLabel: providerLabel ?? this.providerLabel,
      pairText: pairText ?? this.pairText,
      sellAmountText: sellAmountText ?? this.sellAmountText,
      receiveEstimateText: receiveEstimateText ?? this.receiveEstimateText,
      status: status ?? this.status,
      nextAction: nextAction ?? this.nextAction,
      sellAmountBaseUnits: sellAmountBaseUnits ?? this.sellAmountBaseUnits,
      direction: direction ?? this.direction,
      externalAsset: externalAsset ?? this.externalAsset,
      depositAddress: depositAddress ?? this.depositAddress,
      depositMemo: depositMemo ?? this.depositMemo,
      depositTxHash: depositTxHash ?? this.depositTxHash,
      providerQuoteId: providerQuoteId ?? this.providerQuoteId,
      swapFeeText: swapFeeText ?? this.swapFeeText,
      totalFeesText: totalFeesText ?? this.totalFeesText,
      realisedSlippageText: realisedSlippageText ?? this.realisedSlippageText,
      slippageToleranceText:
          slippageToleranceText ?? this.slippageToleranceText,
      priceProtectionText: priceProtectionText ?? this.priceProtectionText,
      minimumReceiveText: minimumReceiveText ?? this.minimumReceiveText,
      providerStatusRaw: providerStatusRaw ?? this.providerStatusRaw,
      nearIntentHash: nearIntentHash ?? this.nearIntentHash,
      originChainTxHash: originChainTxHash ?? this.originChainTxHash,
      destinationChainTxHash:
          destinationChainTxHash ?? this.destinationChainTxHash,
      providerRefundInfo: providerRefundInfo ?? this.providerRefundInfo,
      lastStatusCheckedAt: lastStatusCheckedAt ?? this.lastStatusCheckedAt,
      statusError: clearStatusError ? null : statusError ?? this.statusError,
      broadcastNotice: clearBroadcastNotice
          ? null
          : broadcastNotice ?? this.broadcastNotice,
      oneClickRecipient: oneClickRecipient ?? this.oneClickRecipient,
      oneClickRefundTo: oneClickRefundTo ?? this.oneClickRefundTo,
      depositDeadline: depositDeadline ?? this.depositDeadline,
      accountUuid: accountUuid ?? this.accountUuid,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      completedAt: completedAt ?? this.completedAt,
    );
  }
}

class SwapIntent {
  const SwapIntent({
    required this.id,
    required this.title,
    required this.pair,
    required this.sellAmount,
    required this.receiveEstimate,
    required this.provider,
    required this.status,
    required this.nextAction,
    required this.steps,
    required this.exposure,
    required this.receipt,
    this.sellAmountBaseUnits,
    this.direction,
    this.externalAsset,
    this.depositAddress,
    this.depositMemo,
    this.depositTxHash,
    this.providerQuoteId,
    this.swapFeeText,
    this.totalFeesText,
    this.realisedSlippageText,
    this.slippageToleranceText,
    this.priceProtectionText,
    this.minimumReceiveText,
    this.providerStatusRaw,
    this.nearIntentHash,
    this.originChainTxHash,
    this.destinationChainTxHash,
    this.providerRefundInfo,
    this.lastStatusCheckedAt,
    this.statusError,
    this.oneClickRecipient,
    this.oneClickRefundTo,
    this.depositDeadline,
    this.accountUuid,
    this.createdAt,
    this.updatedAt,
    this.completedAt,
    this.broadcastNotice,
  });

  final String id;
  final String title;
  final String pair;
  final String sellAmount;
  final String receiveEstimate;
  final String provider;
  final SwapIntentStatus status;
  final String nextAction;
  final List<SwapStep> steps;
  final List<SwapDetailField> exposure;
  final List<SwapDetailField> receipt;
  final BigInt? sellAmountBaseUnits;
  final SwapDirection? direction;
  final SwapAsset? externalAsset;
  final String? depositAddress;
  final String? depositMemo;
  final String? depositTxHash;
  final String? providerQuoteId;
  final String? swapFeeText;
  final String? totalFeesText;
  final String? realisedSlippageText;
  final String? slippageToleranceText;
  final String? priceProtectionText;
  final String? minimumReceiveText;
  final String? providerStatusRaw;
  final String? nearIntentHash;
  final String? originChainTxHash;
  final String? destinationChainTxHash;
  final SwapProviderRefundInfo? providerRefundInfo;
  final DateTime? lastStatusCheckedAt;
  final String? statusError;
  final String? oneClickRecipient;
  final String? oneClickRefundTo;
  final DateTime? depositDeadline;
  final String? accountUuid;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? completedAt;
  final String? broadcastNotice;

  String get statusLabel => status.label;

  SwapIntent copyWith({
    String? id,
    String? title,
    String? pair,
    String? sellAmount,
    String? receiveEstimate,
    String? provider,
    SwapIntentStatus? status,
    String? nextAction,
    List<SwapStep>? steps,
    List<SwapDetailField>? exposure,
    List<SwapDetailField>? receipt,
    BigInt? sellAmountBaseUnits,
    SwapDirection? direction,
    SwapAsset? externalAsset,
    String? depositAddress,
    String? depositMemo,
    String? depositTxHash,
    String? providerQuoteId,
    String? swapFeeText,
    String? totalFeesText,
    String? realisedSlippageText,
    String? slippageToleranceText,
    String? priceProtectionText,
    String? minimumReceiveText,
    String? providerStatusRaw,
    String? nearIntentHash,
    String? originChainTxHash,
    String? destinationChainTxHash,
    SwapProviderRefundInfo? providerRefundInfo,
    DateTime? lastStatusCheckedAt,
    String? statusError,
    String? oneClickRecipient,
    String? oneClickRefundTo,
    DateTime? depositDeadline,
    String? accountUuid,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? completedAt,
    String? broadcastNotice,
    bool clearStatusError = false,
    bool clearBroadcastNotice = false,
  }) {
    return SwapIntent(
      id: id ?? this.id,
      title: title ?? this.title,
      pair: pair ?? this.pair,
      sellAmount: sellAmount ?? this.sellAmount,
      receiveEstimate: receiveEstimate ?? this.receiveEstimate,
      provider: provider ?? this.provider,
      status: status ?? this.status,
      nextAction: nextAction ?? this.nextAction,
      steps: steps ?? this.steps,
      exposure: exposure ?? this.exposure,
      receipt: receipt ?? this.receipt,
      sellAmountBaseUnits: sellAmountBaseUnits ?? this.sellAmountBaseUnits,
      direction: direction ?? this.direction,
      externalAsset: externalAsset ?? this.externalAsset,
      depositAddress: depositAddress ?? this.depositAddress,
      depositMemo: depositMemo ?? this.depositMemo,
      depositTxHash: depositTxHash ?? this.depositTxHash,
      providerQuoteId: providerQuoteId ?? this.providerQuoteId,
      swapFeeText: swapFeeText ?? this.swapFeeText,
      totalFeesText: totalFeesText ?? this.totalFeesText,
      realisedSlippageText: realisedSlippageText ?? this.realisedSlippageText,
      slippageToleranceText:
          slippageToleranceText ?? this.slippageToleranceText,
      priceProtectionText: priceProtectionText ?? this.priceProtectionText,
      minimumReceiveText: minimumReceiveText ?? this.minimumReceiveText,
      providerStatusRaw: providerStatusRaw ?? this.providerStatusRaw,
      nearIntentHash: nearIntentHash ?? this.nearIntentHash,
      originChainTxHash: originChainTxHash ?? this.originChainTxHash,
      destinationChainTxHash:
          destinationChainTxHash ?? this.destinationChainTxHash,
      providerRefundInfo: providerRefundInfo ?? this.providerRefundInfo,
      lastStatusCheckedAt: lastStatusCheckedAt ?? this.lastStatusCheckedAt,
      statusError: clearStatusError ? null : statusError ?? this.statusError,
      oneClickRecipient: oneClickRecipient ?? this.oneClickRecipient,
      oneClickRefundTo: oneClickRefundTo ?? this.oneClickRefundTo,
      depositDeadline: depositDeadline ?? this.depositDeadline,
      accountUuid: accountUuid ?? this.accountUuid,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      completedAt: completedAt ?? this.completedAt,
      broadcastNotice: clearBroadcastNotice
          ? null
          : broadcastNotice ?? this.broadcastNotice,
    );
  }
}

extension SwapIntentIterable on Iterable<SwapIntent> {
  SwapIntent? swapIntentById(String? intentId) {
    if (intentId == null) return null;
    for (final intent in this) {
      if (intent.id == intentId) return intent;
    }
    return null;
  }

  List<SwapIntent> replaceSwapIntent(String intentId, SwapIntent updated) {
    return [
      for (final intent in this) intent.id == intentId ? updated : intent,
    ];
  }

  List<SwapIntent> reconcileRefreshedSwapIntents({
    required Iterable<SwapIntent> refreshedIntents,
    required Set<String> refreshedIds,
  }) {
    final refreshedById = {
      for (final intent in refreshedIntents)
        if (refreshedIds.contains(intent.id)) intent.id: intent,
    };
    return [
      for (final current in this)
        if (refreshedIds.contains(current.id))
          refreshedById[current.id] ?? current
        else
          current,
    ];
  }
}
