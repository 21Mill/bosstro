import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:bosstro/core/app_theme.dart';
import 'package:bosstro/features/orders/services/orders_core.dart';
import 'package:bosstro/features/orders/widgets/order_summary_card.dart';
import 'package:bosstro/l10n/app_localizations.dart';
import 'package:bosstro/shared/widgets/labeled_icon_action.dart';
import 'package:bosstro/shared/widgets/order_data_card.dart';

/// One order as the node saw it when it was asked: the summary, always open,
/// with the order's own data (id, amounts, dates, premium), then the two
/// things a solver looks an order up for, open as well (where the seller's
/// sats are, and the payment to the buyer), then the rest, folded: the
/// parties and the deposits. Under it, when the node answered and the way to
/// ask again.
///
/// What the node's database recorded and what its Lightning node reports now
/// sit in neighbouring rows, each named by where it comes from, and are never
/// merged into one verdict: the point of the lookup is to see when they
/// disagree, and that call is the solver's.
///
/// Absence is said, never hidden: an order with no sats locked or no payment
/// under way has a row that says so, so the solver does not wonder whether
/// something failed to load.
class OrderSnapshotView extends StatelessWidget {
  const OrderSnapshotView({
    super.key,
    required this.order,
    required this.askedAt,
    required this.onRefresh,
  });

  final OrderSnapshot order;

  /// When the node's answer was read (Unix seconds).
  final int askedAt;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final pal = ShellPalette.of(context);
    final locale = Localizations.localeOf(context).toString();
    final number = NumberFormat.decimalPattern(locale);
    String sats(int value) => l10n.disputeAmountSats(number.format(value));
    String? dateTime(int? seconds) =>
        seconds == null
            ? null
            : DateFormat.yMMMd(locale).add_Hm().format(
              DateTime.fromMillisecondsSinceEpoch(seconds * 1000),
            );

    // A row whose value is a phrase or a date: it wraps rather than being cut.
    Widget row(IconData icon, String label, String? value) => OrderDataRow(
      icon: icon,
      label: label,
      value: OrderDataValue(value ?? l10n.detailPartyUnknown, wrap: true),
    );
    Widget figure(IconData icon, String label, String value) => OrderDataRow(
      icon: icon,
      label: label,
      value: OrderDataValue(value, figures: true),
    );
    Widget idRow(IconData icon, String label, String? id) => OrderDataRow(
      icon: icon,
      label: label,
      onTap: id == null ? null : () => copyId(context, id),
      value:
          id == null
              ? OrderDataValue(l10n.detailPartyUnknown)
              : OrderIdValue(id: id),
    );

    final funds = <Widget>[
      if (order.holdInvoice case final hold?) ...[
        row(
          Icons.bolt_rounded,
          l10n.orderOnLightning,
          _holdState(l10n, hold.state),
        ),
        if (dateTime(hold.heldAt?.toInt()) case final at?)
          row(Icons.lock_clock_outlined, l10n.orderFundsHeldAt, at),
      ],
      if (order.cashuEscrow case final cashu?) ...[
        row(Icons.account_balance_outlined, l10n.orderCashuMint, cashu.mintUrl),
        if (dateTime(cashu.lockedAt?.toInt()) case final at?)
          row(Icons.lock_clock_outlined, l10n.orderFundsHeldAt, at),
      ],
      if (order.holdInvoice == null && order.cashuEscrow == null)
        row(
          Icons.lock_open_rounded,
          l10n.orderFundsLocked,
          l10n.orderValueNone,
        ),
      if (dateTime(order.holdSettledAt?.toInt()) case final at?)
        row(Icons.task_alt_rounded, l10n.orderFundsSettledAt, at),
    ];

    final payout = <Widget>[
      if (order.payout case final payment?) ...[
        row(
          Icons.bolt_rounded,
          l10n.orderOnLightning,
          _payoutState(l10n, payment.state),
        ),
        if (payment.failureReason case final reason?)
          row(
            Icons.help_outline_rounded,
            l10n.orderPayoutWhyFailed,
            _failureReason(l10n, reason),
          ),
        if (dateTime(payment.resolvedAt?.toInt()) case final at?)
          row(Icons.schedule_rounded, l10n.orderPayoutEndedAt, at),
      ] else
        row(
          Icons.hourglass_empty_rounded,
          l10n.orderPayoutUnderWay,
          l10n.orderValueNone,
        ),
      row(
        Icons.report_gmailerrorred_rounded,
        l10n.orderPayoutLastFailed,
        order.failedPayment ? l10n.settingsSolverYes : l10n.settingsSolverNo,
      ),
      figure(
        Icons.replay_rounded,
        l10n.orderPayoutAttempts,
        number.format(order.paymentAttempts.toInt()),
      ),
      if (order.routingFee.toInt() > 0)
        figure(
          Icons.alt_route_rounded,
          l10n.orderRoutingFee,
          sats(order.routingFee.toInt()),
        ),
    ];

    String who(bool buyer, bool seller) => switch ((buyer, seller)) {
      (true, true) => l10n.orderPartyBoth,
      (true, false) => l10n.detailPartyBuyer,
      (false, true) => l10n.detailPartySeller,
      (false, false) => l10n.orderPartyNobody,
    };
    final parties = <Widget>[
      idRow(Icons.key_outlined, l10n.detailBuyerKey, order.buyerTradePubkey),
      idRow(Icons.key_outlined, l10n.detailSellerKey, order.sellerTradePubkey),
      row(
        Icons.gavel_rounded,
        l10n.orderDisputeOpenedBy,
        who(order.buyerDispute, order.sellerDispute),
      ),
      row(
        Icons.handshake_outlined,
        l10n.orderCancelAskedBy,
        who(order.buyerCooperativeCancel, order.sellerCooperativeCancel),
      ),
    ];

    final deposits = <Widget>[
      for (final bond in order.bonds)
        row(
          Icons.shield_outlined,
          _bondLabel(l10n, bond),
          [
            sats(bond.amount.toInt()),
            _bondState(l10n, bond.state),
            if (bond.slashReason case final reason?) _slashReason(l10n, reason),
          ].join(' · '),
        ),
      if (order.bonds.isEmpty)
        row(Icons.shield_outlined, l10n.detailBonds, l10n.orderDepositsNone),
    ];

    final asked = DateFormat.Hm(
      locale,
    ).format(DateTime.fromMillisecondsSinceEpoch(askedAt * 1000));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OrderSummaryCard(order: order),
        const SizedBox(height: 12),
        CollapsibleDataCard(
          icon: Icons.lock_outline_rounded,
          title: l10n.orderFundsTitle,
          rows: funds,
          expanded: true,
        ),
        const SizedBox(height: 12),
        CollapsibleDataCard(
          icon: Icons.send_rounded,
          title: l10n.orderPayoutTitle,
          rows: payout,
          expanded: true,
        ),
        const SizedBox(height: 12),
        CollapsibleDataCard(
          icon: Icons.people_outline_rounded,
          title: l10n.orderPartiesTitle,
          rows: parties,
        ),
        const SizedBox(height: 12),
        CollapsibleDataCard(
          icon: Icons.shield_outlined,
          title: l10n.orderDepositsTitle(order.bonds.length),
          rows: deposits,
        ),
        const SizedBox(height: 4),
        // A snapshot, not a live view: when it was taken, and the way to
        // take another (asking again is safe). The action moves under the
        // time when both do not fit on a line.
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Text(
                l10n.orderAskedAt(asked),
                style: TextStyle(fontSize: 12, color: pal.textSecondary),
              ),
            ),
            LabeledIconAction(
              icon: Icons.refresh_rounded,
              label: l10n.observerRefresh,
              onPressed: onRefresh,
            ),
          ],
        ),
      ],
    );
  }
}

String _holdState(AppLocalizations l10n, HoldInvoiceState state) =>
    switch (state) {
      HoldInvoiceState.open => l10n.orderHoldOpen,
      HoldInvoiceState.accepted => l10n.orderHoldAccepted,
      HoldInvoiceState.settled => l10n.orderHoldSettled,
      HoldInvoiceState.canceled => l10n.orderHoldCanceled,
      HoldInvoiceState.notFound => l10n.orderLnNotFound,
      HoldInvoiceState.unavailable => l10n.orderLnUnavailable,
      HoldInvoiceState.unknown => l10n.orderValueUnknown,
    };

String _payoutState(AppLocalizations l10n, PayoutState state) =>
    switch (state) {
      PayoutState.inFlight => l10n.orderPayoutInFlight,
      PayoutState.succeeded => l10n.orderPayoutSucceeded,
      PayoutState.failed => l10n.orderPayoutFailed,
      PayoutState.notFound => l10n.orderLnNotFound,
      PayoutState.unavailable => l10n.orderLnUnavailable,
      PayoutState.unknown => l10n.orderValueUnknown,
    };

String _failureReason(
  AppLocalizations l10n,
  PayoutFailureReason reason,
) => switch (reason) {
  PayoutFailureReason.timeout => l10n.orderPayoutReasonTimeout,
  PayoutFailureReason.noRoute => l10n.orderPayoutReasonNoRoute,
  PayoutFailureReason.error => l10n.orderPayoutReasonError,
  PayoutFailureReason.incorrectPaymentDetails => l10n.orderPayoutReasonDetails,
  PayoutFailureReason.insufficientBalance => l10n.orderPayoutReasonBalance,
  PayoutFailureReason.canceled => l10n.orderPayoutReasonCanceled,
  PayoutFailureReason.unknown => l10n.orderValueUnknown,
};

/// Whose deposit a row is, or what the row is on a range order.
String _bondLabel(AppLocalizations l10n, OrderBond bond) {
  final role = switch (bond.role) {
    BondRole.maker => l10n.orderBondMaker,
    BondRole.taker => l10n.orderBondTaker,
    BondRole.unknown => l10n.orderValueUnknown,
  };
  return switch (bond.kind) {
    BondKind.sliceSlash => l10n.orderBondSliceSlash,
    BondKind.makerRefund => l10n.orderBondMakerRefund,
    BondKind.bond || BondKind.unknown =>
      bond.rootOrderId == null ? role : l10n.orderBondOfRoot(role),
  };
}

String _bondState(AppLocalizations l10n, BondState state) => switch (state) {
  BondState.requested => l10n.orderBondRequested,
  BondState.locked => l10n.orderBondLocked,
  BondState.released => l10n.orderBondReleased,
  BondState.pendingPayout => l10n.orderBondPendingPayout,
  BondState.slashed => l10n.orderBondSlashed,
  BondState.forfeited => l10n.orderBondForfeited,
  BondState.failed => l10n.orderBondFailed,
  BondState.unknown => l10n.orderValueUnknown,
};

String _slashReason(AppLocalizations l10n, BondSlashReason reason) =>
    switch (reason) {
      BondSlashReason.lostDispute => l10n.orderBondLostDispute,
      BondSlashReason.timeout => l10n.orderBondTimeout,
      BondSlashReason.unknown => l10n.orderValueUnknown,
    };
