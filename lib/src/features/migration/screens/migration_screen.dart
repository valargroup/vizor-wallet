import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../main.dart' show log;
import '../../../core/formatting/zec_amount.dart';
import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_main_sidebar.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/sync_provider.dart';
import '../../../rust/api/sync.dart' as rust_sync;
import '../migration_copy.dart';
import '../models/migration_step_state.dart';
import '../models/migration_view_state.dart';
import '../providers/migration_expected_transfer_count_provider.dart';
import '../providers/migration_run_controller.dart';
import '../providers/orchard_migration_status_provider.dart';
import '../widgets/migration_step_card.dart';

class MigrationScreen extends ConsumerStatefulWidget {
  const MigrationScreen({super.key});

  @override
  ConsumerState<MigrationScreen> createState() => _MigrationScreenState();
}

class _MigrationScreenState extends ConsumerState<MigrationScreen> {
  Timer? _progressRefreshTimer;

  @override
  void dispose() {
    _progressRefreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accountState = ref.watch(accountProvider).value;
    final account = accountState?.activeAccount;
    final accountUuid = accountState?.activeAccountUuid;
    final isHardware = account?.isHardware ?? false;
    final sync = (ref.watch(syncProvider).value ?? SyncState()).scopedToAccount(
      accountUuid,
    );
    final migrationTransactions = _migrationTransactions(
      sync.recentTransactions,
    );
    final expectedTransferCount = ref.watch(
      migrationExpectedTransferCountProvider,
    );
    final scopedExpectedTransferCount = accountUuid == null
        ? null
        : expectedTransferCount[accountUuid];
    final now = DateTime.now();
    final hasUnconfirmedMigration = migrationTransactions.any(
      _isPendingMigration,
    );
    final expectedTransferCountIsFresh =
        scopedExpectedTransferCount != null &&
        (!scopedExpectedTransferCount.isExpired(now) ||
            hasUnconfirmedMigration);
    final freshExpectedTransferCount = expectedTransferCountIsFresh
        ? scopedExpectedTransferCount
        : null;
    final scopedExpectedCount = freshExpectedTransferCount?.count;
    final currentRunMigrationTransactions = _currentRunMigrationTransactions(
      migrationTransactions,
      freshExpectedTransferCount,
    );
    final currentRunCompletedCount = currentRunMigrationTransactions
        .where(_isCompletedMigration)
        .length;
    final expectedMigrationInProgress =
        scopedExpectedCount != null &&
        currentRunCompletedCount < scopedExpectedCount;
    final hasPendingMigration =
        hasUnconfirmedMigration || expectedMigrationInProgress;
    final hasCompletedMigration = migrationTransactions.any(
      _isCompletedMigration,
    );
    final migrationStatusAsync = ref.watch(
      activeOrchardMigrationStatusProvider,
    );
    final migrationStatus = migrationStatusAsync.value;
    final runState = ref.watch(migrationRunControllerProvider);
    final statusIsLoading =
        !isHardware &&
        accountUuid != null &&
        migrationStatus == null &&
        migrationStatusAsync.isLoading;
    final statusError = migrationStatusAsync.error;

    late final Widget body;
    MigrationViewState? viewState;
    if (statusIsLoading) {
      body = const _StatusNote(
        title: MigrationCopy.checkingTitle,
        body: MigrationCopy.checkingBody,
      );
    } else if (!isHardware &&
        accountUuid != null &&
        statusError != null &&
        migrationStatus == null) {
      body = _StatusNote(
        title: MigrationCopy.failedRecoverableTitle,
        body: MigrationCopy.failedRecoverableBody,
        details: statusError.toString(),
        onRetry: () => ref.invalidate(activeOrchardMigrationStatusProvider),
      );
      viewState = MigrationViewState.failedRecoverable;
    } else {
      viewState = migrationViewState(
        isHardware: isHardware,
        rustPhase: migrationStatus?.phase,
        hasPendingMigration: hasPendingMigration,
        hasCompletedMigration: hasCompletedMigration,
        orchardBalance: sync.orchardBalance,
        ironwoodBalance: sync.ironwoodBalance,
      );

      if (viewState == MigrationViewState.softwareRequired) {
        body = const _SoftwareRequiredView();
      } else {
        final steps = migrationStepsModel(
          viewState: viewState,
          status: migrationStatus,
          runInFlight: runState.inFlight,
          intent: runState.intent,
        );
        final effectiveExpectedCount =
            migrationStatus != null && migrationStatus.totalCount > 0
            ? migrationStatus.totalCount
            : scopedExpectedCount;

        body = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              MigrationCopy.idleTitle,
              style: AppTypography.displaySmall.copyWith(
                color: context.colors.text.accent,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              MigrationCopy.idleBody,
              style: AppTypography.bodyMedium.copyWith(
                color: context.colors.text.secondary,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            const _PoolTransition(),
            const SizedBox(height: AppSpacing.md),
            _stepOneCard(steps, viewState, migrationStatus, runState, sync),
            const SizedBox(height: AppSpacing.s),
            _stepTwoCard(
              steps,
              viewState,
              migrationStatus,
              runState,
              sync,
              currentRunMigrationTransactions,
              effectiveExpectedCount,
            ),
            if (migrationStatus != null && migrationStatus.totalCount > 0) ...[
              const SizedBox(height: AppSpacing.s),
              _RunDetails(status: migrationStatus),
            ],
          ],
        );
      }
    }

    _syncMigrationProgressPolling(
      hasPendingMigration || (viewState?.shouldPollProgress ?? false),
    );
    _clearExpiredExpectedTransferCount(
      accountUuid: accountUuid,
      expectedTransferCount: scopedExpectedTransferCount,
      hasPendingMigration:
          hasUnconfirmedMigration || (viewState?.hasActiveRun ?? false),
    );

    return AppDesktopShell(
      sidebar: const AppMainSidebar(),
      pane: AppDesktopPane(
        padding: EdgeInsets.zero,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: body,
        ),
      ),
    );
  }

  Widget _stepOneCard(
    MigrationStepsModel steps,
    MigrationViewState viewState,
    rust_sync.MigrationStatus? status,
    MigrationRunState runState,
    SyncState sync,
  ) {
    final errorBanner = runState.errorIntent == MigrationRunIntent.preparing
        ? runState.error
        : null;

    return switch (steps.stepOne) {
      MigrationStepOneState.blocked => MigrationStepCard(
        stepNumber: 1,
        title: MigrationCopy.stepOneTitle,
        isDimmed: true,
        statusLine: viewState == MigrationViewState.noOrchardFunds
            ? MigrationCopy.stepOneNoFunds
            : MigrationCopy.stepOneUnspendable,
        errorBanner: errorBanner,
        ctaLabel: MigrationCopy.stepOneCta,
        onCta: null,
      ),
      MigrationStepOneState.active => MigrationStepCard(
        stepNumber: 1,
        title: MigrationCopy.stepOneTitle,
        statusLine: MigrationCopy.stepOneBody,
        errorBanner: errorBanner,
        body: [_readyAmount(sync)],
        ctaLabel: MigrationCopy.stepOneCta,
        onCta: () => ref
            .read(migrationRunControllerProvider.notifier)
            .advance(MigrationRunIntent.preparing),
      ),
      MigrationStepOneState.running => const MigrationStepCard(
        stepNumber: 1,
        title: MigrationCopy.stepOneTitle,
        showSpinner: true,
        statusLine: MigrationCopy.stepOneRunning,
      ),
      MigrationStepOneState.waiting => MigrationStepCard(
        stepNumber: 1,
        title: MigrationCopy.stepOneTitle,
        statusLine: MigrationCopy.stepOneWaiting,
        errorBanner: errorBanner,
        body: [
          if (status != null && status.totalCount > 0)
            Text(
              MigrationCopy.stepOnePreparedCounts(
                status.preparedNoteCount,
                status.totalCount,
              ),
              style: AppTypography.bodyExtraSmall.copyWith(
                color: context.colors.text.secondary,
              ),
            ),
        ],
      ),
      MigrationStepOneState.done => MigrationStepCard(
        stepNumber: 1,
        title: MigrationCopy.stepOneTitle,
        isDone: true,
        statusLine: status != null && status.totalCount > 0
            ? MigrationCopy.stepOneDone(status.totalCount)
            : MigrationCopy.stepOneDoneGeneric,
      ),
      MigrationStepOneState.error => MigrationStepCard(
        stepNumber: 1,
        title: MigrationCopy.stepOneTitle,
        statusLine: status?.message ?? MigrationCopy.failedRecoverableBody,
        statusIsError: true,
        errorBanner: errorBanner,
        ctaLabel: MigrationCopy.retryCta,
        onCta: () => ref
            .read(migrationRunControllerProvider.notifier)
            .advance(MigrationRunIntent.preparing),
      ),
    };
  }

  Widget _stepTwoCard(
    MigrationStepsModel steps,
    MigrationViewState viewState,
    rust_sync.MigrationStatus? status,
    MigrationRunState runState,
    SyncState sync,
    List<rust_sync.TransactionInfo> currentRunMigrationTransactions,
    int? effectiveExpectedCount,
  ) {
    final errorBanner = runState.errorIntent == MigrationRunIntent.migrating
        ? runState.error
        : null;
    final total = status?.totalCount ?? 0;
    void startMigration() => ref
        .read(migrationRunControllerProvider.notifier)
        .advance(MigrationRunIntent.migrating);

    return switch (steps.stepTwo) {
      MigrationStepTwoState.locked => MigrationStepCard(
        stepNumber: 2,
        title: MigrationCopy.stepTwoTitle,
        isDimmed: true,
        statusLine: MigrationCopy.stepTwoLocked,
        errorBanner: errorBanner,
        ctaLabel: MigrationCopy.stepTwoCta,
        onCta: null,
      ),
      MigrationStepTwoState.ready => MigrationStepCard(
        stepNumber: 2,
        title: MigrationCopy.stepTwoTitle,
        statusLine: MigrationCopy.stepTwoReady(
          total,
          MigrationCopy.migrationWindowText(
            (status?.broadcastWindowSeconds ?? BigInt.from(60)).toInt(),
          ),
        ),
        errorBanner: errorBanner,
        body: [
          if (viewState == MigrationViewState.paused)
            Text(
              MigrationCopy.stepTwoPausedNote,
              style: AppTypography.bodyExtraSmall.copyWith(
                color: context.colors.text.secondary,
              ),
            ),
        ],
        ctaLabel: MigrationCopy.stepTwoCta,
        onCta: startMigration,
      ),
      MigrationStepTwoState.running => MigrationStepCard(
        stepNumber: 2,
        title: MigrationCopy.stepTwoTitle,
        showSpinner: true,
        statusLine: _stepTwoRunningLine(status),
        progress: total > 0
            ? (status?.broadcastedTxCount ?? 0).clamp(0, total) / total
            : null,
        body: [_warningRow(MigrationCopy.stepTwoKeepOpen)],
      ),
      MigrationStepTwoState.confirming => MigrationStepCard(
        stepNumber: 2,
        title: MigrationCopy.stepTwoTitle,
        statusLine: MigrationCopy.inProgressBody,
        body: [
          _MigrationTransfersList(
            migrationTransactions: currentRunMigrationTransactions,
            expectedTransferCount: effectiveExpectedCount,
            amountZatoshi: _migrationDisplayAmount(
              sync,
              currentRunMigrationTransactions,
            ),
          ),
          _warningRow(MigrationCopy.keepOpenWarning),
        ],
      ),
      MigrationStepTwoState.done => MigrationStepCard(
        stepNumber: 2,
        title: MigrationCopy.stepTwoTitle,
        isDone: true,
        statusLine: MigrationCopy.doneBody,
      ),
      MigrationStepTwoState.error => MigrationStepCard(
        stepNumber: 2,
        title: MigrationCopy.stepTwoTitle,
        statusLine: switch (viewState) {
          MigrationViewState.failedTerminal =>
            status?.message ?? MigrationCopy.failedTerminalBody,
          MigrationViewState.abandoned => MigrationCopy.abandonedBody,
          _ => status?.message ?? MigrationCopy.failedRecoverableBody,
        },
        statusIsError: true,
        errorBanner: errorBanner,
        ctaLabel: viewState == MigrationViewState.failedRecoverable
            ? MigrationCopy.retryCta
            : null,
        onCta: viewState == MigrationViewState.failedRecoverable
            ? startMigration
            : null,
      ),
    };
  }

  String _stepTwoRunningLine(rust_sync.MigrationStatus? status) {
    final total = status?.totalCount ?? 0;
    final isSubmitting =
        status?.phase == 'broadcasting' ||
        status?.phase == 'broadcast_scheduled';
    if (isSubmitting && total > 0) {
      final next = ((status?.broadcastedTxCount ?? 0) + 1).clamp(1, total);
      return MigrationCopy.stepTwoSubmitting(next, total);
    }
    return MigrationCopy.stepTwoSigning;
  }

  Widget _readyAmount(SyncState sync) {
    final amount = ZecAmount.fromZatoshi(
      sync.orchardBalance,
    ).pretty(denomStyle: ZecDenomStyle.upper).toString();
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          MigrationCopy.readyToMigrateLabel,
          style: AppTypography.labelLarge.copyWith(
            color: colors.text.secondary,
          ),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          amount,
          key: const ValueKey('migration_ready_amount'),
          style: AppTypography.displaySmall.copyWith(
            color: colors.text.accent,
          ),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          MigrationCopy.poolFlow,
          style: AppTypography.bodyExtraSmall.copyWith(
            color: colors.text.secondary,
          ),
        ),
      ],
    );
  }

  Widget _warningRow(String text) {
    final colors = context.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppIcon(
          AppIcons.warning,
          size: AppIconSize.medium,
          color: colors.icon.muted,
        ),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Text(
            text,
            style: AppTypography.bodyExtraSmall.copyWith(
              color: colors.text.secondary,
            ),
          ),
        ),
      ],
    );
  }

  void _syncMigrationProgressPolling(bool enabled) {
    if (enabled && _progressRefreshTimer == null) {
      _progressRefreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
        unawaited(_refreshMigrationProgress());
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(_refreshMigrationProgress());
      });
      return;
    }

    if (!enabled && _progressRefreshTimer != null) {
      _progressRefreshTimer?.cancel();
      _progressRefreshTimer = null;
    }
  }

  Future<void> _refreshMigrationProgress() async {
    try {
      await ref
          .read(syncProvider.notifier)
          .refreshAfterSend(
            transactionHistoryLimit: migrationProgressTransactionHistoryLimit,
          );
    } catch (e) {
      log('MigrationScreen: migration progress refresh failed: $e');
    }
  }

  void _clearExpiredExpectedTransferCount({
    required String? accountUuid,
    required MigrationExpectedTransferCount? expectedTransferCount,
    required bool hasPendingMigration,
  }) {
    if (accountUuid == null ||
        expectedTransferCount == null ||
        hasPendingMigration ||
        !expectedTransferCount.isExpired(DateTime.now())) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref
          .read(migrationExpectedTransferCountProvider.notifier)
          .clearCount(accountUuid);
    });
  }
}

List<rust_sync.TransactionInfo> _migrationTransactions(
  Iterable<rust_sync.TransactionInfo> transactions,
) {
  return transactions
      .where((tx) => tx.txKind == 'migration')
      .toList(growable: false);
}

List<rust_sync.TransactionInfo> _currentRunMigrationTransactions(
  List<rust_sync.TransactionInfo> migrationTransactions,
  MigrationExpectedTransferCount? expectedTransferCount,
) {
  final firstTxid = expectedTransferCount?.firstTxid.toLowerCase();
  if (firstTxid == null) return migrationTransactions;

  final firstTxIndex = migrationFirstTransactionIndex(
    transactionTxids: migrationTransactions.map((tx) => tx.txidHex),
    firstTxid: firstTxid,
  );
  if (firstTxIndex < 0) return const [];

  return migrationTransactions.take(firstTxIndex + 1).toList(growable: false);
}

bool _isPendingMigration(rust_sync.TransactionInfo tx) =>
    tx.minedHeight == BigInt.zero && !tx.expiredUnmined;

bool _isCompletedMigration(rust_sync.TransactionInfo tx) =>
    tx.minedHeight != BigInt.zero && !tx.expiredUnmined;

BigInt _migrationDisplayAmount(
  SyncState sync,
  List<rust_sync.TransactionInfo> migrationTransactions,
) {
  final txAmount = migrationTransactions.fold<BigInt>(
    BigInt.zero,
    (sum, tx) => sum + tx.displayAmount,
  );
  if (txAmount > BigInt.zero) return txAmount;
  return sync.orchardBalance;
}

/// Compact title/body note used for the pre-card loading and status-error
/// branches.
class _StatusNote extends StatelessWidget {
  const _StatusNote({
    required this.title,
    required this.body,
    this.details,
    this.onRetry,
  });

  final String title;
  final String body;
  final String? details;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: AppTypography.displaySmall.copyWith(color: colors.text.accent),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          body,
          style: AppTypography.bodyMedium.copyWith(
            color: colors.text.secondary,
          ),
        ),
        if (details != null && details!.trim().isNotEmpty) ...[
          const SizedBox(height: AppSpacing.s),
          Text(
            details!,
            style: AppTypography.bodyExtraSmall.copyWith(
              color: colors.text.secondary,
            ),
          ),
        ],
        if (onRetry != null) ...[
          const SizedBox(height: AppSpacing.md),
          AppButton(
            onPressed: onRetry,
            child: const Text(MigrationCopy.retryCta),
          ),
        ],
      ],
    );
  }
}

/// Small-print run details below the cards (batch limit, window, counts).
class _RunDetails extends StatelessWidget {
  const _RunDetails({required this.status});

  final rust_sync.MigrationStatus status;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final total = status.totalCount;
    final rows = <String>[
      if (total > 0) 'Prepared notes: ${status.preparedNoteCount} of $total',
      if (status.pendingTxCount > 0)
        'Scheduled transactions: ${status.pendingTxCount}',
      if (total > 0)
        'Broadcasted transactions: ${status.broadcastedTxCount} of $total',
      if (status.confirmedTxCount > 0)
        'Confirmed transactions: ${status.confirmedTxCount} of $total',
      'Signing batch limit: ${status.signingBatchLimit}',
      'Broadcast window: ${status.broadcastWindowSeconds}s',
    ];

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final row in rows) ...[
            Text(
              row,
              style: AppTypography.bodyExtraSmall.copyWith(
                color: colors.text.secondary,
              ),
            ),
            const SizedBox(height: AppSpacing.xxs),
          ],
        ],
      ),
    );
  }
}

class _SoftwareRequiredView extends StatelessWidget {
  const _SoftwareRequiredView();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          MigrationCopy.softwareRequiredTitle,
          style: AppTypography.displaySmall.copyWith(color: colors.text.accent),
        ),
        const SizedBox(height: AppSpacing.s),
        _Card(
          child: Text(
            MigrationCopy.softwareRequiredBody,
            key: const ValueKey('migration_software_required'),
            style: AppTypography.bodyMedium.copyWith(
              color: colors.text.secondary,
            ),
          ),
        ),
      ],
    );
  }
}

/// Transfer list shown inside step 2 while migration transactions confirm.
class _MigrationTransfersList extends StatelessWidget {
  const _MigrationTransfersList({
    required this.migrationTransactions,
    required this.expectedTransferCount,
    required this.amountZatoshi,
  });

  final List<rust_sync.TransactionInfo> migrationTransactions;
  final int? expectedTransferCount;
  final BigInt amountZatoshi;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final amount = ZecAmount.fromZatoshi(
      amountZatoshi,
    ).pretty(denomStyle: ZecDenomStyle.upper).toString();
    final total = [
      migrationTransactions.length,
      expectedTransferCount ?? 0,
      1,
    ].reduce((a, b) => a > b ? a : b);
    final transferTransactions = migrationTransactions.reversed.toList(
      growable: false,
    );
    final completed = transferTransactions.where(_isCompletedMigration).length;
    final progress = migrationTransactions.isEmpty ? null : completed / total;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          MigrationCopy.migratingAmount(amount),
          style: AppTypography.labelLarge.copyWith(
            color: colors.text.secondary,
          ),
        ),
        const SizedBox(height: AppSpacing.s),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadii.full),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 8,
            backgroundColor: colors.background.neutralSubtleOpacity,
            color: colors.icon.success,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          '$completed of $total confirmed',
          style: AppTypography.bodyExtraSmall.copyWith(
            color: colors.text.secondary,
          ),
        ),
        const SizedBox(height: AppSpacing.s),
        for (var i = 0; i < total; i++) ...[
          if (i > 0)
            Divider(height: AppSpacing.md, color: colors.border.subtle),
          _MigrationTransferRow(
            index: i,
            total: total,
            transaction: i < transferTransactions.length
                ? transferTransactions[i]
                : null,
          ),
        ],
      ],
    );
  }
}

class _MigrationTransferRow extends StatelessWidget {
  const _MigrationTransferRow({
    required this.index,
    required this.total,
    required this.transaction,
  });

  final int index;
  final int total;
  final rust_sync.TransactionInfo? transaction;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final tx = transaction;
    final isComplete = tx != null && _isCompletedMigration(tx);
    final isFailed = tx?.expiredUnmined ?? false;
    final statusText = isFailed
        ? 'Failed'
        : isComplete
        ? 'Completed'
        : 'In progress';
    final icon = isFailed
        ? AppIcons.warning
        : isComplete
        ? AppIcons.checkCircle
        : AppIcons.time;
    final iconColor = isFailed
        ? colors.icon.destructive
        : isComplete
        ? colors.icon.success
        : colors.icon.muted;

    return Row(
      children: [
        AppIcon(icon, size: AppIconSize.medium, color: iconColor),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Text(
            MigrationCopy.transferLabel(index + 1, total),
            style: AppTypography.bodyMedium.copyWith(color: colors.text.accent),
          ),
        ),
        Text(
          statusText,
          style: AppTypography.bodyMedium.copyWith(
            color: colors.text.secondary,
          ),
        ),
      ],
    );
  }
}

class _PoolTransition extends StatelessWidget {
  const _PoolTransition();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      children: [
        Expanded(
          child: _Card(
            child: Column(
              children: [
                Text(
                  MigrationCopy.fromPoolName,
                  style: AppTypography.bodyLarge.copyWith(
                    color: colors.text.accent,
                  ),
                ),
                Text(
                  MigrationCopy.fromPoolTag,
                  style: AppTypography.bodyExtraSmall.copyWith(
                    color: colors.text.secondary,
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s),
          child: AppIcon(
            AppIcons.arrowForwardIos,
            size: AppIconSize.medium,
            color: colors.icon.muted,
          ),
        ),
        Expanded(
          child: _Card(
            child: Column(
              children: [
                Text(
                  MigrationCopy.toPoolName,
                  style: AppTypography.bodyLarge.copyWith(
                    color: colors.text.accent,
                  ),
                ),
                Text(
                  MigrationCopy.toPoolTag,
                  style: AppTypography.bodyExtraSmall.copyWith(
                    color: colors.text.secondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: context.colors.background.neutralSubtleOpacity,
        borderRadius: BorderRadius.circular(AppRadii.xSmall),
      ),
      child: child,
    );
  }
}
