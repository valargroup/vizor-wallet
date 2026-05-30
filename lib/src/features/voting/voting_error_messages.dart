String friendlyVotingErrorMessage(Object error) {
  return friendlyVotingErrorText(error.toString());
}

String friendlyVotingErrorText(String text) {
  var message = text.trim();
  for (final prefix in const [
    'Exception: ',
    'StateError: ',
    'Bad state: ',
    'VotingHotkeyUnavailable: ',
    'Invalid input: ',
  ]) {
    if (message.startsWith(prefix)) {
      message = message.substring(prefix.length).trim();
      break;
    }
  }

  final noSpendableNotes = RegExp(
    r'no spendable voting notes at snapshot height (\d+)',
    caseSensitive: false,
  ).firstMatch(message);
  if (noSpendableNotes != null) {
    final heightText = noSpendableNotes.group(1);
    final snapshot = heightText == null
        ? 'the poll snapshot block'
        : 'snapshot block ${_formatBlockHeight(int.parse(heightText))}';
    return 'This account is not eligible for this poll. It had no eligible '
        'shielded funds at $snapshot. Switch to an eligible account to vote.';
  }

  return message.isEmpty ? 'Voting session action failed.' : message;
}

String _formatBlockHeight(int height) {
  final text = height.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < text.length; i++) {
    if (i > 0 && (text.length - i) % 3 == 0) {
      buffer.write(',');
    }
    buffer.write(text[i]);
  }
  return buffer.toString();
}
