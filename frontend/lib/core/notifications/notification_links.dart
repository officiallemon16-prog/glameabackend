import '../constants/app_constants.dart';

/// Maps a push notification data payload to a deep link the router can
/// consume. Payloads are flat string maps, e.g.
///   {"notification_type": "booking", "booking_id": "b-1"} -> glamea://bookings/b-1
/// Unknown payloads fall back to the notifications screen.
String? deepLinkFromPushData(Map<String, String> data) {
  final bookingId = data['booking_id'];
  final type = data['notification_type'];

  // Re-engagement digests/inactive nudges surface new looks: open Discover.
  if (type == 'digest' || type == 'inactive') {
    return '${AppConstants.deepLinkScheme}://discover';
  }

  if (type == 'message' && bookingId != null && bookingId.isNotEmpty) {
    return '${AppConstants.deepLinkScheme}://chat/$bookingId';
  }
  if (bookingId != null && bookingId.isNotEmpty) {
    return '${AppConstants.deepLinkScheme}://bookings/$bookingId';
  }
  final disputeId = data['dispute_id'];
  if (disputeId != null && disputeId.isNotEmpty) {
    return '${AppConstants.deepLinkScheme}://disputes/$disputeId';
  }
  return '${AppConstants.deepLinkScheme}://notifications';
}
