import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_main_sidebar.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_back_link.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_decorative_divider.dart';
import '../../../providers/voting/voting_rounds_provider.dart';
import '../../../providers/voting/voting_state.dart';
import '../voting_routes.dart';

class VotingPollsScreen extends ConsumerStatefulWidget {
  const VotingPollsScreen({super.key});

  @override
  ConsumerState<VotingPollsScreen> createState() => _VotingPollsScreenState();
}

class _VotingPollsScreenState extends ConsumerState<VotingPollsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(votingRoundsProvider.notifier).startPolling();
    });
  }

  @override
  void dispose() {
    ref.read(votingRoundsProvider.notifier).stopPolling();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rounds = ref.watch(votingRoundsProvider);
    return AppDesktopShell(
      sidebar: const AppMainSidebar(),
      pane: AppDesktopPane(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Align(
              alignment: Alignment.centerLeft,
              child: AppRouteBackLink(),
            ),
            const SizedBox(height: AppSpacing.s),
            Text(
              'Coinholder Polling',
              textAlign: TextAlign.center,
              style: AppTypography.displaySmall.copyWith(
                color: context.colors.text.accent,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            const Center(child: AppDecorativeDivider(width: 256)),
            const SizedBox(height: AppSpacing.md),
            Expanded(
              child: rounds.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => _VotingMessage(
                  title: "Couldn't load polls",
                  message: error.toString(),
                  actionLabel: 'Try Again',
                  onAction: () =>
                      ref.read(votingRoundsProvider.notifier).refresh(),
                ),
                data: (items) {
                  if (items.isEmpty) {
                    return const _VotingMessage(
                      title: 'No polls available',
                      message: 'There are no coinholder polls to display yet.',
                    );
                  }
                  return ListView.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: AppSpacing.s),
                    itemBuilder: (context, index) => _PollCard(
                      round: items[index],
                      onTap: () =>
                          context.push(votingPollRoute(items[index].roundId)),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PollCard extends StatelessWidget {
  const _PollCard({required this.round, required this.onTap});

  final VotingRoundView round;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadii.large),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: colors.background.ground.withValues(alpha: 0.78),
          borderRadius: BorderRadius.circular(AppRadii.large),
          border: Border.all(color: colors.border.subtle),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _Chip(label: round.status.isEmpty ? 'open' : round.status),
                const SizedBox(width: AppSpacing.xxs),
                if (round.endorsed) const _Chip(label: 'Endorsed'),
                if (round.unverified) const _Chip(label: 'Unverified Poll'),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              round.title.isEmpty ? round.roundId : round.title,
              style: AppTypography.headlineSmall.copyWith(
                color: colors.text.accent,
              ),
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              round.roundId,
              style: AppTypography.bodySmall.copyWith(
                color: colors.text.secondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: context.colors.background.neutralSubtleOpacity,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: AppTypography.labelSmall.copyWith(
          color: context.colors.text.accent,
        ),
      ),
    );
  }
}

class _VotingMessage extends StatelessWidget {
  const _VotingMessage({
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppTypography.headlineSmall.copyWith(
                color: context.colors.text.accent,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              message,
              textAlign: TextAlign.center,
              style: AppTypography.bodyMedium.copyWith(
                color: context.colors.text.secondary,
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: AppSpacing.sm),
              AppButton(
                onPressed: onAction,
                variant: AppButtonVariant.primary,
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
