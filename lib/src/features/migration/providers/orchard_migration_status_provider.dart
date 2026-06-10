import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/wallet_paths.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/rpc_endpoint_provider.dart';
import '../../../providers/sync_provider.dart';
import '../../../rust/api/sync.dart' as rust_sync;
import '../models/migration_view_state.dart';

final activeOrchardMigrationStatusProvider =
    FutureProvider<rust_sync.MigrationStatus?>((ref) async {
      final accountState = ref.watch(accountProvider).value;
      final account = accountState?.activeAccount;
      final accountUuid = accountState?.activeAccountUuid;
      if (account == null || accountUuid == null || account.isHardware) {
        return null;
      }

      final endpoint = ref.watch(rpcEndpointProvider);

      // Reconcile after account scoped sync data changes. Rust is still the
      // source of truth; this watch only chooses when to ask it again.
      ref.watch(syncProvider);

      final dbPath = await getWalletDbPath();
      return rust_sync.getOrchardMigrationStatus(
        dbPath: dbPath,
        network: endpoint.walletNetworkName,
        accountUuid: accountUuid,
      );
    });

final hasActiveOrchardMigrationRunProvider = Provider<bool>((ref) {
  final status = ref.watch(activeOrchardMigrationStatusProvider).value;
  final viewState = migrationViewStateFromRustPhase(status?.phase);
  return viewState?.hasActiveRun ?? false;
});

final migrationBlocksSendProvider = Provider<bool>((ref) {
  final statusAsync = ref.watch(activeOrchardMigrationStatusProvider);
  if (statusAsync.isLoading || statusAsync.hasError) return true;
  final viewState = migrationViewStateFromRustPhase(statusAsync.value?.phase);
  return viewState?.hasActiveRun ?? false;
});
