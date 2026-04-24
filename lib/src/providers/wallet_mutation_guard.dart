import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'account_provider.dart';
import 'sync_provider.dart';

Future<T> runWithSyncPausedForAccountMutation<T>(
  WidgetRef ref,
  Future<T> Function() action, {
  FutureOr<void> Function()? onStoppingSync,
  FutureOr<void> Function()? onSyncPaused,
}) async {
  final hasExistingAccounts =
      (ref.read(accountProvider).value?.accounts ?? const <AccountInfo>[])
          .isNotEmpty;
  if (!hasExistingAccounts) {
    return action();
  }

  final pause = await ref
      .read(syncProvider.notifier)
      .pauseForWalletMutation(onStoppingSync: onStoppingSync);
  try {
    if (pause.hadWorkToPause) {
      await onSyncPaused?.call();
    }
    return await action();
  } finally {
    ref.read(syncProvider.notifier).resumeAfterWalletMutation(pause);
  }
}
