import '../../rust/api/voting.dart' as rust_voting;

abstract interface class VotingRecoveryApi {
  Future<rust_voting.ApiRoundRecoveryState> getRoundRecoveryState({
    required String dbPath,
    required String walletId,
    required String roundId,
  });

  Future<void> addSentServers({
    required String dbPath,
    required String walletId,
    required String roundId,
    required int bundleIndex,
    required int proposalId,
    required int shareIndex,
    required List<String> newUrls,
  });

  Future<void> clearRecoveryState({
    required String dbPath,
    required String walletId,
    required String roundId,
  });
}

class RustVotingRecoveryApi implements VotingRecoveryApi {
  const RustVotingRecoveryApi();

  @override
  Future<rust_voting.ApiRoundRecoveryState> getRoundRecoveryState({
    required String dbPath,
    required String walletId,
    required String roundId,
  }) {
    return rust_voting.getRoundRecoveryState(
      dbPath: dbPath,
      walletId: walletId,
      roundId: roundId,
    );
  }

  @override
  Future<void> addSentServers({
    required String dbPath,
    required String walletId,
    required String roundId,
    required int bundleIndex,
    required int proposalId,
    required int shareIndex,
    required List<String> newUrls,
  }) {
    return rust_voting.addSentServers(
      dbPath: dbPath,
      walletId: walletId,
      roundId: roundId,
      bundleIndex: bundleIndex,
      proposalId: proposalId,
      shareIndex: shareIndex,
      newUrls: newUrls,
    );
  }

  @override
  Future<void> clearRecoveryState({
    required String dbPath,
    required String walletId,
    required String roundId,
  }) {
    return rust_voting.clearRecoveryState(
      dbPath: dbPath,
      walletId: walletId,
      roundId: roundId,
    );
  }
}
