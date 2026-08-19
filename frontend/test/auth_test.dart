import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glamea/app/app.dart';
import 'package:glamea/core/errors/app_exception.dart';
import 'package:glamea/features/auth/auth_controller.dart';
import 'package:glamea/features/auth/data/auth_api.dart';
import 'package:glamea/models/user.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> pumpApp(WidgetTester tester) async {
  await tester.pumpWidget(const ProviderScope(child: GlameaApp()));
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pumpAndSettle();
}

/// Auth API that always rejects login with invalid credentials.
class FailingAuthApi extends AuthApi {
  FailingAuthApi() : super(Dio());

  @override
  Future<AuthResult> login(String identifier, String password) {
    throw mapAuthError(
      DioException(
        requestOptions: RequestOptions(path: '/auth/login'),
        response: Response(
          requestOptions: RequestOptions(path: '/auth/login'),
          statusCode: 401,
          data: {
            'error': {
              'code': 'invalid_credentials',
              'message': 'invalid email/phone or password',
            },
          },
        ),
        type: DioExceptionType.badResponse,
      ),
    );
  }
}

String cachedUserJson() => jsonEncode(const User(
      id: 'user-1',
      email: 'test@glamea.test',
      firstName: 'Amina',
      lastName: 'Bello',
      role: 'CUSTOMER',
      status: 'ACTIVE',
      emailVerified: true,
      phoneVerified: true,
    ).toJson());

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('redirects from splash to onboarding when logged out',
      (tester) async {
    await pumpApp(tester);
    expect(find.textContaining('Discover your look'), findsOneWidget);
  });

  testWidgets('redirects to home when a session is cached', (tester) async {
    SharedPreferences.setMockInitialValues({
      'access_token': 'jwt',
      'current_user': cachedUserJson(),
    });
    await pumpApp(tester);
    expect(find.text('Home'), findsWidgets);
    expect(find.text('Discover'), findsWidgets);
  });

  testWidgets('onboarding has create account and login links',
      (tester) async {
    await pumpApp(tester);
    expect(find.textContaining('Discover your look'), findsOneWidget);
    expect(find.text('Create account'), findsOneWidget);
    expect(find.text('Log in'), findsOneWidget);
    await tester.tap(find.text('Log in'));
    await tester.pumpAndSettle();
    expect(find.text('Welcome back'), findsOneWidget);
  });

  testWidgets('register screen validates required fields', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const ProviderScope(child: GlameaApp()));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();
    expect(find.text('Create your account'), findsOneWidget);

    await tester.tap(find.text('Create account'));
    await tester.pump();
    expect(find.text('Required'), findsNWidgets(2));
    expect(find.text('Enter your email'), findsOneWidget);
    expect(find.text('Password must be at least 8 characters'), findsOneWidget);
  });

  testWidgets('login screen navigates from onboarding and shows validation',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const ProviderScope(child: GlameaApp()));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Log in'));
    await tester.pumpAndSettle();
    expect(find.text('Welcome back'), findsOneWidget);

    await tester.tap(find.text('Log in'));
    await tester.pump();
    expect(find.text('Enter your email or phone'), findsOneWidget);
    expect(find.text('Enter your password'), findsOneWidget);
  });

  test('mapAuthError surfaces the backend message for a 401', () {
    final error = mapAuthError(
      DioException(
        requestOptions: RequestOptions(path: '/auth/login'),
        response: Response(
          requestOptions: RequestOptions(path: '/auth/login'),
          statusCode: 401,
          data: {
            'error': {
              'code': 'invalid_credentials',
              'message': 'invalid email/phone or password',
            },
          },
        ),
        type: DioExceptionType.badResponse,
      ),
    );

    expect(error, isA<ApiException>());
    expect(error.message, 'invalid email/phone or password');
    expect(error.code, 'invalid_credentials');
  });

  test('login failure exits authenticating and shows the error', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer(
      overrides: [authApiProvider.overrideWithValue(FailingAuthApi())],
    );
    addTearDown(container.dispose);

    expect(
        container.read(authControllerProvider).status, AuthStatus.initializing);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    await container.read(authControllerProvider.notifier).login(
          'test@glamea.test',
          'wrong-password',
        );

    final state = container.read(authControllerProvider);
    expect(state.status, AuthStatus.unauthenticated);
    expect(state.error, 'invalid email/phone or password');
  });

  testWidgets('wrong password shows the error banner and stops loading',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authApiProvider.overrideWithValue(FailingAuthApi())],
        child: const GlameaApp(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Log in'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email or phone number'),
      'test@glamea.test',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Password'),
      'wrong-password',
    );
    await tester.tap(find.text('Log in'));
    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('invalid email/phone or password'), findsOneWidget);
  });
}
