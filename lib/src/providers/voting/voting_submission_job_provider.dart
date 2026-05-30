import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/voting/voting_error_messages.dart';
import '../../features/voting/voting_flow_models.dart';
import '../../features/voting/voting_resume_plan.dart';
import '../../rust/api/keystone.dart' as rust_keystone;
import '../../rust/api/wallet.dart' as rust_wallet;
import '../../rust/third_party/zcash_voting/wire.dart' as rust_wire;
import '../account_provider.dart';
import 'voting_session_provider.dart';
import 'voting_service_providers.dart';
import 'voting_state.dart';
import 'voting_submission_guard_provider.dart';

enum VotingSubmissionJobStatus {
  idle,
  running,
  waitingForKeystone,
  complete,
  error,
}

@immutable
class VotingSubmissionJobState {
  const VotingSubmissionJobState({
    this.key,
    this.status = VotingSubmissionJobStatus.idle,
    this.generation = 0,
    this.errorMessage,
    this.softwareAccountRequired = false,
    this.keystoneUrParts = const [],
    this.keystoneQrError,
    this.pendingDraftVotes,
    this.pendingProposalIds = const [],
    this.pendingProposalOptionCounts = const {},
    this.pendingRecoveryWithoutDraft = false,
  });

  final VotingSessionKey? key;
  final VotingSubmissionJobStatus status;
  final int generation;
  final String? errorMessage;
  final bool softwareAccountRequired;
  final List<String> keystoneUrParts;
  final String? keystoneQrError;
  final List<rust_wire.DraftVoteView>? pendingDraftVotes;
  final List<int> pendingProposalIds;
  final Map<int, int> pendingProposalOptionCounts;
  final bool pendingRecoveryWithoutDraft;

  bool get hasVisibleJob =>
      key != null && status != VotingSubmissionJobStatus.idle;

  bool get isInFlight =>
      status == VotingSubmissionJobStatus.running ||
      status == VotingSubmissionJobStatus.waitingForKeystone;

  bool get shouldWarnBeforeQuit => isInFlight;

  VotingSubmissionJobState copyWith({
    VotingSessionKey? key,
    VotingSubmissionJobStatus? status,
    int? generation,
    String? errorMessage,
    bool clearErrorMessage = false,
    bool? softwareAccountRequired,
    List<String>? keystoneUrParts,
    String? keystoneQrError,
    bool clearKeystoneQrError = false,
    List<rust_wire.DraftVoteView>? pendingDraftVotes,
    bool clearPendingDraftVotes = false,
    List<int>? pendingProposalIds,
    Map<int, int>? pendingProposalOptionCounts,
    bool? pendingRecoveryWithoutDraft,
  }) {
    return VotingSubmissionJobState(
      key: key ?? this.key,
      status: status ?? this.status,
      generation: generation ?? this.generation,
      errorMessage: clearErrorMessage
          ? null
          : errorMessage ?? this.errorMessage,
      softwareAccountRequired:
          softwareAccountRequired ?? this.softwareAccountRequired,
      keystoneUrParts: keystoneUrParts ?? this.keystoneUrParts,
      keystoneQrError: clearKeystoneQrError
          ? null
          : keystoneQrError ?? this.keystoneQrError,
      pendingDraftVotes: clearPendingDraftVotes
          ? null
          : pendingDraftVotes ?? this.pendingDraftVotes,
      pendingProposalIds: pendingProposalIds ?? this.pendingProposalIds,
      pendingProposalOptionCounts:
          pendingProposalOptionCounts ?? this.pendingProposalOptionCounts,
      pendingRecoveryWithoutDraft:
          pendingRecoveryWithoutDraft ?? this.pendingRecoveryWithoutDraft,
    );
  }
}

class VotingSubmissionJobNotifier extends Notifier<VotingSubmissionJobState> {
  VotingSubmissionGuard? _guard;
  Timer? _completionPollTimer;
  int _nextGeneration = 0;

  @override
  VotingSubmissionJobState build() {
    ref.onDispose(() {
      _completionPollTimer?.cancel();
      _completionPollTimer = null;
    });
    return const VotingSubmissionJobState();
  }

  Future<void> start(String roundId) async {
    final current = state;
    if (current.key?.roundId == roundId && current.hasVisibleJob) return;
    if (current.isInFlight) {
      ref.read(votingSubmissionGuardProvider.notifier).throwIfActive();
    }

    final String? accountUuid;
    try {
      accountUuid = await _activeAccountUuid();
    } catch (error) {
      _setInitialError(roundId, _messageFromError(error));
      return;
    }
    if (accountUuid == null) {
      _setInitialError(roundId, 'No active account for voting session.');
      return;
    }

    _startJob(VotingSessionKey(roundId: roundId, accountUuid: accountUuid));
  }

  Future<void> retry() async {
    final key = state.key;
    if (key == null) return;
    _releaseGuard();
    state = const VotingSubmissionJobState();
    _startJob(key);
  }

  void _startJob(VotingSessionKey key) {
    _cancelCompletionPoll();
    _replaceGuard(accountUuid: key.accountUuid, roundId: key.roundId);
    final generation = ++_nextGeneration;
    state = VotingSubmissionJobState(
      key: key,
      status: VotingSubmissionJobStatus.running,
      generation: generation,
    );
    unawaited(_run(key: key, generation: generation));
  }

  Future<void> handleKeystoneSignedPczt(List<int> signedPczt) async {
    final job = state;
    final key = job.key;
    if (key == null || !job.isInFlight || signedPczt.isEmpty) return;
    final generation = job.generation;
    try {
      final sessionNotifier = ref.read(
        votingSubmissionSessionProvider(key).notifier,
      );
      await sessionNotifier.handleKeystoneSignedPczt(signedPczt);
      if (!_isCurrentJob(key: key, generation: generation)) return;
      final session = _sessionForJob(key);
      if (session == null) return;
      if (session.phase == VotingSessionPhase.error) {
        _failFromSession(key: key, generation: generation, session: session);
        return;
      }
      final request = session.keystoneSigningRequest;
      if (request != null) {
        await _updateKeystoneQr(
          key: key,
          generation: generation,
          request: request,
        );
        return;
      }
      await _submitAfterKeystoneSignatures(
        sessionNotifier,
        key: key,
        generation: generation,
      );
    } catch (error) {
      if (!_isCurrentJob(key: key, generation: generation)) return;
      _failJob(
        key: key,
        generation: generation,
        message: _messageFromError(error),
      );
    }
  }

  Future<void> skipRemainingKeystoneBundles() async {
    final job = state;
    final key = job.key;
    if (key == null || !job.isInFlight) return;
    final generation = job.generation;
    try {
      _setRunning(key: key, generation: generation);
      final sessionNotifier = ref.read(
        votingSubmissionSessionProvider(key).notifier,
      );
      await sessionNotifier.skipRemainingKeystoneBundles();
      if (!_isCurrentJob(key: key, generation: generation)) return;
      final session = _sessionForJob(key);
      if (session?.phase == VotingSessionPhase.error) {
        _failFromSession(key: key, generation: generation, session: session!);
        return;
      }
      await _submitAfterKeystoneSignatures(
        sessionNotifier,
        key: key,
        generation: generation,
      );
    } catch (error) {
      if (!_isCurrentJob(key: key, generation: generation)) return;
      _failJob(
        key: key,
        generation: generation,
        message: _messageFromError(error),
      );
    }
  }

  Future<void> _run({
    required VotingSessionKey key,
    required int generation,
  }) async {
    try {
      final sessionProvider = votingSubmissionSessionProvider(key);
      final sessionNotifier = ref.read(sessionProvider.notifier);
      final loadedSession = await ref.read(sessionProvider.future);
      if (!_isCurrentJob(key: key, generation: generation)) return;
      final round = loadedSession.round;
      if (round == null) {
        _failJob(
          key: key,
          generation: generation,
          message:
              'Voting round details are not available yet. Retry in a moment.',
        );
        return;
      }

      final proposals = proposalsFromRound(round);
      final proposalOptionCounts = {
        for (final proposal in proposals) proposal.id: proposal.options.length,
      };
      final draft = await ref
          .read(votingDraftProvider(key).notifier)
          .ensureLoaded();
      if (!_isCurrentJob(key: key, generation: generation)) return;
      final userDraftVotes = draft.toDraftVotes(proposals);
      final proposalIds = proposals.map((proposal) => proposal.id).toList();

      await sessionNotifier.ensureWalletReadyForVoting();
      if (!_isCurrentJob(key: key, generation: generation)) return;
      final afterWalletSync = _sessionForJob(key);
      if (afterWalletSync?.phase == VotingSessionPhase.error ||
          afterWalletSync?.phase == VotingSessionPhase.waitingForWalletSync) {
        if (afterWalletSync?.phase == VotingSessionPhase.error) {
          _failFromSession(
            key: key,
            generation: generation,
            session: afterWalletSync!,
          );
        }
        return;
      }

      final activeSession = afterWalletSync ?? loadedSession;
      final recoveredDraftVotes =
          userDraftVotes.isEmpty && _roundPlanHasNoOpenProposals(activeSession)
          ? _draftVotesFromRoundPlan(activeSession.roundPlan, proposals)
          : const <rust_wire.DraftVoteView>[];
      final draftVotes = userDraftVotes.isNotEmpty
          ? userDraftVotes
          : recoveredDraftVotes;
      final intentProposalIds = userDraftVotes.isNotEmpty
          ? proposalIds
          : const <int>[];
      final canRecoverWithoutDraft = _canRecoverWithoutDraft(activeSession);
      final canPollDelegationWithoutDraft = _canPollDelegationWithoutDraft(
        activeSession,
      );
      final needsDelegation = _sessionNeedsDelegation(activeSession);
      if (draftVotes.isEmpty &&
          !canRecoverWithoutDraft &&
          !canPollDelegationWithoutDraft) {
        _failJob(
          key: key,
          generation: generation,
          message: 'Choose at least one vote before submitting.',
        );
        return;
      }

      if (activeSession.isHardwareAccount &&
          _sessionNeedsKeystoneSigning(activeSession)) {
        _storePendingKeystoneState(
          key: key,
          generation: generation,
          draftVotes: draftVotes,
          intentProposalIds: intentProposalIds,
          proposalOptionCounts: proposalOptionCounts,
          pendingRecoveryWithoutDraft:
              canRecoverWithoutDraft || canPollDelegationWithoutDraft,
        );
        await _prepareKeystoneSigning(
          sessionNotifier,
          key: key,
          generation: generation,
        );
        return;
      }

      if (draftVotes.isNotEmpty || needsDelegation) {
        if (activeSession.isHardwareAccount) {
          if (needsDelegation) {
            _storePendingKeystoneState(
              key: key,
              generation: generation,
              draftVotes: draftVotes,
              intentProposalIds: intentProposalIds,
              proposalOptionCounts: proposalOptionCounts,
              pendingRecoveryWithoutDraft:
                  canRecoverWithoutDraft || canPollDelegationWithoutDraft,
            );
            await _submitAfterKeystoneSignatures(
              sessionNotifier,
              key: key,
              generation: generation,
            );
          } else {
            await _submitVotesAndShares(
              sessionNotifier,
              key: key,
              generation: generation,
              draftVotes: draftVotes,
              intentProposalIds: intentProposalIds,
              proposalOptionCounts: proposalOptionCounts,
              initialSession: activeSession,
            );
          }
          return;
        }
        final mnemonic = await ref
            .read(accountProvider.notifier)
            .getMnemonicForAccount(key.accountUuid);
        if (!_isCurrentJob(key: key, generation: generation)) return;
        if (mnemonic == null || mnemonic.isEmpty) {
          _failJob(
            key: key,
            generation: generation,
            message:
                'Coinholder voting requires a software account. Switch to a software account to vote in this round.',
            softwareAccountRequired: true,
          );
          return;
        }
        final seedBytes = await rust_wallet.deriveSeed(mnemonic: mnemonic);
        try {
          if (!_isCurrentJob(key: key, generation: generation)) return;
          await sessionNotifier.delegatePendingBundles(seedBytes: seedBytes);
        } finally {
          seedBytes.fillRange(0, seedBytes.length, 0);
        }
        if (!_isCurrentJob(key: key, generation: generation)) return;
        final afterDelegation = _sessionForJob(key);
        if (afterDelegation?.phase == VotingSessionPhase.error) {
          _failFromSession(
            key: key,
            generation: generation,
            session: afterDelegation!,
          );
          return;
        }
      }
      final afterDelegation = _sessionForJob(key);
      await _submitVotesAndShares(
        sessionNotifier,
        key: key,
        generation: generation,
        draftVotes: draftVotes,
        intentProposalIds: intentProposalIds,
        proposalOptionCounts: proposalOptionCounts,
        initialSession: afterDelegation ?? activeSession,
      );
    } catch (error) {
      if (!_isCurrentJob(key: key, generation: generation)) return;
      _failJob(
        key: key,
        generation: generation,
        message: _messageFromError(error),
      );
    }
  }

  Future<void> _prepareKeystoneSigning(
    VotingSessionNotifier sessionNotifier, {
    required VotingSessionKey key,
    required int generation,
  }) async {
    await sessionNotifier.prepareKeystoneSigning();
    if (!_isCurrentJob(key: key, generation: generation)) return;
    final session = _sessionForJob(key);
    if (session == null) return;
    if (session.phase == VotingSessionPhase.error) {
      _failFromSession(key: key, generation: generation, session: session);
      return;
    }
    final request = session.keystoneSigningRequest;
    if (request != null) {
      await _updateKeystoneQr(
        key: key,
        generation: generation,
        request: request,
      );
      return;
    }
    await _submitAfterKeystoneSignatures(
      sessionNotifier,
      key: key,
      generation: generation,
    );
  }

  Future<void> _updateKeystoneQr({
    required VotingSessionKey key,
    required int generation,
    required rust_wire.KeystoneDelegationRequestView request,
  }) async {
    if (!_isCurrentJob(key: key, generation: generation)) return;
    state = state.copyWith(
      status: VotingSubmissionJobStatus.waitingForKeystone,
      keystoneUrParts: const [],
      clearKeystoneQrError: true,
    );
    try {
      final urParts = await rust_keystone.encodePcztUrParts(
        pcztBytes: request.redactedPcztBytes,
        maxFragmentLen: BigInt.from(200),
      );
      if (!_isCurrentJob(key: key, generation: generation)) return;
      state = state.copyWith(
        status: VotingSubmissionJobStatus.waitingForKeystone,
        keystoneUrParts: urParts,
        clearKeystoneQrError: true,
      );
    } catch (error) {
      if (!_isCurrentJob(key: key, generation: generation)) return;
      _failJob(
        key: key,
        generation: generation,
        message:
            'Failed to prepare Keystone voting QR: ${_messageFromError(error)}',
      );
    }
  }

  Future<void> _submitAfterKeystoneSignatures(
    VotingSessionNotifier sessionNotifier, {
    required VotingSessionKey key,
    required int generation,
  }) async {
    if (!_isCurrentJob(key: key, generation: generation)) return;
    final draftVotes = state.pendingDraftVotes;
    if (draftVotes == null ||
        (draftVotes.isEmpty && !state.pendingRecoveryWithoutDraft)) {
      _failJob(
        key: key,
        generation: generation,
        message: 'Choose at least one vote before submitting.',
      );
      return;
    }
    _setRunning(key: key, generation: generation);
    final beforeDelegation = _sessionForJob(key);
    if (_sessionNeedsDelegationSubmission(beforeDelegation)) {
      await sessionNotifier.delegatePendingBundlesWithKeystoneSignatures();
      if (!_isCurrentJob(key: key, generation: generation)) return;
      final afterDelegation = _sessionForJob(key);
      if (afterDelegation?.phase == VotingSessionPhase.error) {
        _failFromSession(
          key: key,
          generation: generation,
          session: afterDelegation!,
        );
        return;
      }
      await _submitVotesAndShares(
        sessionNotifier,
        key: key,
        generation: generation,
        draftVotes: draftVotes,
        intentProposalIds: state.pendingProposalIds,
        proposalOptionCounts: state.pendingProposalOptionCounts,
        initialSession: afterDelegation ?? beforeDelegation,
      );
      return;
    }
    await _submitVotesAndShares(
      sessionNotifier,
      key: key,
      generation: generation,
      draftVotes: draftVotes,
      intentProposalIds: state.pendingProposalIds,
      proposalOptionCounts: state.pendingProposalOptionCounts,
      initialSession: beforeDelegation,
    );
  }

  Future<void> _submitVotesAndShares(
    VotingSessionNotifier sessionNotifier, {
    required VotingSessionKey key,
    required int generation,
    required List<rust_wire.DraftVoteView> draftVotes,
    required List<int> intentProposalIds,
    required Map<int, int> proposalOptionCounts,
    VotingSessionState? initialSession,
  }) async {
    if (!_isCurrentJob(key: key, generation: generation)) return;
    final votePollingSession = _sessionForJob(key) ?? initialSession;
    if (draftVotes.isEmpty &&
        (votePollingSession == null ||
            !_canRecoverWithoutDraft(votePollingSession))) {
      _failJob(
        key: key,
        generation: generation,
        message: 'Choose at least one vote before submitting.',
      );
      return;
    }
    if (draftVotes.isNotEmpty || _sessionNeedsVotePolling(votePollingSession)) {
      await sessionNotifier.castVotes(
        draftVotes: draftVotes,
        allProposalIds: intentProposalIds,
        proposalOptionCounts: proposalOptionCounts,
      );
    }
    if (!_isCurrentJob(key: key, generation: generation)) return;
    final afterVotes = _sessionForJob(key);
    if (afterVotes?.phase == VotingSessionPhase.error) {
      _failFromSession(key: key, generation: generation, session: afterVotes!);
      return;
    }
    await sessionNotifier.submitPendingShares();
    if (!_isCurrentJob(key: key, generation: generation)) return;
    final done = _sessionForJob(key);
    if (done?.phase == VotingSessionPhase.error) {
      _failFromSession(key: key, generation: generation, session: done!);
      return;
    }
    if (!_hasCompletedSubmission(done)) {
      _scheduleCompletionPoll(key: key, generation: generation);
      return;
    }
    _completeJob(key: key, generation: generation);
  }

  void _storePendingKeystoneState({
    required VotingSessionKey key,
    required int generation,
    required List<rust_wire.DraftVoteView> draftVotes,
    required List<int> intentProposalIds,
    required Map<int, int> proposalOptionCounts,
    required bool pendingRecoveryWithoutDraft,
  }) {
    if (!_isCurrentJob(key: key, generation: generation)) return;
    state = state.copyWith(
      pendingDraftVotes: draftVotes,
      pendingProposalIds: intentProposalIds,
      pendingProposalOptionCounts: proposalOptionCounts,
      pendingRecoveryWithoutDraft: pendingRecoveryWithoutDraft,
    );
  }

  void _setRunning({required VotingSessionKey key, required int generation}) {
    if (!_isCurrentJob(key: key, generation: generation)) return;
    state = state.copyWith(
      status: VotingSubmissionJobStatus.running,
      keystoneUrParts: const [],
      clearKeystoneQrError: true,
      clearErrorMessage: true,
    );
  }

  void _completeJob({required VotingSessionKey key, required int generation}) {
    if (!_isCurrentJob(key: key, generation: generation)) return;
    _cancelCompletionPoll();
    _releaseGuard();
    state = state.copyWith(
      status: VotingSubmissionJobStatus.complete,
      clearErrorMessage: true,
      softwareAccountRequired: false,
      keystoneUrParts: const [],
      clearKeystoneQrError: true,
      clearPendingDraftVotes: true,
      pendingProposalIds: const [],
      pendingProposalOptionCounts: const {},
      pendingRecoveryWithoutDraft: false,
    );
  }

  void _failFromSession({
    required VotingSessionKey key,
    required int generation,
    required VotingSessionState session,
  }) {
    _failJob(
      key: key,
      generation: generation,
      message: _statusErrorMessage(session) ?? _genericVotingStatusErrorMessage,
    );
  }

  void _failJob({
    required VotingSessionKey key,
    required int generation,
    required String message,
    bool softwareAccountRequired = false,
  }) {
    if (!_isCurrentJob(key: key, generation: generation)) return;
    _cancelCompletionPoll();
    _releaseGuard();
    state = state.copyWith(
      status: VotingSubmissionJobStatus.error,
      errorMessage: message,
      softwareAccountRequired: softwareAccountRequired,
      keystoneUrParts: const [],
      clearKeystoneQrError: true,
      clearPendingDraftVotes: true,
      pendingProposalIds: const [],
      pendingProposalOptionCounts: const {},
      pendingRecoveryWithoutDraft: false,
    );
  }

  void _setInitialError(String roundId, String message) {
    _cancelCompletionPoll();
    final generation = ++_nextGeneration;
    state = VotingSubmissionJobState(
      key: VotingSessionKey(roundId: roundId, accountUuid: ''),
      status: VotingSubmissionJobStatus.error,
      generation: generation,
      errorMessage: message,
    );
  }

  Future<String?> _activeAccountUuid() async {
    final votingAccountUuid = await ref
        .read(votingActiveAccountUuidProvider)
        .call();
    if (votingAccountUuid != null) return votingAccountUuid;
    final immediate = ref.read(accountProvider).value?.activeAccountUuid;
    if (immediate != null) return immediate;
    return (await ref.read(accountProvider.future)).activeAccountUuid;
  }

  VotingSessionState? _sessionForJob(VotingSessionKey key) {
    final session = ref.read(votingSubmissionSessionProvider(key)).value;
    if (session?.accountUuid != key.accountUuid) return null;
    return session;
  }

  bool _isCurrentJob({required VotingSessionKey key, required int generation}) {
    if (!ref.mounted) return false;
    final current = state;
    return current.generation == generation && current.key == key;
  }

  void _replaceGuard({required String accountUuid, required String roundId}) {
    _releaseGuard();
    _guard = ref
        .read(votingSubmissionGuardProvider.notifier)
        .acquire(accountUuid: accountUuid, roundId: roundId);
  }

  void _releaseGuard() {
    final guard = _guard;
    if (guard == null) return;
    _guard = null;
    ref.read(votingSubmissionGuardProvider.notifier).release(guard);
  }

  void _scheduleCompletionPoll({
    required VotingSessionKey key,
    required int generation,
  }) {
    _completionPollTimer?.cancel();
    _completionPollTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!_isCurrentJob(key: key, generation: generation) ||
          !state.isInFlight) {
        timer.cancel();
        if (identical(_completionPollTimer, timer)) _completionPollTimer = null;
        return;
      }
      final session = _sessionForJob(key);
      if (session?.phase == VotingSessionPhase.error) {
        _failFromSession(key: key, generation: generation, session: session!);
        return;
      }
      if (_hasCompletedSubmission(session)) {
        _completeJob(key: key, generation: generation);
      }
    });
  }

  void _cancelCompletionPoll() {
    _completionPollTimer?.cancel();
    _completionPollTimer = null;
  }

  bool _hasCompletedSubmission(VotingSessionState? session) {
    if (session == null) return false;
    return hasCompletedVoteForDisplay(
      roundPlan: session.roundPlan,
      resumePlan: session.resumePlan,
    );
  }

  String _messageFromError(Object error) => friendlyVotingErrorMessage(error);

  String? _statusErrorMessage(VotingSessionState state) {
    final error = state.error;
    if (error != null) return friendlyVotingErrorText(error.message);
    if (state.phase != VotingSessionPhase.error) return null;
    return _genericVotingStatusErrorMessage;
  }

  static const _genericVotingStatusErrorMessage =
      'Voting could not continue for this account. Retry, or switch to an '
      'eligible account if this account cannot vote in this poll.';

  bool _canRecoverWithoutDraft(VotingSessionState session) {
    final roundPlan = session.roundPlan;
    if (roundPlan != null) {
      return _roundPlanHasNoOpenProposals(session) &&
          roundPlan.nextSteps.any(_stepCanRecoverWithoutDraft);
    }
    final resumePlan = session.resumePlan;
    return resumePlan != null &&
        (resumePlan.pendingVoteSubmissionKeys.isNotEmpty ||
            resumePlan.submittedVoteConfirmationKeys.isNotEmpty ||
            resumePlan.unconfirmedShareDelegations.isNotEmpty);
  }

  bool _roundPlanHasNoOpenProposals(VotingSessionState session) {
    final roundPlan = session.roundPlan;
    return roundPlan != null && roundPlan.openProposals.isEmpty;
  }

  bool _canPollDelegationWithoutDraft(VotingSessionState session) {
    final roundPlan = session.roundPlan;
    if (roundPlan != null) {
      var hasSubmittedDelegation = false;
      for (final step in roundPlan.nextSteps) {
        if (step.kind == 'delegate') return false;
        if (step.kind == 'poll_delegation') hasSubmittedDelegation = true;
      }
      return hasSubmittedDelegation;
    }
    final resumePlan = session.resumePlan;
    return resumePlan != null &&
        resumePlan.submittedDelegationBundleIndexes.isNotEmpty &&
        resumePlan.pendingDelegationBundleIndexes.isEmpty;
  }

  bool _stepCanRecoverWithoutDraft(rust_wire.NextStepView step) {
    return step.kind == 'submit_vote' ||
        step.kind == 'submit_shares' ||
        step.kind == 'poll_vote' ||
        step.kind == 'confirm_share';
  }

  bool _sessionNeedsDelegation(VotingSessionState? session) {
    if (session == null) return false;
    final roundPlan = session.roundPlan;
    if (_planNeedsDelegation(roundPlan)) return true;
    if (roundPlan != null && !roundPlanNeedsDraftSetup(roundPlan)) {
      return false;
    }
    return session.resumePlan?.submittedDelegationBundleIndexes.isNotEmpty ??
        false;
  }

  bool _sessionNeedsDelegationSubmission(VotingSessionState? session) {
    if (session == null) return false;
    final roundPlan = session.roundPlan;
    if (_planNeedsDelegation(roundPlan)) return true;
    if (roundPlan != null && !roundPlanNeedsDraftSetup(roundPlan)) {
      return false;
    }
    final plan = session.resumePlan;
    return (plan?.pendingDelegationBundleIndexes.isNotEmpty ?? false) ||
        (plan?.submittedDelegationBundleIndexes.isNotEmpty ?? false);
  }

  bool _sessionNeedsKeystoneSigning(VotingSessionState session) {
    final roundPlan = session.roundPlan;
    if (roundPlan != null) {
      return roundPlan.nextSteps.any((step) => step.kind == 'delegate') ||
          roundPlanNeedsDraftSetup(roundPlan);
    }
    return session.resumePlan?.pendingDelegationBundleIndexes.isNotEmpty ??
        false;
  }

  bool _sessionNeedsVotePolling(VotingSessionState? session) {
    if (session == null) return false;
    if (_planNeedsVotePolling(session.roundPlan)) return true;
    if (session.roundPlan != null) return false;
    return session.resumePlan?.submittedVoteConfirmationKeys.isNotEmpty ??
        false;
  }

  bool _planNeedsDelegation(rust_wire.RoundPlanView? roundPlan) {
    return roundPlan?.nextSteps.any(
          (step) => step.kind == 'delegate' || step.kind == 'poll_delegation',
        ) ??
        false;
  }

  bool _planNeedsVotePolling(rust_wire.RoundPlanView? roundPlan) {
    return roundPlan?.nextSteps.any(
          (step) =>
              step.kind == 'submit_vote' ||
              step.kind == 'submit_shares' ||
              step.kind == 'poll_vote',
        ) ??
        false;
  }

  List<rust_wire.DraftVoteView> _draftVotesFromRoundPlan(
    rust_wire.RoundPlanView? roundPlan,
    List<VotingProposalView> proposals,
  ) {
    if (roundPlan == null) return const [];
    final choicesByProposal = <int, int>{};
    for (final step in roundPlan.nextSteps) {
      if (step.kind != 'cast_vote') continue;
      choicesByProposal.putIfAbsent(step.proposalId, () => step.choice);
    }
    if (choicesByProposal.isEmpty) return const [];
    return [
      for (final proposal in proposals)
        if (choicesByProposal[proposal.id] != null)
          rust_wire.DraftVoteView(
            proposalId: proposal.id,
            choice: choicesByProposal[proposal.id]!,
            numOptions: proposal.options.length,
            vcTreePosition: BigInt.zero,
            singleShare: false,
          ),
    ];
  }
}

final votingSubmissionJobProvider =
    NotifierProvider<VotingSubmissionJobNotifier, VotingSubmissionJobState>(
      VotingSubmissionJobNotifier.new,
    );

final votingSubmissionJobSessionProvider =
    Provider<AsyncValue<VotingSessionState>?>((ref) {
      final key = ref.watch(
        votingSubmissionJobProvider.select((state) => state.key),
      );
      if (key == null || key.accountUuid.isEmpty) return null;
      return ref.watch(votingSubmissionSessionProvider(key));
    });
