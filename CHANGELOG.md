# Changelog

## 0.1.0

First public release.

- Flutter chat app with streaming replies, stop, retry, clear and copy.
- Demo mode with on-device replies, so the app runs without keys.
- Dart proxy server for ChatGPT, Gemini and Claude that keeps API keys off
  the client and normalizes each provider's stream into one event format.
- Unit and widget tests for the app, offline provider tests for the server.
- Dockerfile and deployment notes for the proxy.
