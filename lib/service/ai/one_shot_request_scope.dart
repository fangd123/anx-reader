import 'package:anx_reader/models/ai_request_context.dart';
import 'package:anx_reader/models/ai_system_preset.dart';

class AiResolvedRequestScope {
  const AiResolvedRequestScope({
    this.systemPrompt,
    this.requestContext,
  });

  final String? systemPrompt;
  final AiRequestContext? requestContext;

  bool get isEmpty {
    final hasPrompt = systemPrompt != null && systemPrompt!.trim().isNotEmpty;
    final hasContext = requestContext?.hasContent == true;
    return !hasPrompt && !hasContext;
  }
}

class AiOneShotRequestScope {
  AiSystemPreset? _pendingPreset;
  AiRequestContext? _pendingContext;
  String? _lastSystemPrompt;
  AiRequestContext? _lastContext;

  void seed({
    AiSystemPreset? preset,
    AiRequestContext? requestContext,
  }) {
    _pendingPreset = preset;
    _pendingContext = requestContext;
  }

  void reset() {
    _pendingPreset = null;
    _pendingContext = null;
    _lastSystemPrompt = null;
    _lastContext = null;
  }

  void setPendingPreset(AiSystemPreset? preset) {
    _pendingPreset = preset;
  }

  void setPendingContext(AiRequestContext? requestContext) {
    _pendingContext = requestContext;
  }

  AiSystemPreset? get pendingPreset => _pendingPreset;
  AiRequestContext? get pendingContext => _pendingContext;

  bool get hasPendingOverrides {
    final hasPrompt = _pendingPreset != null &&
        _pendingPreset!.systemPrompt.trim().isNotEmpty;
    final hasContext = _pendingContext?.hasContent == true;
    return hasPrompt || hasContext;
  }

  AiResolvedRequestScope consume({required bool isRegenerate}) {
    if (isRegenerate) {
      return AiResolvedRequestScope(
        systemPrompt: _lastSystemPrompt,
        requestContext: _lastContext,
      );
    }

    final resolved = AiResolvedRequestScope(
      systemPrompt: _pendingPreset?.systemPrompt,
      requestContext: _pendingContext,
    );

    _lastSystemPrompt = resolved.systemPrompt;
    _lastContext = resolved.requestContext;
    _pendingPreset = null;
    _pendingContext = null;
    return resolved;
  }
}
