enum AiReasoningEffort {
  auto('auto'),
  low('low'),
  medium('medium'),
  high('high'),
  max('max');

  const AiReasoningEffort(this.code);

  final String code;

  static AiReasoningEffort fromCode(String? code) {
    return AiReasoningEffort.values.firstWhere(
      (value) => value.code == code,
      orElse: () => AiReasoningEffort.auto,
    );
  }
}
