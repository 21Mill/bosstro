import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bosstro/core/app_theme.dart';
import 'package:bosstro/core/disputes_palette.dart';
import 'package:bosstro/features/serbero/providers/serbero_providers.dart';
import 'package:bosstro/features/serbero/services/serbero_core.dart';
import 'package:bosstro/features/settings/providers/serbero_provider.dart';
import 'package:bosstro/l10n/app_localizations.dart';
import 'package:bosstro/shared/utils/date_time_format.dart';
import 'package:bosstro/shared/widgets/list_empty_state.dart';
import 'package:bosstro/shared/widgets/list_skeleton.dart';
import 'package:bosstro/shared/widgets/order_data_card.dart';
import 'package:bosstro/shared/widgets/redesign_app_bar.dart';
import 'package:bosstro/shared/widgets/secure_window.dart';

/// Open Serbero's mediation of [disputeId] (pushed over the detail, as the
/// observer).
Future<void> openSerberoScreen(BuildContext context, String disputeId) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SerberoScreen(disputeId: disputeId),
      ),
    );

/// What Serbero sent this solver key about a dispute (D13), read only: its
/// brief, the conversation it had with the buyer and the seller, the
/// messages that arrived after the handoff and its final report. Serbero's
/// text and the parties' are shown as plain text, never parsed for links.
///
/// The parties' words are not the solver's to share, so the window is
/// secure while it is open (FLAG_SECURE on Android), as the observer's.
class SerberoScreen extends ConsumerWidget {
  const SerberoScreen({super.key, required this.disputeId});

  final String disputeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final pal = ShellPalette.of(context);
    final state = ref.watch(serberoMediationProvider(disputeId));
    final trusted = ref.watch(serberoNpubProvider).valueOrNull != null;
    return SecureWindow(
      child: Scaffold(
        backgroundColor: pal.bg,
        appBar: redesignAppBar(
          context,
          title: l10n.serberoCardTitle,
          onBack: () => Navigator.of(context).pop(),
        ),
        body: switch (state) {
          AsyncData(:final value) when value == null || value.isBlank =>
            ListEmptyState(
              sticker: 'thinking',
              title: l10n.serberoEmptyTitle,
              body:
                  trusted ? l10n.serberoCardEmpty : l10n.serberoCardNotTrusted,
            ),
          AsyncData(:final value?) => _Mediation(mediation: value),
          AsyncError() => ListEmptyState(
            sticker: 'thinking',
            title: l10n.pendingLoadErrorTitle,
            body: l10n.pendingLoadErrorBody,
          ),
          _ => ListSkeleton(label: l10n.chatLoading, rowHeight: 72),
        },
      ),
    );
  }
}

class _Mediation extends StatelessWidget {
  const _Mediation({required this.mediation});

  final SerberoMediation mediation;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final pal = ShellPalette.of(context);
    final locale = Localizations.localeOf(context).toString();
    final missing = mediation.transcriptParts < mediation.transcriptTotal;
    final small = TextStyle(fontSize: 12, height: 1.4, color: pal.textTertiary);

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        redesignSidePadding,
        8,
        redesignSidePadding,
        24,
      ),
      children: [
        if (mediation.brief case final brief?)
          _NoteCard(title: l10n.serberoBriefTitle, note: brief),
        if (mediation.transcript.isNotEmpty) ...[
          _Heading(l10n.serberoTranscriptTitle),
          Text(l10n.serberoTimesUtc, style: small),
          if (missing)
            Text(
              l10n.serberoTranscriptParts(
                mediation.transcriptParts,
                mediation.transcriptTotal,
              ),
              style: small.copyWith(color: pal.warnText),
            ),
          const SizedBox(height: 8),
          for (final line in mediation.transcript) _LineBubble(line: line),
        ],
        if (mediation.updates.isNotEmpty) ...[
          _Heading(l10n.serberoUpdatesTitle),
          for (final update in mediation.updates) ...[
            Text(formatDateTime(update.sentAt.toInt(), locale), style: small),
            const SizedBox(height: 6),
            for (final line in update.lines) _LineBubble(line: line),
          ],
        ],
        if (mediation.finalReport case final report?) ...[
          const SizedBox(height: 8),
          _NoteCard(title: l10n.serberoFinalTitle, note: report),
        ],
      ],
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 4),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: ShellPalette.of(context).textPrimary,
      ),
    ),
  );
}

/// A Serbero message shown as it wrote it: the brief, the final report.
class _NoteCard extends StatelessWidget {
  const _NoteCard({required this.title, required this.note});

  final String title;
  final SerberoNote note;

  @override
  Widget build(BuildContext context) {
    final pal = ShellPalette.of(context);
    final locale = Localizations.localeOf(context).toString();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: SurfaceCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: pal.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '${note.subject} · ${formatDateTime(note.sentAt.toInt(), locale)}',
              style: TextStyle(fontSize: 12, color: pal.textTertiary),
            ),
            const SizedBox(height: 10),
            SelectableText(
              note.body.trim(),
              style: TextStyle(fontSize: 13, height: 1.45, color: pal.textBody),
            ),
          ],
        ),
      ),
    );
  }
}

/// One line of Serbero's transcript. The buyer's sit on the left on the
/// buyer tint and the seller's on the right on the seller tint, as the
/// observer's; Serbero's sit on the side of the party it wrote to, on a
/// neutral fill. The sender is named in words too (DS-COL-10).
class _LineBubble extends StatelessWidget {
  const _LineBubble({required this.line});

  final SerberoLine line;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final pal = DisputesPalette.of(context);
    final shell = ShellPalette.of(context);
    final speaker = line.speaker;
    if (speaker == null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          line.text,
          style: TextStyle(fontSize: 13, color: shell.textSecondary),
        ),
      );
    }
    final (sender, left, fill, border, label) = switch (speaker) {
      SerberoSpeaker.buyer => (
        l10n.chatSenderBuyer,
        true,
        pal.observedBuyerFill,
        pal.observedBuyerBorder,
        pal.observedBuyerLabel,
      ),
      SerberoSpeaker.seller => (
        l10n.chatSenderSeller,
        false,
        pal.observedSellerFill,
        pal.observedSellerBorder,
        pal.observedSellerLabel,
      ),
      SerberoSpeaker.serberoToBuyer => (
        l10n.serberoSenderToBuyer,
        true,
        shell.inset,
        shell.border,
        shell.textSecondary,
      ),
      SerberoSpeaker.serberoToSeller => (
        l10n.serberoSenderToSeller,
        false,
        shell.inset,
        shell.border,
        shell.textSecondary,
      ),
    };
    final ink = fill == shell.inset ? shell.textBody : pal.bubbleInk;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: LayoutBuilder(
        builder:
            (context, constraints) => Align(
              alignment: left ? Alignment.centerLeft : Alignment.centerRight,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: constraints.maxWidth * 0.82,
                ),
                child: MergeSemantics(
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                    decoration: BoxDecoration(
                      color: fill,
                      borderRadius: BorderRadius.circular(AppRadius.block),
                      border: Border.all(color: border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          sender,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: label,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          line.text,
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.4,
                            color: ink,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          line.time,
                          style: TextStyle(fontSize: 11, color: pal.bubbleMeta),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
      ),
    );
  }
}
