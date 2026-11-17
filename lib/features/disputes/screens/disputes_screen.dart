import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:bosstro/core/app_routes.dart';
import 'package:bosstro/core/app_theme.dart';
import 'package:bosstro/features/disputes/screens/my_disputes_pane.dart';
import 'package:bosstro/features/disputes/screens/pending_pane.dart';
import 'package:bosstro/features/disputes/widgets/detail_segments.dart';
import 'package:bosstro/l10n/app_localizations.dart';
import 'package:bosstro/shared/widgets/labeled_icon_action.dart';
import 'package:bosstro/shared/widgets/redesign_app_bar.dart';
import 'package:bosstro/shared/widgets/tab_app_bar.dart';

/// The three parts of the Disputes tab. Each has a location of its own
/// ([location]), so the router remembers the one on screen and another screen
/// can open the tab on a given part.
enum DisputesSection {
  /// Waiting for a solver on the active node.
  pending,

  /// Held by this key.
  inProgress,

  /// Held by this key until they closed.
  closed;

  String get location => switch (this) {
    DisputesSection.pending => AppRoute.pending,
    DisputesSection.inProgress => AppRoute.inProgress,
    DisputesSection.closed => AppRoute.closed,
  };
}

/// Disputes tab: one segmented control (Pending · In progress · Closed) under
/// the header, and the chosen part under it. Recover a dispute opens from the
/// header of the ones in progress (Mostrix's Shift+R) and from their empty
/// state.
///
/// The header and the segments stay fixed above the part while the screen
/// has the room. On a short screen or at a large text scale they would leave
/// the list a sliver of the screen (the segments wrap onto several lines), so
/// there they scroll away with it.
class DisputesScreen extends StatelessWidget {
  const DisputesScreen({super.key, required this.section});

  final DisputesSection section;

  /// Below this height, or above this text scale, nothing stays fixed.
  static const double _fixedMinHeight = 420;
  static const double _fixedMaxTextScale = 1.3;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final part = switch (section) {
      DisputesSection.pending => const PendingPane(),
      DisputesSection.inProgress => const MyDisputesPane(closed: false),
      DisputesSection.closed => const MyDisputesPane(closed: true),
    };
    return ColoredBox(
      color: ShellPalette.of(context).bg,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final fixed =
              constraints.maxHeight >= _fixedMinHeight &&
              MediaQuery.textScalerOf(context).scale(1) <= _fixedMaxTextScale;
          final top = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TabHeader(
                title: l10n.disputesTitle,
                // Recover brings back a dispute in progress: not the job of
                // the other parts. While the header is fixed it keeps its
                // room there, unseen, untappable and unheard, so the segments
                // under it never jump.
                action: Visibility(
                  visible: section == DisputesSection.inProgress,
                  maintainSize: fixed,
                  maintainAnimation: fixed,
                  maintainState: fixed,
                  child: LabeledIconAction(
                    icon: Icons.history_rounded,
                    label: l10n.recoverAction,
                    onPressed: () => context.push(AppRoute.recover),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  redesignSidePadding,
                  4,
                  redesignSidePadding,
                  4,
                ),
                child: DetailSegments<DisputesSection>(
                  semanticLabel: l10n.disputesSegmentsLabel,
                  selected: section,
                  onSelected: (value) => context.go(value.location),
                  segments: [
                    DetailSegment(
                      value: DisputesSection.pending,
                      label: l10n.disputesPendingSegment,
                    ),
                    DetailSegment(
                      value: DisputesSection.inProgress,
                      label: l10n.myDisputesOpenSegment,
                    ),
                    DetailSegment(
                      value: DisputesSection.closed,
                      label: l10n.myDisputesClosedSegment,
                    ),
                  ],
                ),
              ),
            ],
          );
          // Each part its own scroll position, kept while another is on
          // screen.
          final key = PageStorageKey('disputes-${section.name}');
          if (!fixed) {
            return CustomScrollView(
              key: key,
              slivers: [SliverToBoxAdapter(child: top), part],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              top,
              Expanded(child: CustomScrollView(key: key, slivers: [part])),
            ],
          );
        },
      ),
    );
  }
}
