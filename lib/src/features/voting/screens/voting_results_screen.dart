import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_main_sidebar.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_back_link.dart';
import '../../../providers/voting/voting_config_provider.dart';
import '../../../providers/voting/voting_service_providers.dart';
import '../../../providers/voting/voting_session_provider.dart';
import '../voting_flow_models.dart';

final _roundTallyProvider = FutureProvider.family((ref, String roundId) async {
  final config = await ref.watch(votingConfigProvider.future);
  return ref
      .read(votingApiClientProvider(config.apiBaseUrl))
      .getRoundTally(roundId);
});

class VotingResultsScreen extends ConsumerWidget {
  const VotingResultsScreen({super.key, required this.roundId});

  final String roundId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(votingSessionProvider(roundId));
    final tally = ref.watch(_roundTallyProvider(roundId));
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
              'Poll Results',
              textAlign: TextAlign.center,
              style: AppTypography.displaySmall.copyWith(
                color: context.colors.text.accent,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Expanded(
              child: tally.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => _Message("Couldn't load results: $error"),
                data: (result) {
                  final round = session.value?.round;
                  final proposals = round == null
                      ? <VotingProposalView>[]
                      : proposalsFromRound(round);
                  if (_isTallying(result.rawJson)) {
                    return const _Message('Results pending...');
                  }
                  return ListView.separated(
                    itemCount: proposals.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: AppSpacing.s),
                    itemBuilder: (context, index) => _ResultCard(
                      proposal: proposals[index],
                      tally: _proposalTally(
                        result.rawJson,
                        proposals[index].id,
                      ),
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

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.proposal, required this.tally});

  final VotingProposalView proposal;
  final Map<int, num> tally;

  @override
  Widget build(BuildContext context) {
    final total = tally.values.fold<num>(0, (sum, value) => sum + value);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: context.colors.background.ground.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(AppRadii.large),
        border: Border.all(color: context.colors.border.subtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            proposal.title,
            style: AppTypography.headlineSmall.copyWith(
              color: context.colors.text.accent,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final option in proposal.options)
            _TallyRow(
              label: option.label,
              amount: tally[option.index] ?? 0,
              total: total,
            ),
        ],
      ),
    );
  }
}

class _TallyRow extends StatelessWidget {
  const _TallyRow({
    required this.label,
    required this.amount,
    required this.total,
  });

  final String label;
  final num amount;
  final num total;

  @override
  Widget build(BuildContext context) {
    final pct = total <= 0 ? 0.0 : (amount / total).clamp(0.0, 1.0).toDouble();
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: AppTypography.bodyMedium.copyWith(
                    color: context.colors.text.accent,
                  ),
                ),
              ),
              Text(
                '${amount.toStringAsFixed(0)} (${(pct * 100).toStringAsFixed(1)}%)',
                style: AppTypography.bodySmall.copyWith(
                  color: context.colors.text.secondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          LinearProgressIndicator(value: pct),
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

bool _isTallying(Map<String, dynamic> json) {
  final status = (json['status'] ?? json['phase'] ?? '')
      .toString()
      .toLowerCase();
  return status == 'tallying' || status == 'pending';
}

Map<int, num> _proposalTally(Map<String, dynamic> json, int proposalId) {
  final tallies = json['tallies'] ?? json['results'] ?? json['proposals'];
  final values = tallies is List ? tallies : const [];
  for (final value in values) {
    final object = value is Map
        ? value.map((key, value) => MapEntry(key.toString(), value))
        : const <String, dynamic>{};
    final id = int.tryParse(
      (object['proposal_id'] ?? object['proposalId'] ?? object['id'] ?? '')
          .toString(),
    );
    if (id == proposalId) {
      return _entriesToTally(
        object['entries'] ?? object['options'] ?? object['tally'],
      );
    }
  }
  return _entriesToTally(json['entries'] ?? json['tally']);
}

Map<int, num> _entriesToTally(Object? value) {
  if (value is Map) {
    return value.map(
      (key, value) => MapEntry(int.tryParse(key.toString()) ?? 0, _num(value)),
    );
  }
  if (value is List) {
    return {
      for (final entry in value)
        if (entry is Map)
          int.tryParse(
                (entry['decision'] ?? entry['choice'] ?? entry['index'] ?? 0)
                    .toString(),
              ) ??
              0: _num(
            entry['amount'] ?? entry['votes'] ?? entry['value'],
          ),
    };
  }
  return const {};
}

num _num(Object? value) {
  if (value is num) return value;
  return num.tryParse(value?.toString() ?? '') ?? 0;
}
