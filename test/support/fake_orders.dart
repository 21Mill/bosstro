import 'dart:async';

import 'package:bosstro/features/nodes/models/node_display.dart';
import 'package:bosstro/features/orders/services/orders_core.dart';

/// An order id as mostrod writes one.
const sampleOrderId = '308e1272-d5f4-47e6-bd97-3504baea9c23';

final _uuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  caseSensitive: false,
);

/// The order lookup in Dart: what the next lookup answers, and every id
/// asked about.
class FakeOrdersCore implements OrdersCore {
  /// What `lookup` answers: an [OrderLookupOutcome] (a found one carries
  /// [order]), or an [OrderLookupError] to throw.
  Object answer = OrderLookupOutcome.found;

  /// The snapshot a found lookup carries; [sampleOrder] of the id asked when
  /// null.
  OrderSnapshot? order;

  /// The reason a refused lookup carries.
  String? reason;

  /// Holds every lookup until the test completes it.
  Completer<void>? hold;

  final List<String> lookups = [];

  @override
  bool isOrderId(String text) => _uuid.hasMatch(text.trim());

  @override
  Future<OrderLookupResult> lookup(String orderId) async {
    final id = orderId.trim().toLowerCase();
    lookups.add(id);
    if (hold case final hold?) await hold.future;
    final answer = this.answer;
    if (answer is OrderLookupError) throw answer;
    final outcome = answer as OrderLookupOutcome;
    return OrderLookupResult(
      mostroPubkey: mostroNodePubkey,
      orderId: id,
      outcome: outcome,
      order:
          outcome == OrderLookupOutcome.found
              ? (order ?? sampleOrder(id: id))
              : null,
      reason: outcome == OrderLookupOutcome.refused ? reason : null,
      askedAt: 1700000500,
    );
  }
}

/// An order the node settled whose payment to the buyer failed: the case the
/// lookup exists for (the database and Lightning tell different halves).
OrderSnapshot sampleOrder({
  String id = sampleOrderId,
  OrderStatus status = OrderStatus.settledHoldInvoice,
  String statusRaw = 'settled-hold-invoice',
  OrderKind kind = OrderKind.sell,
  String fiatCode = 'EUR',
  String paymentMethod = 'SEPA',
  HoldInvoice? holdInvoice = const HoldInvoice(
    state: HoldInvoiceState.settled,
    heldAt: 1700000200,
  ),
  CashuEscrow? cashuEscrow,
  Payout? payout,
  List<OrderBond> bonds = const [
    OrderBond(
      role: BondRole.maker,
      amount: 5000,
      state: BondState.locked,
      kind: BondKind.bond,
    ),
    OrderBond(
      role: BondRole.taker,
      amount: 1000,
      state: BondState.pendingPayout,
      slashReason: BondSlashReason.lostDispute,
      kind: BondKind.bond,
    ),
  ],
}) => OrderSnapshot(
  orderId: id,
  kind: kind,
  kindRaw: kind == OrderKind.buy ? 'buy' : 'sell',
  status: status,
  statusRaw: statusRaw,
  amount: 100000,
  fee: 600,
  routingFee: 12,
  fiatCode: fiatCode,
  fiatAmount: 50,
  paymentMethod: paymentMethod,
  premium: 1,
  createdAt: 1700000000,
  takenAt: 1700000100,
  expiresAt: 1700086400,
  buyerTradePubkey: '22' * 32,
  sellerTradePubkey: '11' * 32,
  buyerDispute: false,
  sellerDispute: true,
  buyerCooperativeCancel: false,
  sellerCooperativeCancel: false,
  failedPayment: true,
  paymentAttempts: 2,
  holdSettledAt: 1700000250,
  holdInvoice: holdInvoice,
  cashuEscrow: cashuEscrow,
  payout: payout,
  bonds: bonds,
);
