import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'network_config.dart';

final swapFeatureEnabledProvider = Provider<bool>((ref) {
  return isSwapFeatureEnabledForNetwork(kZcashDefaultNetworkName);
});

bool isSwapFeatureEnabledForNetwork(String networkName) {
  return zcashNetworkFromName(networkName) == ZcashNetwork.mainnet;
}
