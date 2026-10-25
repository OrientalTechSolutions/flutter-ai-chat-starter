import 'package:ai_chat_starter/app.dart';
import 'package:ai_chat_starter/features/chat/data/demo_chat_repository.dart';
import 'package:ai_chat_starter/features/chat/presentation/widgets/empty_state.dart';
import 'package:ai_chat_starter/features/chat/presentation/widgets/typing_indicator.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Short, fixed delays keep the test fast. The demo is timer driven, so the
  // tests advance the clock with pump(duration) instead of pumpAndSettle,
  // which would never settle while the typing dots animate.
  const demo = DemoChatRepository(
    thinkingDelay: Duration(milliseconds: 100),
    wordDelay: Duration(milliseconds: 10),
  );
  const enoughTimeForAReply = Duration(seconds: 5);
  const dialogTransition = Duration(milliseconds: 500);

  Future<void> pumpApp(WidgetTester tester) {
    return tester.pumpWidget(
      ProviderScope(
        overrides: [demoChatRepositoryProvider.overrideWithValue(demo)],
        child: const ChatApp(),
      ),
    );
  }

  testWidgets('streams a demo reply to a suggested prompt', (tester) async {
    await pumpApp(tester);
    final prompt = EmptyState.suggestions.first;
    expect(find.text('How can I help?'), findsOneWidget);

    await tester.tap(find.text(prompt));
    await tester.pump();

    expect(find.text(prompt), findsOneWidget);
    expect(find.byType(TypingIndicator), findsOneWidget);
    expect(find.byTooltip('Stop generating'), findsOneWidget);

    await tester.pump(enoughTimeForAReply);

    // The long reply can push the prompt above the viewport, so only the
    // reply is checked here.
    expect(find.byType(TypingIndicator), findsNothing);
    expect(find.text(DemoChatRepository.replyFor(prompt)), findsOneWidget);
    expect(find.byTooltip('Copy'), findsOneWidget);
    expect(find.byTooltip('Send message'), findsOneWidget);
  });

  testWidgets('sends the typed message with Enter', (tester) async {
    await pumpApp(tester);

    await tester.enterText(find.byType(TextField), 'Hello');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(find.text('Hello'), findsOneWidget);
    expect(find.byType(TypingIndicator), findsOneWidget);

    await tester.pump(enoughTimeForAReply);

    expect(find.text(DemoChatRepository.replyFor('Hello')), findsOneWidget);
  });

  testWidgets('clear chat asks for confirmation first', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text(EmptyState.suggestions.first));
    await tester.pump(enoughTimeForAReply);

    await tester.tap(find.byTooltip('Clear chat'));
    await tester.pump(dialogTransition);
    await tester.tap(find.text('Cancel'));
    await tester.pump(dialogTransition);

    expect(find.text('How can I help?'), findsNothing);

    await tester.tap(find.byTooltip('Clear chat'));
    await tester.pump(dialogTransition);
    await tester.tap(find.text('Clear'));
    await tester.pump(dialogTransition);

    expect(find.text('How can I help?'), findsOneWidget);
  });
}
