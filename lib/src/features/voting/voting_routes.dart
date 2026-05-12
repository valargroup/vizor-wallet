String _roundSegment(String roundId) => Uri.encodeComponent(roundId);

String votingPollRoute(String roundId) =>
    '/voting/poll/${_roundSegment(roundId)}';

String votingReviewRoute(String roundId) =>
    '${votingPollRoute(roundId)}/review';

String votingStatusRoute(String roundId) =>
    '${votingPollRoute(roundId)}/status';

String votingSubmissionConfirmedRoute(String roundId) =>
    '${votingPollRoute(roundId)}/submitted';

String votingResultsRoute(String roundId) =>
    '${votingPollRoute(roundId)}/results';
