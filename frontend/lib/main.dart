import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Surface uncaught framework errors instead of a blank/white screen.
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    // In release the default is a gray screen; we still log for diagnostics.
    debugPrint('FlutterError: ${details.exception}\\n${details.stack}');
  };

  // Catch async errors outside the Flutter framework (timers, microtasks).
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('Uncaught async error: $error\\n$stack');
    return true;
  };

  ErrorWidget.builder = (details) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              const Text(
                'Something went wrong',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                details.exception.toString(),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: Colors.grey),
              ),
            ],
          ),
        ),
      ),
    );
  };

  runApp(const ProviderScope(child: GlameaApp()));
}
