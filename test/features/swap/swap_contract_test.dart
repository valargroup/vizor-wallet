import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_models.dart';

void main() {
  test('blocks review when token amount exceeds asset decimals', () {
    const state = SwapState(
      direction: SwapDirection.zecToExternal,
      amountText: '',
      receiveAmountText: '105.1234567',
      destinationText: '0xrecipient',
      externalAsset: SwapAsset.usdc,
      reviewVisible: false,
      intents: [],
      quoteMode: SwapQuoteMode.exactOutput,
    );

    expect(
      state.quoteAmountPrecisionError,
      'USDC supports up to 6 decimal places.',
    );
    expect(state.canReviewQuote, isFalse);

    final valid = state.copyWith(receiveAmountText: '105.123456');

    expect(valid.quoteAmountPrecisionError, isNull);
    expect(valid.canReviewQuote, isTrue);
  });

  test(
    'formats protection amounts using token decimals before display floors',
    () {
      final sendZecQuote = SwapQuote.estimate(
        direction: SwapDirection.zecToExternal,
        externalAsset: SwapAsset.usdc,
        amount: 0.002,
        slippageBps: 50,
      );

      expect(sendZecQuote.slippageToleranceText, '0.00001 ZEC (0.5%)');

      final receiveZecQuote = SwapQuote.estimate(
        direction: SwapDirection.externalToZec,
        externalAsset: SwapAsset.usdc,
        amount: 0.1,
        externalPerZec: 50,
        slippageBps: 50,
      );

      expect(receiveZecQuote.slippageToleranceText, '0.0005 USDC (0.5%)');
      expect(receiveZecQuote.priceProtectionText, '0.00001 ZEC (0.5%)');

      final belowReadableEthQuote = SwapQuote.estimate(
        direction: SwapDirection.zecToExternal,
        externalAsset: SwapAsset.eth,
        amount: 0.0000001,
        slippageBps: 50,
      );

      expect(
        belowReadableEthQuote.priceProtectionText,
        '<0.00000001 ETH (0.5%)',
      );
      expect(belowReadableEthQuote.fiatValueBasis, isNull);
    },
  );
}
