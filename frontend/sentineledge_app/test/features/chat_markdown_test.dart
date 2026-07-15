// Assistant chat bubbles render LLM output (Markdown + LaTeX) instead of
// showing raw source text — the regression here was a plain Text() widget
// displaying "**bold**" and "$$x^2$$" literally.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

Widget _wrap(Widget child) =>
    MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child)));

void main() {
  testWidgets('markdown bold renders styled, not as literal asterisks',
      (tester) async {
    await tester.pumpWidget(_wrap(
      const GptMarkdown('This is **important** text.',
          useDollarSignsForLatex: true),
    ));
    await tester.pumpAndSettle();

    // The raw markdown source must not be visible anywhere.
    expect(find.textContaining('**'), findsNothing);
    // The content itself is still present (inside a rich text span).
    expect(
      find.byWidgetPredicate(
        (w) => w is RichText && w.text.toPlainText().contains('important'),
      ),
      findsWidgets,
    );
  });

  testWidgets('LaTeX with dollar delimiters renders as math, not raw source',
      (tester) async {
    await tester.pumpWidget(_wrap(
      const GptMarkdown(r'The area is $$A = \pi r^2$$ for a circle.',
          useDollarSignsForLatex: true),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining(r'$$'), findsNothing);
    expect(find.textContaining(r'\pi'), findsNothing);
  });

  testWidgets(r'LaTeX with \( \) delimiters renders as math, not raw source',
      (tester) async {
    await tester.pumpWidget(_wrap(
      const GptMarkdown(r'Euler: \( e^{i\pi} + 1 = 0 \) famously.',
          useDollarSignsForLatex: true),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining(r'\('), findsNothing);
    expect(find.textContaining(r'e^{i'), findsNothing);
  });

  testWidgets('markdown table renders as a table widget, not pipes',
      (tester) async {
    await tester.pumpWidget(_wrap(
      const GptMarkdown(
        '| Camera | Status |\n|---|---|\n| Front Door | Online |',
        useDollarSignsForLatex: true,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('|---|'), findsNothing);
    expect(find.byType(Table), findsWidgets);
  });
}
