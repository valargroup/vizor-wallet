import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/app_secure_store.dart';
import '../models/swap_prototype_models.dart';

const _swapDraftKey = 'zcash_swap_draft_v1';

final swapDraftStoreProvider = Provider<SwapDraftStore>((ref) {
  return AppSecureStoreSwapDraftStore(AppSecureStore.instance);
});

abstract interface class SwapDraftStore {
  Future<SwapDraftSnapshot?> loadDraft();

  Future<void> saveDraft(SwapDraftSnapshot draft);
}

class AppSecureStoreSwapDraftStore implements SwapDraftStore {
  const AppSecureStoreSwapDraftStore(this._storage);

  final AppSecureStore _storage;

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

int? _optionalInt(Object? value) {
  if (value is int) return value;
  if (value is String) return int.tryParse(value);
  return null;
}

T? _optionalEnumByName<T extends Enum>(List<T> values, Object? name) {
  if (name is! String) return null;
  for (final value in values) {
    if (value.name == name) return value;
  }
  return null;
}
