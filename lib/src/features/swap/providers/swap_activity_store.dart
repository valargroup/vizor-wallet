import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/app_secure_store.dart';
import '../../../core/storage/wallet_paths.dart';
import '../models/swap_prototype_models.dart';

const _swapActivityKey = 'zcash_swap_activities_v1';
const _swapActivityStorageVersion = 1;
const _swapActivityEncryptedStorageVersion = 2;
const _swapActivityRecordsKey = 'records';
const _swapActivityVersionKey = 'version';
const _swapActivityMetadataKeyPrefix = 'zcash_swap_activity_metadata_key_v1';
const _swapActivityEncryptionAlgorithm = 'AES-256-GCM-HKDF-SHA256';
const _swapActivityEncryptionInfo = 'vizor-swap-activity-metadata-v1';
const _swapActivityEncryptionKeyLength = 32;
const _swapActivitySaltLength = 32;
const _swapActivityNonceLength = 12;

String _swapActivityKeyFor(String accountUuid) =>
    '$_swapActivityKey:$accountUuid';

String _swapActivityMetadataKeyFor(String accountUuid) =>
    '$_swapActivityMetadataKeyPrefix:$accountUuid';

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
  AppSecureStoreSwapActivityStore(
    this._storage, {
    Future<Directory> Function()? supportDirectoryProvider,
  }) : _supportDirectoryProvider =
           supportDirectoryProvider ?? getWalletSupportDirectory;

  final AppSecureStore _storage;
  final Future<Directory> Function() _supportDirectoryProvider;

  @override
  Future<List<SwapIntentRecord>> loadRecords({
    required String accountUuid,
  }) async {
    final file = await _storageFileFor(accountUuid);
    if (await file.exists()) {
      final records = await _loadEncryptedRecords(file, accountUuid);
      if (records != null) return records;
    }

    final legacyRecords = await _loadLegacyRecords(accountUuid);
    if (legacyRecords == null) {
      return const [];
    }

    await saveRecords(accountUuid: accountUuid, records: legacyRecords);
    await _deleteLegacyRecordsBestEffort(accountUuid);
    return legacyRecords;
  }

  @override
  Future<void> saveRecords({
    required String accountUuid,
    required List<SwapIntentRecord> records,
  }) async {
    final clearText = jsonEncode({
      _swapActivityVersionKey: _swapActivityStorageVersion,
      _swapActivityRecordsKey: [
        for (final record in records)
          _recordToJson(record.copyWith(accountUuid: accountUuid)),
      ],
    });
    final encrypted = await _encryptStoragePayload(accountUuid, clearText);
    final file = await _storageFileFor(accountUuid);
    await file.parent.create(recursive: true);
    await file.writeAsString(encrypted, flush: true);
    await _deleteLegacyRecordsBestEffort(accountUuid);
  }

  Future<List<SwapIntentRecord>?> _loadEncryptedRecords(
    File file,
    String accountUuid,
  ) async {
    try {
      final clearText = await _decryptStoragePayload(
        accountUuid,
        await file.readAsString(),
      );
      final records = _recordItemsFromStorage(jsonDecode(clearText));
      return _recordsFromStorage(records, accountUuid);
    } on FormatException {
      return null;
    } on SecretBoxAuthenticationError {
      return null;
    }
  }

  Future<List<SwapIntentRecord>?> _loadLegacyRecords(String accountUuid) async {
    final raw = await _storage.readString(_swapActivityKeyFor(accountUuid));
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }
    try {
      final records = _recordItemsFromStorage(jsonDecode(raw));
      return _recordsFromStorage(records, accountUuid);
    } on FormatException {
      return null;
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

  Future<String> _encryptStoragePayload(
    String accountUuid,
    String clearText,
  ) async {
    final metadataKey = await _metadataKeyFor(accountUuid);
    final salt = _randomBytes(_swapActivitySaltLength);
    final nonce = _randomBytes(_swapActivityNonceLength);
    final secretKey = await _derivePayloadKey(metadataKey, salt);
    final secretBox = await AesGcm.with256bits().encrypt(
      utf8.encode(clearText),
      secretKey: secretKey,
      nonce: nonce,
    );
    return jsonEncode({
      _swapActivityVersionKey: _swapActivityEncryptedStorageVersion,
      'algorithm': _swapActivityEncryptionAlgorithm,
      'keyId': 'v1',
      'salt': base64Encode(salt),
      'nonce': base64Encode(secretBox.nonce),
      'cipherText': base64Encode(secretBox.cipherText),
      'mac': base64Encode(secretBox.mac.bytes),
    });
  }

  Future<String> _decryptStoragePayload(
    String accountUuid,
    String encryptedText,
  ) async {
    final decoded = jsonDecode(encryptedText);
    if (decoded is! Map) {
      throw const FormatException('Swap activity payload is not an object.');
    }
    if (decoded[_swapActivityVersionKey] !=
        _swapActivityEncryptedStorageVersion) {
      throw const FormatException(
        'Unsupported swap activity encryption version.',
      );
    }
    if (decoded['algorithm'] != _swapActivityEncryptionAlgorithm) {
      throw const FormatException('Unsupported swap activity encryption.');
    }

    final metadataKey = await _metadataKeyFor(accountUuid);
    final salt = _decodeBase64Field(decoded['salt'], 'salt');
    final nonce = _decodeBase64Field(decoded['nonce'], 'nonce');
    final cipherText = _decodeBase64Field(decoded['cipherText'], 'cipherText');
    final mac = _decodeBase64Field(decoded['mac'], 'mac');
    final secretKey = await _derivePayloadKey(metadataKey, salt);
    final clearBytes = await AesGcm.with256bits().decrypt(
      SecretBox(cipherText, nonce: nonce, mac: Mac(mac)),
      secretKey: secretKey,
    );
    return utf8.decode(clearBytes);
  }

  Future<SecretKey> _derivePayloadKey(List<int> metadataKey, List<int> salt) {
    return Hkdf(
      hmac: Hmac.sha256(),
      outputLength: _swapActivityEncryptionKeyLength,
    ).deriveKey(
      secretKey: SecretKey(metadataKey),
      nonce: salt,
      info: utf8.encode(_swapActivityEncryptionInfo),
    );
  }

  Future<List<int>> _metadataKeyFor(String accountUuid) async {
    final keyName = _swapActivityMetadataKeyFor(accountUuid);
    final existing = await _storage.readString(keyName);
    final decoded = _tryDecodeBase64(existing);
    if (decoded != null && decoded.length == _swapActivityEncryptionKeyLength) {
      return decoded;
    }

    final generated = _randomBytes(_swapActivityEncryptionKeyLength);
    await _storage.writeString(keyName, base64Encode(generated));
    return generated;
  }

  Future<File> _storageFileFor(String accountUuid) async {
    final supportDirectory = await _supportDirectoryProvider();
    final dir = Directory(
      '${supportDirectory.path}${Platform.pathSeparator}swap'
      '${Platform.pathSeparator}activity',
    );
    final accountHash = crypto.sha256
        .convert(utf8.encode(accountUuid))
        .toString();
    return File('${dir.path}${Platform.pathSeparator}$accountHash.json');
  }

  Future<void> _deleteLegacyRecordsBestEffort(String accountUuid) async {
    try {
      await _storage.delete(_swapActivityKeyFor(accountUuid));
    } on Object {
      // The encrypted file is already authoritative; a stale legacy secure
      // storage value should not make the save path fail.
    }
  }
}

List<int> _randomBytes(int length) {
  final random = Random.secure();
  return List<int>.generate(length, (_) => random.nextInt(256));
}

List<int> _decodeBase64Field(Object? value, String name) {
  if (value is! String) {
    throw FormatException('Missing swap activity encryption $name.');
  }
  try {
    return base64Decode(value);
  } on FormatException {
    throw FormatException('Invalid swap activity encryption $name.');
  }
}

List<int>? _tryDecodeBase64(String? value) {
  if (value == null || value.isEmpty) return null;
  try {
    return base64Decode(value);
  } on FormatException {
    return null;
  }
}

@visibleForTesting
String legacySwapActivityStorageKeyForTest(String accountUuid) =>
    _swapActivityKeyFor(accountUuid);

@visibleForTesting
String swapActivityMetadataKeyForTest(String accountUuid) =>
    _swapActivityMetadataKeyFor(accountUuid);

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
