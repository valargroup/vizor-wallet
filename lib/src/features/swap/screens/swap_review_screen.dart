import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/formatting/zec_amount.dart';
import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_layout.dart';
import '../../../core/layout/app_main_sidebar.dart';
import '../../../core/profile_pictures.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_back_link.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/sync_provider.dart';
import '../models/swap_models.dart';
import '../models/swap_activity_navigation.dart';
import '../providers/swap_state_provider.dart';
import '../widgets/swap_near_intents_attribution.dart';
import '../widgets/swap_review_page_content.dart';

class SwapReviewScreen extends ConsumerStatefulWidget {
  const SwapReviewScreen({super.key});

  @override
  ConsumerState<SwapReviewScreen> createState() => _SwapReviewScreenState();
}

class _SwapReviewScreenState extends ConsumerState<SwapReviewScreen> {
  var _hadReviewState = false;
  var _startingIntent = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(appLayoutProvider.notifier).setMode(AppLayoutMode.large);
    });
  }

  String? _accountLabelFor(AccountState? accountState, String? accountUuid) {
    if (accountUuid == null || accountUuid.trim().isEmpty) return null;
    for (final account in accountState?.accounts ?? const <AccountInfo>[]) {
      if (account.uuid == accountUuid) return account.name;
    }
    return null;
  }

  String _accountProfilePictureIdFor(
    AccountState? accountState,
    String? accountUuid,
  ) {
    if (accountUuid == null || accountUuid.trim().isEmpty) {
      return kDefaultProfilePictureId;
    }
    for (final account in accountState?.accounts ?? const <AccountInfo>[]) {
      if (account.uuid == accountUuid) return account.profilePictureId;
    }
    return kDefaultProfilePictureId;
  }

  void _returnToSwap() {
    ref.read(swapStateProvider.notifier).cancelReviewQuote();
    context.go('/swap');
  }

  void _reviewAgain() {
    unawaited(() async {
      await ref.read(swapStateProvider.notifier).showReview();
      if (!mounted) return;
      final next = ref.read(swapStateProvider);
      if (!next.reviewVisible ||
          next.reviewQuote == null ||
          next.reviewAddressPlan == null) {
        context.go('/swap');
      }
    }());
  }

  void _startIntent() {
    unawaited(() async {
      if (!_startingIntent) {
        setState(() => _startingIntent = true);
      }
      final started = await ref.read(swapStateProvider.notifier).startIntent();
      if (!mounted) return;
      if (!started) {
        setState(() => _startingIntent = false);
        return;
      }
      final startedIntent = ref.read(swapStateProvider).selectedIntentOrNull;
      if (startedIntent != null) {
        context.go(
          swapActivityDetailUri(
            intentId: startedIntent.id,
            returnTarget: SwapActivityReturnTarget.swap,
          ).toString(),
        );
        return;
      }
      context.go('/activity');
    }());
  }

  @override
  Widget build(BuildContext context) {
    final swapState = ref.watch(swapStateProvider);
    final quote = swapState.reviewQuote;
    final addressPlan = swapState.reviewAddressPlan;
    if (!swapState.reviewVisible || quote == null || addressPlan == null) {
      if (!_hadReviewState || !_startingIntent) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) context.go('/swap');
        });
      }
      return const SizedBox.shrink();
    }
    _hadReviewState = true;

    final accountState = ref.watch(accountProvider).value;
    final sync = ref.watch(
      syncProvider.select(
        (value) => (value.value ?? SyncState()).scopedToAccount(
          accountState?.activeAccountUuid,
        ),
      ),
    );
    final accountLabel = _accountLabelFor(
      accountState,
      swapState.reviewAccountUuid,
    );
    final accountProfilePictureId = _accountProfilePictureIdFor(
      accountState,
      swapState.reviewAccountUuid,
    );
    final startBlockedReason =
        _reviewQuoteExceedsAvailableZec(quote, sync.spendableBalance)
        ? 'Required pay exceeds available ZEC. Review a smaller target amount.'
        : null;

    return AppDesktopShell(
      sidebar: const AppMainSidebar(),
      pane: AppDesktopPane(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.md,
          AppSpacing.md,
          0,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: AppBackLink(
                label: 'Swap',
                minWidth: 60,
                onTap: _returnToSwap,
              ),
            ),
            const SizedBox(height: AppSpacing.s),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return Stack(
                    children: [
                      Positioned.fill(
                        child: SwapReviewPageScrollArea(
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              minHeight: constraints.maxHeight,
                            ),
                            child: Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SwapReviewPageContent(
                                    quote: quote,
                                    addressPlan: addressPlan,
                                    accountLabel: accountLabel,
                                    accountProfilePictureId:
                                        accountProfilePictureId,
                                    expired: swapState.quoteExpired,
                                    amountWarning:
                                        swapState.reviewAmountDifferenceWarning,
                                    startError: swapState.statusError,
                                    startBlockedReason: startBlockedReason,
                                    payFiatTextOverride:
                                        _reviewFiatTextForAsset(
                                          swapState,
                                          asset: quote.sellAsset,
                                          amount: quote.sellAmount,
                                        ),
                                    receiveFiatTextOverride:
                                        _reviewFiatTextForAsset(
                                          swapState,
                                          asset: quote.receiveAsset,
                                          amount: quote.receiveAmount,
                                        ),
                                  ),
                                  const SizedBox(height: AppSpacing.sm),
                                  SwapReviewPageActions(
                                    expired: swapState.quoteExpired,
                                    starting: swapState.startSubmitting,
                                    startBlockedReason: startBlockedReason,
                                    sendsZec: quote.direction.sendsZec,
                                    onReviewAgain: _reviewAgain,
                                    onCancelReview: _returnToSwap,
                                    onStartIntent: _startIntent,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (constraints.maxHeight >= 520)
                        const Positioned(
                          left: 0,
                          bottom: AppSpacing.md,
                          child: SwapNearIntentsAttribution(),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String? _reviewFiatTextForAsset(
  SwapState state, {
  required SwapAsset asset,
  required double amount,
}) {
  final usdValue = _reviewUsdValueForAsset(state, asset: asset, amount: amount);
  return usdValue == null ? null : _formatReviewUsd(usdValue);
}

double? _reviewUsdValueForAsset(
  SwapState state, {
  required SwapAsset asset,
  required double amount,
}) {
  if (!amount.isFinite || amount <= 0) return 0;
  if (_isUsdLike(asset)) return amount;
  if (asset.isNativeZec && _isUsdLike(state.externalAsset)) {
    final zecUsd =
        state.indicativeExternalPerZec[state.externalAsset] ??
        state.externalAsset.fallbackExternalPerZec;
    return amount * zecUsd;
  }
  return null;
}

bool _isUsdLike(SwapAsset asset) {
  final symbol = asset.symbol.toUpperCase();
  return symbol == 'USDC' || symbol == 'USDT' || symbol == 'DAI';
}

String _formatReviewUsd(double value) {
  if (!value.isFinite || value <= 0) return r'$0.00';
  if (value >= 1000000) {
    return '\$${_trimFixed(value / 1000000, 3)}M';
  }
  if (value >= 1000) {
    return '\$${_trimFixed(value / 1000, 2)}K';
  }
  return '\$${value.toStringAsFixed(2)}';
}

String _trimFixed(double value, int fractionDigits) {
  var text = value.toStringAsFixed(fractionDigits);
  while (text.contains('.') && text.endsWith('0')) {
    text = text.substring(0, text.length - 1);
  }
  if (text.endsWith('.')) text = text.substring(0, text.length - 1);
  return text;
}

bool _reviewQuoteExceedsAvailableZec(SwapQuote quote, BigInt availableZatoshi) {
  if (!quote.direction.sendsZec) return false;
  final amountText = quote.sellAmountText.split(' ').first.trim();
  final amount = parseZecAmount(amountText);
  if (amount == null || amount <= BigInt.zero) return false;
  return amount >= availableZatoshi;
}
