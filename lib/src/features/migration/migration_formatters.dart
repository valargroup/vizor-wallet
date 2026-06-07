String formatRemaining(Duration remaining) {
  if (remaining.inMinutes <= 0) return 'Wrapping up';
  if (remaining.inHours >= 1) {
    final h = remaining.inHours;
    return 'About $h hour${h == 1 ? '' : 's'} remaining';
  }
  final m = remaining.inMinutes;
  return 'About $m minute${m == 1 ? '' : 's'} remaining';
}

String formatStartedAgo(Duration sinceStart) {
  if (sinceStart.inMinutes < 1) return 'started just now';
  if (sinceStart.inHours >= 1) return 'started ${sinceStart.inHours}h ago';
  return 'started ${sinceStart.inMinutes}m ago';
}

String formatTransferEta(Duration eta) {
  if (eta.inMinutes <= 0) return 'Soon';
  if (eta.inHours >= 1) return '~${eta.inHours}h';
  return '~${eta.inMinutes}m';
}
