import 'dart:convert';

// Events sent to the app. The README documents this contract and the Flutter
// client parses exactly these three shapes, skipping comment lines.

String deltaEvent(String text) => _encode({'type': 'delta', 'text': text});

String doneEvent() => _encode({'type': 'done'});

String errorEvent(String message) =>
    _encode({'type': 'error', 'message': message});

/// An SSE comment. Clients ignore it, but it keeps idle connections from
/// being closed by proxies while a model thinks before its first token.
const heartbeatComment = ': keep-alive\n\n';

String _encode(Map<String, String> payload) =>
    'data: ${jsonEncode(payload)}\n\n';

/// Yields the payload of each `data:` line in an upstream SSE body.
///
/// The providers send one JSON document per `data:` line, so multi-line data
/// fields are not reassembled. `event:` lines, comments and blank lines are
/// skipped.
Stream<String> readSseData(Stream<List<int>> body) => body
    .transform(utf8.decoder)
    .transform(const LineSplitter())
    .where((line) => line.startsWith('data:'))
    .map((line) => line.substring('data:'.length).trim());
