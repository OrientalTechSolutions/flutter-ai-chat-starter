# Chat proxy

A small Dart server that sits between the Flutter app and the AI providers. It
holds the API keys, calls OpenAI, Gemini or Anthropic with streaming turned
on, and forwards each provider's stream to the app in one simple format.

## Run it locally

```bash
cd server
cp .env.example .env     # then add at least one API key
dart pub get
dart run bin/server.dart
```

The server reads `.env` from the current directory when it starts. Real
environment variables win over the file, which is how you should configure it
in production.

> [!WARNING]
> The server listens on all network interfaces so phones on your Wi-Fi can
> reach it. That also means anyone else on that network can send it requests
> and use your API keys. Stop it when you are done and avoid shared or public
> networks. If you only test from this machine, set `HOST=127.0.0.1`.

Check it is up:

```bash
curl http://localhost:8080/health
# {"status":"ok","providers":["claude"]}
```

Send a message and watch the stream:

```bash
curl -N http://localhost:8080/chat \
  -H "content-type: application/json" \
  -d '{"provider":"claude","messages":[{"role":"user","content":"Hello"}]}'
```

## Configuration

| Variable                     | Default            | Notes                                                    |
| ---------------------------- | ------------------ | -------------------------------------------------------- |
| `HOST`                       | `0.0.0.0`          | All IPv4 interfaces. `127.0.0.1` keeps it local.         |
| `PORT`                       | `8080`             | Cloud Run and most hosts set this.                       |
| `OPENAI_API_KEY`             | none               | Enables `openai` (ChatGPT).                              |
| `GEMINI_API_KEY`             | none               | Enables `gemini`.                                        |
| `ANTHROPIC_API_KEY`          | none               | Enables `claude`.                                        |
| `OPENAI_MODEL`               | `gpt-6.1-sol`      | Any Chat Completions model.                              |
| `GEMINI_MODEL`               | `gemini-3.8-flash` | Any model with `streamGenerateContent`.                  |
| `CLAUDE_MODEL`               | `claude-opus-5-5`  | Read the fallback note below before changing it.         |
| `SYSTEM_PROMPT`              | plain-text helper  | Sent with every conversation.                            |
| `ALLOW_CLIENT_SYSTEM_PROMPT` | `true`             | `false` ignores the `system` field sent by the app.      |
| `ALLOWED_ORIGIN`             | `*`                | CORS origin for the web build.                           |

Keys are never logged. The startup log only shows which providers are enabled
and the address the server listens on.

The Claude provider opts in to Anthropic's server-side refusal fallback
(`"fallbacks": "default"` plus its `anthropic-beta` header): if a safety
classifier declines a request, Anthropic retries it on a recommended fallback
model inside the same stream instead of returning a refusal. Only some Claude
models support it. If you switch `CLAUDE_MODEL` to a model that rejects the
field (Haiku models, for example), remove the field and the header in
`lib/src/providers/claude_provider.dart`.

## Endpoints

- `GET /health` returns `{"status":"ok","providers":[...]}` with the providers
  that have a key.
- `POST /chat` takes `{"provider", "messages", "system"?}` and answers with a
  `text/event-stream` of `delta`, `done` and `error` events. The full contract
  is in the [main README](../README.md#streaming-contract).

Invalid requests get a `400` with `{"error": "..."}`, and bodies over 256 KB
get a `413`. A conversation can hold at most 100 messages. Upstream failures
arrive as an `error` event with a message that is safe to show to users;
provider error bodies are never forwarded, though a trimmed copy goes to the
server log to help with debugging.

While a model is thinking, the stream carries a `: keep-alive` comment every
15 seconds so load balancers do not close the connection before the first
token. Upstream calls time out after 30 seconds without a response, or 120
seconds without new data.

## Deploy

The proxy is a single Dart binary with no state, so it runs on any host that
can run a container or a Dart executable.

**Docker**

```bash
docker build -t chat-proxy .
docker run -p 8080:8080 --env-file .env chat-proxy
```

Leave `HOST` unset for containers. A server bound to `127.0.0.1` inside the
container cannot be reached through the published port.

**Google Cloud Run**

```bash
gcloud run deploy chat-proxy \
  --source . \
  --region europe-west1 \
  --allow-unauthenticated \
  --set-secrets ANTHROPIC_API_KEY=anthropic-api-key:latest
```

Store keys in Secret Manager (as above) rather than plain environment
variables. Cloud Run streams responses, so replies arrive token by token.

**Anything else**

`dart compile exe bin/server.dart -o chat-proxy` produces a self-contained
binary for the build machine's platform. Put it behind your usual reverse
proxy; if that is nginx, the `X-Accel-Buffering: no` header the server sends
keeps it from buffering the stream.

## Before going to production

The proxy is intentionally small. Anyone who knows its URL can spend your API
credit, so before a public launch add:

- authentication (Firebase Auth, Supabase or your own JWTs) checked in a
  middleware in `lib/src/router.dart`,
- rate limiting per user or per IP,
- `ALLOW_CLIENT_SYSTEM_PROMPT=false`, so callers cannot replace
  `SYSTEM_PROMPT`,
- a specific `ALLOWED_ORIGIN` if you ship the web build.

## Tests

```bash
dart test
```

The provider tests replay sample SSE streams in each API's format through a
fake HTTP client, so they run offline and need no keys.
