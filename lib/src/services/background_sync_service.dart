import 'dart:io';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../../main.dart' show log;

/// Checks if background sync is available on this platform/version.
Future<bool> isBackgroundSyncAvailable() async {
  if (Platform.isAndroid) {
    return true; // Always available on Android via foreground service
  }
  if (Platform.isIOS) {
    // BGContinuedProcessingTask requires iOS 26+
    // Parse version from Platform.operatingSystemVersion
    final versionStr = Platform.operatingSystemVersion;
    final match = RegExp(r'(\d+)\.').firstMatch(versionStr);
    if (match != null) {
      final major = int.tryParse(match.group(1)!) ?? 0;
      return major >= 26;
    }
    return false;
  }
  return false;
}

/// Start background sync with platform notification.
Future<void> startBackgroundSync() async {
  if (Platform.isAndroid) {
    await _startAndroidForegroundService();
  } else if (Platform.isIOS) {
    // iOS BGContinuedProcessingTask will be implemented in Step 3
    // For now, sync continues in foreground
    log('BackgroundSync: iOS background sync not yet implemented');
  }
}

/// Update background sync notification with progress.
Future<void> updateBackgroundSyncProgress({
  required double percentage,
  required int scannedHeight,
  required int chainTipHeight,
}) async {
  if (Platform.isAndroid) {
    final pct = (percentage * 100).toStringAsFixed(1);
    FlutterForegroundTask.updateService(
      notificationTitle: 'Zcash Wallet — Syncing $pct%',
      notificationText: 'Block $scannedHeight / $chainTipHeight',
    );
  }
  // iOS: Live Activity update will be added in Step 4
}

/// Stop background sync service.
Future<void> stopBackgroundSync() async {
  if (Platform.isAndroid) {
    await FlutterForegroundTask.stopService();
  }
}

/// Check if background sync is currently running.
Future<bool> isBackgroundSyncRunning() async {
  if (Platform.isAndroid) {
    return await FlutterForegroundTask.isRunningService;
  }
  return false;
}

// ======================== Android ========================

Future<void> _startAndroidForegroundService() async {
  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      channelId: 'zcash_sync',
      channelName: 'Zcash Sync',
      channelDescription: 'Blockchain synchronization progress',
      channelImportance: NotificationChannelImportance.LOW,
      priority: NotificationPriority.LOW,
      playSound: false,
      showBadge: false,
    ),
    iosNotificationOptions: const IOSNotificationOptions(
      showNotification: false,
    ),
    foregroundTaskOptions: ForegroundTaskOptions(
      eventAction: ForegroundTaskEventAction.nothing(),
      autoRunOnBoot: false,
      allowWakeLock: true,
      allowWifiLock: true,
    ),
  );

  await FlutterForegroundTask.startService(
    notificationTitle: 'Zcash Wallet',
    notificationText: 'Syncing blockchain...',
    serviceId: 1001,
  );

  log('BackgroundSync: Android foreground service started');
}
