import 'package:bosstro/src/rust/api/order_info.dart' as order_api;
import 'package:bosstro/src/rust/api/order_info.dart' show OrderLookupResult;

export 'package:bosstro/src/rust/api/order_info.dart'
    show
        BondKind,
        BondRole,
        BondSlashReason,
        BondState,
        CashuEscrow,
        HoldInvoice,
        HoldInvoiceState,
        OrderBond,
        OrderKind,
        OrderLookupError,
        OrderLookupOutcome,
        OrderLookupResult,
        OrderSnapshot,
        OrderStatus,
        Payout,
        PayoutFailureReason,
        PayoutState;

/// The Rust core's order lookup (`rust/src/api/order_info.rs`): the real
/// state of any order of the active node, read only. An interface so widget
/// tests, which run without the native library, drive a fake.
abstract interface class OrdersCore {
  /// Whether [text] is an order id (a UUID, with any space around it).
  bool isOrderId(String text);

  /// Ask the active node about [orderId] and wait for its answer. Throws an
  /// [OrderLookupError] when the request was not sent. Nothing is stored, and
  /// asking again is safe.
  Future<OrderLookupResult> lookup(String orderId);
}

class RustOrdersCore implements OrdersCore {
  const RustOrdersCore();

  @override
  bool isOrderId(String text) => order_api.isOrderId(text: text);

  @override
  Future<OrderLookupResult> lookup(String orderId) =>
      order_api.lookupOrder(orderId: orderId);
}
