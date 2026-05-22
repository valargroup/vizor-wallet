import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_prototype_models.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_activity_store.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_activity_tracker.dart';

void main() {
  test('refreshes every open activity for the active account', () async {
    final store = _MemorySwapActivityStore();
    final provider = _StatusSwapProvider({
      'deposit-a': _snapshot(
        id: 'swap-a',
        depositAddress: 'deposit-a',
        status: SwapIntentStatus.processing,
      ),
      'deposit-b': _snapshot(
        id: 'swap-b',
        depositAddress: 'deposit-b',
        status: SwapIntentStatus.complete,
      ),
    });
    final tracker = SwapActivityTracker(
      activityStore: store,
      swapProvider: provider,
    );
    final persistedIntents = [
      _intent(id: 'swap-a', depositAddress: 'deposit-a'),
      _intent(
        id: 'swap-b',
        depositAddress: 'deposit-b',
        status: SwapIntentStatus.depositObserved,
      ),
      _intent(
        id: 'swap-c',
        depositAddress: 'deposit-c',
        status: SwapIntentStatus.complete,
      ),
    ];
    store.savedRecords = [
      for (final intent in persistedIntents) SwapIntentRecord.fromIntent(intent),
    ];

    final result = await tracker.refreshOpenIntents(
      accountUuid: 'account-1',
      currentIntents: [persistedIntents.first],
    );

    expect(provider.statusRequests, ['deposit-a', 'deposit-b']);
    expect(result.intents.map((intent) => intent.status), [
      SwapIntentStatus.processing,
      SwapIntentStatus.complete,
      SwapIntentStatus.complete,
    ]);
    expect(store.savedRecords, hasLength(3));
    expect(store.savedRecords.map((record) => record.status), [
      SwapIntentStatus.processing,
      SwapIntentStatus.complete,
      SwapIntentStatus.complete,
    ]);
  });

  test('does not refresh or save hidden terminal-only activity', () async {
    final store = _MemorySwapActivityStore();
    final provider = _StatusSwapProvider({});
    final tracker = SwapActivityTracker(
      activityStore: store,
      swapProvider: provider,
    );
    final currentIntents = [
      _intent(
        id: 'swap-complete',
        depositAddress: 'deposit-complete',
        status: SwapIntentStatus.complete,
      ),
      _intent(
        id: 'swap-failed',
        depositAddress: 'deposit-failed',
        status: SwapIntentStatus.failed,
      ),
    ];

    final result = await tracker.refreshOpenIntents(
      accountUuid: 'account-1',
      currentIntents: currentIntents,
    );

    expect(result.didRefresh, isFalse);
    expect(provider.statusRequests, isEmpty);
    expect(store.saveCount, 0);
  });
}

SwapPrototypeIntent _intent({
  required String id,
  required String depositAddress,
  SwapIntentStatus status = SwapIntentStatus.awaitingDeposit,
}) {
  return SwapPrototypeIntent(
    id: id,
    title: 'ZEC to USDC',
    pair: 'ZEC -> USDC',
    sellAmount: '1.0000 ZEC',
    receiveEstimate: '70.00 USDC',
    provider: 'NEAR Intents',
    status: status,
    nextAction: 'Checking swap status',
    steps: const [],
    exposure: const [],
    receipt: const [],
    direction: SwapDirection.zecToExternal,
    externalAsset: SwapAsset.usdc,
    depositAddress: depositAddress,
    providerQuoteId: 'quote-$id',
    accountUuid: 'account-1',
  );
}

SwapIntentSnapshot _snapshot({
  required String id,
  required String depositAddress,
  required SwapIntentStatus status,
}) {
  return SwapIntentSnapshot(
    id: id,
    providerLabel: 'NEAR Intents',
    pairText: 'ZEC -> USDC',
    sellAmountText: '1.0000 ZEC',
    receiveEstimateText: '70.00 USDC',
    status: status,
    nextAction: 'Provider status updated',
    depositInstruction: SwapDepositInstruction(
      asset: SwapAsset.zec,
      address: depositAddress,
      expiresInLabel: '01:30',
      reuseWarning: 'Do not reuse this address',
    ),
  );
}

class _MemorySwapActivityStore implements SwapActivityStore {
  var saveCount = 0;
  List<SwapIntentRecord> savedRecords = const [];

  @override
  Future<List<SwapIntentRecord>> loadRecords({
    required String accountUuid,
  }) async {
    return savedRecords;
  }

  @override
  Future<void> saveRecords({
    required String accountUuid,
    required List<SwapIntentRecord> records,
  }) async {
    saveCount++;
    savedRecords = records;
  }
}

class _StatusSwapProvider implements SwapProvider {
  _StatusSwapProvider(this.statuses);

  final Map<String, SwapIntentSnapshot> statuses;
  final statusRequests = <String>[];

  @override
  String get providerLabel => 'NEAR Intents';

  @override
  Future<List<SwapAsset>> listSupportedExternalAssets() async => const [];

  @override
  Future<SwapQuote> quote(SwapQuoteRequest request) {
    throw UnimplementedError();
  }

  @override
  Future<SwapIntentSnapshot> startSwap(SwapQuote quote) {
    throw UnimplementedError();
  }

  @override
  Future<SwapIntentSnapshot> getStatus(
    String intentId, {
    String? depositMemo,
  }) async {
    statusRequests.add(intentId);
    return statuses[intentId] ??
        _snapshot(
          id: intentId,
          depositAddress: intentId,
          status: SwapIntentStatus.processing,
        );
  }

  @override
  Future<SwapIntentSnapshot> submitDepositTransaction({
    required String depositAddress,
    required String txHash,
    String? depositMemo,
    String? nearSenderAccount,
  }) {
    throw UnimplementedError();
  }
}
