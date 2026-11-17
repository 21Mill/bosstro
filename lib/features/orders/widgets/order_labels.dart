import 'package:bosstro/features/orders/services/orders_core.dart';
import 'package:bosstro/l10n/app_localizations.dart';

/// An order's real status in words. One the node added after this build
/// reads as the node wrote it ([raw]): better a protocol word than nothing.
String orderStatusLabel(
  AppLocalizations l10n,
  OrderStatus status,
  String raw,
) => switch (status) {
  OrderStatus.pending => l10n.orderStatusPending,
  OrderStatus.waitingMakerBond => l10n.orderStatusWaitingMakerDeposit,
  OrderStatus.waitingTakerBond => l10n.orderStatusWaitingTakerDeposit,
  OrderStatus.waitingBuyerInvoice => l10n.orderStatusWaitingBuyerInvoice,
  OrderStatus.waitingPayment => l10n.orderStatusWaitingPayment,
  OrderStatus.inProgress => l10n.orderStatusInProgress,
  OrderStatus.active => l10n.orderStatusActive,
  OrderStatus.fiatSent => l10n.orderStatusFiatSent,
  OrderStatus.settledHoldInvoice => l10n.orderStatusSatsReleased,
  OrderStatus.success => l10n.orderStatusSuccess,
  OrderStatus.dispute => l10n.orderStatusDispute,
  OrderStatus.canceled => l10n.orderStatusCanceled,
  OrderStatus.cooperativelyCanceled => l10n.orderStatusCooperativelyCanceled,
  OrderStatus.canceledByAdmin => l10n.orderStatusRefundedBySolver,
  OrderStatus.settledByAdmin => l10n.orderStatusSettledBySolver,
  OrderStatus.completedByAdmin => l10n.orderStatusPaidBySolver,
  OrderStatus.expired => l10n.orderStatusExpired,
  OrderStatus.unknown => raw,
};

/// Whether the order buys or sells sats, in words; null when this build does
/// not know the kind.
String? orderKindLabel(AppLocalizations l10n, OrderKind kind) => switch (kind) {
  OrderKind.buy => l10n.detailOrderKindBuy,
  OrderKind.sell => l10n.detailOrderKindSell,
  OrderKind.unknown => null,
};
