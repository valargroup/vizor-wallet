import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/sync_provider.dart';
import '../../../providers/wallet_provider.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  @override
  void initState() {
    super.initState();
    // Auto-start sync when home screen loads
    Future.microtask(() {
      ref.read(syncProvider.notifier).startSync();
    });
  }

  @override
  Widget build(BuildContext context) {
    final walletAsync = ref.watch(walletProvider);
    final syncState = ref.watch(syncProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Zcash Wallet'),
        centerTitle: true,
      ),
      body: walletAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Error: $err')),
        data: (wallet) => _buildContent(
          context,
          wallet,
          syncState.value ?? SyncState(),
        ),
      ),
    );
  }

  String _formatZec(BigInt zatoshi) {
    final zec = zatoshi.toDouble() / 100000000;
    return zec.toStringAsFixed(8);
  }

  Widget _buildSyncBadge(BuildContext context, SyncState sync) {
    if (sync.error != null) {
      return GestureDetector(
        onTap: () => ref.read(syncProvider.notifier).startSync(),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.errorContainer,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            'Sync error - tap to retry',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onErrorContainer,
                ),
          ),
        ),
      );
    }

    if (sync.isSyncing) {
      return Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              'Syncing ${(sync.percentage * 100).toStringAsFixed(1)}%',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 48),
            child: LinearProgressIndicator(value: sync.percentage),
          ),
          const SizedBox(height: 4),
          Text(
            '${sync.scannedHeight} / ${sync.chainTipHeight}',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      );
    }

    if (sync.chainTipHeight > 0) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.tertiaryContainer,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          'Synced',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onTertiaryContainer,
              ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        'Starting sync...',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.onPrimaryContainer,
            ),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    WalletState wallet,
    SyncState sync,
  ) {
    final address = wallet.unifiedAddress ?? 'No address';

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const SizedBox(height: 32),
            Text(
              _formatZec(sync.totalBalance),
              style: Theme.of(context).textTheme.displayMedium?.copyWith(
                    fontWeight: FontWeight.w300,
                  ),
            ),
            Text(
              'ZEC',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 8),
            _buildSyncBadge(context, sync),
            const SizedBox(height: 48),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.account_balance_wallet_outlined,
                            size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'Your Address',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const Spacer(),
                        Text(
                          wallet.network?.toUpperCase() ?? '',
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      address,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontFamily: 'monospace',
                          ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: address));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('Address copied to clipboard')),
                          );
                        },
                        icon: const Icon(Icons.copy, size: 16),
                        label: const Text('Copy Address'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
