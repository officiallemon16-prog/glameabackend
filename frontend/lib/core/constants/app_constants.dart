import 'package:flutter/foundation.dart';

/// Global app constants.
abstract final class AppConstants {
  AppConstants._();

  /// Backend base URL. Override at build/run time via --dart-define=API_BASE_URL.
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8080/api/v1',
  );

  static const String appName = 'Glamea';

  /// Pagination - cursor based.
  static const int pageSize = 20;

  /// Analytics event names (spec section 20).
  static const String eventAppOpened = 'app_opened';
  static const String eventOnboardingStarted = 'onboarding_started';
  static const String eventOnboardingCompleted = 'onboarding_completed';
  static const String eventSearchStarted = 'search_started';
  static const String eventSearchCompleted = 'search_completed';
  static const String eventLookViewed = 'look_viewed';
  static const String eventProfessionalViewed = 'professional_viewed';
  static const String eventServiceViewed = 'service_viewed';
  static const String eventSaved = 'saved';
  static const String eventBooking = 'booking';
  static const String eventPayment = 'payment';
  static const String eventMessage = 'message';
  static const String eventReview = 'review';

  /// Deep link scheme (spec section 20).
  static const String deepLinkScheme = 'glamea';

  /// Map backend error codes to friendly UI messages (spec section 18).
  static const Map<String, String> errorMessages = {
    'BOOKING_UNAVAILABLE': 'The selected time is no longer available.',
    'SLOT_LOCKED': 'That time was just booked. Please pick another.',
    'PAYMENT_FAILED': 'Payment could not be processed. Please try again.',
    'NETWORK_ERROR': 'You appear to be offline. Check your connection.',
    'not_your_booking': 'This booking does not belong to your account.',
    'invalid_amount_type': 'That payment option is not available.',
    'nothing_to_pay': 'There is nothing left to pay for this booking.',
    'insufficient_balance': 'You do not have enough balance to complete this payment.',
    'intent_not_found': 'We could not find that payment. Try again.',
    'not_your_intent': 'You do not have access to that payment.',
    'payment_provider_error': 'The payment provider could not be reached. Try again in a moment.',
    'cloudinary_not_configured': 'Media upload is temporarily unavailable.',
    'local_media_not_configured': 'Media upload is not available right now.',
    'file_required': 'Choose a photo first.',
    'file_too_large': 'That image is too large to upload.',
    'unsupported_file_type': 'Only JPG, PNG, WEBP, GIF, HEIC and HEIF images are supported.',
    'media_asset_required': 'Choose a photo first.',
    'media_not_found': 'That photo could not be found. Choose it again.',
  };

  static bool get isWeb => kIsWeb;
}
