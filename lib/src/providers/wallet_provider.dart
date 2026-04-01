import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

import '../../main.dart' show log;
import '../core/config/network_config.dart';
import '../rust/api/wallet.dart' as rust_wallet;

const _mnemonicKey = 'zcash_wallet_mnemonic';
const _networkKey = 'zcash_wallet_network';

class WalletState {
  final bool hasWallet;
  final String? unifiedAddress;
  final String? network;

  const WalletState({
    this.hasWallet = false,
    this.unifiedAddress,
    this.network,
  });

  WalletState copyWith({
    bool? hasWallet,
    String? unifiedAddress,
    String? network,
  }) =>
      WalletState(
        hasWallet: hasWallet ?? this.hasWallet,
        unifiedAddress: unifiedAddress ?? this.unifiedAddress,
        network: network ?? this.network,
      );
}

class WalletNotifier extends AsyncNotifier<WalletState> {
  static const _storage = FlutterSecureStorage();

  @override
  Future<WalletState> build() async {
    log('WalletNotifier.build: starting');
    final dbPath = await _getDbPath();
    log('WalletNotifier.build: dbPath=$dbPath');
    final exists = rust_wallet.walletExists(dbPath: dbPath);
    log('WalletNotifier.build: walletExists=$exists');
    if (!exists) {
      log('WalletNotifier.build: no wallet found, returning empty state');
      return const WalletState();
    }

    final network = await _storage.read(key: _networkKey) ?? 'main';
    log('WalletNotifier.build: network=$network');
    try {
      final address = await rust_wallet.getUnifiedAddress(
        dbPath: dbPath,
        network: network,
      );
      log('WalletNotifier.build: address=${address.substring(0, 20)}...');
      return WalletState(
        hasWallet: true,
        unifiedAddress: address,
        network: network,
      );
    } catch (e) {
      log('WalletNotifier.build: ERROR getting address: $e');
      return const WalletState();
    }
  }

  /// Create a new wallet. Returns the mnemonic that must be shown to the user.
  Future<String> createWallet({String network = 'main'}) async {
    log('createWallet: starting, network=$network');
    final dbPath = await _getDbPath();
    log('createWallet: dbPath=$dbPath');
    await _deleteExistingDb(dbPath);
    try {
      // Fetch chain tip as birthday so new wallets don't full-scan
      final networkConfig = network == 'main' ? ZcashNetwork.mainnet : ZcashNetwork.testnet;
      final birthday = await rust_wallet.getLatestBlockHeight(
        lightwalletdUrl: networkConfig.lightwalletdUrl,
      );
      log('createWallet: birthday=$birthday');

      final result = await rust_wallet.createWallet(
        network: network,
        dbPath: dbPath,
        birthdayHeight: birthday,
      );
      log('createWallet: success, address=${result.unifiedAddress.substring(0, 20)}...');

      await _storage.write(key: _mnemonicKey, value: result.mnemonic);
      await _storage.write(key: _networkKey, value: network);
      log('createWallet: mnemonic and network saved to secure storage');

      state = AsyncData(WalletState(
        hasWallet: true,
        unifiedAddress: result.unifiedAddress,
        network: network,
      ));

      return result.mnemonic;
    } catch (e, st) {
      log('createWallet: ERROR: $e\n$st');
      rethrow;
    }
  }

  /// Import a wallet from an existing mnemonic.
  Future<void> importWallet({
    required String mnemonic,
    int? birthdayHeight,
    String network = 'main',
  }) async {
    log('importWallet: starting, network=$network, birthdayHeight=$birthdayHeight');
    log('importWallet: mnemonic word count=${mnemonic.trim().split(' ').length}');
    final dbPath = await _getDbPath();
    log('importWallet: dbPath=$dbPath');
    await _deleteExistingDb(dbPath);
    try {
      final result = await rust_wallet.importWallet(
        mnemonic: mnemonic,
        birthdayHeight:
            birthdayHeight != null ? BigInt.from(birthdayHeight) : null,
        network: network,
        dbPath: dbPath,
      );
      log('importWallet: success, address=${result.unifiedAddress.substring(0, 20)}...');

      await _storage.write(key: _mnemonicKey, value: mnemonic);
      await _storage.write(key: _networkKey, value: network);
      log('importWallet: saved to secure storage');

      state = AsyncData(WalletState(
        hasWallet: true,
        unifiedAddress: result.unifiedAddress,
        network: network,
      ));
      log('importWallet: state updated');
    } catch (e, st) {
      log('importWallet: ERROR: $e\n$st');
      rethrow;
    }
  }

  Future<String> _getDbPath() async {
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}${Platform.pathSeparator}zcash_wallet.db';
  }

  Future<void> _deleteExistingDb(String dbPath) async {
    final file = File(dbPath);
    if (file.existsSync()) {
      log('_deleteExistingDb: removing existing DB at $dbPath');
      file.deleteSync();
    }
    // Also remove SQLite journal/wal files
    for (final suffix in ['-journal', '-wal', '-shm']) {
      final f = File('$dbPath$suffix');
      if (f.existsSync()) f.deleteSync();
    }
  }
}

final walletProvider =
    AsyncNotifierProvider<WalletNotifier, WalletState>(WalletNotifier.new);
