import 'dart:async';

import 'package:http/http.dart' as http;

/// Who wrote a turn of the conversation.
enum ChatRole { user, assistant }

/// One turn of conversation history, as sent by the app.
class ChatTurn {
  const ChatTurn({required this.role, required this.content});

  final ChatRole role;
  final String content;
}

/// A model provider that streams replies as plain text deltas.
abstract interface class ChatProvider {
  /// Display name used in logs and error messages, such as "Claude".
  String get name;

  /// Streams the reply to [messages], which end with a user turn.
  ///
  /// Upstream failures are reported as [ProviderException] errors.
  Stream<String> stream(List<ChatTurn> messages, {String? system});
}

/// An upstream failure with a [message] that is safe to show in the app.
///
/// Upstream error bodies are never copied into [message]. They are not
/// written for end users and can echo details of the request. The original
/// error, if any, is kept in [cause] for server logs.
class ProviderException implements Exception {
  const ProviderException(this.message, {this.cause});

  /// Describes a non-200 upstream response by its status code alone.
  factory ProviderException.forStatus(
    String provider,
    int statusCode, {
    Object? cause,
  }) {
    return ProviderException(switch (statusCode) {
      400 => '$provider rejected the request.',
      401 || 403 => '$provider rejected the API key set on the server.',
      404 => '$provider does not recognize the configured model.',
      429 => '$provider is rate limiting requests. Try again shortly.',
      >= 500 => '$provider is having problems. Try again shortly.',
      _ => '$provider returned an unexpected error ($statusCode).',
    }, cause: cause);
  }

  final String message;
  final Object? cause;

  @override
  String toString() => cause == null
      ? 'ProviderException: $message'
      : 'ProviderException: $message ($cause)';
}

/// Sends [request] and returns the response body as a byte stream.
///
/// Connection failures, non-200 responses and timeouts become
/// [ProviderException]s. [responseTimeout] limits the wait for the response
/// headers. [idleTimeout] limits the gap between body chunks; it is generous
/// because reasoning models can think for a while before the first token.
Future<Stream<List<int>>> sendStreamingRequest(
  http.Client client,
  http.BaseRequest request, {
  required String provider,
  Duration responseTimeout = const Duration(seconds: 30),
  Duration idleTimeout = const Duration(seconds: 120),
}) async {
  final http.StreamedResponse response;
  try {
    response = await client.send(request).timeout(responseTimeout);
  } on TimeoutException catch (error) {
    throw ProviderException('$provider did not respond in time.', cause: error);
  } on Exception catch (error) {
    throw ProviderException('Could not reach $provider.', cause: error);
  }

  if (response.statusCode != 200) {
    throw ProviderException.forStatus(
      provider,
      response.statusCode,
      cause: 'HTTP ${response.statusCode}: ${await _readErrorBody(response)}',
    );
  }

  return response.stream.timeout(
    idleTimeout,
    onTimeout: (sink) {
      sink
        ..addError(
          ProviderException('$provider stopped responding. Try again.'),
        )
        ..close();
    },
  );
}

/// Reads an upstream error body for the server log.
///
/// The body usually says why a request failed (a retired model, a prompt that
/// is too long), so it is worth logging. It is capped so an HTML error page
/// cannot flood the log.
Future<String> _readErrorBody(http.StreamedResponse response) async {
  const maxLength = 500;
  try {
    final body = await response.stream.bytesToString();
    return body.length > maxLength
        ? '${body.substring(0, maxLength)}...'
        : body;
  } on Exception {
    return '';
  }
}
