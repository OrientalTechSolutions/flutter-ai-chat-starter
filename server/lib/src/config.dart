import 'dart:io';

/// Default models. Each can be overridden with an environment variable.
const defaultOpenAiModel = 'gpt-6.1-sol';
const defaultGeminiModel = 'gemini-3.8-flash';
const defaultClaudeModel = 'claude-opus-5-5';

/// Used when SYSTEM_PROMPT is not set. The app renders plain text, so the
/// prompt steers models away from Markdown.
const defaultSystemPrompt =
    'You are a helpful assistant inside a mobile chat app. Keep answers '
    'clear and reasonably short. Reply in plain text without Markdown; use '
    'simple numbered or dashed lists when a list helps.';

/// Server settings, read from environment variables.
class ProxyConfig {
  const ProxyConfig({
    this.host = '0.0.0.0',
    this.port = 8080,
    this.openAiKey,
    this.geminiKey,
    this.anthropicKey,
    this.openAiModel = defaultOpenAiModel,
    this.geminiModel = defaultGeminiModel,
    this.claudeModel = defaultClaudeModel,
    this.systemPrompt = defaultSystemPrompt,
    this.allowClientSystemPrompt = true,
    this.allowedOrigin = '*',
  });

  /// Reads settings from [env]. Blank values count as unset.
  factory ProxyConfig.fromEnvironment(Map<String, String> env) {
    String? read(String name) {
      final value = env[name]?.trim();
      return value == null || value.isEmpty ? null : value;
    }

    return ProxyConfig(
      host: read('HOST') ?? '0.0.0.0',
      port: int.tryParse(read('PORT') ?? '') ?? 8080,
      openAiKey: read('OPENAI_API_KEY'),
      geminiKey: read('GEMINI_API_KEY'),
      anthropicKey: read('ANTHROPIC_API_KEY'),
      openAiModel: read('OPENAI_MODEL') ?? defaultOpenAiModel,
      geminiModel: read('GEMINI_MODEL') ?? defaultGeminiModel,
      claudeModel: read('CLAUDE_MODEL') ?? defaultClaudeModel,
      systemPrompt: read('SYSTEM_PROMPT') ?? defaultSystemPrompt,
      allowClientSystemPrompt:
          read('ALLOW_CLIENT_SYSTEM_PROMPT')?.toLowerCase() != 'false',
      allowedOrigin: read('ALLOWED_ORIGIN') ?? '*',
    );
  }

  /// Address to listen on. The default, `0.0.0.0`, accepts connections on
  /// every IPv4 interface, which containers and phones on the same Wi-Fi
  /// need. `127.0.0.1` keeps the server reachable from this machine only.
  final String host;

  final int port;
  final String? openAiKey;
  final String? geminiKey;
  final String? anthropicKey;
  final String openAiModel;
  final String geminiModel;
  final String claudeModel;
  final String systemPrompt;

  /// Whether a `system` field in a chat request replaces [systemPrompt].
  /// Turn it off in production so callers cannot remove your instructions.
  final bool allowClientSystemPrompt;

  /// Value of the `Access-Control-Allow-Origin` header. Set it to your web
  /// app's origin in production.
  final String allowedOrigin;
}

/// Reads `KEY=value` lines from a `.env` file, if one exists.
///
/// Meant for local development only. In production, set real environment
/// variables, which take precedence over the file.
Map<String, String> readDotEnv(File file) {
  if (!file.existsSync()) return const {};

  final values = <String, String>{};
  for (final line in file.readAsLinesSync()) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) continue;

    final separator = trimmed.indexOf('=');
    if (separator <= 0) continue;

    final key = trimmed.substring(0, separator).trim();
    var value = trimmed.substring(separator + 1).trim();
    final isQuoted =
        value.length >= 2 &&
        (value[0] == '"' || value[0] == "'") &&
        value[value.length - 1] == value[0];
    if (isQuoted) value = value.substring(1, value.length - 1);

    values[key] = value;
  }
  return values;
}
