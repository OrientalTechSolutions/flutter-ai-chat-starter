import 'dart:io';

import 'package:chat_proxy/chat_proxy.dart';
import 'package:test/test.dart';

void main() {
  group('ProxyConfig.fromEnvironment', () {
    test('uses defaults when nothing is set', () {
      final config = ProxyConfig.fromEnvironment({});

      expect(config.host, '0.0.0.0');
      expect(config.port, 8080);
      expect(config.openAiKey, isNull);
      expect(config.claudeModel, defaultClaudeModel);
      expect(config.systemPrompt, defaultSystemPrompt);
      expect(config.allowClientSystemPrompt, isTrue);
      expect(config.allowedOrigin, '*');
    });

    test('reads values and treats blank keys as unset', () {
      final config = ProxyConfig.fromEnvironment({
        'HOST': '127.0.0.1',
        'PORT': '9000',
        'ANTHROPIC_API_KEY': 'test-key',
        'OPENAI_API_KEY': '   ',
        'GEMINI_MODEL': 'gemini-custom',
        'ALLOW_CLIENT_SYSTEM_PROMPT': 'false',
      });

      expect(config.host, '127.0.0.1');
      expect(config.port, 9000);
      expect(config.anthropicKey, 'test-key');
      expect(config.openAiKey, isNull);
      expect(config.geminiModel, 'gemini-custom');
      expect(config.allowClientSystemPrompt, isFalse);
    });
  });

  group('readDotEnv', () {
    late Directory directory;

    setUp(() {
      directory = Directory.systemTemp.createTempSync('chat_proxy_test');
      addTearDown(() => directory.deleteSync(recursive: true));
    });

    test('parses keys, skips comments and strips quotes', () {
      final file = File('${directory.path}/.env')
        ..writeAsStringSync(
          '# Local settings\n'
          'PORT=9000\n'
          '\n'
          'SYSTEM_PROMPT="Be brief."\n'
          "ALLOWED_ORIGIN='http://localhost:5000'\n"
          'OPENAI_API_KEY=\n',
        );

      expect(readDotEnv(file), {
        'PORT': '9000',
        'SYSTEM_PROMPT': 'Be brief.',
        'ALLOWED_ORIGIN': 'http://localhost:5000',
        'OPENAI_API_KEY': '',
      });
    });

    test('returns nothing when the file is missing', () {
      expect(readDotEnv(File('${directory.path}/missing.env')), isEmpty);
    });
  });
}
