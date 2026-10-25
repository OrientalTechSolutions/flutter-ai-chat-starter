import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ai_provider.dart';
import 'chat_message.dart';
import 'chat_repository.dart';

final demoChatRepositoryProvider = Provider<ChatRepository>(
  (ref) => const DemoChatRepository(),
);

/// Streams canned replies on device, so the app runs with no server and no
/// API keys. Useful for a first run, UI work and screenshots.
class DemoChatRepository implements ChatRepository {
  const DemoChatRepository({
    this.thinkingDelay = const Duration(milliseconds: 600),
    this.wordDelay = const Duration(milliseconds: 40),
  });

  /// Pause before the first word, like a real model getting started.
  final Duration thinkingDelay;

  /// Pause between words. Tests shorten both delays to stay fast.
  final Duration wordDelay;

  static final _words = RegExp(r'\S+\s*');

  @override
  Stream<String> streamReply(
    AiProvider provider,
    List<ChatMessage> history,
  ) async* {
    await Future<void>.delayed(thinkingDelay);

    final reply = replyFor(history.last.text);
    for (final word in _words.allMatches(reply)) {
      await Future<void>.delayed(wordDelay);
      yield word[0]!;
    }
  }

  /// Picks the canned reply whose keywords appear in [prompt].
  static String replyFor(String prompt) {
    final words = prompt.toLowerCase().split(RegExp('[^a-z0-9]+')).toSet();
    for (final reply in _replies) {
      if (reply.keywords.any(words.contains)) return reply.text;
    }
    return _fallbackReply;
  }
}

const _replies = <({List<String> keywords, String text})>[
  (
    keywords: ['key', 'keys', 'secret', 'secure', 'security', 'safe'],
    text:
        'The app never holds an API key. It sends the conversation to a '
        'small Dart server in the /server folder, and that server adds the '
        'key when it calls OpenAI, Google or Anthropic. The reply streams '
        'back to the app as plain text events.\n\n'
        "That means a key can't be pulled out of the app binary or spotted "
        "in the browser's network tab. You can also rotate keys, switch "
        'models or add rate limits without shipping a new app release.',
  ),
  (
    keywords: ['riverpod', 'state', 'provider', 'providers'],
    text:
        'Riverpod is a state management library that keeps app state '
        'outside the widget tree. You declare providers, small objects that '
        'create and hold a piece of state, and widgets watch the ones they '
        'need. When a value changes, only the widgets that depend on it '
        'rebuild. Compared with passing data down by hand, you get '
        'compile-time safety, no dependency on BuildContext for reading '
        'state, and easy testing, because any provider can be overridden in '
        'a test. This app uses a Notifier to manage the conversation, which '
        'keeps send, stop and retry simple to test.',
  ),
  (
    keywords: ['idea', 'ideas', 'feature', 'features'],
    text:
        'Three AI features that fit a food delivery app well:\n\n'
        "1. Smart reorder: suggest a customer's usual order around the time "
        'they usually eat, with one tap to confirm.\n'
        '2. Natural language search: turn "something spicy and cheap near '
        'me" into cuisine, price and distance filters.\n'
        '3. Honest delivery times: use order history, weather and traffic '
        'to predict arrival and warn early about delays.\n\n'
        'Each one can start as a single model call behind your own API and '
        'grow from there.',
  ),
  (
    keywords: ['welcome', 'fitness', 'onboarding'],
    text:
        "Here's a short welcome message you could use:\n\n"
        "Welcome aboard! Whether you're taking your first steps or "
        "training for a new personal best, we're here to help. Set a goal, "
        "log your first workout and we'll build a plan around your week. "
        "Small steps every day add up. Let's get moving.",
  ),
  (
    keywords: ['flutter', 'dart', 'widget', 'widgets'],
    text:
        'Flutter builds iOS, Android, web and desktop apps from one Dart '
        'codebase. Everything on screen is a widget, and widgets are cheap '
        'to rebuild, so the UI is simply a function of state. Hot reload '
        'keeps iteration fast, and because Flutter draws every pixel itself, '
        'the app looks and behaves the same on each platform.',
  ),
  (
    keywords: ['hello', 'hi', 'hey', 'salam'],
    text:
        'Hi! This is the offline demo of AI Chat Starter. Try one of the '
        'suggested prompts, or switch to ChatGPT, Gemini or Claude once the '
        'proxy server is running.',
  ),
];

const _fallbackReply =
    'This is the offline demo, so I only know a few '
    'topics: Flutter, Riverpod, keeping API keys safe and a couple of '
    'writing tasks. Start the proxy server in /server and pick ChatGPT, '
    'Gemini or Claude above to get a real answer to anything you ask.';
