import 'package:intl/intl.dart';

/// Presentation helpers for money, durations and counts.
abstract final class Formatters {
  static String currencySymbol(String currency) {
    switch (currency.toUpperCase()) {
      case 'NGN':
        return '\u20A6';
      case 'USD':
        return r'$';
      case 'GBP':
        return '\u00A3';
      case 'EUR':
        return '\u20AC';
      default:
        return '$currency ';
    }
  }

  /// e.g. 1000.0, 'NGN' -> "₦1,000"
  static String money(double amount, String currency) {
    final decimals = amount % 1 == 0 ? 0 : 2;
    return NumberFormat.currency(
      locale: 'en',
      symbol: currencySymbol(currency),
      decimalDigits: decimals,
    ).format(amount);
  }

  /// e.g. 90 -> "1 hr 30 min", 45 -> "45 min"
  static String duration(int minutes) {
    if (minutes < 60) return '$minutes min';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return m == 0 ? '$h hr' : '$h hr $m min';
  }

  /// e.g. 1200 -> "1.2k"
  static String compact(int value) {
    if (value >= 1000) {
      final k = value / 1000;
      return '${k.toStringAsFixed(k >= 100 ? 0 : 1)}k';
    }
    return '$value';
  }

  /// e.g. 2026-08-13 -> "13 Aug 2026" (empty when null).
  static String date(DateTime? value) {
    if (value == null) return '';
    return DateFormat('d MMM yyyy').format(value.toLocal());
  }

  /// Relative label such as "2 Aug", "3w ago" or "Today".
  static String relativeDate(DateTime value) {
    final now = DateTime.now();
    final local = value.toLocal();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(local.year, local.month, local.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    if (diff < 7) return '${local.day} ${DateFormat('MMM').format(local)}';
    if (diff < 365) return '${local.day} ${DateFormat('MMM').format(local)}';
    return DateFormat('d MMM yyyy').format(local);
  }

  /// e.g. 09:30 -> "9:30 AM".
  static String time(DateTime value) {
    return DateFormat('h:mm a').format(value.toLocal()).replaceFirst(' ', ' ');
  }

  /// Day label for date strips, e.g. "Thu, 14".
  static String dayShort(DateTime value) {
    return DateFormat('EEE, d').format(value.toLocal());
  }

  /// Compact chat timestamp: time today, weekday this week, else date.
  static String relativeTime(DateTime value) {
    final now = DateTime.now();
    final local = value.toLocal();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(local.year, local.month, local.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return time(local);
    if (diff == 1) return 'Yesterday';
    if (diff < 7) return DateFormat('EEE').format(local);
    return DateFormat('d MMM').format(local);
  }

  /// Date key sent to the availability API: "2026-08-14".
  static String apiDate(DateTime value) {
    return DateFormat('yyyy-MM-dd').format(value.toLocal());
  }
}
