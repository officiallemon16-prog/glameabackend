import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glamea/app/app.dart';
import 'package:glamea/core/errors/app_exception.dart';
import 'package:glamea/features/auth/auth_controller.dart';
import 'package:glamea/features/auth/data/auth_api.dart';
import 'package:glamea/features/auth/verify_email_controller.dart';
import 'package:glamea/features/profile/data/profile_api.dart';
import 'package:glamea/models/user.dart';
import 'package:shared_preferences/shared_preferences.dart';

const unverifiedUser = User(
  id: 'u-1',
  email: 'amina@glamea.test',
  firstName: 'Amina',
  lastName: 'Bello',
  role: 'CUSTOMER',
  status: 'ACTIVE',
  emailVerified: false,
  phoneVerified: true,
);

const verifiedUser = User(
  id: 'u-1',
  email: 'amina@glamea.test',
  firstName: 'Amina',
  lastName: 'Bello',
  role: 'CUSTOMER',
  status: 'ACTIVE',
  emailVerified: true,
  phoneVerified: true,
);

class FakeAuthApi extends AuthApi {
  FakeAuthApi({this.failSend = false, this.failVerify = false}) : super(Dio());

  final bool failSend;
  final bool failVerify;
  int sendCalls = 0;
  String? lastEmail;
  String? lastCode;
  void Function()? onVerified;

  @override
  Future<void> sendEmailCode(String email) async {
    sendCalls += 1;
    lastEmail = email;
    if (failSend) {
      throw const ApiException('Could not send the code.',
          code: 'server_error', statusCode: 500);
    }
  }

  @override
  Future<void> verifyEmail(String email, String code) async {
    lastEmail = email;
    lastCode = code;
    if (failVerify) {
      throw mapAuthError(
        DioException(
          requestOptions: RequestOptions(path: '/auth/verify-email'),
          response: Response(
            requestOptions: RequestOptions(path: '/auth/verify-email'),
            statusCode: 400,
            data: {
              'error': {
                'code': 'invalid_or_expired_code',
                'message': 'code is invalid or has expired',
              },
            },
          ),
          type: DioExceptionType.badResponse,
        ),
      );
    }
    onVerified?.call();
  }
}

class FakeProfileApi extends ProfileApi {
  FakeProfileApi({this.verified = false}) : super(Dio());

  bool verified;

  @override
  Future<User> fetchMe() async => verified ? verifiedUser : unverifiedUser;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('VerifyEmailController', () {
    test('request sends a code for the email', () async {
      final api = FakeAuthApi();
      final container = ProviderContainer(
        overrides: [authApiProvider.overrideWithValue(api)],
      );
      addTearDown(container.dispose);

      final ok = await container
          .read(verifyEmailControllerProvider.notifier)
          .request('amina@glamea.test');

      expect(ok, isTrue);
      expect(api.sendCalls, 1);
      expect(api.lastEmail, 'amina@glamea.test');
      expect(
        container.read(verifyEmailControllerProvider).status,
        VerifyEmailStatus.idle,
      );
    });

    test('request failure surfaces the error', () async {
      final api = FakeAuthApi(failSend: true);
      final container = ProviderContainer(
        overrides: [authApiProvider.overrideWithValue(api)],
      );
      addTearDown(container.dispose);

      final ok = await container
          .read(verifyEmailControllerProvider.notifier)
          .request('amina@glamea.test');

      expect(ok, isFalse);
      expect(container.read(verifyEmailControllerProvider).error,
          'Could not send the code.');
    });

    test('verify success marks verified and refreshes the session user',
        () async {
      SharedPreferences.setMockInitialValues({
        'access_token': 'jwt',
        'current_user': jsonEncode(unverifiedUser.toJson()),
      });
      final api = FakeAuthApi();
      final profileApi = FakeProfileApi();
      api.onVerified = () => profileApi.verified = true;
      final container = ProviderContainer(
        overrides: [
          authApiProvider.overrideWithValue(api),
          profileApiProvider.overrideWithValue(profileApi),
        ],
      );
      addTearDown(container.dispose);
      container.read(authControllerProvider);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final ok = await container
          .read(verifyEmailControllerProvider.notifier)
          .verify('amina@glamea.test', '123456');

      expect(ok, isTrue);
      expect(api.lastCode, '123456');
      expect(
        container.read(verifyEmailControllerProvider).status,
        VerifyEmailStatus.verified,
      );
      expect(container.read(authControllerProvider).user?.emailVerified, isTrue);
    });

    test('verify failure surfaces the error', () async {
      final api = FakeAuthApi(failVerify: true);
      final container = ProviderContainer(
        overrides: [authApiProvider.overrideWithValue(api)],
      );
      addTearDown(container.dispose);

      final ok = await container
          .read(verifyEmailControllerProvider.notifier)
          .verify('amina@glamea.test', '000000');

      expect(ok, isFalse);
      final state = container.read(verifyEmailControllerProvider);
      expect(state.status, VerifyEmailStatus.idle);
      expect(state.error, 'code is invalid or has expired');
    });
  });

  group('Verify email screen', () {
    testWidgets('unverified email shows the row and completes verification',
        (tester) async {
      SharedPreferences.setMockInitialValues({
        'access_token': 'jwt',
        'current_user': jsonEncode(unverifiedUser.toJson()),
      });
      final authApi = FakeAuthApi();
      final profileApi = FakeProfileApi();
      authApi.onVerified = () => profileApi.verified = true;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authApiProvider.overrideWithValue(authApi),
            profileApiProvider.overrideWithValue(profileApi),
          ],
          child: const GlameaApp(),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.person_outline_rounded));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Verify email'));
      expect(find.text('Verify email'), findsOneWidget);

      await tester.tap(find.text('Verify email'));
      await tester.pumpAndSettle();

      expect(find.text('Verify your email'), findsOneWidget);
      expect(find.textContaining('amina@glamea.test'), findsWidgets);

      await tester.enterText(find.byType(TextField).last, '123456');
      await tester.pump();
      await tester.tap(find.text('Verify'));
      await tester.pumpAndSettle();

      expect(find.text('Email verified'), findsOneWidget);
      final ctx = tester.element(find.text('Email verified'));
      final container = ProviderScope.containerOf(ctx);
      expect(container.read(authControllerProvider).user?.emailVerified, isTrue);

      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
    });

    testWidgets('no verify row when the email is already verified',
        (tester) async {
      SharedPreferences.setMockInitialValues({
        'access_token': 'jwt',
        'current_user': jsonEncode(verifiedUser.toJson()),
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            profileApiProvider.overrideWithValue(FakeProfileApi(verified: true)),
          ],
          child: const GlameaApp(),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.person_outline_rounded));
      await tester.pumpAndSettle();

      expect(find.text('Verify email'), findsNothing);
    });
  });
}
