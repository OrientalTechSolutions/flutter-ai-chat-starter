import 'dart:convert';

import 'package:ai_chat_starter/features/chat/data/sse_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseSseLine', () {
    test('parses delta, done and error events', () {
      expect(
        parseSseLine('data: {"type":"delta","text":"Hi"}'),
        isA<DeltaEvent>().having((e) => e.text, 'text', 'Hi'),
      );
      expect(parseSseLine('data: {"type":"done"}'), isA<DoneEvent>());
      expect(
        parseSseLine('data: {"type":"error","message":"Rate limited"}'),
        isA<ErrorEvent>().having((e) => e.message, 'message', 'Rate limited'),
      );
    });

    test('accepts data lines without a space after the colon', () {
      expect(parseSseLine('data:{"type":"done"}'), isA<DoneEvent>());
    });

    test('ignores blank lines, comments, other fields and unknown types', () {
      expect(parseSseLine(''), isNull);
      expect(parseSseLine(': keep-alive'), isNull);
      expect(parseSseLine('event: message'), isNull);
      expect(parseSseLine('data: {"type":"usage","tokens":42}'), isNull);
    });

    test('throws on malformed JSON', () {
      expect(() => parseSseLine('data: {"type":'), throwsFormatException);
    });
  });

  group('decodeChatEvents', () {
    test('reassembles events split across network chunks', () async {
      final bytes = utf8.encode(
        'data: {"type":"delta","text":"Hel"}\n\n'
        'data: {"type":"delta","text":"lo"}\n\n'
        'data: {"type":"done"}\n\n',
      );
      final chunks = <List<int>>[
        bytes.sublist(0, 9),
        bytes.sublist(9, 50),
        bytes.sublist(50),
      ];

      final events = await decodeChatEvents(
        Stream.fromIterable(chunks),
      ).toList();

      expect(events.whereType<DeltaEvent>().map((e) => e.text).join(), 'Hello');
      expect(events.last, isA<DoneEvent>());
    });

    test('decodes a multi-byte character split between chunks', () async {
      final bytes = utf8.encode('data: {"type":"delta","text":"café"}\n\n');
      // 0xC3 is the first of the two bytes that encode "é".
      final splitAt = bytes.indexOf(0xC3) + 1;

      final chunks = <List<int>>[
        bytes.sublist(0, splitAt),
        bytes.sublist(splitAt),
      ];

      final events = await decodeChatEvents(
        Stream.fromIterable(chunks),
      ).toList();

      expect(
        events.single,
        isA<DeltaEvent>().having((e) => e.text, 'text', 'café'),
      );
    });

    test('handles CRLF line endings', () async {
      final List<int> bytes = utf8.encode('data: {"type":"done"}\r\n\r\n');

      final events = await decodeChatEvents(Stream.value(bytes)).toList();

      expect(events.single, isA<DoneEvent>());
    });
  });
}
