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
import '../models/migration_view_state.dart';
import '../providers/migration_expected_transfer_count_provider.dart';
import '../providers/orchard_migration_status_provider.dart';
import '../widgets/migration_signing_overlay.dart';

class MigrationScreen extends ConsumerStatefulWidget {
  const MigrationScreen({super.key});

  @override
  ConsumerState<MigrationScreen> createState() => _MigrationScreenState();
}

class _MigrationScreenState extends ConsumerState<MigrationScreen> {
  bool _signing = false;
  Timer? _progressRefreshTimer;

  void _startSigning() => setState(() => _signing = true);
  void _cancelSigning() => setState(() => _signing = false);

  void _completeSigning(MigrationSigningCompletion completion) {
    ref.invalidate(activeOrchardMigrationStatusProvider);
    final totalCount = completion.result.totalCount;
    if (totalCount > 0 && completion.firstTxid != null) {
      ref
          .read(migrationExpectedTransferCountProvider.notifier)
          .setCount(
            completion.accountUuid,
            totalCount,
            firstTxid: completion.firstTxid!,
          );
    }
    setState(() => _signing = false);
  }

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
    final statusIsLoading =
        !isHardware &&
        accountUuid != null &&
        migrationStatus == null &&
        migrationStatusAsync.isLoading;
    final statusError = migrationStatusAsync.error;

    late final Widget body;
    MigrationViewState? viewState;
    if (statusIsLoading) {
      body = const _PhaseStatusView(
        title: MigrationCopy.checkingTitle,
        body: MigrationCopy.checkingBody,
      );
    } else if (!isHardware &&
        accountUuid != null &&
        statusError != null &&
        migrationStatus == null) {
      body = _PhaseStatusView(
        title: MigrationCopy.failedRecoverableTitle,
        body: MigrationCopy.failedRecoverableBody,
        details: statusError.toString(),
        actionLabel: MigrationCopy.retryCta,
        onAction: () => ref.invalidate(activeOrchardMigrationStatusProvider),
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
      final effectiveExpectedCount =
          migrationStatus != null && migrationStatus.totalCount > 0
          ? migrationStatus.totalCount
          : scopedExpectedCount;

      body = switch (viewState) {
        MigrationViewState.softwareRequired => const _SoftwareRequiredView(),
        MigrationViewState.noOrchardFunds => const _PhaseStatusView(
          title: MigrationCopy.noOrchardFundsTitle,
          body: MigrationCopy.noOrchardFundsBody,
        ),
        MigrationViewState.waitingForSpendableOrchard => const _PhaseStatusView(
          title: MigrationCopy.waitingForSpendableTitle,
          body: MigrationCopy.waitingForSpendableBody,
        ),
        MigrationViewState.planningDenominations => _IdleView(
          onStart: _startSigning,
          orchardBalance: sync.orchardBalance,
        ),
        MigrationViewState.preparingDenominations => _PhaseStatusView(
          title: MigrationCopy.preparingDenominationsTitle,
          body: MigrationCopy.preparingDenominationsBody,
          status: migrationStatus,
        ),
        MigrationViewState.waitingDenomConfirmations => _PhaseStatusView(
          title: MigrationCopy.waitingDenomTitle,
          body: MigrationCopy.waitingDenomBody,
          status: migrationStatus,
        ),
        MigrationViewState.readyToMigrate => _PhaseStatusView(
          title: MigrationCopy.readyPreparedTitle,
          body: MigrationCopy.readyPreparedBody,
          status: migrationStatus,
          actionLabel: MigrationCopy.readyPreparedCta,
          onAction: _startSigning,
        ),
        MigrationViewState.buildingSigningBatch => _PhaseStatusView(
          title: MigrationCopy.buildingBatchTitle,
          body: MigrationCopy.buildingBatchBody,
          status: migrationStatus,
        ),
        MigrationViewState.signingBatch => _PhaseStatusView(
          title: MigrationCopy.signingBatchTitle,
          body: MigrationCopy.signingBatchBody,
          status: migrationStatus,
        ),
        MigrationViewState.broadcastScheduled => _PhaseStatusView(
          title: MigrationCopy.broadcastScheduledTitle,
          body: MigrationCopy.broadcastScheduledBody,
          status: migrationStatus,
        ),
        MigrationViewState.broadcasting => _PhaseStatusView(
          title: MigrationCopy.broadcastingStatusTitle,
          body: MigrationCopy.broadcastingStatusBody,
          status: migrationStatus,
        ),
        MigrationViewState.waitingMigrationConfirmations => _InProgressView(
          migrationTransactions: currentRunMigrationTransactions,
          expectedTransferCount: effectiveExpectedCount,
          amountZatoshi: _migrationDisplayAmount(
            sync,
            currentRunMigrationTransactions,
          ),
        ),
        MigrationViewState.complete => const _CompleteView(),
        MigrationViewState.paused => _PhaseStatusView(
          title: MigrationCopy.pausedTitle,
          body: MigrationCopy.pausedBody,
          status: migrationStatus,
          actionLabel: MigrationCopy.readyPreparedCta,
          onAction: _startSigning,
        ),
        MigrationViewState.failedRecoverable => _PhaseStatusView(
          title: MigrationCopy.failedRecoverableTitle,
          body: MigrationCopy.failedRecoverableBody,
          details: migrationStatus?.message,
          status: migrationStatus,
          actionLabel: MigrationCopy.retryCta,
          onAction: _startSigning,
        ),
        MigrationViewState.failedTerminal => _PhaseStatusView(
          title: MigrationCopy.failedTerminalTitle,
          body: MigrationCopy.failedTerminalBody,
          details: migrationStatus?.message,
          status: migrationStatus,
        ),
        MigrationViewState.abandoned => const _PhaseStatusView(
          title: MigrationCopy.abandonedTitle,
          body: MigrationCopy.abandonedBody,
        ),
      };
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
        child: Stack(
          fit: StackFit.expand,
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: body,
            ),
            if (_signing)
              MigrationSigningOverlay(
                onCancel: _cancelSigning,
                onComplete: _completeSigning,
              ),
          ],
        ),
      ),
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

class _PhaseStatusView extends StatelessWidget {
  const _PhaseStatusView({
    required this.title,
    required this.body,
    this.details,
    this.status,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String body;
  final String? details;
  final rust_sync.MigrationStatus? status;
  final String? actionLabel;
  final VoidCallback? onAction;

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
        const SizedBox(height: AppSpacing.md),
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppIcon(
                    AppIcons.time,
                    size: AppIconSize.medium,
                    color: colors.icon.muted,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      _statusSummary(status),
                      key: const ValueKey('migration_phase_summary'),
                      style: AppTypography.bodyMedium.copyWith(
                        color: colors.text.accent,
                      ),
                    ),
                  ),
                ],
              ),
              if (status != null) ...[
                const SizedBox(height: AppSpacing.s),
                _MigrationRunCounts(status: status!),
              ],
              if (details != null && details!.trim().isNotEmpty) ...[
                const SizedBox(height: AppSpacing.s),
                Text(
                  details!,
                  style: AppTypography.bodyExtraSmall.copyWith(
                    color: colors.text.secondary,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (actionLabel != null && onAction != null) ...[
          const SizedBox(height: AppSpacing.md),
          AppButton(
            onPressed: onAction,
            leading: const AppIcon(AppIcons.doubleArrowVertical),
            child: Text(actionLabel!),
          ),
        ],
      ],
    );
  }

  String _statusSummary(rust_sync.MigrationStatus? status) {
    if (status == null) return 'No active migration run.';
    final total = status.totalCount;
    if (total == 0) return 'Run ${status.activeRunId ?? ''}'.trim();
    return '${status.broadcastedTxCount} of $total migration transactions submitted.';
  }
}

class _MigrationRunCounts extends StatelessWidget {
  const _MigrationRunCounts({required this.status});

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

    return Column(
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
    );
  }
}

class _IdleView extends StatelessWidget {
  const _IdleView({required this.onStart, required this.orchardBalance});
  final VoidCallback onStart;
  final BigInt orchardBalance;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final amount = ZecAmount.fromZatoshi(
      orchardBalance,
    ).pretty(denomStyle: ZecDenomStyle.upper).toString();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          MigrationCopy.idleTitle,
          style: AppTypography.displaySmall.copyWith(color: colors.text.accent),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          MigrationCopy.idleBody,
          style: AppTypography.bodyMedium.copyWith(
            color: colors.text.secondary,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        const _PoolTransition(),
        const SizedBox(height: AppSpacing.md),
        _Card(
          child: Column(
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
          ),
        ),
        const SizedBox(height: AppSpacing.s),
        const _Bullets(),
        const SizedBox(height: AppSpacing.md),
        AppButton(
          key: const ValueKey('migration_start_button'),
          onPressed: onStart,
          leading: const AppIcon(AppIcons.doubleArrowVertical),
          child: const Text(MigrationCopy.startCta),
        ),
      ],
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

class _InProgressView extends StatelessWidget {
  const _InProgressView({
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
          MigrationCopy.inProgressTitle,
          key: const ValueKey('migration_in_progress_title'),
          style: AppTypography.displaySmall.copyWith(color: colors.text.accent),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          MigrationCopy.inProgressBody,
          style: AppTypography.bodyMedium.copyWith(
            color: colors.text.secondary,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        _Card(
          child: Column(
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
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.s),
        _Card(
          child: Column(
            children: [
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
          ),
        ),
        const SizedBox(height: AppSpacing.s),
        _Card(
          child: Row(
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
                  MigrationCopy.keepOpenWarning,
                  style: AppTypography.bodyExtraSmall.copyWith(
                    color: colors.text.secondary,
                  ),
                ),
              ),
            ],
          ),
        ),
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

class _CompleteView extends StatelessWidget {
  const _CompleteView();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          MigrationCopy.doneTitle,
          key: const ValueKey('migration_done_title'),
          style: AppTypography.displaySmall.copyWith(color: colors.text.accent),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          MigrationCopy.doneBody,
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

class _Bullets extends StatelessWidget {
  const _Bullets();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    Widget bullet(String text) => Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '›  ',
            style: AppTypography.bodyMedium.copyWith(
              color: colors.text.secondary,
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: AppTypography.bodyMedium.copyWith(
                color: colors.text.secondary,
              ),
            ),
          ),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        bullet(MigrationCopy.bullet1),
        bullet(MigrationCopy.bullet2),
        bullet(MigrationCopy.bullet3),
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
