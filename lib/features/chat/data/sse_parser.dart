import 'dart:convert';

/// An event in the proxy's reply stream.
///
/// The wire format is described in the README under "Streaming contract".
sealed class ChatEvent {
  const ChatEvent();
}

/// A chunk of reply text.
final class DeltaEvent extends ChatEvent {
  const DeltaEvent(this.text);

  final String text;
}

/// The reply finished normally.
final class DoneEvent extends ChatEvent {
  const DoneEvent();
}

/// The proxy or the upstream provider failed. [message] is safe to show.
final class ErrorEvent extends ChatEvent {
  const ErrorEvent(this.message);

  final String message;
}

/// Parses a single line of a server-sent event stream.
///
/// Returns null for blank lines, comments, fields other than `data` and
/// event types this version of the app does not know. Throws a
/// [FormatException] if a data line is not valid JSON.
ChatEvent? parseSseLine(String line) {
  if (!line.startsWith('data:')) return null;
  final payload = line.substring('data:'.length).trim();
  if (payload.isEmpty) return null;

  return switch (jsonDecode(payload)) {
    {'type': 'delta', 'text': final String text} => DeltaEvent(text),
    {'type': 'done'} => const DoneEvent(),
    {'type': 'error', 'message': final String message} => ErrorEvent(message),
    _ => null,
  };
}

/// Decodes the proxy's raw response body into [ChatEvent]s.
///
/// Network chunks can split a line, or a multi-byte character, anywhere, so
/// the bytes are decoded and re-split into whole lines before parsing.
Stream<ChatEvent> decodeChatEvents(Stream<List<int>> bytes) async* {
  final lines = bytes.transform(utf8.decoder).transform(const LineSplitter());
  await for (final line in lines) {
    final event = parseSseLine(line);
    if (event != null) yield event;
  }
}
