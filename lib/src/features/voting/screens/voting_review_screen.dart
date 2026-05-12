import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_main_sidebar.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_back_link.dart';
import '../../../core/widgets/app_button.dart';
import '../../../providers/voting/voting_session_provider.dart';
import '../voting_flow_models.dart';
import '../voting_routes.dart';

class VotingReviewScreen extends ConsumerWidget {
  const VotingReviewScreen({super.key, required this.roundId});

  final String roundId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(votingSessionProvider(roundId));
    final draft = ref.watch(votingDraftProvider(roundId));
    return AppDesktopShell(
      sidebar: const AppMainSidebar(),
      pane: AppDesktopPane(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: session.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => _Message("Couldn't load review: $error"),
          data: (state) {
            final round = state.round;
            final proposals = round == null
                ? <VotingProposalView>[]
                : proposalsFromRound(round);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Align(
                  alignment: Alignment.centerLeft,
                  child: AppRouteBackLink(),
                ),
                const Spacer(),
                Text(
                  'Review Your Votes',
                  textAlign: TextAlign.center,
                  style: AppTypography.displaySmall.copyWith(
                    color: context.colors.text.accent,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 620),
                  child: Column(
                    children: [
                      for (final proposal in proposals)
                        if (draft.choices[proposal.id] != null)
                          _ReviewRow(
                            title: proposal.title,
                            value: proposal.options
                                .firstWhere(
                                  (option) =>
                                      option.index ==
                                      draft.choices[proposal.id],
                                  orElse: () => VotingOptionView(
                                    index: draft.choices[proposal.id]!,
                                    label:
                                        'Choice ${draft.choices[proposal.id]}',
                                  ),
                                )
                                .label,
                          ),
                    ],
                  ),
                ),
                if (draft.isEmpty)
                  const _Message(
                    'Choose at least one option before submitting.',
                  ),
                const SizedBox(height: AppSpacing.md),
                Center(
                  child: AppButton(
                    onPressed: draft.isEmpty
                        ? null
                        : () => context.go(votingStatusRoute(roundId)),
                    variant: AppButtonVariant.primary,
                    minWidth: 240,
                    child: const Text('Submit Votes'),
                  ),
                ),
                const Spacer(),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ReviewRow extends StatelessWidget {
  const _ReviewRow({required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.xs),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: context.colors.background.ground.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(AppRadii.medium),
        border: Border.all(color: context.colors.border.subtle),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: AppTypography.bodyMedium.copyWith(
                color: context.colors.text.secondary,
              ),
            ),
          ),
          Text(
            value,
            style: AppTypography.bodyMediumStrong.copyWith(
              color: context.colors.text.accent,
            ),
          ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: AppTypography.bodyMedium.copyWith(
          color: context.colors.text.secondary,
        ),
      ),
    );
  }
}
