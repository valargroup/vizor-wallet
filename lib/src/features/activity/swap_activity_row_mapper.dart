import 'package:flutter/widgets.dart';

import '../../core/privacy/privacy_mask.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_icon.dart';
import '../swap/models/swap_prototype_models.dart';
import 'activity_row_mapper.dart';
import 'models/activity_row_data.dart';

const _swapActivityAmountPrivacyMaskLength = 3;

List<ActivityRowData> buildSwapActivityRows({
  required BuildContext context,
  required Iterable<SwapIntentRecord> records,
  bool privacyModeEnabled = false,
  ValueChanged<SwapIntentRecord>? onSwapTap,
}) {
  return [
    for (final record in records)
      buildSwapActivityRow(
        context: context,
        record: record,
        privacyModeEnabled: privacyModeEnabled,
        onTap: onSwapTap == null ? null : () => onSwapTap(record),
      ),
  ];
}

ActivityRowData buildSwapActivityRow({
  required BuildContext context,
  required SwapIntentRecord record,
  bool privacyModeEnabled = false,
  VoidCallback? onTap,
}) {
  final colors = context.colors;
  final failed = _swapActivityFailed(record.status);
  final returnsFunds = _swapActivityReturnsFunds(record.status);
  final actionNeeded = _swapActivityNeedsAction(record.status);
  final complete = record.status == SwapIntentStatus.complete;
  final sellAsset = _swapActivitySellAsset(record);
  final progress = _swapActivityProgress(record.status);

  return ActivityRowData(
    title: _swapActivityTitle(record.status),
    leadingIconName: AppIcons.swapArrows,
    leadingBackgroundColor: colors.background.neutralSubtleOpacity,
    leadingIconColor: colors.icon.regular,
    leadingProgressValue: progress?.value,
    subtitle: _swapActivityAssetSubtitle(sellAsset) ?? record.providerLabel,
    amountText: _swapActivityAmountText(
      record,
      includeSign: !returnsFunds,
      privacyModeEnabled: privacyModeEnabled,
    ),
    amountIconName: returnsFunds ? AppIcons.arrowBack : null,
    amountIconColor: returnsFunds ? colors.icon.regular : null,
    amountColor: colors.text.accent,
    amountSubtitle: returnsFunds ? 'Refunded' : null,
    statusText: _swapActivityStatusText(record.status, progress),
    statusIconName: failed
        ? AppIcons.skull
        : record.status == SwapIntentStatus.refunded
        ? AppIcons.arrowBack
        : actionNeeded
        ? AppIcons.warning
        : complete
        ? null
        : AppIcons.loader,
    statusColor: failed
        ? colors.text.destructive
        : actionNeeded
        ? colors.text.brandCrimson
        : colors.text.secondary,
    timestampText: formatActivityTimestamp(record.activityTimestamp),
    onTap: onTap,
  );
}

String _swapActivityAmountText(
  SwapIntentRecord record, {
  required bool includeSign,
  required bool privacyModeEnabled,
}) {
  if (privacyModeEnabled) {
    return hideAmountIfPrivacyMode(
      '',
      privacyModeEnabled: true,
      maskLength: _swapActivityAmountPrivacyMaskLength,
    );
  }
  final amount = record.sellAmountText;
  if (amount.trim().isEmpty) return '--';
  if (!includeSign) return amount;
  return '-$amount';
}

String _swapActivityStatusText(
  SwapIntentStatus status,
  _SwapActivityProgress? progress,
) {
  return switch (status) {
    SwapIntentStatus.awaitingDeposit ||
    SwapIntentStatus.awaitingExternalDeposit ||
    SwapIntentStatus.incompleteDeposit => 'Action needed',
    SwapIntentStatus.depositObserved ||
    SwapIntentStatus.processing => progress?.label ?? 'In progress',
    SwapIntentStatus.providerStatusUnknown => 'Checking',
    SwapIntentStatus.complete => 'Completed',
    SwapIntentStatus.refunded => 'Refunded',
    SwapIntentStatus.expired => 'Expired',
    SwapIntentStatus.failed => 'Failed',
  };
}

class _SwapActivityProgress {
  const _SwapActivityProgress({
    required this.currentStep,
    required this.totalSteps,
  });

  final int currentStep;
  final int totalSteps;

  double get value => currentStep / totalSteps;

  String get label => '$currentStep/$totalSteps In progress';
}

bool _swapActivityFailed(SwapIntentStatus status) {
  return status == SwapIntentStatus.failed ||
      status == SwapIntentStatus.expired;
}

bool _swapActivityReturnsFunds(SwapIntentStatus status) {
  return _swapActivityFailed(status) || status == SwapIntentStatus.refunded;
}

bool _swapActivityNeedsAction(SwapIntentStatus status) {
  return status == SwapIntentStatus.awaitingDeposit ||
      status == SwapIntentStatus.awaitingExternalDeposit ||
      status == SwapIntentStatus.incompleteDeposit;
}

String _swapActivityTitle(SwapIntentStatus status) {
  return switch (status) {
    SwapIntentStatus.complete => 'Swapped',
    SwapIntentStatus.failed || SwapIntentStatus.expired => 'Swap failed',
    SwapIntentStatus.refunded => 'Swap refunded',
    _ => 'Swapping...',
  };
}

SwapAsset? _swapActivitySellAsset(SwapIntentRecord record) {
  final direction = record.direction;
  final externalAsset = record.externalAsset;
  if (direction == null || externalAsset == null) return null;
  return direction.fromAsset(externalAsset);
}

String? _swapActivityAssetSubtitle(SwapAsset? asset) {
  if (asset == null) return null;
  if (asset.isNativeZec) return '${asset.symbol} ${asset.chainLabel}';
  return '${asset.symbol} on ${asset.chainLabel}';
}

_SwapActivityProgress? _swapActivityProgress(SwapIntentStatus status) {
  return switch (status) {
    SwapIntentStatus.depositObserved || SwapIntentStatus.processing =>
      const _SwapActivityProgress(currentStep: 1, totalSteps: 4),
    SwapIntentStatus.awaitingDeposit ||
    SwapIntentStatus.awaitingExternalDeposit ||
    SwapIntentStatus.incompleteDeposit ||
    SwapIntentStatus.providerStatusUnknown ||
    SwapIntentStatus.complete ||
    SwapIntentStatus.refunded ||
    SwapIntentStatus.expired ||
    SwapIntentStatus.failed => null,
  };
}
