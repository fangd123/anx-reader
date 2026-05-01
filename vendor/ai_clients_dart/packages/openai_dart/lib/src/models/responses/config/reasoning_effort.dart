/// Reasoning effort level for reasoning models.
enum ReasoningEffort {
  /// Unknown effort level (fallback for unrecognized values).
  unknown('unknown'),

  /// Low reasoning effort.
  low('low'),

  /// Medium reasoning effort.
  medium('medium'),

  /// High reasoning effort.
  high('high'),

  /// DeepSeek-specific maximum reasoning effort.
  max('max');

  /// The JSON value for this effort level.
  final String value;

  const ReasoningEffort(this.value);

  /// Creates a [ReasoningEffort] from a JSON value.
  factory ReasoningEffort.fromJson(String json) {
    return ReasoningEffort.values.firstWhere(
      (e) => e.value == json,
      orElse: () => ReasoningEffort.unknown,
    );
  }

  /// Converts to JSON value.
  String toJson() => value;
}
