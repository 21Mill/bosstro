import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:bosstro/core/app_routes.dart';
import 'package:bosstro/features/disputes/providers/pending_providers.dart';
import 'package:bosstro/features/disputes/services/disputes_core.dart';
import 'package:bosstro/features/disputes/widgets/in_progress_dispute_row.dart';
import 'package:bosstro/l10n/app_localizations.dart';
import 'package:bosstro/shared/widgets/list_empty_state.dart';
import 'package:bosstro/shared/widgets/list_skeleton.dart';
import 'package:bosstro/shared/widgets/primary_button.dart';
import 'package:bosstro/shared/widgets/redesign_app_bar.dart';

/// The In progress and Closed parts of the Disputes tab: the disputes this
/// solver holds on the active node, the one that has waited longest first
/// (Mostrix's Disputes Management), or the ones it held that closed, read
/// only, the one closed last first ([closed]). A tap on a dispute opens its
/// detail and chats on a screen of its own, at any width: on a wide window
/// too the detail needs the room (the chat, the files, the resolution), so
/// there is no split view. A sliver: the tab owns the scroll view.
class MyDisputesPane extends ConsumerWidget {
  const MyDisputesPane({super.key, required this.closed});

  /// The closed ones rather than the ones in progress.
  final bool closed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final held = ref.watch(inProgressDisputesProvider);
    return switch (held) {
      AsyncError() => ListEmptyState.sliver(
        sticker: 'thinking',
        title: l10n.pendingLoadErrorTitle,
        body: l10n.pendingLoadErrorBody,
      ),
      AsyncData(:final value?) => _MyDisputes(
        disputes: value.disputes,
        closedDisputes: value.closed,
        closed: closed,
      ),
      AsyncData() => closed ? const _ClosedEmpty() : const _OpenEmpty(),
      _ => SliverToBoxAdapter(
        child: ListSkeleton(label: l10n.loadingDisputes, rowHeight: 160),
      ),
    };
  }
}

/// The open ones' empty state, with the way to recover a lost take.
class _OpenEmpty extends StatelessWidget {
  const _OpenEmpty();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListEmptyState.sliver(
      sticker: 'thinking',
      title: l10n.inProgressEmptyTitle,
      body: l10n.inProgressEmptyBody,
      action: TextLink(
        label: l10n.recoverTitle,
        onPressed: () => context.push(AppRoute.recover),
      ),
    );
  }
}

/// The closed ones' empty state.
class _ClosedEmpty extends StatelessWidget {
  const _ClosedEmpty();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListEmptyState.sliver(
      sticker: 'thinking',
      title: l10n.closedEmptyTitle,
      body: l10n.closedEmptyBody,
    );
  }
}

/// The chosen part, with the ages counted to a clock that moves every
/// minute; the same tick reads the list again (a dispute past its expiration
/// leaves).
class _MyDisputes extends ConsumerStatefulWidget {
  const _MyDisputes({
    required this.disputes,
    required this.closedDisputes,
    required this.closed,
  });

  final List<TakenDisputeSummary> disputes;

  /// The disputes this key held that closed, the one closed last first.
  final List<TakenDisputeSummary> closedDisputes;

  /// Which of the two is on screen.
  final bool closed;

  @override
  ConsumerState<_MyDisputes> createState() => _MyDisputesState();
}

class _MyDisputesState extends ConsumerState<_MyDisputes> {
  late DateTime _now;
  late final Timer _tick = Timer.periodic(const Duration(minutes: 1), (_) {
    setState(() => _now = clock.now());
    unawaited(ref.read(inProgressDisputesProvider.notifier).refresh());
  });

  @override
  void initState() {
    super.initState();
    // Read now, not on first use: an empty part shows no age, and the clock
    // must still be the one of the moment the list appeared.
    _now = clock.now();
    _tick;
  }

  @override
  void dispose() {
    _tick.cancel();
    super.dispose();
  }

  void _open(String id) => context.push(AppRoute.disputeDetail(id));

  @override
  Widget build(BuildContext context) {
    final rows = [
      if (widget.closed)
        for (final dispute in widget.closedDisputes)
          ClosedDisputeRow(
            key: ValueKey(dispute.disputeId),
            dispute: dispute,
            now: _now,
            onTap: () => _open(dispute.disputeId),
          )
      else
        for (final dispute in widget.disputes)
          InProgressDisputeRow(
            key: ValueKey(dispute.disputeId),
            dispute: dispute,
            now: _now,
            onTap: () => _open(dispute.disputeId),
          ),
    ];
    if (rows.isEmpty) {
      return widget.closed ? const _ClosedEmpty() : const _OpenEmpty();
    }
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(
        redesignSidePadding,
        8,
        redesignSidePadding,
        24,
      ),
      sliver: SliverList.separated(
        itemCount: rows.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, i) => rows[i],
      ),
    );
  }
}
