import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_activity_status_mapper.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_detail_tooltips.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_models.dart';
import 'package:zcash_wallet/src/features/swap/widgets/swap_status_page_content.dart';

void main() {
  test('maps in-progress status page data from the saved swap intent', () {
    final presentation = swapActivityStatusPresentationForIntent(
      _state(indicativeExternalPerZec: {SwapAsset.usdc: 70}),
      _intent(
        status: SwapIntentStatus.processing,
        direction: SwapDirection.zecToExternal,
        externalAsset: SwapAsset.usdc,
        sellAmount: '2.0000 ZEC',
        receiveEstimate: '140.00 USDC',
        depositAddress: 't1deposit-address',
        oneClickRecipient: '0xrecipient-address',
        oneClickRefundTo: 'u1refund-address',
      ),
      accountDetail: const SwapActivityAccountDetail(
        name: 'Shielded account',
        profilePictureId: 'profile-1',
      ),
    );

    expect(presentation.title, 'Swapping ...');
    expect(presentation.payAsset, SwapAsset.zec);
    expect(presentation.receiveAsset, SwapAsset.usdc);
    expect(presentation.payFiatText, r'$140.00');
    expect(presentation.receiveFiatText, r'$140.00');
    expect(presentation.badgeKind, SwapStatusBadgeKind.liveQuote);
    expect(presentation.progressIndex, 2);
    expect(presentation.showTabs, isTrue);
    expect(presentation.steps.map((step) => step.title), [
      'ZEC',
      'Deposit confirmation',
      'Swap',
      'Deliver USDC',
    ]);
    expect(_detailValue(presentation.details, 'Account'), 'Shielded account');
    expect(
      _detailValue(presentation.details, 'USDC recipient'),
      contains('0x'),
    );
    expect(
      _detailValue(presentation.details, 'Deposit ZEC to'),
      contains('t1'),
    );
    expect(
      _detailValue(presentation.details, 'Guaranteed minimum'),
      '140.00 USDC',
    );
    expect(
      _detailRow(presentation.details, 'Swap fee').helpTooltip,
      swapFeeTooltip,
    );
    expect(
      _detailRow(presentation.details, 'Guaranteed minimum').helpTooltip,
      swapMinimumReceiveTooltip('USDC'),
    );
  });

  test('keeps terminal failure details compact and final', () {
    final presentation = swapActivityStatusPresentationForIntent(
      _state(),
      _intent(
        status: SwapIntentStatus.failed,
        direction: SwapDirection.zecToExternal,
        externalAsset: SwapAsset.usdc,
        totalFeesText: '0.00002 ZEC',
        realisedSlippageText: '0.01 USDC (0.01%)',
        oneClickRefundTo: 'u1refund-address',
        completedAt: DateTime(2026, 5, 7, 10, 30),
      ),
    );

    expect(presentation.title, 'Swap failed');
    expect(presentation.badgeKind, SwapStatusBadgeKind.failed);
    expect(presentation.progressIndex, 3);
    expect(presentation.showTabs, isFalse);
    expect(_detailValue(presentation.details, 'Total fees'), '0.00002 ZEC');
    expect(
      _detailRow(presentation.details, 'Total fees').helpTooltip,
      swapTotalFeesTooltip,
    );
    expect(
      presentation.details.map((detail) => detail.label),
      isNot(contains('Realized slippage')),
    );
    expect(
      _detailValue(presentation.details, 'ZEC refunded to'),
      contains('u1'),
    );
    expect(
      _detailValue(presentation.details, 'Timestamp'),
      'May 7, 2026 10:30',
    );
  });

  test('maps route plan progress and staged display states', () {
    final plan = SwapActivityRoutePlan.fromIntent(
      _intent(
        status: SwapIntentStatus.processing,
        direction: SwapDirection.zecToExternal,
        externalAsset: SwapAsset.usdc,
      ),
    );

    expect(plan.steps.map((step) => step.label), [
      'Send ZEC',
      'Confirm',
      'Swap',
      'Deliver',
    ]);
    expect(plan.progressIndex, 2);
    expect(plan.canAnimateProgress, isTrue);
    expect(
      plan.semanticLabel,
      'Now: Swap, Provider is converting funds and preparing delivery., 2 of 4 steps done',
    );

    final displayed = plan.displayedAtProgress(1);
    expect(displayed.steps.map((step) => step.state), [
      SwapActivityRouteStepState.done,
      SwapActivityRouteStepState.active,
      SwapActivityRouteStepState.pending,
      SwapActivityRouteStepState.pending,
    ]);
  });

  test('moves broadcast deposits to confirmation while awaiting provider', () {
    final intent = _intent(
      status: SwapIntentStatus.awaitingDeposit,
      direction: SwapDirection.zecToExternal,
      externalAsset: SwapAsset.usdc,
      depositTxHash: 'zec-deposit-txid',
    );

    final presentation = swapActivityStatusPresentationForIntent(
      _state(),
      intent,
    );
    expect(presentation.progressIndex, 1);

    final plan = SwapActivityRoutePlan.fromIntent(intent);
    expect(plan.progressIndex, 1);
    expect(
      plan.semanticLabel,
      'Now: Confirm, Waiting for the source chain and provider to recognize the deposit., 1 of 4 steps done',
    );
    expect(plan.steps.map((step) => step.state), [
      SwapActivityRouteStepState.done,
      SwapActivityRouteStepState.active,
      SwapActivityRouteStepState.pending,
      SwapActivityRouteStepState.pending,
    ]);
  });

  test('maps active status plan copy from intent status', () {
    final awaitingBroadcast = SwapActivityStatusPlan.fromIntent(
      _intent(
        status: SwapIntentStatus.awaitingDeposit,
        direction: SwapDirection.zecToExternal,
        externalAsset: SwapAsset.usdc,
      ),
    );
    expect(awaitingBroadcast.title, 'Send ZEC');
    expect(awaitingBroadcast.tone, SwapActivityStatusPlanTone.action);

    final awaitingConfirm = SwapActivityStatusPlan.fromIntent(
      _intent(
        status: SwapIntentStatus.awaitingDeposit,
        direction: SwapDirection.zecToExternal,
        externalAsset: SwapAsset.usdc,
        depositTxHash: 'zec-deposit-txid',
      ),
    );
    expect(awaitingConfirm.title, 'ZEC sent');
    expect(awaitingConfirm.detail, 'Waiting for the deposit to confirm.');

    final unknown = SwapActivityStatusPlan.fromIntent(
      _intent(
        status: SwapIntentStatus.providerStatusUnknown,
        direction: SwapDirection.zecToExternal,
        externalAsset: SwapAsset.usdc,
        providerStatusRaw: 'mystery_status',
      ),
    );
    expect(unknown.tone, SwapActivityStatusPlanTone.warning);
    expect(
      unknown.detail,
      'Provider returned mystery_status. Keep this record open.',
    );
  });

  test('maps failed route plans without animating alert states', () {
    final plan = SwapActivityRoutePlan.fromIntent(
      _intent(
        status: SwapIntentStatus.failed,
        direction: SwapDirection.zecToExternal,
        externalAsset: SwapAsset.usdc,
      ),
    );

    expect(plan.progressIndex, 0);
    expect(plan.canAnimateProgress, isFalse);
    expect(plan.steps.first.state, SwapActivityRouteStepState.failed);
    expect(
      plan.semanticLabel,
      'Stopped, Send the quoted amount to the one-time deposit address., 0 of 4 steps done',
    );
    expect(identical(plan.displayedAtProgress(0), plan), isTrue);
  });

  test('maps resolution messaging and actions for attention states', () {
    final incomplete = SwapActivityResolution.fromIntent(
      _intent(
        status: SwapIntentStatus.incompleteDeposit,
        direction: SwapDirection.zecToExternal,
        externalAsset: SwapAsset.usdc,
      ),
    );
    expect(incomplete?.tone, SwapActivityResolutionTone.warning);
    expect(
      incomplete?.primaryAction,
      SwapActivityResolutionAction.copyTopUpDetails,
    );

    final unknown = SwapActivityResolution.fromIntent(
      _intent(
        status: SwapIntentStatus.providerStatusUnknown,
        direction: SwapDirection.zecToExternal,
        externalAsset: SwapAsset.usdc,
        providerStatusRaw: 'mystery_status',
      ),
    );
    expect(unknown?.primaryAction, isNull);
    expect(unknown?.message, 'The provider returned mystery_status.');

    final failed = SwapActivityResolution.fromIntent(
      _intent(
        status: SwapIntentStatus.failed,
        direction: SwapDirection.zecToExternal,
        externalAsset: SwapAsset.usdc,
      ),
    );
    expect(failed?.tone, SwapActivityResolutionTone.destructive);
    expect(
      failed?.primaryAction,
      SwapActivityResolutionAction.reviewFreshQuote,
    );

    final processing = SwapActivityResolution.fromIntent(
      _intent(
        status: SwapIntentStatus.processing,
        direction: SwapDirection.zecToExternal,
        externalAsset: SwapAsset.usdc,
      ),
    );
    expect(processing, isNull);
  });

  test('maps deposit instructions by swap direction', () {
    final zecInstruction = SwapActivityDepositInstruction.fromIntent(
      _intent(
        status: SwapIntentStatus.awaitingDeposit,
        direction: SwapDirection.zecToExternal,
        externalAsset: SwapAsset.usdc,
        depositAddress: 't1deposit-address',
        depositMemo: 'memo-1',
      ),
    );

    expect(zecInstruction?.sendLabel, 'Send ZEC');
    expect(zecInstruction?.depositSymbol, 'ZEC');
    expect(zecInstruction?.depositAddressLabel, 'ZEC deposit');
    expect(zecInstruction?.memo, 'memo-1');
    expect(zecInstruction?.qr, isNull);

    final externalInstruction = SwapActivityDepositInstruction.fromIntent(
      _intent(
        status: SwapIntentStatus.awaitingExternalDeposit,
        direction: SwapDirection.externalToZec,
        externalAsset: SwapAsset.usdc,
        depositAddress: '0xdeposit-address',
      ),
    );

    expect(externalInstruction?.sendLabel, 'Send USDC from source chain');
    expect(externalInstruction?.depositSymbol, 'USDC');
    expect(externalInstruction?.depositAddressLabel, 'USDC source deposit');
    expect(externalInstruction?.qr?.railLabel, 'Ethereum USDC');
    expect(externalInstruction?.qr?.reuseWarning, 'Do not reuse this address');
    expect(externalInstruction?.txHashLabel, 'USDC deposit tx hash');
    expect(externalInstruction?.qr, isNotNull);
  });

  test('maps deposit page and refresh predicates', () {
    final externalAwaiting = _intent(
      status: SwapIntentStatus.awaitingExternalDeposit,
      direction: SwapDirection.externalToZec,
      externalAsset: SwapAsset.usdc,
      depositAddress: '0xdeposit-address',
    );
    expect(swapActivityShowsExternalDepositPage(externalAwaiting), isTrue);
    expect(
      swapActivityShowsDepositPage(externalAwaiting, intentIsHardware: false),
      isTrue,
    );

    final hardwareAwaiting = _intent(
      status: SwapIntentStatus.awaitingDeposit,
      direction: SwapDirection.zecToExternal,
      externalAsset: SwapAsset.usdc,
      depositAddress: 't1deposit-address',
    );
    expect(
      swapActivityShowsHardwareZecDepositPage(
        hardwareAwaiting,
        intentIsHardware: true,
      ),
      isTrue,
    );
    expect(
      swapActivityShowsHardwareZecDepositPage(
        hardwareAwaiting,
        intentIsHardware: false,
      ),
      isFalse,
    );

    final broadcasted = _intent(
      status: SwapIntentStatus.awaitingDeposit,
      direction: SwapDirection.zecToExternal,
      externalAsset: SwapAsset.usdc,
      depositAddress: 't1deposit-address',
      depositTxHash: 'zec-deposit-txid',
    );
    expect(
      swapActivityShowsHardwareZecDepositPage(
        broadcasted,
        intentIsHardware: true,
      ),
      isFalse,
    );

    final expired = _intent(
      status: SwapIntentStatus.expired,
      direction: SwapDirection.zecToExternal,
      externalAsset: SwapAsset.usdc,
    );
    expect(SwapActivityDepositInstruction.fromIntent(expired), isNull);
    expect(
      swapActivityShowsDepositPage(expired, intentIsHardware: false),
      isTrue,
    );

    expect(swapActivityShowDepositControls(SwapIntentStatus.processing), true);
    expect(
      swapActivityShowDepositControls(SwapIntentStatus.providerStatusUnknown),
      false,
    );
    expect(canRefreshSwapIntentStatus(SwapIntentStatus.complete), false);
    expect(canRefreshSwapIntentStatus(SwapIntentStatus.failed), true);
  });
}

SwapState _state({Map<SwapAsset, double> indicativeExternalPerZec = const {}}) {
  return SwapState(
    direction: SwapDirection.zecToExternal,
    amountText: '',
    receiveAmountText: '',
    destinationText: '',
    externalAsset: SwapAsset.usdc,
    reviewVisible: false,
    intents: const [],
    indicativeExternalPerZec: indicativeExternalPerZec,
  );
}

SwapIntent _intent({
  required SwapIntentStatus status,
  required SwapDirection direction,
  required SwapAsset externalAsset,
  String sellAmount = '2.0000 ZEC',
  String receiveEstimate = '140.00 USDC',
  String? depositAddress,
  String? depositMemo,
  String? depositTxHash,
  String? totalFeesText,
  String? realisedSlippageText,
  String? oneClickRecipient,
  String? oneClickRefundTo,
  String? providerStatusRaw,
  DateTime? completedAt,
}) {
  return SwapIntent(
    id: 'swap-activity',
    title: 'ZEC to USDC',
    pair: 'ZEC -> USDC',
    sellAmount: sellAmount,
    receiveEstimate: receiveEstimate,
    provider: 'NEAR Intents',
    status: status,
    nextAction: 'Next action',
    steps: const [],
    exposure: const [],
    receipt: const [],
    direction: direction,
    externalAsset: externalAsset,
    depositAddress: depositAddress,
    depositMemo: depositMemo,
    depositTxHash: depositTxHash,
    totalFeesText: totalFeesText,
    realisedSlippageText: realisedSlippageText,
    minimumReceiveText: receiveEstimate,
    oneClickRecipient: oneClickRecipient,
    oneClickRefundTo: oneClickRefundTo,
    providerStatusRaw: providerStatusRaw,
    completedAt: completedAt,
  );
}

String _detailValue(List<SwapStatusDetailRowData> rows, String label) {
  return _detailRow(rows, label).value;
}

SwapStatusDetailRowData _detailRow(
  List<SwapStatusDetailRowData> rows,
  String label,
) {
  return rows.singleWhere((row) => row.label == label);
}
