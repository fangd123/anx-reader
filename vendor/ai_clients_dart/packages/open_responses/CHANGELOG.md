## 0.1.4

This release adds inline streaming error detection for improved reliability when handling streamed responses.

- **FEAT**: Detect inline streaming errors ([#91](https://github.com/davidmigloz/ai_clients_dart/issues/91)). ([9f0eaf37](https://github.com/davidmigloz/ai_clients_dart/commit/9f0eaf37dfa2e1ce7d05c4d0ae1b00af2d8f78f6))
- **DOCS**: Improve READMEs with badges, sponsor section, and vertex_ai deprecation ([#90](https://github.com/davidmigloz/ai_clients_dart/issues/90)). ([5741f2f3](https://github.com/davidmigloz/ai_clients_dart/commit/5741f2f3bcecdc947235aa10e9a7534baef95741))

## 0.1.3

Internal improvements to build tooling and package publishing configuration.

- **REFACTOR**: Migrate API skills to the shared api-toolkit CLI ([#74](https://github.com/davidmigloz/ai_clients_dart/issues/74)). ([923cc83e](https://github.com/davidmigloz/ai_clients_dart/commit/923cc83e9d72be370b2af8580a41970604df0787))
- **CHORE**: Add .pubignore to exclude .agents/ and specs/ from publishing ([#78](https://github.com/davidmigloz/ai_clients_dart/issues/78)). ([0ff199bf](https://github.com/davidmigloz/ai_clients_dart/commit/0ff199bf9c7b4cc090cde73b994cca5ae5d3eaf9))

## 0.1.2

Added `baseUrl` and `defaultHeaders` parameters to `withApiKey` constructors and unified equality helpers across packages.

- **FEAT**: Add baseUrl and defaultHeaders to withApiKey constructors ([#57](https://github.com/davidmigloz/ai_clients_dart/issues/57)). ([f0dd0caa](https://github.com/davidmigloz/ai_clients_dart/commit/f0dd0caac1247e065e4add236d7a6dca38ceea56))
- **REFACTOR**: Unify equality_helpers.dart across packages ([#67](https://github.com/davidmigloz/ai_clients_dart/issues/67)). ([ec2897f8](https://github.com/davidmigloz/ai_clients_dart/commit/ec2897f8e5b5370a78e8b95832fde503cfaa5dd7))

## 0.1.1

Added `withApiKey` convenience constructor for simplified client initialization.

- **FEAT**: Add withApiKey convenience constructors ([#56](https://github.com/davidmigloz/ai_clients_dart/issues/56)). ([b06e3df3](https://github.com/davidmigloz/ai_clients_dart/commit/b06e3df31cea2228489525b68b7d0055f678fecc))
- **CHORE**: Bump googleapis from 15.0.0 to 16.0.0 and Dart SDK to 3.9.0 ([#52](https://github.com/davidmigloz/ai_clients_dart/issues/52)). ([eae130b7](https://github.com/davidmigloz/ai_clients_dart/commit/eae130b785d38074e85d460eefa9210f4acdf215))

## 0.1.0

Initial release of the OpenResponses Dart client.

### Features

- **Core Client**: `OpenResponsesClient` with configurable base URL and authentication
- **Response Creation**: `responses.create()` for non-streaming requests
- **Streaming**: `responses.createStream()` and `responses.stream()` with builder pattern
- **Multi-provider Support**: Works with OpenAI, Ollama, Hugging Face, OpenRouter, and LM Studio

### Request Features

- String or message item list input
- System instructions via `instructions` parameter
- Multi-turn conversations with `previousResponseId`
- Temperature and max output tokens control
- Service tier selection

### Tools

- `FunctionTool`: Define custom functions with JSON Schema parameters
- `McpTool`: Remote Model Context Protocol server tools
- Tool choice configuration (auto, required, specific function)

### Structured Output

- `TextConfig` with format options
- `JsonSchemaFormat` for structured JSON responses with strict mode
- `TextResponseFormat` and `JsonObjectFormat`

### Reasoning Models

- `ReasoningConfig` with effort levels (low, medium, high)
- Reasoning summary modes (concise, detailed, auto)
- Access to reasoning items via `response.reasoningItems`

### Streaming Events

- Full SSE event parsing with 25+ event types
- Response lifecycle events (created, queued, in_progress, completed, failed)
- Output item and content part events
- Text delta and done events
- Function call argument streaming
- Reasoning delta and summary events
- Error events

### Content Types

- `InputTextContent`: Text input
- `InputImageContent`: Image URLs with detail level
- `InputFileContent`: File references
- `OutputTextContent`: Text output with annotations
- `RefusalContent`: Model refusal messages

### Message Items

- `MessageItem` with role (user, assistant, system, developer)
- Convenience factories: `userText()`, `systemText()`, `assistantText()`
- `FunctionCallItem` and `FunctionCallOutputItem`
- `ItemReference` for referencing previous items

### DX Extensions

- `response.outputText`: Concatenated text from output
- `response.functionCalls`: All function call items
- `response.reasoningItems`: All reasoning items
- `response.hasToolCalls`, `response.isCompleted`, `response.isFailed`
- `event.textDelta`, `event.isFinal`
- `stream.text`, `stream.finalResponse`

### Error Handling

- `OpenResponsesException` sealed class hierarchy
- `ApiException` with error code and details
- `AuthenticationException` for auth failures
- `RateLimitException` with retry-after duration
- `ValidationException` for invalid requests
- `TimeoutException` and `AbortedException`

### Authentication

- `BearerTokenProvider` for API key authentication
- `NoAuthProvider` for local providers (Ollama, LM Studio)
- Extensible `AuthProvider` interface

### Configuration

- `OpenResponsesConfig` with base URL, auth, headers, timeout
- `RetryPolicy` with exponential backoff and jitter
- Custom HTTP client support

### Commits

- **FEAT**: Initial implementation of OpenResponses Dart client ([#10](https://github.com/davidmigloz/ai_clients_dart/issues/10)). ([4fac8fa6](https://github.com/davidmigloz/ai_clients_dart/commit/4fac8fa684be13fea30c96a9481c415c3a1a5f66))
- **FEAT**: Comprehensive model improvements with new features ([#16](https://github.com/davidmigloz/ai_clients_dart/issues/16)). ([6b6450a7](https://github.com/davidmigloz/ai_clients_dart/commit/6b6450a7a23987dd7ba67aacef16ad8f67d6898d))
- **FEAT**: Add SummaryTextContent for reasoning models ([#23](https://github.com/davidmigloz/ai_clients_dart/issues/23)). ([93ce0a00](https://github.com/davidmigloz/ai_clients_dart/commit/93ce0a008c8c8d065c7c4ba475d55d96756e5e54))
- **FEAT**: Add ReasoningInputItem, UnknownEvent, and provider aliases ([#28](https://github.com/davidmigloz/ai_clients_dart/issues/28)). ([e1fa0afe](https://github.com/davidmigloz/ai_clients_dart/commit/e1fa0afe20fc8c45a5ded1c360a1507a7fa0fa2c))
- **REFACTOR**: Align client package architecture across SDK packages ([#37](https://github.com/davidmigloz/ai_clients_dart/issues/37)). ([cf741ee1](https://github.com/davidmigloz/ai_clients_dart/commit/cf741ee12ac45667b86fe166b33dad37d85962b2))
- **REFACTOR**: Align API surface across all SDK packages ([#36](https://github.com/davidmigloz/ai_clients_dart/issues/36)). ([ed969cc7](https://github.com/davidmigloz/ai_clients_dart/commit/ed969cc7ad964da60702f2c97c14851ebe9aa992))
