import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

import '../main.dart' show log;
import 'providers/account_models.dart';
import 'rust/api/wallet.dart' as rust_wallet;

const _accountsKey = 'zcash_accounts';
const _activeAccountKey = 'zcash_active_account';
const _networkKey = 'zcash_wallet_network';

final appBootstrapProvider = Provider<AppBootstrapState>((_) {
  throw StateError('appBootstrapProvider must be overridden in main()');
});

class AppBootstrapState {
  const AppBootstrapState({
    required this.initialLocation,
    required this.initialAccountState,
    required this.network,
  });

  final String initialLocation;
  final AccountState initialAccountState;
  final String network;

  bool get hasWallet => initialAccountState.hasAccounts;

  static const empty = AppBootstrapState(
    initialLocation: '/welcome',
    initialAccountState: AccountState(),
    network: 'main',
  );
}

Future<AppBootstrapState> loadAppBootstrap() async {
  const storage = FlutterSecureStorage();

  try {
    log('bootstrap: loading startup snapshot');
    final network = await storage.read(key: _networkKey) ?? 'main';
    final dbPath = await _getDbPath();
    final storedAccounts = await _readStoredAccounts(storage);
    final storedActiveUuid = await storage.read(key: _activeAccountKey);

    var rustAccounts = <AccountInfo>[];
    final rustAddressesByUuid = <String, String>{};
    if (rust_wallet.walletExists(dbPath: dbPath)) {
      try {
        final listed = await rust_wallet.listAccounts(
          dbPath: dbPath,
          network: network,
        );
        rustAccounts = await Future.wait(
          listed.indexed.map((entry) async {
            final (index, account) = entry;
            rustAddressesByUuid[account.uuid] = account.unifiedAddress;
            final mnemonic = await storage.read(
              key: 'zcash_account_mnemonic_${account.uuid}',
            );
            return AccountInfo(
              uuid: account.uuid,
              name: account.name,
              order: index,
              isHardware: mnemonic == null,
            );
          }),
        );
        log('bootstrap: rust accounts=${rustAccounts.length}');
      } catch (e) {
        log('bootstrap: failed to list Rust accounts: $e');
      }
    }

    final accounts = rustAccounts.isNotEmpty ? rustAccounts : storedAccounts;
    final activeAccountUuid = _resolveActiveUuid(storedActiveUuid, accounts);
    final activeAddress = activeAccountUuid == null
        ? null
        : rustAddressesByUuid[activeAccountUuid];
    final hasWallet = accounts.isNotEmpty;

    log(
      'bootstrap: hasWallet=$hasWallet, initialLocation=${hasWallet ? '/home' : '/welcome'}',
    );

    return AppBootstrapState(
      initialLocation: hasWallet ? '/home' : '/welcome',
      initialAccountState: AccountState(
        accounts: accounts,
        activeAccountUuid: activeAccountUuid,
        activeAddress: activeAddress,
      ),
      network: network,
    );
  } catch (e) {
    log('bootstrap: failed, falling back to welcome: $e');
    return AppBootstrapState.empty;
  }
}

Future<List<AccountInfo>> _readStoredAccounts(
  FlutterSecureStorage storage,
) async {
  final accountsJson = await storage.read(key: _accountsKey);
  if (accountsJson == null || accountsJson.isEmpty) return const [];

  final List<dynamic> decoded = jsonDecode(accountsJson);
  return decoded
      .map((e) => AccountInfo.fromJson(e as Map<String, dynamic>))
      .toList();
}

String? _resolveActiveUuid(
  String? storedActiveUuid,
  List<AccountInfo> accounts,
) {
  if (accounts.isEmpty) return null;
  if (storedActiveUuid != null &&
      accounts.any((account) => account.uuid == storedActiveUuid)) {
    return storedActiveUuid;
  }
  return accounts.first.uuid;
}

Future<String> _getDbPath() async {
  final dir = await getApplicationDocumentsDirectory();
  return '${dir.path}${Platform.pathSeparator}zcash_wallet.db';
}
