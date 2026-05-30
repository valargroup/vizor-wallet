import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/config/swap_feature_config.dart';
import 'package:zcash_wallet/src/providers/account_models.dart';

void main() {
  test('enables swap only for mainnet wallet networks', () {
    expect(isSwapFeatureEnabledForNetwork('main'), isTrue);
    expect(isSwapFeatureEnabledForNetwork('test'), isFalse);
    expect(isSwapFeatureEnabledForNetwork('regtest'), isFalse);
  });

  test('provider follows the bootstrapped wallet network', () {
    final cases = {'main': true, 'test': false, 'regtest': false};

    for (final entry in cases.entries) {
      final container = ProviderContainer(
        overrides: [
          appBootstrapProvider.overrideWithValue(_bootstrap(entry.key)),
        ],
      );
      addTearDown(container.dispose);

      expect(
        container.read(swapFeatureEnabledProvider),
        entry.value,
        reason: 'network=${entry.key}',
      );
    }
  });
}

AppBootstrapState _bootstrap(String network) {
  return AppBootstrapState(
    initialLocation: '/home',
    initialAccountState: AccountState(),
    initialSyncSnapshot: AppSyncSnapshot.empty,
    network: network,
    rpcEndpointConfig: defaultRpcEndpointConfig(network),
    themeMode: ThemeMode.system,
    privacyModeEnabled: false,
    isPasswordConfigured: false,
    isUnlocked: false,
    passwordRotationRecoveryFailed: false,
  );
}
