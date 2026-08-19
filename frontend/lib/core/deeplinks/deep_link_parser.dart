import '../../app/router/app_router.dart';
import '../constants/app_constants.dart';

/// Maps an inbound URI (custom scheme or HTTPS web link) to a router path.
///
/// Accepts both host-included and host-less forms, e.g.:
///   glamea://open/professionals/abc
///   glamea:///professional/abc
///   https://glamea.app/bookings/abc/chat
///
/// Returns null for unsupported or malformed links.
String? deepLinkPath(String raw) {
  final uri = Uri.tryParse(raw);
  if (uri == null) return null;
  if (uri.scheme != AppConstants.deepLinkScheme && uri.scheme != 'https' && uri.scheme != 'http') {
    return null;
  }

  final segments = <String>[];
  // A host like "open" or "glamea.app" is just a namespace, not a route
  // segment. "glamea://professionals/x" (host=professionals) keeps the host.
  const namespaces = {'open', 'app', 'glamea', 'glamea.app', 'www.glamea.app'};
  if (uri.host.isNotEmpty && !namespaces.contains(uri.host)) {
    segments.add(uri.host);
  }
  segments.addAll(uri.pathSegments.where((s) => s.isNotEmpty));

  return _match(segments);
}

String? _match(List<String> segments) {
  if (segments.isEmpty) return null;

  switch (segments.first) {
    case 'professional':
    case 'professionals':
      if (segments.length >= 2) return AppRoutes.professionalFor(segments[1]);
      return null;

    case 'booking':
    case 'bookings':
      if (segments.length == 1) return AppRoutes.bookingList;
      if (segments.length >= 2) {
        final id = segments[1];
        final sub = segments.length >= 3 ? segments[2] : null;
        switch (sub) {
          case 'chat':
            return AppRoutes.chatFor(id);
          case 'pay':
            return AppRoutes.payFor(id);
          case 'dispute':
            return AppRoutes.raiseDisputeFor(id);
          default:
            return AppRoutes.bookingFor(id);
        }
      }
      return null;

    case 'chat':
      if (segments.length >= 2) return AppRoutes.chatFor(segments[1]);
      return null;

    case 'wallet':
      return AppRoutes.wallet;

    case 'notifications':
      return AppRoutes.notifications;

    case 'discover':
      return AppRoutes.discover;

    case 'favorites':
      return AppRoutes.favorites;

    case 'look':
    case 'looks':
      if (segments.length >= 2) return AppRoutes.lookFor(segments[1]);
      return null;

    case 'category':
    case 'categories':
      if (segments.length >= 2) return AppRoutes.categoryFor(segments[1]);
      return null;

    case 'disputes':
      if (segments.length >= 2) return AppRoutes.disputeDetailFor(segments[1]);
      return AppRoutes.disputes;

    case 'reviews':
      return AppRoutes.myReviews;

    default:
      return null;
  }
}
