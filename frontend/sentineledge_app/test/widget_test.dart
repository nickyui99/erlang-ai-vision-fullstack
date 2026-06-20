import 'package:flutter_test/flutter_test.dart';
import 'package:sentineledge_app/main.dart';

void main() {
  testWidgets('shows sign in action', (WidgetTester tester) async {
    await tester.pumpWidget(const SentinelEdgeApp());

    expect(find.text('SentinelEdge'), findsOneWidget);
    expect(find.text('Sign in with Google'), findsOneWidget);
  });
}
