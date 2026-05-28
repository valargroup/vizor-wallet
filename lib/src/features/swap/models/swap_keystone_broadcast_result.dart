class SwapKeystoneBroadcastResult {
  const SwapKeystoneBroadcastResult({
    required this.txHash,
    required this.status,
    this.message,
  });

  final String txHash;
  final String status;
  final String? message;

  bool get isCertain => status == 'broadcasted';
}
