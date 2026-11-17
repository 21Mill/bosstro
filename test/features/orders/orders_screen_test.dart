import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:bosstro/core/app_routes.dart';
import 'package:bosstro/features/disputes/providers/pending_providers.dart';
import 'package:bosstro/features/disputes/services/disputes_core.dart';
import 'package:bosstro/features/disputes/widgets/not_solver_banner.dart';
import 'package:bosstro/features/nodes/providers/node_providers.dart';
import 'package:bosstro/features/orders/providers/orders_providers.dart';
import 'package:bosstro/features/orders/screens/orders_screen.dart';
import 'package:bosstro/features/orders/services/orders_core.dart';
import 'package:bosstro/features/orders/widgets/lookup_notice.dart';
import 'package:bosstro/features/orders/widgets/order_snapshot_view.dart';
import 'package:bosstro/features/orders/widgets/order_summary_card.dart';
import 'package:bosstro/shared/widgets/primary_button.dart';

import '../../support/screen_harness.dart';

void _mockClipboard(WidgetTester tester, String? text) {
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async =>
        call.method == 'Clipboard.getData'
            ? (text == null ? null : <String, dynamic>{'text': text})
            : null,
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
}

Future<void> _pump(
  WidgetTester tester,
  FakeOrdersCore orders, {
  Locale locale = const Locale('en'),
  Brightness brightness = Brightness.dark,
  double textScale = 1,
  FakeNodesCore? nodes,
  FakeDisputesCore? disputes,
}) => pumpApp(
  tester,
  location: AppRoute.orders,
  locale: locale,
  brightness: brightness,
  textScale: textScale,
  overrides: fakeCoreOverrides(
    orders: orders,
    nodes: nodes,
    disputes: disputes,
  ),
);

/// The screen's own scroll.
Finder _list() =>
    find
        .descendant(
          of: find.byType(OrdersScreen),
          matching: find.byType(Scrollable),
        )
        .first;

/// Brings [text] on screen (the snapshot is longer than the screen).
Future<void> _show(WidgetTester tester, String text) async {
  await tester.scrollUntilVisible(find.text(text), 120, scrollable: _list());
  await tester.pumpAndSettle();
}

/// Opens the folded card titled [title].
Future<void> _open(WidgetTester tester, String title) async {
  await _show(tester, title);
  await tester.tap(find.text(title));
  await tester.pumpAndSettle();
}

/// A Unix time as the snapshot writes a date and a time, in English.
String _date(int seconds) => DateFormat.yMMMd(
  'en',
).add_Hm().format(DateTime.fromMillisecondsSinceEpoch(seconds * 1000));

PrimaryButton _button(WidgetTester tester) =>
    tester.widget<PrimaryButton>(find.byType(PrimaryButton));

/// Types [id] and asks: the button, brought on screen first.
Future<void> _ask(WidgetTester tester, {String id = sampleOrderId}) async {
  await tester.enterText(find.byType(TextField), id);
  await tester.pump();
  await tester.ensureVisible(find.byType(PrimaryButton));
  await tester.pumpAndSettle();
  await tester.tap(find.byType(PrimaryButton));
  await tester.pumpAndSettle();
}

void main() {
  // DS-A11Y-4: the screen at 320 dp, 2× text, Spanish, in both themes, in
  // every state, with no overflow.
  for (final brightness in Brightness.values) {
    final theme = brightness.name;

    testWidgets('Orders fits before a lookup and with an order, $theme', (
      tester,
    ) async {
      setSurface(tester);
      await _pump(
        tester,
        FakeOrdersCore(),
        locale: const Locale('es'),
        brightness: brightness,
        textScale: 2,
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Consultar una orden'), findsOneWidget);

      await _ask(tester);
      expect(tester.takeException(), isNull);
      expect(find.byType(OrderSummaryCard), findsOneWidget);
      await tester.ensureVisible(find.byType(OrderSummaryCard));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        find.text('Sats liberados, comprador aún sin pagar'),
        findsOneWidget,
      );
      // Both folded cards open: the whole snapshot, to its end.
      for (final title in ['Partes', 'Depósitos (2)']) {
        await tester.ensureVisible(find.text(title));
        await tester.pumpAndSettle();
        await tester.tap(find.text(title));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: title);
      }
      await expectClearOfNavBar(
        tester,
        scrollable: _list(),
        last: find.text('Actualizar'),
      );
      expect(tester.takeException(), isNull);
    });

    for (final answer in <Object>[
      OrderLookupOutcome.notFound,
      OrderLookupOutcome.notSolver,
      OrderLookupOutcome.noAnswer,
      OrderLookupOutcome.refused,
      OrderLookupError.sendFailed,
      OrderLookupError.nodeInfoUnavailable,
      OrderLookupError.protocolUnsupported,
    ]) {
      testWidgets('Orders fits when the lookup ends $answer, $theme', (
        tester,
      ) async {
        setSurface(tester);
        final core =
            FakeOrdersCore()
              ..answer = answer
              ..reason = 'invalid_action';
        await _pump(
          tester,
          core,
          locale: const Locale('es'),
          brightness: brightness,
          textScale: 2,
        );
        await _ask(tester);
        expect(tester.takeException(), isNull);
        final notice =
            answer == OrderLookupOutcome.notSolver
                ? find.byType(NotSolverBanner)
                : find.byType(LookupNotice);
        expect(notice, findsOneWidget);
        await tester.ensureVisible(notice);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byType(OrderSummaryCard), findsNothing);
      });
    }

    testWidgets('Orders fits before a node is chosen, $theme', (tester) async {
      setSurface(tester);
      await _pump(
        tester,
        FakeOrdersCore(),
        locale: const Locale('es'),
        brightness: brightness,
        textScale: 2,
        nodes: FakeNodesCore(),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Primero elige tu nodo'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
    });
  }

  group('the form', () {
    testWidgets('offers the lookup only for an order id', (tester) async {
      setSurface(tester, width: 400, height: 800);
      final core = FakeOrdersCore();
      await _pump(tester, core);
      expect(find.text('Look up an order'), findsOneWidget);
      // One primary action, off until there is an id to ask about.
      expect(find.byType(PrimaryButton), findsOneWidget);
      expect(_button(tester).onPressed, isNull);

      await tester.enterText(find.byType(TextField), '308e1272');
      await tester.pump();
      expect(_button(tester).onPressed, isNull);

      await tester.enterText(find.byType(TextField), ' $sampleOrderId ');
      await tester.pump();
      expect(_button(tester).onPressed, isNotNull);
      expect(core.lookups, isEmpty, reason: 'nothing is sent while typing');
    });

    testWidgets('a text that is no id, submitted from the keyboard, says so '
        'and sends nothing', (tester) async {
      setSurface(tester, width: 400, height: 800);
      final core = FakeOrdersCore();
      await _pump(tester, core);

      await tester.enterText(find.byType(TextField), 'not-an-id');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();

      expect(find.textContaining('That is not an order ID'), findsOneWidget);
      expect(core.lookups, isEmpty);

      // Typing again clears it.
      await tester.enterText(find.byType(TextField), 'not');
      await tester.pump();
      expect(find.textContaining('That is not an order ID'), findsNothing);
    });

    testWidgets('Paste fills the field from the clipboard', (tester) async {
      setSurface(tester, width: 400, height: 800);
      await _pump(tester, FakeOrdersCore());
      _mockClipboard(tester, '  $sampleOrderId\n');

      await tester.tap(find.text('Paste'));
      await tester.pump();

      expect(find.text(sampleOrderId), findsOneWidget);
      expect(_button(tester).onPressed, isNotNull);
    });

    testWidgets('an empty clipboard, or one with no id, says so', (
      tester,
    ) async {
      setSurface(tester, width: 400, height: 800);
      await _pump(tester, FakeOrdersCore());

      _mockClipboard(tester, null);
      await tester.tap(find.text('Paste'));
      await tester.pump();
      expect(find.text('The clipboard is empty.'), findsOneWidget);

      _mockClipboard(tester, 'hello');
      await tester.tap(find.text('Paste'));
      await tester.pump();
      expect(find.textContaining('That is not an order ID'), findsOneWidget);
      expect(_button(tester).onPressed, isNull);
    });

    testWidgets('while the node answers the button is busy and a second '
        'request does not leave', (tester) async {
      setSurface(tester, width: 400, height: 800);
      final core = FakeOrdersCore()..hold = Completer();
      await _pump(tester, core);
      await tester.enterText(find.byType(TextField), sampleOrderId);
      await tester.pump();
      await tester.tap(find.byType(PrimaryButton));
      await tester.pump();

      // The button's own spinner, never one in the middle of the screen
      // (DS-CMP-13).
      expect(_button(tester).busy, isTrue);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.tap(find.byType(PrimaryButton), warnIfMissed: false);
      await tester.pump();
      expect(core.lookups, [sampleOrderId]);

      core.hold!.complete();
      await tester.pumpAndSettle();
      expect(_button(tester).busy, isFalse);
      expect(find.byType(OrderSummaryCard), findsOneWidget);
    });
  });

  group('the answer', () {
    testWidgets('an order shows its real status in words, what the trade is, '
        'its id and its amounts', (tester) async {
      setSurface(tester, width: 400, height: 800);
      final core = FakeOrdersCore();
      await _pump(tester, core);
      await _ask(tester);

      expect(core.lookups, [sampleOrderId]);
      expect(find.text('Sats released, buyer not paid yet'), findsOneWidget);
      expect(find.text('Sell order · 50 EUR · SEPA'), findsOneWidget);
      expect(find.text('Status'), findsOneWidget);
      expect(find.text('308e1272…9c23'), findsOneWidget);
      expect(find.text('100,000 sats'), findsOneWidget);
      expect(find.text('600 sats'), findsOneWidget);
      // The protocol's word is not what the solver reads.
      expect(find.text('settled-hold-invoice'), findsNothing);
    });

    testWidgets('amounts read in the solver\'s language', (tester) async {
      setSurface(tester, width: 400, height: 800);
      await _pump(tester, FakeOrdersCore(), locale: const Locale('es'));
      await _ask(tester);

      expect(find.text('100.000 sats'), findsOneWidget);
      expect(find.text('Orden de venta · 50 EUR · SEPA'), findsOneWidget);
    });

    testWidgets('a status this build does not know reads as the node wrote '
        'it', (tester) async {
      setSurface(tester, width: 400, height: 800);
      final core =
          FakeOrdersCore()
            ..order = sampleOrder(
              status: OrderStatus.unknown,
              statusRaw: 'frozen-by-audit',
            );
      await _pump(tester, core);
      await _ask(tester);

      expect(find.text('frozen-by-audit'), findsOneWidget);
    });

    testWidgets('every status has its words', (tester) async {
      setSurface(tester, width: 400, height: 800);
      final core = FakeOrdersCore();
      await _pump(tester, core);
      for (final status in OrderStatus.values) {
        if (status == OrderStatus.unknown) continue;
        core.order = sampleOrder(status: status, statusRaw: 'raw-wire-word');
        await _ask(tester);
        expect(
          find.byType(OrderSummaryCard),
          findsOneWidget,
          reason: '$status',
        );
        expect(find.text('raw-wire-word'), findsNothing, reason: '$status');
      }
    });

    testWidgets('an unknown order is not found, in neutral: not an error', (
      tester,
    ) async {
      setSurface(tester, width: 400, height: 800);
      final core = FakeOrdersCore()..answer = OrderLookupOutcome.notFound;
      await _pump(tester, core);
      await _ask(tester);

      expect(find.text('Order not found'), findsOneWidget);
      expect(
        tester.widget<LookupNotice>(find.byType(LookupNotice)).error,
        isFalse,
      );
    });

    testWidgets('a key that is no solver gets the banner and the way to '
        'switch node', (tester) async {
      setSurface(tester, width: 400, height: 800);
      final core = FakeOrdersCore()..answer = OrderLookupOutcome.notSolver;
      await _pump(tester, core);
      await _ask(tester);

      expect(find.byType(NotSolverBanner), findsOneWidget);
      expect(find.text('You are not a solver on this node'), findsOneWidget);
      expect(find.text('Switch node'), findsOneWidget);
    });

    testWidgets('no answer says the node may not support it, and that asking '
        'again is safe', (tester) async {
      setSurface(tester, width: 400, height: 800);
      final core = FakeOrdersCore()..answer = OrderLookupOutcome.noAnswer;
      await _pump(tester, core);
      await _ask(tester);

      expect(find.text('The node did not answer'), findsOneWidget);
      expect(
        find.textContaining('does not answer order lookups yet'),
        findsOneWidget,
      );
      expect(find.textContaining('you can ask again'), findsOneWidget);

      // And it can: the same id, asked again, is sent again.
      core.answer = OrderLookupOutcome.found;
      await tester.tap(find.byType(PrimaryButton));
      await tester.pumpAndSettle();
      expect(core.lookups, [sampleOrderId, sampleOrderId]);
      expect(find.byType(OrderSummaryCard), findsOneWidget);
      expect(find.text('The node did not answer'), findsNothing);
    });

    testWidgets('a refusal says why in words, never in the protocol\'s', (
      tester,
    ) async {
      setSurface(tester, width: 400, height: 800);
      final core =
          FakeOrdersCore()
            ..answer = OrderLookupOutcome.refused
            ..reason = 'invalid_action';
      await _pump(tester, core);
      await _ask(tester);

      expect(find.text('The node refused the request'), findsOneWidget);
      expect(
        find.textContaining('does not answer order lookups'),
        findsOneWidget,
      );
      expect(find.textContaining('invalid_action'), findsNothing);
      expect(
        tester.widget<LookupNotice>(find.byType(LookupNotice)).error,
        isTrue,
      );

      for (final (reason, words) in [
        ('too_many_requests', 'too many requests'),
        // A reason this build has no words for is not shown as it came.
        ('price_too_stale', 'a reason this version of Bosstro does not know'),
        (null, 'It gave no reason'),
      ]) {
        core.reason = reason;
        await tester.tap(find.byType(PrimaryButton));
        await tester.pumpAndSettle();
        expect(find.textContaining(words), findsOneWidget, reason: '$reason');
        if (reason != null) {
          expect(find.textContaining(reason), findsNothing);
        }
      }
    });

    testWidgets('a request that did not leave says why', (tester) async {
      setSurface(tester, width: 400, height: 800);
      final core = FakeOrdersCore()..answer = OrderLookupError.sendFailed;
      await _pump(tester, core);
      await _ask(tester);
      expect(find.text('The request was not sent'), findsOneWidget);
      expect(find.textContaining('No relay took it'), findsOneWidget);

      // Nothing was tried: the relays are not blamed for it.
      for (final (error, words) in [
        (OrderLookupError.noRelays, 'Not connected to any relay'),
        (OrderLookupError.noNode, 'No node is chosen'),
        (OrderLookupError.noKey, 'No secret key is loaded'),
      ]) {
        core.answer = error;
        await tester.tap(find.byType(PrimaryButton));
        await tester.pumpAndSettle();
        expect(find.textContaining(words), findsOneWidget, reason: '$error');
        expect(find.textContaining('No relay took it'), findsNothing);
      }

      core.answer = OrderLookupError.nodeInfoUnavailable;
      await tester.tap(find.byType(PrimaryButton));
      await tester.pumpAndSettle();
      expect(find.textContaining('proof of work'), findsOneWidget);
    });

    testWidgets('another order replaces the one on screen', (tester) async {
      setSurface(tester, width: 400, height: 800);
      final core = FakeOrdersCore();
      await _pump(tester, core);
      await _ask(tester);
      expect(find.text('308e1272…9c23'), findsOneWidget);

      const other = '0d4f6a2b-7c1e-4f3a-8b5d-9e0f1a2b3c4d';
      core.hold = Completer();
      await tester.enterText(find.byType(TextField), other);
      await tester.pump();
      await tester.tap(find.byType(PrimaryButton));
      await tester.pump();
      // The first order is not left on screen under another one's id.
      expect(find.byType(OrderSummaryCard), findsNothing);

      core.hold!.complete();
      await tester.pumpAndSettle();
      expect(find.text('0d4f6a2b…3c4d'), findsOneWidget);
      expect(find.text('308e1272…9c23'), findsNothing);
    });
  });

  group('the snapshot', () {
    Future<void> shown(WidgetTester tester, OrderSnapshot order) async {
      setSurface(tester, width: 400, height: 800);
      await _pump(tester, FakeOrdersCore()..order = order);
      await _ask(tester);
      expect(find.byType(OrderSnapshotView), findsOneWidget);
    }

    testWidgets('the seller\'s sats: what Lightning says now beside what the '
        'node recorded, each named by where it comes from', (tester) async {
      await shown(tester, sampleOrder());

      // Open without a tap: it is what the solver came for.
      await _show(tester, 'On Lightning now');
      expect(find.text('Collected by the node'), findsOneWidget);
      expect(find.text('Locked (node\'s record)'), findsOneWidget);
      expect(find.text(_date(1700000200)), findsOneWidget);
      expect(find.text('Collected (node\'s record)'), findsOneWidget);
      expect(find.text(_date(1700000250)), findsOneWidget);
    });

    testWidgets('no payment under way is said, with whether the last one '
        'failed and how many were tried', (tester) async {
      await shown(tester, sampleOrder());

      await _show(tester, 'Payment attempts');
      expect(find.text('Payment under way'), findsOneWidget);
      expect(find.text('None'), findsOneWidget);
      expect(find.text('Last payment failed'), findsOneWidget);
      expect(find.text('Yes'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      await _show(tester, 'Routing fee');
      expect(find.text('12 sats'), findsOneWidget);
    });

    testWidgets('a payment that failed says why and when', (tester) async {
      await shown(
        tester,
        sampleOrder(
          payout: const Payout(
            state: PayoutState.failed,
            failureReason: PayoutFailureReason.noRoute,
            resolvedAt: 1700000300,
          ),
        ),
      );

      await _show(tester, 'Why it failed');
      expect(find.text('Failed'), findsOneWidget);
      expect(find.text('No route to the buyer'), findsOneWidget);
      expect(find.text(_date(1700000300)), findsOneWidget);
      expect(find.text('Payment under way'), findsNothing);
    });

    testWidgets('"Lightning did not answer" and "not known to this version" '
        'are two different things', (tester) async {
      await shown(
        tester,
        sampleOrder(
          holdInvoice: const HoldInvoice(state: HoldInvoiceState.unavailable),
          payout: const Payout(state: PayoutState.unknown),
        ),
      );

      await _show(tester, 'Payment attempts');
      expect(find.text('Lightning did not answer'), findsOneWidget);
      expect(find.text('Not known to this version'), findsOneWidget);
    });

    testWidgets('an order with no sats locked says so', (tester) async {
      await shown(tester, sampleOrder(holdInvoice: null));

      await _show(tester, 'Payment attempts');
      expect(find.text('Locked sats'), findsOneWidget);
      expect(find.text('On Lightning now'), findsNothing);
      // None locked, and no payment under way.
      expect(find.text('None'), findsNWidgets(2));
    });

    testWidgets('a Cashu order shows its mint in place of Lightning', (
      tester,
    ) async {
      await shown(
        tester,
        sampleOrder(
          holdInvoice: null,
          cashuEscrow: const CashuEscrow(
            mintUrl: 'https://mint.example',
            // Another minute than the order's own dates, now in view too.
            lockedAt: 1700003000,
          ),
        ),
      );

      await _show(tester, 'Cashu mint');
      expect(find.text('https://mint.example'), findsOneWidget);
      expect(find.text(_date(1700003000)), findsOneWidget);
      expect(find.text('Locked sats'), findsNothing);
    });

    testWidgets('the parties are folded; open, their keys read short and who '
        'opened a dispute or asked to cancel is named', (tester) async {
      await shown(tester, sampleOrder());

      await _show(tester, 'Parties');
      expect(find.text('Buyer\'s trade key'), findsNothing);
      await _open(tester, 'Parties');
      await _show(tester, 'Cancel asked by');

      expect(find.text('22222222…2222'), findsOneWidget);
      expect(find.text('11111111…1111'), findsOneWidget);
      expect(find.text('Dispute opened by'), findsOneWidget);
      expect(find.text('Seller'), findsOneWidget);
      expect(find.text('Nobody'), findsOneWidget);
    });

    testWidgets('the deposits are counted in their title and read as amount, '
        'state and why', (tester) async {
      await shown(tester, sampleOrder());

      await _open(tester, 'Deposits (2)');
      await _show(tester, 'Taker');

      expect(find.text('Maker'), findsOneWidget);
      expect(find.text('5,000 sats · Locked'), findsOneWidget);
      expect(
        find.text('1,000 sats · Slashed, payout owed · lost the dispute'),
        findsOneWidget,
      );
    });

    testWidgets('an order with no deposit says so', (tester) async {
      await shown(tester, sampleOrder(bonds: const []));

      await _open(tester, 'Deposits (0)');
      await _show(tester, 'No deposit on this order');
      expect(find.text('No deposit on this order'), findsOneWidget);
    });

    testWidgets('a range order\'s deposits name what each row is', (
      tester,
    ) async {
      const root = '0d4f6a2b-7c1e-4f3a-8b5d-9e0f1a2b3c4d';
      await shown(
        tester,
        sampleOrder(
          bonds: const [
            OrderBond(
              role: BondRole.maker,
              amount: 5000,
              state: BondState.locked,
              kind: BondKind.bond,
              rootOrderId: root,
            ),
            OrderBond(
              role: BondRole.maker,
              amount: 500,
              state: BondState.slashed,
              slashReason: BondSlashReason.timeout,
              kind: BondKind.sliceSlash,
            ),
            OrderBond(
              role: BondRole.maker,
              amount: 4500,
              state: BondState.released,
              kind: BondKind.makerRefund,
            ),
          ],
        ),
      );

      await _open(tester, 'Deposits (3)');
      await _show(tester, 'Rest returned to the maker');

      expect(find.text('Maker (root order)'), findsOneWidget);
      expect(find.text('Slashed on one slice'), findsOneWidget);
      expect(
        find.text('500 sats · Slashed and paid out · did not act in time'),
        findsOneWidget,
      );
      expect(find.text('4,500 sats · Returned'), findsOneWidget);
    });

    testWidgets('the order\'s dates and premium are in the summary, in view '
        'without opening anything', (tester) async {
      await shown(tester, sampleOrder());

      await _show(tester, 'Expires');
      final summary = find.byType(OrderSummaryCard);
      Finder inSummary(String text) =>
          find.descendant(of: summary, matching: find.text(text));
      expect(inSummary('Created'), findsOneWidget);
      expect(inSummary(_date(1700000000)), findsOneWidget);
      expect(inSummary('Taken'), findsOneWidget);
      expect(inSummary(_date(1700000100)), findsOneWidget);
      expect(inSummary(_date(1700086400)), findsOneWidget);
      expect(inSummary('1 %'), findsOneWidget);
      // Not a range order: no range.
      expect(find.text('Fiat range'), findsNothing);
      expect(find.text('More details'), findsNothing);
    });

    testWidgets('an order nobody took yet reads Pending, with no taken time', (
      tester,
    ) async {
      setSurface(tester, width: 400, height: 800);
      final core =
          FakeOrdersCore()
            ..order = sampleOrder(
              status: OrderStatus.pending,
              statusRaw: 'pending',
              takenAt: null,
            );
      await _pump(tester, core);
      await _ask(tester);

      expect(find.text('Pending'), findsOneWidget);
      await _show(tester, 'Taken');
      expect(
        find.descendant(
          of: find.byType(OrderSummaryCard),
          matching: find.text('Not known'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a range order shows its range and the order it is part of', (
      tester,
    ) async {
      await shown(
        tester,
        sampleOrder(
          minAmount: 10,
          maxAmount: 100,
          rangeParentId: '0d4f6a2b-7c1e-4f3a-8b5d-9e0f1a2b3c4d',
        ),
      );

      await _show(tester, 'Part of range order');
      expect(find.text('10 – 100 EUR'), findsOneWidget);
      expect(find.text('0d4f6a2b…3c4d'), findsOneWidget);
    });

    testWidgets('it says when it was asked, and Refresh asks about the order '
        'on screen again, whatever the field says by now', (tester) async {
      setSurface(tester, width: 400, height: 800);
      final core = FakeOrdersCore();
      await _pump(tester, core);
      await _ask(tester);
      final asked = DateFormat.Hm(
        'en',
      ).format(DateTime.fromMillisecondsSinceEpoch(1700000500 * 1000));

      await tester.enterText(find.byType(TextField), 'something else');
      await tester.pump();
      await _show(tester, 'Refresh');
      expect(find.text('Asked at $asked'), findsOneWidget);

      core.hold = Completer();
      await tester.tap(find.text('Refresh'));
      await tester.pump();
      // The snapshot stays while its newer one is on the way.
      expect(find.byType(OrderSnapshotView), findsOneWidget);
      expect(core.lookups, [sampleOrderId, sampleOrderId]);

      core.order = sampleOrder(
        status: OrderStatus.success,
        statusRaw: 'success',
      );
      core.hold!.complete();
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Completed'),
        -200,
        scrollable: _list(),
      );
      expect(find.text('Completed'), findsOneWidget);
    });
  });

  group('only while the solver stays on the tab', () {
    testWidgets('a look at another tab empties it: the order and the id', (
      tester,
    ) async {
      setSurface(tester, width: 400, height: 800);
      final core = FakeOrdersCore();
      await _pump(tester, core);
      await _ask(tester);
      expect(find.byType(OrderSnapshotView), findsOneWidget);

      for (final other in ['Settings', 'Disputes']) {
        await tester.tap(find.text(other));
        await tester.pumpAndSettle();
        expect(find.byType(OrdersScreen), findsNothing);
        await tester.tap(find.text('Orders'));
        await tester.pumpAndSettle();

        expect(find.byType(OrderSnapshotView), findsNothing, reason: other);
        expect(find.text(sampleOrderId), findsNothing, reason: other);
        expect(_button(tester).onPressed, isNull, reason: other);
        // What the lookup is for, as before the first one.
        expect(find.textContaining('Looking changes nothing'), findsOneWidget);

        await _ask(tester);
        expect(find.byType(OrderSnapshotView), findsOneWidget, reason: other);
      }
      expect(core.lookups, hasLength(3), reason: 'only when asked');
    });

    testWidgets('the browser\'s Back and Forward empty it as the bottom bar '
        'does', (tester) async {
      setSurface(tester, width: 400, height: 800);
      final core = FakeOrdersCore();
      await _pump(tester, core);
      await _ask(tester);
      final router = GoRouter.of(tester.element(find.byType(OrdersScreen)));
      // What the engine reports when the browser moves through its history.
      Future<void> browserGoesTo(String location) async {
        await router.routeInformationProvider.didPushRouteInformation(
          RouteInformation(uri: Uri.parse(location)),
        );
        await tester.pumpAndSettle();
      }

      await browserGoesTo(AppRoute.settings);
      expect(find.byType(OrdersScreen), findsNothing);
      await browserGoesTo(AppRoute.orders);

      expect(find.byType(OrderSnapshotView), findsNothing);
      expect(find.text(sampleOrderId), findsNothing);
      expect(core.lookups, [sampleOrderId], reason: 'not asked again');
    });

    testWidgets('a tap on Orders itself keeps the order', (tester) async {
      setSurface(tester, width: 400, height: 800);
      await _pump(tester, FakeOrdersCore());
      await _ask(tester);

      await tester.tap(find.text('Orders'));
      await tester.pumpAndSettle();

      expect(find.byType(OrderSnapshotView), findsOneWidget);
      expect(find.text(sampleOrderId), findsOneWidget);
    });

    testWidgets('the app going to the background and back keeps the order', (
      tester,
    ) async {
      setSurface(tester, width: 400, height: 800);
      final core = FakeOrdersCore();
      await _pump(tester, core);
      await _ask(tester);

      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
        await tester.pump();
      }
      await tester.pumpAndSettle();

      expect(find.byType(OrderSnapshotView), findsOneWidget);
      expect(find.text(sampleOrderId), findsOneWidget);
      expect(core.lookups, [sampleOrderId], reason: 'not asked again');
    });

    testWidgets('an answer that arrives after the solver left the tab is '
        'dropped', (tester) async {
      setSurface(tester, width: 400, height: 800);
      final core = FakeOrdersCore()..hold = Completer();
      await _pump(tester, core);
      await tester.enterText(find.byType(TextField), sampleOrderId);
      await tester.pump();
      await tester.tap(find.byType(PrimaryButton));
      await tester.pump();

      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      core.hold!.complete();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Orders'));
      await tester.pumpAndSettle();

      expect(find.byType(OrderSnapshotView), findsNothing);
      expect(_button(tester).busy, isFalse);
    });

    testWidgets('another node starts empty: an order of one node is never '
        'shown under another', (tester) async {
      setSurface(tester, width: 400, height: 800);
      await _pump(tester, FakeOrdersCore());
      await _ask(tester);
      expect(find.byType(OrderSummaryCard), findsOneWidget);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(OrdersScreen)),
      );
      container.read(activeNodeProvider.notifier).state = cubaPubkey;
      await tester.pumpAndSettle();

      expect(find.byType(OrderSummaryCard), findsNothing);
      expect(container.read(orderLookupProvider).result, isNull);
    });

    testWidgets('an answer that arrives after the node changed is dropped', (
      tester,
    ) async {
      setSurface(tester, width: 400, height: 800);
      final core = FakeOrdersCore()..hold = Completer();
      await _pump(tester, core);
      await tester.enterText(find.byType(TextField), sampleOrderId);
      await tester.pump();
      await tester.tap(find.byType(PrimaryButton));
      await tester.pump();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(OrdersScreen)),
      );
      container.read(activeNodeProvider.notifier).state = cubaPubkey;
      await tester.pump();
      core.hold!.complete();
      await tester.pumpAndSettle();

      expect(find.byType(OrderSummaryCard), findsNothing);
      expect(container.read(orderLookupProvider).asking, isFalse);
    });
  });

  testWidgets('a lookup that says "not a solver" is read into the key\'s '
      'standing at once', (tester) async {
    setSurface(tester, width: 400, height: 800);
    final disputes = FakeDisputesCore();
    final core = FakeOrdersCore()..answer = OrderLookupOutcome.notSolver;
    await _pump(tester, core, disputes: disputes);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(OrdersScreen)),
    );
    expect(
      container.read(solverStandingProvider).valueOrNull?.status,
      isNot(SolverStatus.no),
    );

    // The Rust core records it before the lookup returns.
    disputes.status = SolverStatus.no;
    await _ask(tester);

    expect(
      container.read(solverStandingProvider).valueOrNull?.status,
      SolverStatus.no,
    );
  });

  testWidgets('so is one that answers after the solver left the tab', (
    tester,
  ) async {
    setSurface(tester, width: 400, height: 800);
    final disputes = FakeDisputesCore();
    final core =
        FakeOrdersCore()
          ..answer = OrderLookupOutcome.notSolver
          ..hold = Completer();
    await _pump(tester, core, disputes: disputes);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(OrdersScreen)),
    );
    await tester.enterText(find.byType(TextField), sampleOrderId);
    await tester.pump();
    await tester.tap(find.byType(PrimaryButton));
    await tester.pump();

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    disputes.status = SolverStatus.no;
    core.hold!.complete();
    await tester.pumpAndSettle();

    expect(
      container.read(solverStandingProvider).valueOrNull?.status,
      SolverStatus.no,
    );
    expect(container.read(orderLookupProvider).result, isNull);
  });
}
