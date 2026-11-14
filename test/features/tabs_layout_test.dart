import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bosstro/core/app_routes.dart';
import 'package:bosstro/features/disputes/screens/disputes_screen.dart';
import 'package:bosstro/features/disputes/services/disputes_core.dart';
import 'package:bosstro/features/disputes/widgets/detail_segments.dart';
import 'package:bosstro/shared/widgets/tab_app_bar.dart';

import '../support/screen_harness.dart';

/// DS-A11Y-4: every screen at 2× text, 320 dp wide, in the longest locale
/// (Spanish), in both themes, without overflow.
void main() {
  for (final location in [...AppRoute.disputeSections, AppRoute.settings]) {
    for (final brightness in Brightness.values) {
      testWidgets('$location fits at 320 dp, 2× text, es, ${brightness.name}', (
        tester,
      ) async {
        setSurface(tester);
        await pumpApp(tester, location: location, brightness: brightness);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('the bottom bar switches tabs', (tester) async {
    setSurface(tester, width: 400, height: 800);
    await pumpApp(
      tester,
      location: AppRoute.pending,
      locale: const Locale('en'),
      textScale: 1,
    );
    // The tab and its title read the same.
    expect(find.text('Disputes'), findsNWidgets(2));

    await tester.tap(find.text('Orders'));
    await tester.pumpAndSettle();
    expect(find.text('Look up an order'), findsOneWidget);
    expect(find.byType(DisputesScreen), findsNothing);

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Language'), findsOneWidget);

    await tester.tap(find.text('Disputes'));
    await tester.pumpAndSettle();
    expect(find.byType(DisputesScreen), findsOneWidget);
  });

  testWidgets('Disputes has one control for its three parts, and comes back '
      'to the one it was left on', (tester) async {
    setSurface(tester, width: 400, height: 800);
    await pumpApp(
      tester,
      location: AppRoute.pending,
      locale: const Locale('en'),
      textScale: 1,
    );
    DisputesSection section() =>
        tester.widget<DisputesScreen>(find.byType(DisputesScreen)).section;
    final segments = find.byType(DetailSegments<DisputesSection>);
    expect(segments, findsOneWidget);
    expect(section(), DisputesSection.pending);
    expect(find.text('No disputes waiting'), findsOneWidget);
    final top = tester.getTopLeft(segments);

    await tester.tap(find.text('In progress'));
    await tester.pumpAndSettle();
    expect(section(), DisputesSection.inProgress);
    expect(find.text('No disputes in progress'), findsOneWidget);
    // Nothing above them moved.
    expect(tester.getTopLeft(segments), top);

    await tester.tap(find.text('Closed'));
    await tester.pumpAndSettle();
    expect(section(), DisputesSection.closed);
    expect(find.text('No closed disputes yet'), findsOneWidget);
    expect(tester.getTopLeft(segments), top);
    // Never one control under another.
    expect(segments, findsOneWidget);

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Disputes'));
    await tester.pumpAndSettle();
    expect(section(), DisputesSection.closed);

    // A tap on the active tab returns it to its root.
    await tester.tap(find.text('Disputes').last);
    await tester.pumpAndSettle();
    expect(section(), DisputesSection.pending);
  });

  testWidgets('at a large text scale the header scrolls away with the list', (
    tester,
  ) async {
    setSurface(tester);
    await pumpApp(tester, location: AppRoute.inProgress);
    final header = find.byType(TabHeader);
    final before = tester.getTopLeft(header).dy;
    await tester.drag(find.byType(DisputesScreen), const Offset(0, -150));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(header).dy, lessThan(before));
    expect(tester.takeException(), isNull);
  });

  testWidgets('every tab title sits at the same height, with an action '
      'beside it or not', (tester) async {
    // Wide enough for Recover to stay on the title's line in the test font.
    setSurface(tester, width: 600, height: 800);
    await pumpApp(
      tester,
      location: AppRoute.pending,
      locale: const Locale('en'),
      textScale: 1,
    );
    // The header's title is its first text, whatever the copy says.
    Rect title() => tester.getRect(
      find
          .descendant(of: find.byType(TabHeader), matching: find.byType(Text))
          .first,
    );
    final pending = title();

    await tester.tap(find.text('In progress'));
    await tester.pumpAndSettle();
    // Recover sits beside this title, a 48-dp target.
    final recover = tester.getCenter(find.text('Recover'));
    expect(recover.dy, closeTo(title().center.dy, 1));
    expect(title().top, pending.top);

    await tester.tap(find.text('Orders'));
    await tester.pumpAndSettle();
    expect(find.text('Look up an order'), findsOneWidget);
    expect(title().top, pending.top);

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Language'), findsOneWidget);
    expect(title().top, pending.top);
  });

  testWidgets('a data row puts its value flush right (DS-CMP-24)', (
    tester,
  ) async {
    setSurface(tester, width: 400, height: 800);
    await pumpApp(
      tester,
      location: AppRoute.settings,
      locale: const Locale('en'),
      textScale: 1,
      overrides: fakeCoreOverrides(
        disputes: FakeDisputesCore()..status = SolverStatus.yes,
      ),
    );
    // "Solver on this node: Yes". Side inset 18, the card's 1-px border,
    // card padding 14.
    expect(tester.getRect(find.text('Yes')).right, 400 - 18 - 1 - 14);
  });

  testWidgets('empty lists explain themselves (DS-CMP-14)', (tester) async {
    setSurface(tester, width: 400, height: 800);
    await pumpApp(
      tester,
      location: AppRoute.pending,
      locale: const Locale('en'),
      textScale: 1,
    );
    expect(find.text('No disputes waiting'), findsOneWidget);
    expect(find.textContaining('waiting for a solver'), findsOneWidget);
  });

  testWidgets('the app bar says no node is selected, in words', (tester) async {
    setSurface(tester, width: 400, height: 800);
    await pumpApp(
      tester,
      location: AppRoute.pending,
      locale: const Locale('en'),
      textScale: 1,
      overrides: fakeCoreOverrides(nodes: FakeNodesCore()),
    );
    expect(find.text('No node selected'), findsOneWidget);
  });
}
