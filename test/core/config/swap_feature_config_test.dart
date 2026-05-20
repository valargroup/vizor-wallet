import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/config/swap_feature_config.dart';

void main() {
  test('enables swap only for mainnet builds', () {
    expect(isSwapFeatureEnabledForNetwork('main'), isTrue);
    expect(isSwapFeatureEnabledForNetwork('test'), isFalse);
    expect(isSwapFeatureEnabledForNetwork('regtest'), isFalse);
  });
}
