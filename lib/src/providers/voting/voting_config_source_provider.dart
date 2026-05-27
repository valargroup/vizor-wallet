import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/app_secure_store.dart';
import '../../services/voting/voting_config_loader.dart';

class VotingConfigSourceState {
  const VotingConfigSourceState({
    required this.sourceUrl,
    required this.isDefault,
  });

  factory VotingConfigSourceState.defaultSource() {
    return const VotingConfigSourceState(
      sourceUrl: kDefaultStaticVotingConfigSource,
      isDefault: true,
    );
  }

  final String sourceUrl;
  final bool isDefault;

  StaticVotingConfigSource get staticConfigSource =>
      StaticVotingConfigSource.parse(sourceUrl);
}

abstract interface class VotingConfigSourceStore {
  Future<String?> readSourceUrl();

  Future<void> writeSourceUrl(String sourceUrl);

  Future<void> resetSourceUrl();
}

final votingConfigSourceStoreProvider = Provider<VotingConfigSourceStore>((
  ref,
) {
  return AppSecureStoreVotingConfigSourceStore(AppSecureStore.instance);
});

class AppSecureStoreVotingConfigSourceStore implements VotingConfigSourceStore {
  const AppSecureStoreVotingConfigSourceStore(this._store);

  final AppSecureStore _store;

  @override
  Future<String?> readSourceUrl() {
    return _store.readPlain(kVotingConfigSourceKey);
  }

  @override
  Future<void> writeSourceUrl(String sourceUrl) {
    return _store.writePlain(kVotingConfigSourceKey, sourceUrl);
  }

  @override
  Future<void> resetSourceUrl() {
    return _store.delete(kVotingConfigSourceKey);
  }
}

class VotingConfigSourceNotifier
    extends AsyncNotifier<VotingConfigSourceState> {
  @override
  Future<VotingConfigSourceState> build() async {
    final stored = await ref
        .read(votingConfigSourceStoreProvider)
        .readSourceUrl();
    final trimmed = stored?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return VotingConfigSourceState.defaultSource();
    }
    return VotingConfigSourceState(sourceUrl: trimmed, isDefault: false);
  }

  Future<void> setCustom(String sourceUrl) async {
    final trimmed = sourceUrl.trim();
    StaticVotingConfigSource.parse(trimmed);
    await ref.read(votingConfigSourceStoreProvider).writeSourceUrl(trimmed);
    state = AsyncData(
      VotingConfigSourceState(sourceUrl: trimmed, isDefault: false),
    );
  }

  Future<void> resetDefault() async {
    await ref.read(votingConfigSourceStoreProvider).resetSourceUrl();
    state = AsyncData(VotingConfigSourceState.defaultSource());
  }
}

final votingConfigSourceProvider =
    AsyncNotifierProvider<VotingConfigSourceNotifier, VotingConfigSourceState>(
      VotingConfigSourceNotifier.new,
    );
