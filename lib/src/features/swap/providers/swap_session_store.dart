import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/app_secure_store.dart';
import '../models/swap_intent_presentation_mapper.dart';
import '../models/swap_prototype_models.dart';

const _swapSessionsKey = 'zcash_swap_sessions_v1';
const _swapDraftKey = 'zcash_swap_draft_v1';

String _swapSessionsKeyFor(String accountUuid) =>
    '$_swapSessionsKey:$accountUuid';

final swapSessionStoreProvider = Provider<SwapSessionStore>((ref) {
  return AppSecureStoreSwapSessionStore(AppSecureStore.instance);
});

final swapPendingIntentCountProvider = FutureProvider.family<int, String>((
  ref,
  accountUuid,
) async {
  final intents = await ref
      .read(swapSessionStoreProvider)
      .loadIntents(accountUuid: accountUuid);
  return intents.where((intent) => !intent.status.isTerminal).length;
});

abstract interface class SwapSessionStore {
  Future<List<SwapPrototypeIntent>> loadIntents({required String accountUuid});

  Future<void> saveIntents({
    required String accountUuid,
    required List<SwapPrototypeIntent> intents,
  });

  Future<SwapDraftSnapshot?> loadDraft();

  Future<void> saveDraft(SwapDraftSnapshot draft);
}

class AppSecureStoreSwapSessionStore implements SwapSessionStore {
  const AppSecureStoreSwapSessionStore(this._storage);

  final AppSecureStore _storage;

  @override
  Future<List<SwapPrototypeIntent>> loadIntents({
    required String accountUuid,
  }) async {
    final raw = await _storage.readString(_swapSessionsKeyFor(accountUuid));
    if (raw == null || raw.trim().isEmpty) {
      return const [];
    }
    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      return const [];
    }
    return [
      for (final item in decoded)
        if (item is Map<String, dynamic>)
          swapPrototypeIntentFromRecord(
            _recordFromJson(item).copyWith(accountUuid: accountUuid),
          ),
    ];
  }

  @override
  Future<void> saveIntents({
    required String accountUuid,
    required List<SwapPrototypeIntent> intents,
  }) async {
    await _storage.writeString(
      _swapSessionsKeyFor(accountUuid),
      jsonEncode([
        for (final intent in intents)
          _recordToJson(
            SwapIntentRecord.fromIntent(
              intent.copyWith(accountUuid: accountUuid),
            ),
          ),
      ]),
    );
  }

  @override
  Future<SwapDraftSnapshot?> loadDraft() async {
    final raw = await _storage.readString(_swapDraftKey);
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      return null;
    }
    return _draftFromJson(decoded);
  }

  @override
  Future<void> saveDraft(SwapDraftSnapshot draft) async {
    await _storage.writeString(_swapDraftKey, jsonEncode(_draftToJson(draft)));
  }
}

Map<String, Object?> _draftToJson(SwapDraftSnapshot draft) {
  return {
    'direction': draft.direction.name,
    'externalAsset': draft.externalAsset.toPersistedJson(),
    'slippageBps': draft.slippageBps,
  };
}

SwapDraftSnapshot? _draftFromJson(Map<String, dynamic> json) {
  final direction = _optionalEnumByName(
    SwapDirection.values,
    json['direction'],
  );
  final externalAsset = SwapAsset.fromPersistedJson(json['externalAsset']);
  if (direction == null || externalAsset == null) return null;
  if (externalAsset == SwapAsset.zec) return null;
  final slippageBps = _optionalInt(json['slippageBps'])?.clamp(10, 500).toInt();
  return SwapDraftSnapshot(
    direction: direction,
    externalAsset: externalAsset,
    slippageBps: slippageBps ?? defaultSwapSlippageBps,
  );
}

Map<String, Object?> _recordToJson(SwapIntentRecord record) {
  return {
    'id': record.id,
    'provider': record.providerLabel,
    'pair': record.pairText,
    'sellAmount': record.sellAmountText,
    'receiveEstimate': record.receiveEstimateText,
    'status': record.status.name,
    'nextAction': record.nextAction,
    'direction': record.direction?.name,
    'externalAsset': record.externalAsset?.toPersistedJson(),
    'depositAddress': record.depositAddress,
    'depositMemo': record.depositMemo,
    'depositTxHash': record.depositTxHash,
    'providerQuoteId': record.providerQuoteId,
    'providerSignature': record.providerSignature,
    'providerStatusRaw': record.providerStatusRaw,
    'nearIntentHash': record.nearIntentHash,
    'nearTransactionHash': record.nearTransactionHash,
    'originChainTxHash': record.originChainTxHash,
    'destinationChainTxHash': record.destinationChainTxHash,
    'providerRefundInfo': _providerRefundInfoToJson(record.providerRefundInfo),
    'lastStatusCheckedAt':
        record.lastStatusCheckedAt?.toUtc().toIso8601String(),
    'statusError': record.statusError,
    'broadcastNotice': record.broadcastNotice,
    'oneClickRecipient': record.oneClickRecipient,
    'oneClickRefundTo': record.oneClickRefundTo,
    'depositDeadline': record.depositDeadline?.toUtc().toIso8601String(),
    'accountUuid': record.accountUuid,
    'createdAt': record.createdAt?.toUtc().toIso8601String(),
    'updatedAt': record.updatedAt?.toUtc().toIso8601String(),
    'completedAt': record.completedAt?.toUtc().toIso8601String(),
  };
}

SwapIntentRecord _recordFromJson(Map<String, dynamic> json) {
  return SwapIntentRecord(
    id: _string(json['id']),
    pairText: _string(json['pair']),
    sellAmountText: _string(json['sellAmount']),
    receiveEstimateText: _string(json['receiveEstimate']),
    providerLabel: _string(json['provider']),
    status: _enumByName(
      SwapIntentStatus.values,
      json['status'],
      SwapIntentStatus.processing,
    ),
    nextAction: _string(json['nextAction']),
    direction: _optionalEnumByName(SwapDirection.values, json['direction']),
    externalAsset: SwapAsset.fromPersistedJson(json['externalAsset']),
    depositAddress: _optionalString(json['depositAddress']),
    depositMemo: _optionalString(json['depositMemo']),
    depositTxHash: _optionalString(json['depositTxHash']),
    providerQuoteId: _optionalString(json['providerQuoteId']),
    providerSignature: _optionalString(json['providerSignature']),
    providerStatusRaw: _optionalString(json['providerStatusRaw']),
    nearIntentHash: _optionalString(json['nearIntentHash']),
    nearTransactionHash: _optionalString(json['nearTransactionHash']),
    originChainTxHash: _optionalString(json['originChainTxHash']),
    destinationChainTxHash: _optionalString(json['destinationChainTxHash']),
    providerRefundInfo: _providerRefundInfoFromJson(json['providerRefundInfo']),
    lastStatusCheckedAt: _optionalDateTime(json['lastStatusCheckedAt']),
    statusError: _optionalString(json['statusError']),
    broadcastNotice: _optionalString(json['broadcastNotice']),
    oneClickRecipient: _optionalString(json['oneClickRecipient']),
    oneClickRefundTo: _optionalString(json['oneClickRefundTo']),
    depositDeadline: _optionalDateTime(json['depositDeadline']),
    accountUuid: _optionalString(json['accountUuid']),
    createdAt: _optionalDateTime(json['createdAt']),
    updatedAt: _optionalDateTime(json['updatedAt']),
    completedAt: _optionalDateTime(json['completedAt']),
  );
}

Map<String, Object?>? _providerRefundInfoToJson(SwapProviderRefundInfo? info) {
  if (info == null || !info.hasAny) return null;
  return {
    'minimumDepositText': info.minimumDepositText,
    'refundFeeText': info.refundFeeText,
    'depositedAmountText': info.depositedAmountText,
    'refundedAmountText': info.refundedAmountText,
    'refundReason': info.refundReason,
  };
}

SwapProviderRefundInfo? _providerRefundInfoFromJson(Object? value) {
  if (value is! Map) return null;
  final info = SwapProviderRefundInfo(
    minimumDepositText: _optionalString(value['minimumDepositText']),
    refundFeeText: _optionalString(value['refundFeeText']),
    depositedAmountText: _optionalString(value['depositedAmountText']),
    refundedAmountText: _optionalString(value['refundedAmountText']),
    refundReason: _optionalString(value['refundReason']),
  );
  return info.hasAny ? info : null;
}

String _string(Object? value) => value is String ? value : '';

String? _optionalString(Object? value) => value is String ? value : null;

DateTime? _optionalDateTime(Object? value) {
  if (value is! String) return null;
  return DateTime.tryParse(value)?.toUtc();
}

int? _optionalInt(Object? value) {
  if (value is int) return value;
  if (value is String) return int.tryParse(value);
  return null;
}

T _enumByName<T extends Enum>(List<T> values, Object? name, T fallback) {
  final parsed = _optionalEnumByName(values, name);
  return parsed ?? fallback;
}

T? _optionalEnumByName<T extends Enum>(List<T> values, Object? name) {
  if (name is! String) return null;
  for (final value in values) {
    if (value.name == name) return value;
  }
  return null;
}
