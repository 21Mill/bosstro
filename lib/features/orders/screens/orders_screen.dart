import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:bosstro/core/app_routes.dart';
import 'package:bosstro/core/app_theme.dart';
import 'package:bosstro/features/disputes/widgets/not_solver_banner.dart';
import 'package:bosstro/features/nodes/providers/node_providers.dart';
import 'package:bosstro/features/orders/providers/orders_providers.dart';
import 'package:bosstro/features/orders/services/orders_core.dart';
import 'package:bosstro/features/orders/widgets/lookup_notice.dart';
import 'package:bosstro/features/orders/widgets/order_snapshot_view.dart';
import 'package:bosstro/l10n/app_localizations.dart';
import 'package:bosstro/shared/widgets/boxed_field.dart';
import 'package:bosstro/shared/widgets/input_source_action.dart';
import 'package:bosstro/shared/widgets/list_empty_state.dart';
import 'package:bosstro/shared/widgets/order_data_card.dart';
import 'package:bosstro/shared/widgets/primary_button.dart';
import 'package:bosstro/shared/widgets/redesign_app_bar.dart';
import 'package:bosstro/shared/widgets/tab_app_bar.dart';

/// Orders tab: look up any order of the active node by its id, in dispute or
/// not (mostrod's `admin-order-info`, issue #51). The form first, and under
/// it what the lookup is for, then how it ended: the order as the node sees it now, or why there
/// is none. Read only: nothing here changes an order or a dispute, and
/// nothing looked up is stored. An order shows only when it was just asked
/// for: leaving the tab empties it, the app going to the background does not.
///
/// The lookup is offered only for a text that is an order id, so no proof of
/// work is spent on a request the node would refuse.
class OrdersScreen extends ConsumerStatefulWidget {
  const OrdersScreen({super.key});

  @override
  ConsumerState<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends ConsumerState<OrdersScreen> {
  final _id = TextEditingController();

  /// Under the field: the clipboard was empty, or what was submitted is not
  /// an id.
  String? _fieldError;

  @override
  void dispose() {
    _id.dispose();
    super.dispose();
  }

  bool get _valid => ref.read(ordersCoreProvider).isOrderId(_id.text);

  Future<void> _paste() async {
    final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text?.trim();
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    setState(() {
      if (text == null || text.isEmpty) {
        _fieldError = l10n.clipboardEmpty;
      } else {
        _id.text = text;
        _fieldError = _valid ? null : l10n.orderIdInvalid;
      }
    });
  }

  Future<void> _lookup() async {
    if (!_valid) {
      setState(() => _fieldError = AppLocalizations.of(context).orderIdInvalid);
      return;
    }
    FocusScope.of(context).unfocus();
    await ref.read(orderLookupProvider.notifier).lookup(_id.text);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final pal = ShellPalette.of(context);
    final hasNode = ref.watch(activeNodeProvider) != null;
    final view = ref.watch(orderLookupProvider);
    // The tab starts empty again (the solver left it, or the node or the key
    // changed): the id asked about goes with the order.
    ref.listen(orderLookupProvider.select((view) => view.session), (_, _) {
      _id.clear();
      setState(() => _fieldError = null);
    });

    final form = SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BoxedField(
            controller: _id,
            label: l10n.detailOrderId,
            hint: l10n.orderIdHint,
            errorText: _fieldError,
            mono: true,
            textInputAction: TextInputAction.search,
            onChanged: (_) => setState(() => _fieldError = null),
            onSubmitted: (_) => _lookup(),
          ),
          const SizedBox(height: 12),
          InputSourceAction(
            icon: Icons.content_paste_rounded,
            label: l10n.pasteAction,
            onTap: view.asking ? null : _paste,
          ),
          const SizedBox(height: 12),
          PrimaryButton(
            label: l10n.orderLookupAction,
            busy: view.asking,
            onPressed: _valid ? _lookup : null,
          ),
        ],
      ),
    );

    return ColoredBox(
      color: pal.bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TabHeader(title: l10n.ordersTitle),
          Expanded(
            child:
                !hasNode
                    ? ListEmptyState(
                      sticker: 'thinking',
                      title: l10n.pendingNoNodeTitle,
                      body: l10n.ordersNoNodeBody,
                      action: PrimaryButton(
                        label: l10n.pendingNoNodeAction,
                        onPressed: () => context.push(AppRoute.settingsNode),
                      ),
                    )
                    : ListView(
                      padding: const EdgeInsets.fromLTRB(
                        redesignSidePadding,
                        4,
                        redesignSidePadding,
                        24,
                      ),
                      children: [
                        form,
                        const SizedBox(height: 16),
                        switch (_outcome(l10n, view)) {
                          // Said aloud when it arrives: the solver's eyes
                          // are on the form.
                          final outcome? => Semantics(
                            liveRegion: true,
                            child: outcome,
                          ),
                          // Before the first lookup, what it is for. Under
                          // the form, so a large text never pushes the field
                          // off the screen.
                          null => Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 2),
                            child: Text(
                              l10n.ordersIntro,
                              style: TextStyle(
                                fontSize: 14,
                                height: 1.5,
                                color: pal.textSecondary,
                              ),
                            ),
                          ),
                        },
                      ],
                    ),
          ),
        ],
      ),
    );
  }

  /// How the last lookup ended; null before the first one.
  Widget? _outcome(AppLocalizations l10n, OrderLookupView view) {
    if (view.error case final error?) {
      return LookupNotice(
        icon: Icons.error_outline_rounded,
        error: true,
        title: l10n.takeFailedTitle,
        body: switch (error) {
          OrderLookupError.invalidOrderId => l10n.orderIdInvalid,
          OrderLookupError.protocolUnsupported => l10n.takeProtocolBody,
          OrderLookupError.nodeInfoUnavailable => l10n.takeNodeInfoBody,
          // Nothing was tried: no relay refused it.
          OrderLookupError.noKey => l10n.requestNoKeyBody,
          OrderLookupError.noNode => l10n.requestNoNodeBody,
          OrderLookupError.noRelays => l10n.chatErrorNoRelays,
          OrderLookupError.sendFailed => l10n.takeFailedBody,
        },
      );
    }
    final result = view.result;
    if (result == null) return null;
    return switch (result.outcome) {
      OrderLookupOutcome.found => switch (result.order) {
        final order? => OrderSnapshotView(
          order: order,
          askedAt: result.askedAt.toInt(),
          // The order on screen, whatever the field says by now.
          onRefresh:
              () =>
                  ref.read(orderLookupProvider.notifier).lookup(result.orderId),
        ),
        // Found always carries its order; without one there is nothing to
        // show but that the answer could not be read.
        null => LookupNotice(
          icon: Icons.error_outline_rounded,
          error: true,
          title: l10n.resolveRefusedTitle,
          body: l10n.orderRefusedBody,
        ),
      },
      OrderLookupOutcome.notFound => LookupNotice(
        icon: Icons.search_off_rounded,
        title: l10n.orderNotFoundTitle,
        body: l10n.orderNotFoundBody,
      ),
      OrderLookupOutcome.notSolver => const NotSolverBanner(),
      OrderLookupOutcome.noAnswer => LookupNotice(
        icon: Icons.hourglass_empty_rounded,
        title: l10n.noAnswerTitle,
        body: l10n.orderNoAnswerBody,
      ),
      OrderLookupOutcome.refused => LookupNotice(
        icon: Icons.error_outline_rounded,
        error: true,
        title: l10n.resolveRefusedTitle,
        body: orderRefusedBody(l10n, result.reason),
      ),
    };
  }
}

/// Why the node refused a lookup, in words. [reason] is the protocol's own
/// marker (mostro-core's `CantDoReason`), never shown as it came. A lookup's
/// "not found" and "not a solver" are outcomes of their own; what is left is
/// what a node of another version or in another state may answer.
String orderRefusedBody(AppLocalizations l10n, String? reason) =>
    switch (reason) {
      null || '' => l10n.orderRefusedBody,
      'invalid_action' => l10n.orderRefusedUnsupportedBody,
      'too_many_requests' => l10n.orderRefusedBusyBody,
      _ => l10n.orderRefusedUnknownBody,
    };
