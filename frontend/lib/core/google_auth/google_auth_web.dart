import 'dart:async';
import 'dart:convert';

import 'dart:js_util' as js_util;
import 'dart:js' as js;

class GoogleAuthWeb {
  /// Opens a Google OAuth popup and returns the ID token.
  static Future<String?> signIn() async {
    try {
      final result = await js_util.promiseToFuture<String?>(
        js_util.callMethod(js.context, 'openGoogleOAuth', <Object>[]),
      );
      return result;
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic>? decodeJwtPayload(String jwt) {
    try {
      final parts = jwt.split('.');
      if (parts.length != 3) return null;
      var payload = parts[1];
      while (payload.length % 4 != 0) {
        payload += '=';
      }
      payload = payload.replaceAll('-', '+').replaceAll('_', '/');
      final decoded = utf8.decode(base64.decode(payload));
      return jsonDecode(decoded) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }
}
