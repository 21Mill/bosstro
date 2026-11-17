import 'package:intl/intl.dart';

/// A Unix time in seconds as [locale] writes a date and a time, in the
/// phone's time zone ("Nov 14, 2023 22:13"). The one format a moment is
/// shown in, on every screen (DS-L10N-5).
String formatDateTime(int seconds, String locale) => DateFormat.yMMMd(
  locale,
).add_Hm().format(DateTime.fromMillisecondsSinceEpoch(seconds * 1000));
