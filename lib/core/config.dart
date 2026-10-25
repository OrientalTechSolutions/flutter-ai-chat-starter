/// Settings fixed at build time through `--dart-define`.
abstract final class AppConfig {
  /// Base URL of the chat proxy in `/server`.
  ///
  /// Override with `--dart-define=CHAT_API_URL=https://chat.example.com`.
  /// The Android emulator reaches the host machine at `http://10.0.2.2:8080`.
  static const chatApiUrl = String.fromEnvironment(
    'CHAT_API_URL',
    defaultValue: 'http://localhost:8080',
  );
}
