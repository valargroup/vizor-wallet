enum SwapStatusBadgeKind { liveQuote, completed, failed }

enum SwapStatusTab { progress, details }

enum SwapStatusStepState { complete, active, pending }

class SwapStatusStepData {
  const SwapStatusStepData({
    required this.title,
    required this.state,
    this.completeTitle,
    this.activeTitle,
    this.pendingTitle,
    this.lastCheckedLabel,
    this.description,
  });

  final String title;
  final SwapStatusStepState state;
  final String? completeTitle;
  final String? activeTitle;
  final String? pendingTitle;
  final String? lastCheckedLabel;
  final String? description;

  String titleForState(SwapStatusStepState state) {
    return switch (state) {
      SwapStatusStepState.complete => completeTitle ?? title,
      SwapStatusStepState.active => activeTitle ?? title,
      SwapStatusStepState.pending => pendingTitle ?? title,
    };
  }

  SwapStatusStepData copyWithState(SwapStatusStepState state) {
    return SwapStatusStepData(
      title: title,
      state: state,
      completeTitle: completeTitle,
      activeTitle: activeTitle,
      pendingTitle: pendingTitle,
      lastCheckedLabel: lastCheckedLabel,
      description: description,
    );
  }
}

class SwapStatusDetailRowData {
  const SwapStatusDetailRowData({
    required this.label,
    required this.value,
    this.copyable = false,
    this.copyText,
    this.help = false,
    this.helpTooltip,
    this.accountProfilePictureId,
  });

  final String label;
  final String value;
  final bool copyable;
  final String? copyText;
  final bool help;
  final String? helpTooltip;
  final String? accountProfilePictureId;
}
