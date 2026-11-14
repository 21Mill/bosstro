import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:bosstro/core/app_theme.dart';
import 'package:bosstro/features/orders/services/orders_core.dart';
import 'package:bosstro/features/orders/widgets/order_labels.dart';
import 'package:bosstro/l10n/app_localizations.dart';
import 'package:bosstro/shared/widgets/order_data_card.dart';

/// The top of a looked-up order, always open: its real status first, in
/// words and in the neutral ink (the solver only looks here; lime is "your
/// turn" and red is danger), then what the trade is, and the order's own
/// data as label → value rows (DS-CMP-24): its id, its amounts, when it was
/// created, taken and expires, its premium, and on a range order its range
/// and the order it is a part of. None of it is folded: a solver reads an
/// order's dates as readily as its amounts.
class OrderSummaryCard extends StatelessWidget {
  const OrderSummaryCard({super.key, required this.order});

  final OrderSnapshot order;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final pal = ShellPalette.of(context);
    final locale = Localizations.localeOf(context).toString();
    final number = NumberFormat.decimalPattern(locale);
    String sats(int value) => l10n.disputeAmountSats(number.format(value));
    // A date and a time as the locale writes them; "Not known" for a time
    // the node does not keep (an order nobody took has no taken time).
    Widget date(IconData icon, String label, int? seconds) => OrderDataRow(
      icon: icon,
      label: label,
      value: OrderDataValue(
        seconds == null
            ? l10n.detailPartyUnknown
            : DateFormat.yMMMd(locale).add_Hm().format(
              DateTime.fromMillisecondsSinceEpoch(seconds * 1000),
            ),
        wrap: true,
      ),
    );

    final fiat =
        order.fiatCode.isEmpty
            ? number.format(order.fiatAmount.toInt())
            : l10n.disputeAmountFiat(
              number.format(order.fiatAmount.toInt()),
              order.fiatCode,
            );
    // What the trade is, on one line that wraps: kind · fiat · method.
    final trade = [
      if (orderKindLabel(l10n, order.kind) case final kind?) kind,
      fiat,
      if (order.paymentMethod.isNotEmpty) order.paymentMethod,
    ].join(' · ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.detailStatus,
                style: TextStyle(fontSize: 12, color: pal.textSecondary),
              ),
              const SizedBox(height: 4),
              Semantics(
                header: true,
                child: Text(
                  orderStatusLabel(l10n, order.status, order.statusRaw),
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: pal.textPrimary,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                trade,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.5,
                  color: pal.textSecondary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        OrderDataCard(
          rows: [
            OrderDataRow(
              icon: Icons.receipt_long_outlined,
              label: l10n.detailOrderId,
              onTap: () => copyId(context, order.orderId),
              value: OrderIdValue(id: order.orderId),
            ),
            OrderDataRow(
              icon: Icons.currency_bitcoin_rounded,
              label: l10n.detailAmount,
              value: OrderDataValue(sats(order.amount.toInt()), figures: true),
            ),
            OrderDataRow(
              icon: Icons.toll_outlined,
              label: l10n.detailFee,
              value: OrderDataValue(sats(order.fee.toInt()), figures: true),
            ),
            OrderDataRow(
              icon: Icons.percent_rounded,
              label: l10n.detailPremium,
              value: OrderDataValue(
                l10n.detailPremiumValue(number.format(order.premium.toInt())),
                figures: true,
              ),
            ),
            if ((order.minAmount, order.maxAmount) case (
              final min?,
              final max?,
            ))
              OrderDataRow(
                icon: Icons.straighten_rounded,
                label: l10n.orderFiatRange,
                value: OrderDataValue(
                  l10n.orderFiatRangeValue(
                    number.format(min.toInt()),
                    number.format(max.toInt()),
                    order.fiatCode,
                  ),
                  figures: true,
                ),
              ),
            if (order.rangeParentId case final parent?)
              OrderDataRow(
                icon: Icons.account_tree_outlined,
                label: l10n.orderRangeParent,
                onTap: () => copyId(context, parent),
                value: OrderIdValue(id: parent),
              ),
            date(
              Icons.schedule_rounded,
              l10n.orderCreatedAt,
              order.createdAt?.toInt(),
            ),
            date(
              Icons.how_to_reg_outlined,
              l10n.orderTakenAt,
              order.takenAt?.toInt(),
            ),
            date(
              Icons.timer_outlined,
              l10n.orderExpiresAt,
              order.expiresAt?.toInt(),
            ),
          ],
        ),
      ],
    );
  }
}
