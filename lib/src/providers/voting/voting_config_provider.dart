import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../rust/api/voting_config.dart';
import '../../rust/third_party/zcash_voting/config.dart';
import '../../services/voting/voting_models.dart';
import 'voting_config_source_provider.dart';
import 'voting_rounds_provider.dart';
import 'voting_service_providers.dart';
import 'voting_session_provider.dart';
import 'voting_submission_guard_provider.dart';
import 'voting_tree_sync_provider.dart';

class VotingConfigRefreshFailure {
  const VotingConfigRefreshFailure({
    required this.error,
    required this.stackTrace,
  });

  final Object error;
  final StackTrace stackTrace;
}

class VotingConfigRefreshFailureNotifier
    extends Notifier<VotingConfigRefreshFailure?> {
  @override
  VotingConfigRefreshFailure? build() => null;

  void clear() {
    state = null;
  }

  void record({required Object error, required StackTrace stackTrace}) {
    state = VotingConfigRefreshFailure(error: error, stackTrace: stackTrace);
  }
}

/// Side channel for the most recent refresh failure while keeping last-good
/// config data available during transient outages.
final votingConfigRefreshFailureProvider =
    NotifierProvider<
      VotingConfigRefreshFailureNotifier,
      VotingConfigRefreshFailure?
    >(VotingConfigRefreshFailureNotifier.new);

/// Resolves the active dynamic voting configuration for the current source.
///
/// Initial resolution failures remain explicit `AsyncError`s so voting fails
/// closed. Refresh failures keep the last-good config for retryable transport
/// issues and expose the error via [votingConfigRefreshFailureProvider].
class VotingConfigNotifier extends AsyncNotifier<ResolvedVotingConfig> {
  int _loadGeneration = 0;
  ResolvedVotingConfig? _previousResolvedConfig;

  @override
  Future<ResolvedVotingConfig> build() async {
    final generation = ++_loadGeneration;
    ref.onDispose(() {
      _loadGeneration++;
    });
    try {
      final config = await _loadAndCommit(generation);
      if (config != null) return config;
      final latest = state.value;
      if (latest != null) return latest;
      final error = state.error;
      if (error != null) {
        Error.throwWithStackTrace(
          error,
          state.stackTrace ?? StackTrace.current,
        );
      }
      throw StateError('Ignored stale voting config load.');
    } catch (_) {
      if (!_isCurrentLoad(generation)) {
        final latest = state.value;
        if (latest != null) return latest;
        final error = state.error;
        if (error != null) {
          Error.throwWithStackTrace(
            error,
            state.stackTrace ?? StackTrace.current,
          );
        }
      }
      rethrow;
    }
  }

  Future<void> refresh() async {
    final generation = ++_loadGeneration;
    state = const AsyncLoading<ResolvedVotingConfig>();
    try {
      final config = await _loadAndCommit(generation);
      if (config == null) return;
      state = AsyncData(config);
    } catch (error, stackTrace) {
      if (!_isCurrentLoad(generation)) return;
      _recordRefreshFailure(error: error, stackTrace: stackTrace);
      final lastGoodConfig = _previousResolvedConfig;
      if (_isRetryableRefreshError(error) && lastGoodConfig != null) {
        state = AsyncData(lastGoodConfig);
        return;
      }
      state = AsyncError(error, stackTrace);
    }
  }

  bool _isCurrentLoad(int generation) {
    return ref.mounted && generation == _loadGeneration;
  }

  /// Resolves config and commits cache mutations only for active loads.
  ///
  /// Returning `null` signals this generation became stale while resolving.
  Future<ResolvedVotingConfig?> _loadAndCommit(int generation) async {
    await ref.read(votingConfigSourceProvider.future);
    final resolution = await _loadWithConfigRetry(
      () => ref
          .read(votingConfigLoaderProvider)
          .load(previous: _previousResolvedConfig),
    );
    if (!_isCurrentLoad(generation)) return null;
    return _commitResolution(resolution);
  }

  ResolvedVotingConfig _commitResolution(VotingConfigResolution resolution) {
    _applySwitch(resolution.switchKind);
    _previousResolvedConfig = resolution.config;
    _clearRefreshFailure();
    return resolution.config;
  }

  void _clearRefreshFailure() {
    ref.read(votingConfigRefreshFailureProvider.notifier).clear();
  }

  void _recordRefreshFailure({
    required Object error,
    required StackTrace stackTrace,
  }) {
    ref
        .read(votingConfigRefreshFailureProvider.notifier)
        .record(error: error, stackTrace: stackTrace);
  }

  /// Applies the Rust-computed switch plan to dependent voting state.
  ///
  /// `unchanged`/`initialLoad` keep all caches. The remaining kinds all imply
  /// the vote/PIR endpoints, signing keys, rounds, or protocol moved, so
  /// endpoint-dependent caches are rebuilt to force re-resolution against the new
  /// config:
  ///
  /// - shared transport/client + PIR resolver caches via [_invalidateEndpointState];
  /// - the poll list ([votingRoundsProvider]) and the interactive session
  ///   ([votingSessionProvider]) so status polls and session setup rerun;
  /// - the submission-session family ([votingSubmissionSessionProvider]) so a
  ///   subsequent submission re-resolves its endpoints. Active submission guards
  ///   keep existing sessions alive until their jobs release process-local state.
  void _applySwitch(ConfigSwitchKind kind) {
    switch (kind) {
      case ConfigSwitchKind.unchanged:
      case ConfigSwitchKind.initialLoad:
        return;
      case ConfigSwitchKind.sameChainServiceUpdate:
      case ConfigSwitchKind.newChainOrRound:
      case ConfigSwitchKind.protocolChanged:
        _invalidateEndpointState();
        ref.invalidate(votingRoundsProvider);
        if (ref.read(votingSubmissionGuardProvider).isEmpty) {
          ref.invalidate(votingSessionProvider);
          ref.invalidate(votingSubmissionSessionProvider);
        }
        return;
    }
  }

  void _invalidateEndpointState() {
    ref.invalidate(votingApiClientProvider);
    ref.invalidate(votingHelperHealthTrackerProvider);
    ref.invalidate(votingPirResolverProvider);
    ref.invalidate(votingTreePreSyncProvider);
  }

  Future<T> _loadWithConfigRetry<T>(Future<T> Function() operation) async {
    const delays = <Duration>[
      Duration(milliseconds: 200),
      Duration(milliseconds: 600),
    ];
    Object? lastError;
    for (var attempt = 0; attempt <= delays.length; attempt++) {
      try {
        return await operation();
      } catch (error) {
        lastError = error;
        if (attempt == delays.length || !_isRetryableRefreshError(error)) {
          rethrow;
        }
        await Future<void>.delayed(delays[attempt]);
      }
    }
    throw StateError('Config retry exhausted unexpectedly: $lastError');
  }

  bool _isRetryableRefreshError(Object error) {
    if (error is TimeoutException ||
        error is SocketException ||
        error is HttpException) {
      return true;
    }
    if (error is VotingHttpException) {
      return error.statusCode == 502 || error.statusCode == 503;
    }
    return false;
  }
}

final votingConfigProvider =
    AsyncNotifierProvider<VotingConfigNotifier, ResolvedVotingConfig>(
      VotingConfigNotifier.new,
    );
