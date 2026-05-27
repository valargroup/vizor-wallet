import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_intent_presentation_mapper.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_prototype_models.dart';

void main() {
  test('builds presentation rows from raw swap intent records', () {
    final intent = swapPrototypeIntentFromRecord(
      SwapIntentRecord(
        id: 'swap-record',
        providerLabel: 'NEAR Intents',
        pairText: 'ZEC -> USDC',
        sellAmountText: '0.0030 ZEC',
        receiveEstimateText: '0.21 USDC',
        status: SwapIntentStatus.processing,
        nextAction: 'Swap is processing',
        direction: SwapDirection.zecToExternal,
        externalAsset: SwapAsset.usdc,
        depositAddress: 't1deposit',
        depositTxHash: 'deposit-txid',
        providerQuoteId: 'quote-1',
        swapFeeText: 'Included in shown rate',
        totalFeesText: '0.00002 ZEC',
        realisedSlippageText: '0.000758 USDC (0.07%)',
        slippageToleranceText: '0.00003 ZEC (1.0%)',
        priceProtectionText: '0.0021 USDC (1.0%)',
        minimumReceiveText: '0.2079 USDC',
        providerStatusRaw: 'PROCESSING',
        providerRefundInfo: const SwapProviderRefundInfo(
          minimumDepositText: '0.0029 ZEC',
          refundFeeText: '0.0001 ZEC',
        ),
        broadcastNotice: 'local storage failed after broadcast',
        oneClickRecipient: '0xrecipient',
        oneClickRefundTo: 'u1refund',
      ),
    );

    expect(intent.title, 'ZEC to USDC');
    expect(intent.steps.map((step) => step.label), contains('Processing'));
    expect(intent.swapFeeText, 'Included in shown rate');
    expect(intent.totalFeesText, '0.00002 ZEC');
    expect(intent.realisedSlippageText, '0.000758 USDC (0.07%)');
    expect(intent.slippageToleranceText, '0.00003 ZEC (1.0%)');
    expect(intent.priceProtectionText, '0.0021 USDC (1.0%)');
    expect(intent.minimumReceiveText, '0.2079 USDC');
    expect(_receiptValue(intent, 'Deposit tx'), 'deposit-txid');
    expect(_receiptValue(intent, 'Provider status'), 'PROCESSING');
    expect(_receiptValue(intent, 'Minimum deposit'), '0.0029 ZEC');
    expect(_receiptValue(intent, 'Refund fee'), '0.0001 ZEC');
    expect(
      _receiptValue(intent, 'Broadcast status'),
      'local storage failed after broadcast',
    );
  });

  test('updates raw lifecycle facts from provider status snapshots', () {
    final createdAt = DateTime.utc(2026, 5, 7, 10);
    final checkedAt = DateTime.utc(2026, 5, 7, 10, 30);
    final intent = swapPrototypeIntentFromRecord(
      SwapIntentRecord(
        id: 'swap-record',
        providerLabel: 'NEAR Intents',
        pairText: 'ZEC -> USDC',
        sellAmountText: '0.0030 ZEC',
        receiveEstimateText: '0.21 USDC',
        status: SwapIntentStatus.processing,
        nextAction: 'Swap is processing',
        direction: SwapDirection.zecToExternal,
        externalAsset: SwapAsset.usdc,
        depositAddress: 't1deposit',
        createdAt: createdAt,
        updatedAt: createdAt,
      ),
    );

    final updated = updateSwapIntentFromSnapshot(
      intent,
      SwapIntentSnapshot(
        id: 'swap-record',
        providerLabel: 'NEAR Intents',
        pairText: 'ZEC -> USDC',
        sellAmountText: '0.0030 ZEC',
        receiveEstimateText: '0.21 USDC',
        status: SwapIntentStatus.complete,
        nextAction: 'Complete',
        depositInstruction: const SwapDepositInstruction(
          asset: SwapAsset.zec,
          address: 't1deposit',
          expiresInLabel: '2h',
          reuseWarning: 'Do not reuse',
        ),
        providerStatusRaw: 'SUCCESS',
        nearIntentHash: 'intent-hash',
        destinationChainTxHash: 'destination-txid',
        swapFeeText: 'Included in shown rate',
        totalFeesText: '0.00002 ZEC',
        realisedSlippageText: '0.000758 USDC (0.07%)',
        slippageToleranceText: '0.00003 ZEC (1.0%)',
        priceProtectionText: '0.0021 USDC (1.0%)',
        minimumReceiveText: '0.2079 USDC',
      ),
      updatedAt: checkedAt,
      lastStatusCheckedAt: checkedAt,
    );

    expect(updated.status, SwapIntentStatus.complete);
    expect(updated.providerStatusRaw, 'SUCCESS');
    expect(updated.nearIntentHash, 'intent-hash');
    expect(updated.destinationChainTxHash, 'destination-txid');
    expect(updated.swapFeeText, 'Included in shown rate');
    expect(updated.totalFeesText, '0.00002 ZEC');
    expect(updated.realisedSlippageText, '0.000758 USDC (0.07%)');
    expect(updated.slippageToleranceText, '0.00003 ZEC (1.0%)');
    expect(updated.priceProtectionText, '0.0021 USDC (1.0%)');
    expect(updated.minimumReceiveText, '0.2079 USDC');
    expect(updated.createdAt, createdAt);
    expect(updated.updatedAt, checkedAt);
    expect(updated.completedAt, checkedAt);
    expect(updated.lastStatusCheckedAt, checkedAt);
    expect(_receiptValue(updated, 'Provider status'), 'SUCCESS');
  });
}

String _receiptValue(SwapPrototypeIntent intent, String label) {
  return intent.receipt.where((field) => field.label == label).single.value;
}
