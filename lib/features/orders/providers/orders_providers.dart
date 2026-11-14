import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bosstro/features/disputes/providers/pending_providers.dart';
import 'package:bosstro/features/nodes/providers/node_providers.dart';
import 'package:bosstro/features/orders/services/orders_core.dart';
import 'package:bosstro/features/solver_key/providers/solver_key_providers.dart';

/// The core behind the order lookup. Tests override it with a fake.
final ordersCoreProvider = Provider<OrdersCore>(
  (ref) => const RustOrdersCore(),
);

/// The Orders tab as it stands: a lookup under way, and how the last one
/// ended.
@immutable
class OrderLookupView {
  const OrderLookupView({this.asking = false, this.result, this.error});

  /// A request is waiting for the node's answer.
  final bool asking;

  /// The node's last answer; null before the first, and after a request that
  /// was not sent.
  final OrderLookupResult? result;

  /// Why the last request was not sent; null when it was.
  final OrderLookupError? error;
}

/// The last order looked up on the active node with the loaded key. Kept in
/// memory for the session, so it is still there when the solver comes back
/// to the tab, and nowhere else: a snapshot carries the parties' trade keys
/// and the amounts, and the database is not encrypted. Another node or
/// another key starts empty.
final orderLookupProvider =
    NotifierProvider<OrderLookupNotifier, OrderLookupView>(
      OrderLookupNotifier.new,
    );

class OrderLookupNotifier extends Notifier<OrderLookupView> {
  /// The node and key the state belongs to: an answer to a request made under
  /// another one is dropped.
  Object _epoch = Object();

  @override
  OrderLookupView build() {
    ref.watch(activeNodeProvider);
    ref.watch(solverKeyProvider);
    _epoch = Object();
    return const OrderLookupView();
  }

  /// Ask the active node about [orderId]. The answer on screen stays while
  /// the same order is asked about again; it goes when another one is.
  Future<void> lookup(String orderId) async {
    if (state.asking) return;
    final epoch = _epoch;
    final asked = orderId.trim().toLowerCase();
    final shown = state.result;
    state = OrderLookupView(
      asking: true,
      result: shown != null && shown.orderId == asked ? shown : null,
    );
    OrderLookupView next;
    try {
      final result = await ref.read(ordersCoreProvider).lookup(orderId);
      next = OrderLookupView(result: result);
    } on OrderLookupError catch (error) {
      next = OrderLookupView(error: error);
    } catch (e) {
      debugPrint('[orders] lookup failed: ${e.runtimeType}');
      next = const OrderLookupView(error: OrderLookupError.sendFailed);
    }
    if (!identical(epoch, _epoch)) return;
    state = next;
    // The answer may have taught whether this key is a solver here, and no
    // dispute update says so: read it now.
    try {
      await ref.read(solverStandingProvider.notifier).refresh();
    } catch (e) {
      debugPrint('[orders] standing not refreshed: ${e.runtimeType}');
    }
  }
}
