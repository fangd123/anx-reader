import 'package:anx_reader/enums/ai_reasoning_effort.dart';
import 'package:anx_reader/models/ai_provider.dart';

const String deepSeekProviderId = 'deepseek';
const String deepSeekApiHost = 'api.deepseek.com';
const String deepSeekV4ProModel = 'deepseek-v4-pro';

bool isDeepSeekProviderId(String identifier) {
  return identifier.trim().toLowerCase() == deepSeekProviderId;
}

bool isDeepSeekUrl(String? url) {
  if (url == null || url.trim().isEmpty) {
    return false;
  }

  final uri = Uri.tryParse(url.trim());
  final host = uri?.host.toLowerCase() ?? '';
  return host == deepSeekApiHost || host.endsWith('.$deepSeekApiHost');
}

bool isDeepSeekProvider({
  required String identifier,
  String? url,
}) {
  return isDeepSeekProviderId(identifier) || isDeepSeekUrl(url);
}

bool isDeepSeekProviderModel(String? model) {
  return model?.trim().toLowerCase() == deepSeekV4ProModel;
}

bool supportsDeepSeekThinking({
  required String identifier,
  String? url,
  String? model,
}) {
  return isDeepSeekProvider(identifier: identifier, url: url) &&
      isDeepSeekProviderModel(model);
}

AiReasoningEffort defaultReasoningEffortForProvider({
  required String identifier,
  String? url,
}) {
  if (isDeepSeekProvider(identifier: identifier, url: url)) {
    return AiReasoningEffort.max;
  }
  return AiReasoningEffort.auto;
}

AiProvider normalizeDeepSeekProvider(AiProvider provider) {
  if (!isDeepSeekProvider(identifier: provider.id, url: provider.url)) {
    return provider;
  }

  if (provider.reasoningEffort != AiReasoningEffort.auto) {
    return provider;
  }

  return provider.copyWith(
    reasoningEffort: AiReasoningEffort.max,
  );
}
