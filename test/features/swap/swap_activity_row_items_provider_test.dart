import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/activity/swap_activity_row_items_provider.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_models.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_activity_store.dart';

void main() {
  test('exposes persisted swap records as activity row items', () async {
    final updatedAt = DateTime.utc(2026, 5, 7, 10, 30);
    final store = _FakeSwapActivityStore({
      'account-1': [
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
          depositTxHash: 'zec-deposit-txid',
          updatedAt: updatedAt,
        ),
      ],
    });
    final container = ProviderContainer(
      overrides: [swapActivityStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);

    final items = await container.read(
      swapActivityRowItemsProvider('account-1').future,
    );

    expect(items, hasLength(1));
    expect(items.single.intentId, 'swap-record');
    expect(items.single.providerLabel, 'NEAR Intents');
    expect(items.single.sellAmountText, '0.0030 ZEC');
    expect(items.single.receiveEstimateText, '0.21 USDC');
    expect(items.single.status, SwapIntentStatus.processing);
    expect(items.single.direction, SwapDirection.zecToExternal);
    expect(items.single.externalAsset, SwapAsset.usdc);
    expect(items.single.depositTxHash, 'zec-deposit-txid');
    expect(items.single.activityTimestamp, updatedAt);
  });
}

class _FakeSwapActivityStore implements SwapActivityStore {
  const _FakeSwapActivityStore(this.recordsByAccount);

  final Map<String, List<SwapIntentRecord>> recordsByAccount;

  @override
  Future<List<SwapIntentRecord>> loadRecords({
    required String accountUuid,
  }) async {
    return recordsByAccount[accountUuid] ?? const [];
  }

  @override
  Future<void> saveRecords({
    required String accountUuid,
    required List<SwapIntentRecord> records,
  }) async {
    throw UnsupportedError('saveRecords is not used by this test');
  }
}
