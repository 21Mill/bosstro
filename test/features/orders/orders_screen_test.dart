import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bosstro/core/app_routes.dart';
import 'package:bosstro/features/disputes/providers/pending_providers.dart';
import 'package:bosstro/features/disputes/services/disputes_core.dart';
import 'package:bosstro/features/disputes/widgets/not_solver_banner.dart';
import 'package:bosstro/features/nodes/providers/node_providers.dart';
import 'package:bosstro/features/orders/providers/orders_providers.dart';
import 'package:bosstro/features/orders/screens/orders_screen.dart';
import 'package:bosstro/features/orders/services/orders_core.dart';
import 'package:bosstro/features/orders/widgets/lookup_notice.dart';
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
      await expectClearOfNavBar(
        tester,
        scrollable:
            find
                .descendant(
                  of: find.byType(OrdersScreen),
                  matching: find.byType(Scrollable),
                )
                .first,
        last: find.text('Comisión del nodo'),
      );
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

    testWidgets('a refusal shows the node\'s reason when it gave one', (
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
      expect(find.textContaining('invalid_action'), findsOneWidget);
      expect(
        tester.widget<LookupNotice>(find.byType(LookupNotice)).error,
        isTrue,
      );

      core.reason = null;
      await tester.tap(find.byType(PrimaryButton));
      await tester.pumpAndSettle();
      expect(find.textContaining('It gave no reason'), findsOneWidget);
    });

    testWidgets('a request that did not leave says why', (tester) async {
      setSurface(tester, width: 400, height: 800);
      final core = FakeOrdersCore()..answer = OrderLookupError.sendFailed;
      await _pump(tester, core);
      await _ask(tester);
      expect(find.text('The request was not sent'), findsOneWidget);
      expect(find.textContaining('No relay took it'), findsOneWidget);

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

  group('kept in memory only', () {
    testWidgets('the answer and the id are still there after a look at '
        'another tab', (tester) async {
      setSurface(tester, width: 400, height: 800);
      await _pump(tester, FakeOrdersCore());
      await _ask(tester);

      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      expect(find.byType(OrdersScreen), findsNothing);
      await tester.tap(find.text('Orders'));
      await tester.pumpAndSettle();

      expect(find.byType(OrderSummaryCard), findsOneWidget);
      expect(find.text(sampleOrderId), findsOneWidget);
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
}
