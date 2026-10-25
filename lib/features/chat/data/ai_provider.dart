/// The models a user can chat with.
enum AiProvider {
  demo('Demo', null),
  chatGpt('ChatGPT', 'openai'),
  gemini('Gemini', 'gemini'),
  claude('Claude', 'claude');

  const AiProvider(this.displayName, this.apiId);

  final String displayName;

  /// The provider id the proxy expects, or null for the on-device demo.
  final String? apiId;

  bool get isDemo => apiId == null;
}
