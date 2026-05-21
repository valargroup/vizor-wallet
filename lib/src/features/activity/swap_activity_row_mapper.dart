import 'package:flutter/widgets.dart';

import '../../core/privacy/privacy_mask.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_icon.dart';
import '../swap/models/swap_intent_presentation_mapper.dart';
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
  final actionNeeded = _swapActivityNeedsAction(record.status);
  final complete = record.status == SwapIntentStatus.complete;
  final inboundZec = record.direction == SwapDirection.externalToZec;

  return ActivityRowData(
    title: 'Swap ${swapIntentTitle(record)}',
    leadingIconName: _swapActivityIcon(record.status),
    leadingBackgroundColor: colors.background.neutralSubtleOpacity,
    leadingIconColor:
        failed
            ? colors.icon.destructive
            : actionNeeded
            ? colors.icon.brandCrimson
            : colors.icon.regular,
    subtitle: record.providerLabel,
    subtitleIconName: AppIcons.link,
    amountText: _swapActivityAmountText(
      record,
      inboundZec: inboundZec,
      privacyModeEnabled: privacyModeEnabled,
    ),
    amountIconName:
        record.status == SwapIntentStatus.refunded ? AppIcons.arrowBack : null,
    amountIconColor:
        record.status == SwapIntentStatus.refunded ? colors.icon.regular : null,
    amountColor: inboundZec ? colors.text.brandCrimson : colors.text.accent,
    statusText: _swapActivityStatusText(record.status),
    statusIconName:
        failed
            ? AppIcons.block
            : actionNeeded
            ? AppIcons.warning
            : complete
            ? AppIcons.checkCircle
            : AppIcons.loader,
    statusColor:
        failed
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
  required bool inboundZec,
  required bool privacyModeEnabled,
}) {
  if (privacyModeEnabled) {
    return hideAmountIfPrivacyMode(
      '',
      privacyModeEnabled: true,
      maskLength: _swapActivityAmountPrivacyMaskLength,
    );
  }
  final amount =
      inboundZec ? record.receiveEstimateText : record.sellAmountText;
  if (amount.trim().isEmpty) return '--';
  if (record.status == SwapIntentStatus.refunded) return amount;
  return inboundZec ? '+$amount' : '-$amount';
}

String _swapActivityStatusText(SwapIntentStatus status) {
  return switch (status) {
    SwapIntentStatus.awaitingDeposit ||
    SwapIntentStatus.awaitingExternalDeposit ||
    SwapIntentStatus.incompleteDeposit => 'Action needed',
    SwapIntentStatus.depositObserved ||
    SwapIntentStatus.processing => 'In progress',
    SwapIntentStatus.providerStatusUnknown => 'Checking',
    SwapIntentStatus.complete => 'Completed',
    SwapIntentStatus.refunded => 'Refunded',
    SwapIntentStatus.expired => 'Expired',
    SwapIntentStatus.failed => 'Failed',
  };
}

String _swapActivityIcon(SwapIntentStatus status) {
  return switch (status) {
    SwapIntentStatus.awaitingDeposit ||
    SwapIntentStatus.awaitingExternalDeposit => AppIcons.link,
    SwapIntentStatus.depositObserved => AppIcons.eye,
    SwapIntentStatus.processing => AppIcons.renew,
    SwapIntentStatus.providerStatusUnknown ||
    SwapIntentStatus.incompleteDeposit => AppIcons.warning,
    SwapIntentStatus.complete => AppIcons.checkCircle,
    SwapIntentStatus.refunded => AppIcons.arrowBack,
    SwapIntentStatus.expired || SwapIntentStatus.failed => AppIcons.block,
  };
}

bool _swapActivityFailed(SwapIntentStatus status) {
  return status == SwapIntentStatus.failed ||
      status == SwapIntentStatus.expired;
}

bool _swapActivityNeedsAction(SwapIntentStatus status) {
  return status == SwapIntentStatus.awaitingDeposit ||
      status == SwapIntentStatus.awaitingExternalDeposit ||
      status == SwapIntentStatus.incompleteDeposit;
}
