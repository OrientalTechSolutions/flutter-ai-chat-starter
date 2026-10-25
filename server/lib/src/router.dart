import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'chat_request.dart';
import 'providers/chat_provider.dart';
import 'sse.dart';

/// Largest `POST /chat` body the proxy reads. A long conversation is a few
/// kilobytes, so this is generous while keeping memory use bounded.
const maxBodyBytes = 256 * 1024;

/// Names the app shows for each provider id, used in error messages.
const _providerNames = {
  'openai': 'ChatGPT',
  'gemini': 'Gemini',
  'claude': 'Claude',
};

/// Builds the proxy's HTTP handler.
///
/// [providers] maps the ids the app sends (`openai`, `gemini`, `claude`) to
/// providers. Include only the ones that have an API key configured.
///
/// While a reply is streaming, a comment is sent every [heartbeatInterval]
/// so that proxies in between do not close a connection that is waiting for
/// the model's first token.
Handler buildHandler({
  required Map<String, ChatProvider> providers,
  String? systemPrompt,
  bool allowClientSystemPrompt = true,
  String allowedOrigin = '*',
  Duration heartbeatInterval = const Duration(seconds: 15),
  void Function(String message) log = _noLog,
}) {
  Future<Response> chat(Request request) async {
    final body = await _readBody(request);
    if (body == null) {
      return _json({'error': 'The request is too large.'}, status: 413);
    }

    final ChatRequest chatRequest;
    try {
      chatRequest = ChatRequest.parse(body);
    } on FormatException catch (error) {
      return _json({'error': error.message}, status: 400);
    }

    final provider = providers[chatRequest.provider];
    if (provider == null) {
      final name = _providerNames[chatRequest.provider];
      return _json({
        'error': name == null
            ? 'Unknown provider "${chatRequest.provider}".'
            : 'The chat server has no API key for $name.',
      }, status: 400);
    }

    final replies = provider.stream(
      chatRequest.messages,
      system:
          (allowClientSystemPrompt ? chatRequest.system : null) ?? systemPrompt,
    );
    return Response.ok(
      _eventStream(replies, provider.name, log, heartbeatInterval),
      headers: const {
        'content-type': 'text/event-stream',
        'cache-control': 'no-cache',
        // Stops reverse proxies such as nginx from buffering the stream.
        'x-accel-buffering': 'no',
      },
      context: const {'shelf.io.buffer_output': false},
    );
  }

  final router = Router()
    ..get(
      '/health',
      (Request request) =>
          _json({'status': 'ok', 'providers': providers.keys.toList()}),
    )
    ..post('/chat', chat);

  return const Pipeline()
      .addMiddleware(_cors(allowedOrigin))
      .addHandler(router.call);
}

/// Reads the request body as UTF-8, or returns null if it is larger than
/// [maxBodyBytes]. Stops reading as soon as the limit is passed, so an
/// oversized upload is never held in memory.
Future<String?> _readBody(Request request) async {
  if ((request.contentLength ?? 0) > maxBodyBytes) return null;

  final bytes = BytesBuilder(copy: false);
  await for (final chunk in request.read()) {
    bytes.add(chunk);
    if (bytes.length > maxBodyBytes) return null;
  }
  return utf8.decode(bytes.takeBytes(), allowMalformed: true);
}

/// Turns provider deltas into the app's SSE events, ending with `done` on
/// success or a single `error` event on failure.
///
/// If the app disconnects, cancelling this stream also cancels [replies],
/// which closes the upstream request.
Stream<List<int>> _eventStream(
  Stream<String> replies,
  String providerName,
  void Function(String message) log,
  Duration heartbeatInterval,
) {
  final controller = StreamController<List<int>>();
  StreamSubscription<String>? subscription;
  Timer? heartbeat;

  void send(String event) => controller.add(utf8.encode(event));

  void finish(String lastEvent) {
    heartbeat?.cancel();
    send(lastEvent);
    controller.close();
  }

  void fail(Object error) {
    if (error is ProviderException) {
      log('$providerName: $error');
      finish(errorEvent(error.message));
    } else {
      // Anything else is a bug or a dropped connection. Log the details, but
      // keep them out of the response.
      log('$providerName: unexpected error: $error');
      finish(errorEvent('The reply was interrupted. Please try again.'));
    }
  }

  controller
    ..onListen = () {
      heartbeat = Timer.periodic(
        heartbeatInterval,
        (_) => send(heartbeatComment),
      );
      subscription = replies.listen(
        (text) => send(deltaEvent(text)),
        onError: fail,
        onDone: () => finish(doneEvent()),
        cancelOnError: true,
      );
    }
    ..onCancel = () {
      heartbeat?.cancel();
      return subscription?.cancel();
    };

  return controller.stream;
}

/// Adds CORS headers to every response and answers preflight requests, so
/// the Flutter web build can call the proxy from another origin.
Middleware _cors(String allowedOrigin) {
  final headers = {
    'access-control-allow-origin': allowedOrigin,
    'access-control-allow-methods': 'GET, POST, OPTIONS',
    'access-control-allow-headers': 'content-type',
    'access-control-max-age': '86400',
  };

  return (Handler inner) {
    return (Request request) async {
      if (request.method == 'OPTIONS') {
        return Response(204, headers: headers);
      }
      final response = await inner(request);
      return response.change(headers: headers);
    };
  };
}

Response _json(Object body, {int status = 200}) {
  return Response(
    status,
    body: jsonEncode(body),
    headers: const {'content-type': 'application/json'},
  );
}

void _noLog(String message) {}
