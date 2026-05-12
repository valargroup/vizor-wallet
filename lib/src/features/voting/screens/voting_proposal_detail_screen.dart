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
import '../voting_formatters.dart';
import '../voting_resume_plan.dart';
import '../voting_routes.dart';

class VotingProposalDetailScreen extends ConsumerWidget {
  const VotingProposalDetailScreen({super.key, required this.roundId});

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
          error: (error, _) =>
              _Message(title: "Couldn't load poll", message: '$error'),
          data: (state) {
            final round = state.round;
            if (round == null) {
              return const _Message(
                title: 'Poll unavailable',
                message: 'The selected poll could not be loaded.',
              );
            }
            final proposals = proposalsFromRound(round);
            final completedVote = _CompletedVote.fromPlan(
              state.resumePlan,
              proposals,
            );
            if (completedVote != null) {
              return _VotedPollContent(
                roundTitle: round.title.isEmpty
                    ? 'Coinholder Poll'
                    : round.title,
                snapshotHeight: round.snapshotHeight,
                description: _roundDescription(round.rawJson),
                votingPower: formatVotingPower(state.eligibleWeightZatoshi),
                votedAt: completedVote.votedAt,
                proposals: proposals,
                choicesByProposalId: completedVote.choicesByProposalId,
              );
            }
            final pendingVote = _PendingVoteRecovery.fromPlan(state.resumePlan);
            if (pendingVote != null) {
              return _PendingVoteContent(
                roundTitle: round.title.isEmpty
                    ? 'Coinholder Poll'
                    : round.title,
                snapshotHeight: round.snapshotHeight,
                description: _roundDescription(round.rawJson),
                recovery: pendingVote,
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Align(
                  alignment: Alignment.centerLeft,
                  child: AppRouteBackLink(),
                ),
                const SizedBox(height: AppSpacing.s),
                Text(
                  round.title.isEmpty ? 'Coinholder Poll' : round.title,
                  textAlign: TextAlign.center,
                  style: AppTypography.displaySmall.copyWith(
                    color: context.colors.text.accent,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Expanded(
                  child: proposals.isEmpty
                      ? const _Message(
                          title: 'No proposals',
                          message: 'This poll does not contain any proposals.',
                        )
                      : ListView.separated(
                          itemCount: proposals.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: AppSpacing.s),
                          itemBuilder: (context, index) => _ProposalCard(
                            proposal: proposals[index],
                            selectedChoice: draft.choices[proposals[index].id],
                            onChoice: (choice) => ref
                                .read(votingDraftProvider(roundId).notifier)
                                .setChoice(proposals[index].id, choice),
                          ),
                        ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Align(
                  alignment: Alignment.center,
                  child: AppButton(
                    onPressed: draft.isEmpty
                        ? null
                        : () => context.push(votingReviewRoute(roundId)),
                    variant: AppButtonVariant.primary,
                    minWidth: 220,
                    child: const Text('Review Votes'),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _VotedPollContent extends StatelessWidget {
  const _VotedPollContent({
    required this.roundTitle,
    required this.snapshotHeight,
    required this.description,
    required this.votingPower,
    required this.votedAt,
    required this.proposals,
    required this.choicesByProposalId,
  });

  final String roundTitle;
  final int snapshotHeight;
  final String description;
  final String votingPower;
  final DateTime? votedAt;
  final List<VotingProposalView> proposals;
  final Map<int, int?> choicesByProposalId;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Align(alignment: Alignment.centerLeft, child: AppRouteBackLink()),
        const SizedBox(height: AppSpacing.s),
        _VotedPollHeader(
          title: roundTitle,
          snapshotHeight: snapshotHeight,
          description: description,
          votingPower: votingPower,
          votedAt: votedAt,
        ),
        const SizedBox(height: AppSpacing.md),
        Expanded(
          child: proposals.isEmpty
              ? const _Message(
                  title: 'No proposals',
                  message: 'This poll does not contain any proposals.',
                )
              : ListView.separated(
                  itemCount: proposals.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: AppSpacing.s),
                  itemBuilder: (context, index) {
                    final proposal = proposals[index];
                    return _VotedProposalCard(
                      proposal: proposal,
                      choice: choicesByProposalId[proposal.id],
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _PendingVoteContent extends StatelessWidget {
  const _PendingVoteContent({
    required this.roundTitle,
    required this.snapshotHeight,
    required this.description,
    required this.recovery,
  });

  final String roundTitle;
  final int snapshotHeight;
  final String description;
  final _PendingVoteRecovery recovery;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Align(alignment: Alignment.centerLeft, child: AppRouteBackLink()),
        const Spacer(),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: colors.background.base,
                borderRadius: BorderRadius.circular(AppRadii.large),
                border: Border.all(color: colors.border.subtle),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          roundTitle,
                          style: AppTypography.headlineMedium.copyWith(
                            color: colors.text.accent,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        '#${_formatHeight(snapshotHeight)}',
                        style: AppTypography.headlineSmall.copyWith(
                          color: colors.text.accent,
                        ),
                      ),
                    ],
                  ),
                  if (description.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.bodyMedium.copyWith(
                        color: colors.text.secondary,
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'Vote still finalizing',
                    style: AppTypography.headlineSmall.copyWith(
                      color: colors.text.accent,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    recovery.message,
                    style: AppTypography.bodyMedium.copyWith(
                      color: colors.text.secondary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AppButton(
                    onPressed: () => context.go('/voting'),
                    variant: AppButtonVariant.secondary,
                    child: const Text('Back to polls'),
                  ),
                ],
              ),
            ),
          ),
        ),
        const Spacer(),
      ],
    );
  }
}

class _VotedPollHeader extends StatelessWidget {
  const _VotedPollHeader({
    required this.title,
    required this.snapshotHeight,
    required this.description,
    required this.votingPower,
    required this.votedAt,
  });

  final String title;
  final int snapshotHeight;
  final String description;
  final String votingPower;
  final DateTime? votedAt;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                title,
                style: AppTypography.headlineMedium.copyWith(
                  color: colors.text.accent,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              '#${_formatHeight(snapshotHeight)}',
              style: AppTypography.headlineSmall.copyWith(
                color: colors.text.accent,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xxs,
          children: [
            _MetaText(
              votedAt == null ? 'Voted' : 'Voted ${_formatDate(votedAt!)}',
            ),
            const _MetaText('·'),
            _MetaText('Voting Power $votingPower'),
            const _MetaText('·'),
            const _MetaText('Vote locked'),
          ],
        ),
        if (description.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            description,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.bodyMedium.copyWith(
              color: colors.text.secondary,
            ),
          ),
        ],
      ],
    );
  }
}

class _MetaText extends StatelessWidget {
  const _MetaText(this.value);

  final String value;

  @override
  Widget build(BuildContext context) {
    return Text(
      value,
      style: AppTypography.bodySmall.copyWith(
        color: context.colors.text.secondary,
      ),
    );
  }
}

class _VotedProposalCard extends StatelessWidget {
  const _VotedProposalCard({required this.proposal, required this.choice});

  final VotingProposalView proposal;
  final int? choice;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final choiceLabel = _choiceLabel(proposal, choice);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: colors.background.base,
        borderRadius: BorderRadius.circular(AppRadii.medium),
        border: Border.all(color: colors.border.subtle),
        boxShadow: [
          BoxShadow(
            color: colors.background.neutralScrim.withValues(alpha: 0.12),
            offset: const Offset(0, 8),
            blurRadius: 18,
            spreadRadius: -12,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _ProposalBadge('Proposal ${proposal.id}'),
              const Spacer(),
              _ChoiceBadge(choiceLabel),
            ],
          ),
          const SizedBox(height: AppSpacing.s),
          Text(
            proposal.title,
            style: AppTypography.headlineSmall.copyWith(
              color: colors.text.accent,
            ),
          ),
          if (proposal.description.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xxs),
            Text(
              proposal.description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.bodySmall.copyWith(
                color: colors.text.secondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ProposalBadge extends StatelessWidget {
  const _ProposalBadge(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: colors.background.neutralSubtleOpacity,
        borderRadius: BorderRadius.circular(AppRadii.full),
        border: Border.all(color: colors.border.subtle),
      ),
      child: Text(
        label,
        style: AppTypography.labelMedium.copyWith(color: colors.text.secondary),
      ),
    );
  }
}

class _ChoiceBadge extends StatelessWidget {
  const _ChoiceBadge(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final palette = _choicePalette(colors, label);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: palette.background,
        borderRadius: BorderRadius.circular(AppRadii.xSmall),
        border: Border.all(color: palette.border),
      ),
      child: Text(
        label,
        style: AppTypography.labelMedium.copyWith(color: palette.text),
      ),
    );
  }
}

class _ProposalCard extends StatelessWidget {
  const _ProposalCard({
    required this.proposal,
    required this.selectedChoice,
    required this.onChoice,
  });

  final VotingProposalView proposal;
  final int? selectedChoice;
  final ValueChanged<int> onChoice;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: colors.background.ground.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(AppRadii.large),
        border: Border.all(color: colors.border.subtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            proposal.title,
            style: AppTypography.headlineSmall.copyWith(
              color: colors.text.accent,
            ),
          ),
          if (proposal.description.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xxs),
            Text(
              proposal.description,
              style: AppTypography.bodyMedium.copyWith(
                color: colors.text.secondary,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          for (final option in proposal.options) ...[
            _OptionRow(
              option: option,
              selected: selectedChoice == option.index,
              onTap: () => onChoice(option.index),
            ),
            const SizedBox(height: AppSpacing.xs),
          ],
        ],
      ),
    );
  }
}

class _CompletedVote {
  const _CompletedVote({
    required this.choicesByProposalId,
    required this.votedAt,
  });

  final Map<int, int?> choicesByProposalId;
  final DateTime? votedAt;

  static _CompletedVote? fromPlan(
    VotingResumePlan? plan,
    List<VotingProposalView> proposals,
  ) {
    if (plan == null ||
        _hasBlockingRecoveryWork(plan) ||
        !_hasCompletedVoteArtifact(plan)) {
      return null;
    }
    final choices = <int, int?>{};
    for (final proposal in proposals) {
      final proposalChoices = plan.votesByKey.values
          .where((vote) => vote.proposalId == proposal.id)
          .map((vote) => vote.choice)
          .toSet();
      choices[proposal.id] = proposalChoices.length == 1
          ? proposalChoices.single
          : null;
    }
    return _CompletedVote(
      choicesByProposalId: choices,
      votedAt: _submittedAtFromPlan(plan),
    );
  }
}

class _PendingVoteRecovery {
  const _PendingVoteRecovery({required this.message});

  final String message;

  static _PendingVoteRecovery? fromPlan(VotingResumePlan? plan) {
    if (plan == null ||
        !_hasBlockingRecoveryWork(plan) ||
        !_hasCompletedVoteArtifact(plan)) {
      return null;
    }
    if (plan.pendingDelegationBundleIndexes.isNotEmpty) {
      return const _PendingVoteRecovery(
        message:
            'This vote has local progress, but delegation is not fully confirmed yet. The app should continue recovery before accepting another vote.',
      );
    }
    if (plan.pendingVoteSubmissionKeys.isNotEmpty ||
        plan.incompleteVoteRecoveryKeys.isNotEmpty) {
      return const _PendingVoteRecovery(
        message:
            'This vote has been started, but its commitment transaction recovery data is not complete yet. Do not vote again from this account.',
      );
    }
    return const _PendingVoteRecovery(
      message:
          'This vote was submitted, but some helper-server shares are still waiting for confirmation. Do not vote again from this account.',
    );
  }
}

bool _hasCompletedVoteArtifact(VotingResumePlan plan) {
  return plan.votesByKey.isNotEmpty ||
      plan.voteTxHashesByKey.isNotEmpty ||
      plan.commitmentBundlesByKey.isNotEmpty ||
      plan.shareDelegations.isNotEmpty;
}

bool _hasBlockingRecoveryWork(VotingResumePlan plan) {
  return plan.pendingDelegationBundleIndexes.isNotEmpty ||
      plan.pendingVoteSubmissionKeys.isNotEmpty ||
      plan.incompleteVoteRecoveryKeys.isNotEmpty ||
      plan.unconfirmedShareDelegations.any(
        (record) => record.sentToUrls.isEmpty,
      );
}

class _ChoicePalette {
  const _ChoicePalette({
    required this.background,
    required this.border,
    required this.text,
  });

  final Color background;
  final Color border;
  final Color text;
}

_ChoicePalette _choicePalette(AppColors colors, String label) {
  final lower = label.toLowerCase();
  if (lower.contains('support') || lower.contains('yes')) {
    return _ChoicePalette(
      background: colors.background.utilitySuccessSubtle,
      border: colors.background.utilitySuccessAlpha,
      text: colors.text.success,
    );
  }
  if (lower.contains('oppose') || lower.contains('no')) {
    return _ChoicePalette(
      background: colors.background.utilityDestructiveSubtle,
      border: colors.background.utilityDestructiveAlpha,
      text: colors.text.destructive,
    );
  }
  return _ChoicePalette(
    background: colors.background.neutralSubtleOpacity,
    border: colors.border.subtle,
    text: colors.text.secondary,
  );
}

String _choiceLabel(VotingProposalView proposal, int? choice) {
  if (choice == null) return 'Vote recorded';
  return proposal.options
      .firstWhere(
        (option) => option.index == choice,
        orElse: () => VotingOptionView(index: choice, label: 'Choice $choice'),
      )
      .label;
}

String _roundDescription(Map<String, dynamic> json) {
  for (final key in const ['description', 'body', 'summary']) {
    final value = json[key];
    if (value != null && value.toString().trim().isNotEmpty) {
      return value.toString().trim();
    }
  }
  return '';
}

String _formatHeight(int height) {
  final text = height.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < text.length; i++) {
    final remaining = text.length - i;
    buffer.write(text[i]);
    if (remaining > 1 && remaining % 3 == 1) buffer.write(',');
  }
  return buffer.toString();
}

DateTime? _submittedAtFromPlan(VotingResumePlan plan) {
  final timestamps = plan.shareDelegations
      .map((record) => record.createdAt)
      .where((value) => value > BigInt.zero)
      .toList();
  if (timestamps.isEmpty) return null;
  timestamps.sort();
  final raw = timestamps.last;
  final milliseconds = raw > BigInt.from(100000000000)
      ? raw.toInt()
      : (raw * BigInt.from(1000)).toInt();
  return DateTime.fromMillisecondsSinceEpoch(milliseconds);
}

String _formatDate(DateTime date) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final local = date.toLocal();
  return '${months[local.month - 1]} ${local.day}, ${local.year}';
}

class _OptionRow extends StatelessWidget {
  const _OptionRow({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final VotingOptionView option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadii.small),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: selected
              ? colors.background.brandCrimsonAlpha
              : colors.background.neutralSubtleOpacity,
          borderRadius: BorderRadius.circular(AppRadii.small),
          border: Border.all(
            color: selected
                ? colors.border.brandCrimsonStrong
                : colors.border.subtle,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                option.label,
                style: AppTypography.labelLarge.copyWith(
                  color: colors.text.accent,
                ),
              ),
            ),
            Text(
              selected ? 'Selected' : 'Choose',
              style: AppTypography.bodySmall.copyWith(
                color: selected
                    ? colors.text.brandCrimson
                    : colors.text.secondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        '$title\n$message',
        textAlign: TextAlign.center,
        style: AppTypography.bodyMedium.copyWith(
          color: context.colors.text.accent,
        ),
      ),
    );
  }
}
