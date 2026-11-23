import 'package:intl/intl.dart';

/// Russian date/time formatting helpers with explicit timezone display.
abstract final class EfDateFmt {
  static String shortDateTime(DateTime dt, {String? timezone}) {
    final local = dt.toLocal();
    final formatted = DateFormat('d MMM, HH:mm', 'ru').format(local);
    return timezone != null && timezone.isNotEmpty
        ? '$formatted ($timezone)'
        : formatted;
  }

  static String fullDateTime(DateTime dt, {String? timezone}) {
    final local = dt.toLocal();
    final formatted = DateFormat('d MMMM yyyy, HH:mm', 'ru').format(local);
    return timezone != null && timezone.isNotEmpty
        ? '$formatted ($timezone)'
        : formatted;
  }

  static String dateTimeSeconds(DateTime dt) {
    return DateFormat('d MMM, HH:mm:ss', 'ru').format(dt.toLocal());
  }

  static String timeOnly(DateTime dt) {
    return DateFormat('HH:mm:ss', 'ru').format(dt.toLocal());
  }

  static String dayBadge(DateTime dt) {
    return DateFormat('d', 'ru').format(dt.toLocal());
  }

  static String monthBadge(DateTime dt) {
    return DateFormat('MMM', 'ru').format(dt.toLocal()).toUpperCase();
  }
}
