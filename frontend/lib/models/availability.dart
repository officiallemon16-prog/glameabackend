/// Weekly availability window (backend `availability.Window`).
class AvailabilityWindow {
  const AvailabilityWindow({
    required this.id,
    required this.professionalId,
    required this.dayOfWeek,
    required this.startMinutes,
    required this.endMinutes,
    this.isActive = true,
  });

  factory AvailabilityWindow.fromJson(Map<String, dynamic> json) {
    return AvailabilityWindow(
      id: json['id'] as String? ?? '',
      professionalId: json['professional_id'] as String? ?? '',
      dayOfWeek: (json['day_of_week'] as num?)?.toInt() ?? 0,
      startMinutes: (json['start_minutes'] as num?)?.toInt() ?? 0,
      endMinutes: (json['end_minutes'] as num?)?.toInt() ?? 0,
      isActive: json['is_active'] as bool? ?? true,
    );
  }

  final String id;
  final String professionalId;
  final int dayOfWeek;
  final int startMinutes;
  final int endMinutes;
  final bool isActive;

  String get startLabel => _minutesLabel(startMinutes);
  String get endLabel => _minutesLabel(endMinutes);
}

/// One-off availability exception (backend `availability.Exception`).
class AvailabilityException {
  const AvailabilityException({
    required this.id,
    required this.professionalId,
    required this.date,
    this.startMinutes,
    this.endMinutes,
    this.isAvailable = true,
    this.note = '',
  });

  factory AvailabilityException.fromJson(Map<String, dynamic> json) {
    return AvailabilityException(
      id: json['id'] as String? ?? '',
      professionalId: json['professional_id'] as String? ?? '',
      date: json['date'] as String? ?? '',
      startMinutes: (json['start_minutes'] as num?)?.toInt(),
      endMinutes: (json['end_minutes'] as num?)?.toInt(),
      isAvailable: json['is_available'] as bool? ?? true,
      note: json['note'] as String? ?? '',
    );
  }

  final String id;
  final String professionalId;
  final String date;
  final int? startMinutes;
  final int? endMinutes;
  final bool isAvailable;
  final String note;

  bool get isBlock => !isAvailable;
}

/// Minutes-of-day 0-1439 -> "9:00 AM".
String _minutesLabel(int minutes) {
  final total = minutes % 1440;
  final h24 = total ~/ 60;
  final m = total % 60;
  final period = h24 >= 12 ? 'PM' : 'AM';
  final h = h24 % 12 == 0 ? 12 : h24 % 12;
  final mm = m == 0 ? '' : ':${m.toString().padLeft(2, '0')}';
  return '$h$mm $period';
}

/// Day of week label for 0=Sunday ... 6=Saturday (Go convention).
String dayOfWeekLabel(int day) {
  const days = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
  return days[day.clamp(0, 6)];
}
