import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:erlang_ai_vision_app/features/chat/ai_agent_chat_screen.dart';
import 'package:erlang_ai_vision_app/features/chat/chat_markdown.dart';

void main() {
  testWidgets('waiting indicator explains that Erlang is working', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: AiAgentWaitingIndicator())),
    );

    expect(find.text('Erlang is thinking...'), findsOneWidget);
  });

  test('normalizes display math delimiters for the renderer', () {
    expect(
      normalizeAssistantMarkdown(r'Area \[x^2 + y^2\]'),
      contains(r'$$x^2 + y^2$$'),
    );
  });
}
