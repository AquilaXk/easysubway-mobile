abstract interface class SupportAccessLauncher {
  Future<bool> open(Uri uri);
}

class SupportAccessInfo {
  const SupportAccessInfo({
    this.termsOfServiceUrl = '',
    required this.privacyPolicyUrl,
    this.locationTermsUrl = '',
    required this.supportEmail,
    required this.dataDeletionEmail,
    this.securityEmail = '',
  });

  const SupportAccessInfo.fromEnvironment()
    : termsOfServiceUrl = const String.fromEnvironment(
        'EASYSUBWAY_TERMS_OF_SERVICE_URL',
      ),
      privacyPolicyUrl = const String.fromEnvironment(
        'EASYSUBWAY_PRIVACY_POLICY_URL',
      ),
      locationTermsUrl = const String.fromEnvironment(
        'EASYSUBWAY_LOCATION_TERMS_URL',
      ),
      supportEmail = const String.fromEnvironment('EASYSUBWAY_SUPPORT_EMAIL'),
      dataDeletionEmail = const String.fromEnvironment(
        'EASYSUBWAY_DATA_DELETION_EMAIL',
      ),
      securityEmail = const String.fromEnvironment('EASYSUBWAY_SECURITY_EMAIL');

  final String termsOfServiceUrl;
  final String privacyPolicyUrl;
  final String locationTermsUrl;
  final String supportEmail;
  final String dataDeletionEmail;
  final String securityEmail;

  SupportAccessInfo validatedForBuild({required bool isReleaseMode}) {
    if (!isReleaseMode) {
      return this;
    }
    _validateHttpsUrl(label: 'terms of service URL', value: termsOfServiceUrl);
    _validateHttpsUrl(label: 'privacy policy URL', value: privacyPolicyUrl);
    _validateHttpsUrl(label: 'location terms URL', value: locationTermsUrl);
    _validateEmail(label: 'support email', value: supportEmail);
    _validateEmail(label: 'data deletion email', value: dataDeletionEmail);
    _validateEmail(label: 'security email', value: securityEmail);
    return this;
  }

  static void _validateHttpsUrl({
    required String label,
    required String value,
  }) {
    final normalizedValue = value.trim();
    if (normalizedValue.isEmpty) {
      throw StateError('Release $label must be configured.');
    }
    final uri = Uri.tryParse(normalizedValue);
    if (uri == null || uri.scheme != 'https') {
      throw StateError('Release $label must use HTTPS.');
    }
    if (uri.host.isEmpty) {
      throw StateError('Release $label must include a host.');
    }
  }

  static void _validateEmail({required String label, required String value}) {
    final normalizedValue = value.trim();
    if (normalizedValue.isEmpty) {
      throw StateError('Release $label must be configured.');
    }
    final emailPattern = RegExp(
      r'^[^\s@]+@(?:[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,63}$',
    );
    if (!emailPattern.hasMatch(normalizedValue)) {
      throw StateError('Release $label must be a valid email address.');
    }
  }
}

/// 지원·문의 mailto URI. [body]가 있으면 메일 초안 본문으로 넣는다.
Uri? buildSupportMailtoUri({
  required String email,
  required String subject,
  String? body,
}) {
  final normalizedEmail = email.trim();
  if (normalizedEmail.isEmpty) {
    return null;
  }
  final query = <String, String>{'subject': subject};
  final normalizedBody = body?.trim();
  if (normalizedBody != null && normalizedBody.isNotEmpty) {
    query['body'] = normalizedBody;
  }
  return Uri(scheme: 'mailto', path: normalizedEmail, queryParameters: query);
}
