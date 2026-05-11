import '../../rust/api/voting.dart' as rust_voting;
import 'voting_recovery_api.dart';
import 'voting_resume_plan.dart';

class VotingRecoveryService {
  final VotingRecoveryApi _api;

  const VotingRecoveryService({VotingRecoveryApi? api})
    : _api = api ?? const RustVotingRecoveryApi();

  Future<VotingResumePlan> loadResumePlan({
    required String dbPath,
    required String walletId,
    required String roundId,
  }) async {
    final state = await _api.getRoundRecoveryState(
      dbPath: dbPath,
      walletId: walletId,
      roundId: roundId,
    );

    return buildResumePlan(state);
  }

  VotingResumePlan buildResumePlan(rust_voting.ApiRoundRecoveryState state) {
    final delegatedBundleIndexes = state.delegationTxHashes
        .map((record) => record.bundleIndex)
        .toSet();
    final pendingDelegationBundleIndexes = [
      for (var index = 0; index < state.bundleCount; index++)
        if (!delegatedBundleIndexes.contains(index)) index,
    ];

    final votesByKey = <VotingVoteKey, rust_voting.ApiVoteRecord>{
      for (final vote in state.votes)
        VotingVoteKey(
          bundleIndex: vote.bundleIndex,
          proposalId: vote.proposalId,
        ): vote,
    };
    final voteTxHashesByKey = <VotingVoteKey, String>{
      for (final record in state.voteTxHashes)
        VotingVoteKey(
          bundleIndex: record.bundleIndex,
          proposalId: record.proposalId,
        ): record.txHash,
    };
    final commitmentBundlesByKey =
        <VotingVoteKey, rust_voting.ApiCommitmentBundleRecovery>{
          for (final record in state.commitmentBundles)
            VotingVoteKey(
              bundleIndex: record.bundleIndex,
              proposalId: record.proposalId,
            ): record,
        };

    final voteKeys = votesByKey.keys.toList()..sort(_compareVoteKeys);
    final pendingVoteSubmissionKeys = voteKeys
        .where((key) => !voteTxHashesByKey.containsKey(key))
        .toList();
    final incompleteVoteRecoveryKeys = voteKeys
        .where(
          (key) =>
              !voteTxHashesByKey.containsKey(key) ||
              !commitmentBundlesByKey.containsKey(key),
        )
        .toList();

    final shareDelegations = state.shareDelegations.toList()
      ..sort(_compareShareDelegations);
    final unconfirmedShareDelegations =
        state.unconfirmedShareDelegations
            .where((record) => !record.confirmed)
            .toList()
          ..sort(_compareShareDelegations);

    return VotingResumePlan(
      recoveryState: state,
      pendingDelegationBundleIndexes: pendingDelegationBundleIndexes,
      votesByKey: votesByKey,
      voteTxHashesByKey: voteTxHashesByKey,
      commitmentBundlesByKey: commitmentBundlesByKey,
      pendingVoteSubmissionKeys: pendingVoteSubmissionKeys,
      incompleteVoteRecoveryKeys: incompleteVoteRecoveryKeys,
      shareDelegations: shareDelegations,
      unconfirmedShareDelegations: unconfirmedShareDelegations,
    );
  }

  Future<void> addSentServersForShare({
    required String dbPath,
    required String walletId,
    required rust_voting.ApiShareDelegationRecord share,
    required List<String> newUrls,
  }) {
    return _api.addSentServers(
      dbPath: dbPath,
      walletId: walletId,
      roundId: share.roundId,
      bundleIndex: share.bundleIndex,
      proposalId: share.proposalId,
      shareIndex: share.shareIndex,
      newUrls: newUrls,
    );
  }

  Future<void> finalizeRound({
    required String dbPath,
    required String walletId,
    required String roundId,
  }) {
    return _clearRoundRecoveryState(
      dbPath: dbPath,
      walletId: walletId,
      roundId: roundId,
    );
  }

  Future<void> abandonRound({
    required String dbPath,
    required String walletId,
    required String roundId,
  }) {
    return _clearRoundRecoveryState(
      dbPath: dbPath,
      walletId: walletId,
      roundId: roundId,
    );
  }

  Future<void> _clearRoundRecoveryState({
    required String dbPath,
    required String walletId,
    required String roundId,
  }) {
    return _api.clearRecoveryState(
      dbPath: dbPath,
      walletId: walletId,
      roundId: roundId,
    );
  }

  static int _compareVoteKeys(VotingVoteKey a, VotingVoteKey b) {
    final bundleCompare = a.bundleIndex.compareTo(b.bundleIndex);
    if (bundleCompare != 0) return bundleCompare;
    return a.proposalId.compareTo(b.proposalId);
  }

  static int _compareShareDelegations(
    rust_voting.ApiShareDelegationRecord a,
    rust_voting.ApiShareDelegationRecord b,
  ) {
    final bundleCompare = a.bundleIndex.compareTo(b.bundleIndex);
    if (bundleCompare != 0) return bundleCompare;
    final proposalCompare = a.proposalId.compareTo(b.proposalId);
    if (proposalCompare != 0) return proposalCompare;
    return a.shareIndex.compareTo(b.shareIndex);
  }
}
