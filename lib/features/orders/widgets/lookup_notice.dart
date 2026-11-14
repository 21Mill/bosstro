import 'package:flutter/material.dart';

import 'package:bosstro/core/app_theme.dart';
import 'package:bosstro/shared/widgets/order_data_card.dart';

/// How a lookup that brought no order ended, under the form: an icon, a
/// title and the reason, on a card (the shape of `NotSolverBanner`). The
/// icon is red only for an error ([error]); the words say it all
/// (DS-COL-10).
class LookupNotice extends StatelessWidget {
  const LookupNotice({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.error = false,
  });

  final IconData icon;
  final String title;
  final String body;

  /// Something went wrong (the request did not leave, the node refused it),
  /// rather than an answer that is simply "no".
  final bool error;

  @override
  Widget build(BuildContext context) {
    final pal = ShellPalette.of(context);
    return SurfaceCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(
            child: Icon(
              icon,
              size: 20,
              color: error ? pal.danger : pal.textTertiary,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: pal.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.45,
                    color: pal.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
