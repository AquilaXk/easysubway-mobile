/// 온보딩과 설정이 함께 저장하는 접근성 보기 기본값.
class OnboardingViewPreferences {
  const OnboardingViewPreferences({
    required this.largeTextEnabled,
    required this.highContrastEnabled,
    required this.simpleViewEnabled,
  });

  const OnboardingViewPreferences.defaults()
    : largeTextEnabled = false,
      highContrastEnabled = false,
      simpleViewEnabled = true;

  factory OnboardingViewPreferences.fromJson(Map<String, Object?> json) {
    final largeTextEnabled = json['largeTextEnabled'];
    final highContrastEnabled = json['highContrastEnabled'];
    final simpleViewEnabled = json['simpleViewEnabled'];
    if (largeTextEnabled is! bool ||
        highContrastEnabled is! bool ||
        simpleViewEnabled is! bool) {
      throw const FormatException('Invalid onboarding preferences payload');
    }

    return OnboardingViewPreferences(
      largeTextEnabled: largeTextEnabled,
      highContrastEnabled: highContrastEnabled,
      simpleViewEnabled: simpleViewEnabled,
    );
  }

  final bool largeTextEnabled;
  final bool highContrastEnabled;
  final bool simpleViewEnabled;

  OnboardingViewPreferences copyWith({
    bool? largeTextEnabled,
    bool? highContrastEnabled,
    bool? simpleViewEnabled,
  }) {
    return OnboardingViewPreferences(
      largeTextEnabled: largeTextEnabled ?? this.largeTextEnabled,
      highContrastEnabled: highContrastEnabled ?? this.highContrastEnabled,
      simpleViewEnabled: simpleViewEnabled ?? this.simpleViewEnabled,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'largeTextEnabled': largeTextEnabled,
      'highContrastEnabled': highContrastEnabled,
      'simpleViewEnabled': simpleViewEnabled,
    };
  }
}
