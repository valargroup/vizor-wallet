import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const kVotingSubmissionInProgressMessage =
    'Vote submission is still running. Wait for it to finish before '
    'navigating or switching accounts.';

@immutable
class VotingSubmissionGuard {
  const VotingSubmissionGuard({
    required this.token,
    required this.accountUuid,
    required this.roundId,
  });

  final int token;
  final String accountUuid;
  final String roundId;

  String get message => kVotingSubmissionInProgressMessage;
}

class VotingSubmissionInProgressException implements Exception {
  const VotingSubmissionInProgressException(this.guard);

  final VotingSubmissionGuard guard;

  String get message => guard.message;

  @override
  String toString() => message;
}

class VotingSubmissionGuardNotifier extends Notifier<VotingSubmissionGuard?> {
  int _nextToken = 0;

  @override
  VotingSubmissionGuard? build() => null;

  VotingSubmissionGuard acquire({
    required String accountUuid,
    required String roundId,
  }) {
    final current = state;
    if (current != null &&
        current.accountUuid == accountUuid &&
        current.roundId == roundId) {
      return current;
    }
    if (current != null) {
      throw VotingSubmissionInProgressException(current);
    }
    final guard = VotingSubmissionGuard(
      token: _nextToken++,
      accountUuid: accountUuid,
      roundId: roundId,
    );
    state = guard;
    return guard;
  }

  void release(VotingSubmissionGuard guard) {
    if (state?.token != guard.token) return;
    state = null;
  }

  void throwIfActive() {
    final guard = state;
    if (guard == null) return;
    throw VotingSubmissionInProgressException(guard);
  }
}

final votingSubmissionGuardProvider =
    NotifierProvider<VotingSubmissionGuardNotifier, VotingSubmissionGuard?>(
      VotingSubmissionGuardNotifier.new,
    );
