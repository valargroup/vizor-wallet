import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../../main.dart' show log;
import 'live_activity_service.dart';

const _iosChannel = MethodChannel('com.zcash.wallet/background_sync');

/// Checks if background sync is available on this platform/version.
Future<bool> isBackgroundSyncAvailable() async {
  if (Platform.isAndroid) {
    return true; // Always available on Android via foreground service
  }
  if (Platform.isIOS) {
    try {
      final available = await _iosChannel.invokeMethod<bool>('isAvailable');
      return available ?? false;
    } catch (_) {
      return false;
    }
  }
  return false;
}

/// Start background sync with platform notification.
Future<void> startBackgroundSync() async {
  if (Platform.isAndroid) {
    await _startAndroidForegroundService();
  } else if (Platform.isIOS) {
    await LiveActivityService.instance.startSyncActivity();
    try {
      final success = await _iosChannel.invokeMethod<bool>('startBackgroundSync');
      log('BackgroundSync: iOS BGTask submitted: $success');
    } catch (e) {
      log('BackgroundSync: iOS BGTask failed: $e');
    }
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
  } else if (Platform.isIOS) {
    await LiveActivityService.instance.updateProgress(
      percentage: percentage,
      scannedHeight: scannedHeight,
      chainTipHeight: chainTipHeight,
    );
  }
}

/// Stop background sync service.
Future<void> stopBackgroundSync() async {
  if (Platform.isAndroid) {
    await FlutterForegroundTask.stopService();
  } else if (Platform.isIOS) {
    await LiveActivityService.instance.stopSyncActivity();
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
