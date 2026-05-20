import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/config/swap_feature_config.dart';
import 'package:zcash_wallet/src/features/home/screens/home_screen.dart';
import 'package:zcash_wallet/src/features/swap/screens/swap_screen.dart';
import 'package:zcash_wallet/src/providers/account_models.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';

import 'fakes/fake_sync_notifier.dart';

void main() {
  testWidgets('disabled swap route redirects to home', (tester) async {
    await tester.pumpWidget(_appHarness('/swap', swapEnabled: false));
    await tester.pumpAndSettle();

    expect(find.byType(SwapScreen), findsNothing);
    expect(find.byType(HomeScreen), findsOneWidget);
  });
}

Widget _appHarness(String initialLocation, {required bool swapEnabled}) {
  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(_bootstrap(initialLocation)),
      syncProvider.overrideWith(FakeSyncNotifier.new),
      swapFeatureEnabledProvider.overrideWithValue(swapEnabled),
    ],
    child: const ZcashWalletApp(),
  );
}

AppBootstrapState _bootstrap(String initialLocation) {
  return AppBootstrapState(
    initialLocation: initialLocation,
    initialAccountState: const AccountState(
      accounts: [AccountInfo(uuid: 'account-1', name: 'Account 1', order: 0)],
      activeAccountUuid: 'account-1',
      activeAddress: 'u1testaddress',
    ),
    initialSyncSnapshot: AppSyncSnapshot.empty,
    network: 'main',
    rpcEndpointConfig: defaultRpcEndpointConfig('main'),
    themeMode: ThemeMode.system,
    privacyModeEnabled: false,
    isPasswordConfigured: true,
    isUnlocked: true,
    passwordRotationRecoveryFailed: false,
  );
}
