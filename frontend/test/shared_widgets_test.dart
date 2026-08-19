import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:glamea/app/theme/app_colors.dart';
import 'package:glamea/app/theme/app_dimens.dart';
import 'package:glamea/shared/widgets/widgets.dart';

Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: Center(child: child)));

void main() {
  testWidgets('AppButton renders label and fills width', (tester) async {
    await tester.pumpWidget(wrap(AppButton(label: 'Book now', onPressed: () {})));
    expect(find.text('Book now'), findsOneWidget);
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    final width = tester.getSize(find.byType(AppButton));
    expect(width.width, tester.getSize(find.byType(Scaffold)).width);
    expect(button.onPressed, isNotNull);
  });

  testWidgets('AppButton respects disabled state', (tester) async {
    await tester.pumpWidget(wrap(const AppButton(label: 'Submit', onPressed: null)));
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);
  });

  testWidgets('AppTextField shows hint and validates empty', (tester) async {
    final formKey = GlobalKey<FormState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Form(
            key: formKey,
            child: Center(
              child: AppTextField(hintText: 'Email', validator: (v) => v == null || v.isEmpty ? 'Required' : null),
            ),
          ),
        ),
      ),
    );
    expect(find.text('Email'), findsOneWidget);
    formKey.currentState!.validate();
    await tester.pump();
    expect(find.text('Required'), findsOneWidget);
  });

  testWidgets('AppCard renders child with 16px radius', (tester) async {
    await tester.pumpWidget(wrap(const AppCard(child: Text('Card body'))));
    expect(find.text('Card body'), findsOneWidget);
    final container = tester.widget<Container>(find.byType(Container).first);
    final decoration = container.decoration as BoxDecoration;
    expect(decoration.borderRadius, BorderRadius.circular(AppDimens.cardRadiusMobile));
  });

  testWidgets('RatingStars renders 5 icons', (tester) async {
    await tester.pumpWidget(wrap(const RatingStars(rating: 4.5)));
    expect(find.byType(Icon), findsNWidgets(5));
  });

  testWidgets('StatusBadge uppercases label', (tester) async {
    await tester.pumpWidget(wrap(const StatusBadge(label: 'confirmed', color: AppColors.success)));
    expect(find.text('CONFIRMED'), findsOneWidget);
  });

  testWidgets('EmptyState shows action', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      wrap(EmptyState(title: 'No results', actionLabel: 'Clear', onAction: () => tapped = true)),
    );
    expect(find.text('No results'), findsOneWidget);
    await tester.tap(find.text('Clear'));
    expect(tapped, isTrue);
  });

  testWidgets('ErrorState shows retry', (tester) async {
    var retried = false;
    await tester.pumpWidget(wrap(ErrorState(message: 'Failed', onRetry: () => retried = true)));
    expect(find.text('Failed'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    expect(retried, isTrue);
  });

  testWidgets('AppAvatar renders initials fallback', (tester) async {
    await tester.pumpWidget(wrap(const AppAvatar(name: 'Amara Nwosu')));
    expect(find.text('AN'), findsOneWidget);
  });
}
