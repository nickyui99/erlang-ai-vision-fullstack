// Assistant chat bubbles keep readable Markdown formatting without carrying a
// large math-font package in the landing-page bundle.
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => MaterialApp(
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

void main() {
  testWidgets('markdown bold renders styled, not as literal asterisks', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(const MarkdownBody(data: 'This is **important** text.')),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('**'), findsNothing);
    expect(
      find.byWidgetPredicate(
        (w) => w is RichText && w.text.toPlainText().contains('important'),
      ),
      findsWidgets,
    );
  });

  testWidgets('markdown table renders as a table widget, not pipes', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const MarkdownBody(
          data: '| Camera | Status |\n|---|---|\n| Front Door | Online |',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('|---|'), findsNothing);
    expect(find.byType(Table), findsWidgets);
  });
}
