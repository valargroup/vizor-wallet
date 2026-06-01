import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/voting/voting_flow_models.dart';
import '../../features/voting/voting_resume_plan.dart';
import '../../rust/third_party/zcash_voting/wire.dart' as rust_voting;
import '../../services/voting/voting_api_client.dart';
import '../../services/voting/voting_models.dart';
import 'voting_config_provider.dart';
import 'voting_service_providers.dart';
import 'voting_state.dart';

/// Provides poll-list rows and route-controlled polling.
///
/// Polling is opt-in through [startPolling] so screens can pause network traffic
/// when the voting tab is not mounted or visible.
class VotingRoundsNotifier extends AsyncNotifier<List<VotingRoundView>> {
  static const defaultPollInterval = Duration(seconds: 10);

  Timer? _pollTimer;
  bool _pollingRequested = false;
  Duration _pollInterval = defaultPollInterval;
  bool _refreshInFlight = false;
  int _loadGeneration = 0;

  @override
  Future<List<VotingRoundView>> build() async {
    final generation = ++_loadGeneration;
    ref.onDispose(() {
      _loadGeneration++;
      _refreshInFlight = false;
      _cancelPollTimer();
    });
    ref.watch(votingActiveAccountUuidProvider);
    if (_pollingRequested) {
      _startPollTimer(_pollInterval);
    }
    return _load(generation: generation);
  }

  void startPolling({Duration interval = defaultPollInterval}) {
    _pollingRequested = true;
    if (_pollInterval != interval) {
      _cancelPollTimer();
      _pollInterval = interval;
    }
    _startPollTimer(interval);
    unawaited(refresh());
  }

  void stopPolling() {
    _pollingRequested = false;
    _pollInterval = defaultPollInterval;
    _cancelPollTimer();
  }

  void _startPollTimer(Duration interval) {
    if (_pollTimer != null) return;
    _pollTimer = Timer.periodic(interval, (_) => refresh());
  }

  void _cancelPollTimer() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<void> refresh() async {
    final generation = _loadGeneration;
    if (!_isCurrentLoad(generation)) return;
    if (_refreshInFlight || state.isLoading) return;
    _refreshInFlight = true;
    final previous = state.value;
    if (previous == null) {
      state = const AsyncLoading<List<VotingRoundView>>();
    }
    try {
      final rounds = await _load(generation: generation);
      if (!_isCurrentLoad(generation)) return;
      state = AsyncData(rounds);
    } catch (error, stackTrace) {
      if (!_isCurrentLoad(generation)) return;
      if (previous == null) {
        state = AsyncError(error, stackTrace);
      } else {
        debugPrint(
          '[zcash] Voting: keeping previous poll list after refresh failed: '
          '$error',
        );
      }
    } finally {
      if (generation == _loadGeneration) {
        _refreshInFlight = false;
      }
    }
  }

  bool _isCurrentLoad(int generation) {
    return ref.mounted && generation == _loadGeneration;
  }

  Future<List<VotingRoundView>> _load({required int generation}) async {
    final config = await ref.read(votingConfigProvider.future);
    if (!_isCurrentLoad(generation)) return const [];
    final api = ref.read(votingApiClientProvider(config.apiBaseUrl));
    final endorser = ref.read(votingEndorserClientProvider(config.apiBaseUrl));

    final rounds = await api.listRounds();
    if (!_isCurrentLoad(generation)) return const [];
    final endorsedIds = await endorser.getEndorsedSet();
    if (!_isCurrentLoad(generation)) return const [];
    final recoveryStates = await _roundListRecoveryStates(
      rounds,
      api: api,
      generation: generation,
    );
    if (!_isCurrentLoad(generation)) return const [];
    return [
      for (final round in rounds)
        VotingRoundView.fromSummary(
          round,
          endorsed: endorsedIds.contains(round.roundId),
          voted: recoveryStates[round.roundId]?.voted ?? false,
          inProgress: recoveryStates[round.roundId]?.inProgress ?? false,
        ),
    ];
  }

  Future<Map<String, _RoundListRecoveryState>> _roundListRecoveryStates(
    Iterable<VotingRoundSummary> rounds, {
    required VotingApiClient api,
    required int generation,
  }) async {
    final String accountUuid;
    final String dbPath;
    try {
      if (!_isCurrentLoad(generation)) return const {};
      final activeAccountUuid = await ref
          .read(votingActiveAccountUuidProvider)
          .call();
      if (!_isCurrentLoad(generation)) return const {};
      if (activeAccountUuid == null) return const {};
      accountUuid = activeAccountUuid;
      dbPath = await ref.read(votingWalletDbPathProvider).call();
      if (!_isCurrentLoad(generation)) return const {};
    } catch (error) {
      debugPrint('[zcash] Voting: skipped poll-state lookup: $error');
      return const {};
    }
    final states = <String, _RoundListRecoveryState>{};
    for (final round in rounds) {
      try {
        final recoveryState = await _roundListRecoveryState(
          api: api,
          dbPath: dbPath,
          accountUuid: accountUuid,
          round: round,
          generation: generation,
        );
        if (recoveryState.voted || recoveryState.inProgress) {
          states[round.roundId] = recoveryState;
        }
      } catch (error) {
        debugPrint(
          '[zcash] Voting: skipped poll-state lookup for round '
          '${round.roundId}: '
          '$error',
        );
      }
    }
    return states;
  }

  Future<_RoundListRecoveryState> _roundListRecoveryState({
    required VotingApiClient api,
    required VotingRoundSummary round,
    required String dbPath,
    required String accountUuid,
    required int generation,
  }) async {
    if (!_isCurrentLoad(generation)) {
      return const _RoundListRecoveryState(voted: false, inProgress: false);
    }
    final recovery = ref.read(votingRecoveryServiceProvider);
    final proposalIds = await _proposalIdsForRound(api, round);
    if (!_isCurrentLoad(generation)) {
      return const _RoundListRecoveryState(voted: false, inProgress: false);
    }
    rust_voting.RoundPlanView? roundPlan;
    if (proposalIds.isNotEmpty) {
      try {
        roundPlan = await recovery.loadRoundPlan(
          dbPath: dbPath,
          accountUuid: accountUuid,
          roundId: round.roundId,
          proposalIds: proposalIds,
        );
      } catch (error) {
        debugPrint(
          '[zcash] Voting: skipped in-progress lookup for round '
          '${round.roundId}: $error',
        );
      }
    }
    if (hasBlockingRoundRecoveryWork(roundPlan)) {
      return const _RoundListRecoveryState(voted: false, inProgress: true);
    }
    if (hasCompletedVoteForDisplay(roundPlan)) {
      return const _RoundListRecoveryState(voted: true, inProgress: false);
    }

    return _RoundListRecoveryState(
      voted: false,
      inProgress: roundPlan?.pendingRecovery ?? false,
    );
  }

  List<int> _proposalIdsFromRoundJson(Map<String, dynamic> json) {
    try {
      return proposalsFromJson(json).map((proposal) => proposal.id).toList();
    } catch (error) {
      debugPrint(
        '[zcash] Voting: skipped proposal-id lookup for poll list row: $error',
      );
      return const [];
    }
  }

  Future<List<int>> _proposalIdsForRound(
    VotingApiClient api,
    VotingRoundSummary round,
  ) async {
    final summaryProposalIds = _proposalIdsFromRoundJson(round.rawJson);
    if (summaryProposalIds.isNotEmpty) return summaryProposalIds;

    try {
      final status = await api.getRoundStatus(round.roundId);
      return _proposalIdsFromRoundJson(status.rawJson);
    } catch (error) {
      debugPrint(
        '[zcash] Voting: skipped round detail lookup for poll-state lookup '
        'for round ${round.roundId}: $error',
      );
      return const [];
    }
  }
}

final votingRoundsProvider =
    AsyncNotifierProvider<VotingRoundsNotifier, List<VotingRoundView>>(
      VotingRoundsNotifier.new,
    );

class _RoundListRecoveryState {
  const _RoundListRecoveryState({
    required this.voted,
    required this.inProgress,
  });

  final bool voted;
  final bool inProgress;
}
