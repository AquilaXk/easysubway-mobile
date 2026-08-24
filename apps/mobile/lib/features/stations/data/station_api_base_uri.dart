import 'dart:io';

import 'package:flutter/foundation.dart';

const _debugApiBaseUriRequired =
    'Development API base URL is only available in debug.';

Uri defaultStationApiBaseUri() {
  const configuredBaseUrl = String.fromEnvironment('EASYSUBWAY_API_BASE_URL');
  return stationApiBaseUriForEnvironment(
    configuredBaseUrl: configuredBaseUrl,
    isAndroid: Platform.isAndroid,
    isReleaseMode: kReleaseMode,
  );
}

Uri? defaultOptionalStationApiBaseUri() {
  const configuredBaseUrl = String.fromEnvironment('EASYSUBWAY_API_BASE_URL');
  return optionalStationApiBaseUriForEnvironment(
    configuredBaseUrl: configuredBaseUrl,
    isAndroid: Platform.isAndroid,
    isReleaseMode: kReleaseMode,
  );
}

Uri? optionalStationApiBaseUriForEnvironment({
  required String configuredBaseUrl,
  required bool isAndroid,
  required bool isReleaseMode,
}) {
  if (configuredBaseUrl.trim().isEmpty && isReleaseMode) {
    return null;
  }
  return stationApiBaseUriForEnvironment(
    configuredBaseUrl: configuredBaseUrl,
    isAndroid: isAndroid,
    isReleaseMode: isReleaseMode,
  );
}

Uri stationApiBaseUriForEnvironment({
  required String configuredBaseUrl,
  required bool isAndroid,
  required bool isReleaseMode,
}) {
  return stationApiBaseUriForBuildMode(
    configuredBaseUrl: configuredBaseUrl,
    isAndroid: isAndroid,
    isReleaseMode: isReleaseMode,
    isDebugMode: kDebugMode,
  );
}

@visibleForTesting
Uri stationApiBaseUriForBuildMode({
  required String configuredBaseUrl,
  required bool isAndroid,
  required bool isReleaseMode,
  required bool isDebugMode,
}) {
  final trimmedBaseUrl = configuredBaseUrl.trim();
  if (trimmedBaseUrl.isNotEmpty) {
    final baseUri = Uri.parse(trimmedBaseUrl);
    if (isReleaseMode && baseUri.scheme != 'https') {
      throw StateError('Release API base URL must use HTTPS.');
    }
    if (isReleaseMode && baseUri.host.isEmpty) {
      throw StateError('Release API base URL must include a host.');
    }
    return baseUri;
  }
  if (isReleaseMode) {
    throw StateError('Release API base URL must be configured.');
  }
  if (!isDebugMode) throw StateError(_debugApiBaseUriRequired);
  return Uri.parse(
    isAndroid ? 'http://10.0.2.2:8080' : 'http://127.0.0.1:8080',
  );
}
