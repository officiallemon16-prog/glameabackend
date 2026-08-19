/// An available time slot for a professional on a given day
/// (backend `bookings.Slot`).
class AvailabilitySlot {
  const AvailabilitySlot({required this.start, required this.end});

  factory AvailabilitySlot.fromJson(Map<String, dynamic> json) {
    return AvailabilitySlot(
      start: DateTime.tryParse(json['start'] as String? ?? '') ?? DateTime.now(),
      end: DateTime.tryParse(json['end'] as String? ?? '') ?? DateTime.now(),
    );
  }

  final DateTime start;
  final DateTime end;
}
