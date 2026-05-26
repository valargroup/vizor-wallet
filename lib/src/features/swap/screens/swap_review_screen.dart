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
import '../models/swap_prototype_models.dart';
import '../models/swap_activity_navigation.dart';
import '../providers/swap_prototype_provider.dart';
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

  bool _isHardwareIntent(SwapPrototypeIntent intent) {
    final accountUuid = intent.accountUuid;
    if (accountUuid == null || accountUuid.trim().isEmpty) return false;
    final accountState = ref.read(accountProvider).value;
    final accountHardwareByUuid = {
      for (final account in accountState?.accounts ?? const <AccountInfo>[])
        account.uuid: account.isHardware,
    };
    return accountHardwareByUuid[accountUuid] ?? false;
  }

  void _returnToSwap() {
    ref.read(swapPrototypeProvider.notifier).cancelReviewQuote();
    context.go('/swap');
  }

  void _reviewAgain() {
    unawaited(() async {
      await ref.read(swapPrototypeProvider.notifier).showReview();
      if (!mounted) return;
      final next = ref.read(swapPrototypeProvider);
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
      final started = await ref
          .read(swapPrototypeProvider.notifier)
          .startIntent();
      if (!mounted) return;
      if (!started) {
        setState(() => _startingIntent = false);
        return;
      }
      final startedIntent = ref
          .read(swapPrototypeProvider)
          .selectedIntentOrNull;
      if (startedIntent != null) {
        final needsKeystoneDeposit =
            _isHardwareIntent(startedIntent) &&
            startedIntent.direction == SwapDirection.zecToExternal &&
            !(startedIntent.depositTxHash?.trim().isNotEmpty ?? false);
        context.go(
          swapActivityDetailUri(
            intentId: startedIntent.id,
            returnTarget: SwapActivityReturnTarget.swap,
            autoSignZecDeposit: needsKeystoneDeposit,
          ).toString(),
        );
        return;
      }
      context.go('/activity');
    }());
  }

  @override
  Widget build(BuildContext context) {
    final swapState = ref.watch(swapPrototypeProvider);
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
                                  ),
                                  const SizedBox(height: AppSpacing.base),
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

bool _reviewQuoteExceedsAvailableZec(SwapQuote quote, BigInt availableZatoshi) {
  if (!quote.direction.sendsZec) return false;
  final amountText = quote.sellAmountText.split(' ').first.trim();
  final amount = parseZecAmount(amountText);
  if (amount == null || amount <= BigInt.zero) return false;
  return amount >= availableZatoshi;
}
