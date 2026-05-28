import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_bootstrap.dart';
import 'network_config.dart';

final swapFeatureEnabledProvider = Provider<bool>((ref) {
  final networkName = ref.watch(appBootstrapProvider).network;
  return isSwapFeatureEnabledForNetwork(networkName);
});

bool isSwapFeatureEnabledForNetwork(String networkName) {
  return zcashNetworkFromName(networkName) == ZcashNetwork.mainnet;
}
