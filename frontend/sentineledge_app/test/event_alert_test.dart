import 'package:erlang_ai_vision_app/app/app_messenger.dart';
import 'package:erlang_ai_vision_app/shared/event_alert.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('recognizes verified events from either backend field', () {
    expect(isPositiveVerification({'verified': true}), isTrue);
    expect(isPositiveVerification({'verified': 'TRUE'}), isTrue);
    expect(isPositiveVerification({'status': 'verified'}), isTrue);
    expect(
      isPositiveVerification({'verified': false, 'status': 'false_positive'}),
      isFalse,
    );
  });
  testWidgets('event alert remains visible and supports a View action', (
    tester,
  ) async {
    final messengerKey = appScaffoldMessengerKey;
    var viewed = false;

    await tester.pumpWidget(
      MaterialApp(
        scaffoldMessengerKey: messengerKey,
        home: const Scaffold(body: SizedBox()),
      ),
    );

    showEventAlert(
      null,
      title: 'New high detection',
      body: 'Person detected at the front door.',
      onView: () => viewed = true,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('New high detection'), findsOneWidget);
    expect(find.text('Person detected at the front door.'), findsOneWidget);
    expect(find.text('View'), findsOneWidget);

    await tester.tap(find.text('View'));
    expect(viewed, isTrue);
  });
}
