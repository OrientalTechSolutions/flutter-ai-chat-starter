import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// An upstream request captured by [fakeUpstream].
typedef SentRequest = ({http.BaseRequest request, Object? json});

/// A client that answers every request with [body].
///
/// The body is delivered in small chunks so that parsers are exercised on
/// lines split across network reads, as they are in production.
MockClient fakeUpstream(
  String body, {
  int statusCode = 200,
  void Function(SentRequest sent)? onRequest,
}) {
  return MockClient.streaming((request, bodyStream) async {
    final sentBody = await bodyStream.bytesToString();
    onRequest?.call((request: request, json: jsonDecode(sentBody)));
    return http.StreamedResponse(_chunked(utf8.encode(body)), statusCode);
  });
}

Stream<List<int>> _chunked(List<int> bytes, {int size = 16}) async* {
  for (var start = 0; start < bytes.length; start += size) {
    yield bytes.sublist(start, math.min(start + size, bytes.length));
  }
}
