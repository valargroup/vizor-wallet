import '../../../core/storage/app_secure_store.dart';
import '../models/migration_demo_state.dart';

/// Persists the migration demo state per account in plain (non-secret) storage.
class MigrationDemoStore {
  MigrationDemoStore({AppSecureStore? store})
      : _store = store ?? AppSecureStore.instance;

  final AppSecureStore _store;

  static const _prefix = 'vizor_migration_demo_state_';
  static String _key(String accountUuid) => '$_prefix$accountUuid';

  Future<MigrationDemoState?> read(String accountUuid) async {
    final raw = await _store.readPlain(_key(accountUuid));
    if (raw == null || raw.isEmpty) return null;
    try {
      return MigrationDemoState.decode(raw);
    } catch (_) {
      await clear(accountUuid);
      return null;
    }
  }

  Future<void> write(MigrationDemoState state) =>
      _store.writePlain(_key(state.accountUuid), state.encode());

  Future<void> clear(String accountUuid) =>
      _store.deletePlainKeysWithPrefix(_key(accountUuid));
}
