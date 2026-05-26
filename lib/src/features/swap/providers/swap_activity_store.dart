import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/app_secure_store.dart';
import '../models/swap_prototype_models.dart';

const _swapActivityKey = 'zcash_swap_activities_v1';
const _swapActivityStorageVersion = 1;
const _swapActivityRecordsKey = 'records';
const _swapActivityVersionKey = 'version';

String _swapActivityKeyFor(String accountUuid) =>
    '$_swapActivityKey:$accountUuid';

final swapActivityStoreProvider = Provider<SwapActivityStore>((ref) {
  return AppSecureStoreSwapActivityStore(AppSecureStore.instance);
});

class SwapActivityRecordsRevisionNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void bump() {
    state++;
  }
}

final swapActivityRecordsRevisionProvider =
    NotifierProvider<SwapActivityRecordsRevisionNotifier, int>(
      SwapActivityRecordsRevisionNotifier.new,
    );

final swapActivityRecordsProvider =
    FutureProvider.family<List<SwapIntentRecord>, String>((ref, accountUuid) {
      ref.watch(swapActivityRecordsRevisionProvider);
      return ref
          .read(swapActivityStoreProvider)
          .loadRecords(accountUuid: accountUuid);
    });

final swapPendingIntentCountProvider = FutureProvider.family<int, String>((
  ref,
  accountUuid,
) async {
  final records = await ref.watch(
    swapActivityRecordsProvider(accountUuid).future,
  );
  return records.where((record) => !record.status.isTerminal).length;
});

abstract interface class SwapActivityStore {
  Future<List<SwapIntentRecord>> loadRecords({required String accountUuid});

  Future<void> saveRecords({
    required String accountUuid,
    required List<SwapIntentRecord> records,
  });
}

class AppSecureStoreSwapActivityStore implements SwapActivityStore {
  const AppSecureStoreSwapActivityStore(this._storage);

  final AppSecureStore _storage;

  @override
  Future<List<SwapIntentRecord>> loadRecords({
    required String accountUuid,
  }) async {
    final raw = await _storage.readString(_swapActivityKeyFor(accountUuid));
    if (raw == null || raw.trim().isEmpty) {
      return const [];
    }
    try {
      final records = _recordItemsFromStorage(jsonDecode(raw));
      return _recordsFromStorage(records, accountUuid) ?? const [];
    } on FormatException {
      return const [];
    }
  }

  List<SwapIntentRecord>? _recordsFromStorage(
    List<Object?>? records,
    String accountUuid,
  ) {
    if (records == null) {
      return null;
    }
    return [
      for (final item in records)
        if (item is Map<String, dynamic>)
          _recordFromJson(item).copyWith(accountUuid: accountUuid),
    ];
  }

  @override
  Future<void> saveRecords({
    required String accountUuid,
    required List<SwapIntentRecord> records,
  }) async {
    await _storage.writeString(
      _swapActivityKeyFor(accountUuid),
      jsonEncode({
        _swapActivityVersionKey: _swapActivityStorageVersion,
        _swapActivityRecordsKey: [
          for (final record in records)
            _recordToJson(record.copyWith(accountUuid: accountUuid)),
        ],
      }),
    );
  }
}

@visibleForTesting
String swapActivityStorageKeyForTest(String accountUuid) =>
    _swapActivityKeyFor(accountUuid);

List<Object?>? _recordItemsFromStorage(Object? decoded) {
  if (decoded is List) {
    return decoded;
  }
  if (decoded is Map) {
    final version = decoded[_swapActivityVersionKey];
    if (version is int && version > _swapActivityStorageVersion) {
      return null;
    }
    final records = decoded[_swapActivityRecordsKey];
    if (records is List) {
      return records;
    }
  }
  return null;
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
    'lastStatusCheckedAt': record.lastStatusCheckedAt
        ?.toUtc()
        .toIso8601String(),
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
