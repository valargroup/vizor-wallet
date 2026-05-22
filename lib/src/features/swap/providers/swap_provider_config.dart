import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/near_intents_one_click_swap_provider.dart';
import '../models/swap_prototype_models.dart';

const _oneClickBaseUrl = String.fromEnvironment(
  'ZCASH_SWAP_1CLICK_BASE_URL',
  defaultValue: 'https://config-lambda.keplr.app/api/near-intents/1click',
);

final swapIntentProvider = Provider<SwapProvider>((ref) {
  return NearIntentsOneClickSwapProvider(
    baseUri: Uri.parse(_oneClickBaseUrl),
    referral: 'vizor',
  );
});

final swapStatusPollIntervalProvider = Provider<Duration>((ref) {
  return const Duration(seconds: 20);
});

final swapPriceRefreshIntervalProvider = Provider<Duration>((ref) {
  return const Duration(seconds: 30);
});

final swapPreviewQuoteDebounceProvider = Provider<Duration>((ref) {
  return const Duration(milliseconds: 500);
});

const _liveFundsEnabled = bool.fromEnvironment(
  'ZCASH_SWAP_ENABLE_LIVE_FUNDS',
  defaultValue: true,
);

final swapLiveFundsEnabledProvider = Provider<bool>((ref) {
  return _liveFundsEnabled;
});
