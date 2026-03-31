import 'dart:io';

import 'package:live_activities/live_activities.dart';

import '../../main.dart' show log;

/// Manages iOS Live Activity for sync progress (Dynamic Island + Lock Screen).
/// No-ops on non-iOS platforms and devices that don't support Live Activities.
class LiveActivityService {
  static final LiveActivityService _instance = LiveActivityService._();
  static LiveActivityService get instance => _instance;
  LiveActivityService._();

  static const _appGroupId = 'group.com.zcash.zcashWallet';

  final _liveActivitiesPlugin = LiveActivities();
  String? _activityId;
  bool _enabled = false;
  bool _initialized = false;

  Future<void> _ensureInit() async {
    if (_initialized) return;
    await _liveActivitiesPlugin.init(appGroupId: _appGroupId);
    _initialized = true;
  }

  /// Check if Live Activities are supported on this device.
  Future<bool> isSupported() async {
    if (!Platform.isIOS) return false;
    try {
      return await _liveActivitiesPlugin.areActivitiesEnabled();
    } catch (_) {
      return false;
    }
  }

  /// Start a Live Activity showing sync progress.
  Future<void> startSyncActivity() async {
    if (!Platform.isIOS || _activityId != null) return;

    try {
      await _ensureInit();
      final supported = await isSupported();
      if (!supported) return;

      _activityId = await _liveActivitiesPlugin.createActivity(
        'zcash-sync',
        {
          'percentage': 0.0,
          'scannedHeight': 0,
          'chainTipHeight': 0,
          'status': 'Starting sync...',
        },
        removeWhenAppIsKilled: true,
      );
      _enabled = true;
      log('LiveActivity: started with id=$_activityId');
    } catch (e) {
      log('LiveActivity: failed to start: $e');
    }
  }

  /// Update the Live Activity with new sync progress.
  Future<void> updateProgress({
    required double percentage,
    required int scannedHeight,
    required int chainTipHeight,
  }) async {
    if (!_enabled || _activityId == null) return;

    try {
      await _liveActivitiesPlugin.updateActivity(
        _activityId!,
        {
          'percentage': percentage,
          'scannedHeight': scannedHeight,
          'chainTipHeight': chainTipHeight,
          'status': 'Syncing ${(percentage * 100).toStringAsFixed(1)}%',
        },
      );
    } catch (e) {
      log('LiveActivity: failed to update: $e');
    }
  }

  /// End the Live Activity.
  Future<void> stopSyncActivity() async {
    if (_activityId == null) return;

    try {
      await _liveActivitiesPlugin.endActivity(_activityId!);
      log('LiveActivity: stopped');
    } catch (e) {
      log('LiveActivity: failed to stop: $e');
    }
    _activityId = null;
    _enabled = false;
  }
}
