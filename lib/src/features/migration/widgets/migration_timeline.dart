import 'package:flutter/material.dart';

import '../../../core/formatting/zec_amount.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../rust/api/sync.dart' as rust_sync;
import '../migration_copy.dart';
import '../models/migration_timeline_model.dart';

/// Connected three-node migration timeline (split → confirm → send). Pure
/// presentation: all state comes in via [model] and the data fields.
class MigrationTimeline extends StatelessWidget {
  const MigrationTimeline({
    required this.model,
    required this.status,
    required this.shares,
    required this.amountZatoshi,
    required this.totalShares,
    required this.now,
    this.confirming = false,
    this.onScanSends,
    this.onRetry,
    super.key,
  });

  final MigrationTimelineModel model;
  final rust_sync.MigrationStatus? status;

  /// Current-run migration transactions, newest first (as the screen scopes
  /// them today).
  final List<rust_sync.TransactionInfo> shares;
  final BigInt amountZatoshi;
  final int totalShares;
  final DateTime now;

  /// True while the run is in `waiting_migration_confirmations` (sends are out,
  /// awaiting confirmation).
  final bool confirming;

  /// Staged Keystone fallback: invoked by the Send node's "Scan to sign the
  /// sends" button.
  final VoidCallback? onScanSends;

  /// Recoverable-failure retry.
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _node(
          context,
          id: MigrationNodeId.split,
          isLast: false,
          title: MigrationCopy.splitTitle,
          child: _splitBody(context),
        ),
        _node(
          context,
          id: MigrationNodeId.confirm,
          isLast: false,
          title: MigrationCopy.confirmTitle,
          child: _confirmBody(context),
        ),
        _node(
          context,
          id: MigrationNodeId.send,
          isLast: true,
          title: confirming
              ? MigrationCopy.sendConfirmingTitle
              : MigrationCopy.sendTitle,
          child: _sendBody(context),
        ),
      ],
    );
  }

  Widget _node(
    BuildContext context, {
    required MigrationNodeId id,
    required bool isLast,
    required String title,
    required Widget child,
  }) {
    final colors = context.colors;
    final nodeStatus = model.statusFor(id);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              _Dot(status: nodeStatus),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 2),
                    color: nodeStatus == MigrationNodeStatus.done
                        ? colors.icon.success
                        : colors.border.subtle,
                  ),
                ),
            ],
          ),
          const SizedBox(width: AppSpacing.s),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTypography.bodyMediumStrong.copyWith(
                      color: nodeStatus == MigrationNodeStatus.pending
                          ? colors.text.secondary
                          : colors.text.accent,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  child,
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _splitBody(BuildContext context) {
    final colors = context.colors;
    if (model.split == MigrationNodeStatus.error) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            status?.message ?? MigrationCopy.failedRecoverableBody,
            style: AppTypography.bodySmall.copyWith(
              color: colors.text.destructive,
            ),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: AppSpacing.s),
            AppButton(
              onPressed: onRetry,
              child: const Text(MigrationCopy.retryCta),
            ),
          ],
        ],
      );
    }
    final text = switch (model.split) {
      MigrationNodeStatus.active => MigrationCopy.splitActive,
      MigrationNodeStatus.done => status != null && status!.totalCount > 0
          ? MigrationCopy.splitDone(status!.totalCount)
          : MigrationCopy.splitDoneGeneric,
      MigrationNodeStatus.pending => '',
      MigrationNodeStatus.error => '',
    };
    if (text.isEmpty) return const SizedBox.shrink();
    return Text(
      text,
      style: AppTypography.bodySmall.copyWith(color: colors.text.secondary),
    );
  }

  Widget _confirmBody(BuildContext context) {
    final colors = context.colors;
    if (model.confirm == MigrationNodeStatus.active) {
      final target = (status?.denominationConfirmationTarget ?? 3).clamp(1, 99);
      final count = (status?.denominationConfirmationCount ?? 0)
          .clamp(0, target)
          .toInt();
      return Text(
        MigrationCopy.confirmActive(count, target),
        style: AppTypography.bodySmall.copyWith(color: colors.text.secondary),
      );
    }
    if (model.confirm == MigrationNodeStatus.done) {
      return Text(
        MigrationCopy.confirmDone,
        style: AppTypography.bodySmall.copyWith(color: colors.text.secondary),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _sendBody(BuildContext context) {
    final colors = context.colors;
    if (model.send == MigrationNodeStatus.pending) {
      return const SizedBox.shrink();
    }
    if (model.send == MigrationNodeStatus.error) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            status?.message ?? MigrationCopy.failedRecoverableBody,
            style: AppTypography.bodySmall.copyWith(
              color: colors.text.destructive,
            ),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: AppSpacing.s),
            AppButton(
              onPressed: onRetry,
              child: const Text(MigrationCopy.retryCta),
            ),
          ],
        ],
      );
    }

    // active or done
    final rows = shares.reversed.toList(growable: false); // oldest -> newest
    final total = [rows.length, totalShares, 1].reduce((a, b) => a > b ? a : b);
    final confirmed = rows.where(_isConfirmed).length;
    final amount = ZecAmount.fromZatoshi(
      amountZatoshi,
    ).pretty(denomStyle: ZecDenomStyle.upper).toString();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          MigrationCopy.migratingAmount(amount),
          style: AppTypography.bodySmall.copyWith(color: colors.text.secondary),
        ),
        const SizedBox(height: AppSpacing.xs),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadii.xSmall),
          child: LinearProgressIndicator(
            value: total == 0 ? 0.0 : confirmed / total,
            minHeight: 6,
            backgroundColor: colors.background.neutralSubtleOpacity,
            color: colors.icon.success,
          ),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          MigrationCopy.sendProgress(confirmed, total),
          style: AppTypography.bodyExtraSmall.copyWith(
            color: colors.text.secondary,
          ),
        ),
        if (model.sendNeedsScan && onScanSends != null) ...[
          const SizedBox(height: AppSpacing.s),
          AppButton(
            onPressed: onScanSends,
            child: const Text(MigrationCopy.sendScanCta),
          ),
        ],
        const SizedBox(height: AppSpacing.s),
        for (var i = 0; i < total; i++) ...[
          if (i > 0) Divider(height: AppSpacing.md, color: colors.border.subtle),
          _ShareRow(
            index: i,
            transaction: i < rows.length ? rows[i] : null,
            now: now,
          ),
        ],
      ],
    );
  }
}

bool _isConfirmed(rust_sync.TransactionInfo tx) =>
    tx.minedHeight != BigInt.zero && !tx.expiredUnmined;

class _Dot extends StatelessWidget {
  const _Dot({required this.status});

  final MigrationNodeStatus status;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    switch (status) {
      case MigrationNodeStatus.done:
        return AppIcon(
          AppIcons.checkCircle,
          size: AppIconSize.medium,
          color: colors.icon.success,
        );
      case MigrationNodeStatus.error:
        return AppIcon(
          AppIcons.warning,
          size: AppIconSize.medium,
          color: colors.icon.destructive,
        );
      case MigrationNodeStatus.active:
        return SizedBox(
          width: AppIconSize.medium,
          height: AppIconSize.medium,
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: colors.icon.success,
            ),
          ),
        );
      case MigrationNodeStatus.pending:
        return Container(
          width: AppIconSize.medium,
          height: AppIconSize.medium,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: colors.border.subtle, width: 2),
          ),
        );
    }
  }
}

class _ShareRow extends StatelessWidget {
  const _ShareRow({
    required this.index,
    required this.transaction,
    required this.now,
  });

  final int index;
  final rust_sync.TransactionInfo? transaction;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final tx = transaction;
    final isFailed = tx?.expiredUnmined ?? false;
    final isConfirmed = tx != null && _isConfirmed(tx);
    final isSending = tx != null && !isConfirmed && !isFailed;
    final statusText = isFailed
        ? MigrationCopy.shareFailed
        : isConfirmed
        ? MigrationCopy.shareConfirmed
        : isSending
        ? MigrationCopy.shareSending
        : MigrationCopy.shareScheduled;
    final icon = isFailed
        ? AppIcons.warning
        : isConfirmed
        ? AppIcons.checkCircle
        : AppIcons.time;
    final iconColor = isFailed
        ? colors.icon.destructive
        : isConfirmed
        ? colors.icon.success
        : colors.icon.muted;

    return Row(
      children: [
        AppIcon(icon, size: AppIconSize.medium, color: iconColor),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Text(
            MigrationCopy.shareLabel(index + 1),
            style: AppTypography.bodyMedium.copyWith(color: colors.text.accent),
          ),
        ),
        Text(
          statusText,
          style: AppTypography.bodyMedium.copyWith(color: colors.text.secondary),
        ),
      ],
    );
  }
}
