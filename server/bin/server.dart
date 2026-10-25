import 'dart:io';

import 'package:chat_proxy/chat_proxy.dart';
import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

Future<void> main() async {
  final config = ProxyConfig.fromEnvironment({
    ...readDotEnv(File('.env')),
    ...Platform.environment,
  });

  final client = http.Client();
  final providers = <String, ChatProvider>{
    if (config.openAiKey case final key?)
      'openai': OpenAiProvider(
        apiKey: key,
        model: config.openAiModel,
        client: client,
      ),
    if (config.geminiKey case final key?)
      'gemini': GeminiProvider(
        apiKey: key,
        model: config.geminiModel,
        client: client,
      ),
    if (config.anthropicKey case final key?)
      'claude': ClaudeProvider(
        apiKey: key,
        model: config.claudeModel,
        client: client,
      ),
  };

  if (providers.isEmpty) {
    _log(
      'No API keys set. Add OPENAI_API_KEY, GEMINI_API_KEY or '
      'ANTHROPIC_API_KEY to enable a provider.',
    );
  } else {
    _log('Providers enabled: ${providers.keys.join(', ')}');
  }

  final handler = const Pipeline()
      .addMiddleware(logRequests())
      .addHandler(
        buildHandler(
          providers: providers,
          systemPrompt: config.systemPrompt,
          allowClientSystemPrompt: config.allowClientSystemPrompt,
          allowedOrigin: config.allowedOrigin,
          log: _log,
        ),
      );

  final server = await shelf_io.serve(handler, config.host, config.port);
  _log('Chat proxy listening on ${server.address.address}:${server.port}');
}

void _log(String message) {
  stdout.writeln('${DateTime.now().toUtc().toIso8601String()}  $message');
}
