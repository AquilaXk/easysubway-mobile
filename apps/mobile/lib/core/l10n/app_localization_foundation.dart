import 'package:flutter/material.dart';

/// 앱이 지원하는 표시 언어 로케일(`ko`, `en`).
enum SupportedAppLocale {
  ko(Locale('ko'), 'ko'),
  en(Locale('en'), 'en');

  const SupportedAppLocale(this.locale, this.languageCode);

  final Locale locale;
  final String languageCode;

  bool get isKorean => this == SupportedAppLocale.ko;
  bool get isEnglish => this == SupportedAppLocale.en;
}

/// 시스템 로케일 목록을 받아 지원 로케일(`ko`, `en`)을 선택하고
/// 나머지 언어는 제품 정책에 따라 `ko`로 결정론적으로 폴백하는 해석기.
abstract final class AppLocalePolicy {
  /// 비정상 대량 로케일 목록을 차단하기 위한 후보 수 상한.
  static const int maxLocaleCandidates = 64;

  static const SupportedAppLocale defaultFallbackLocale = SupportedAppLocale.ko;

  static const List<Locale> supportedLocales = <Locale>[
    Locale('ko'),
    Locale('en'),
  ];

  /// 기기 시스템 로케일 목록을 순서대로 순회해 첫 번째로 일치하는 `ko` 또는 `en`을 선택한다.
  /// 목록이 비어 있거나 일치하는 언어가 없으면 [defaultFallbackLocale](`ko`)을 반환한다.
  static SupportedAppLocale resolveSystemLocales(List<Locale>? systemLocales) {
    if (systemLocales == null || systemLocales.isEmpty) {
      return defaultFallbackLocale;
    }
    if (systemLocales.length > maxLocaleCandidates) {
      throw ArgumentError.value(
        systemLocales.length,
        'systemLocales',
        'Locale candidate list exceeds budget of $maxLocaleCandidates.',
      );
    }
    for (var i = 0; i < systemLocales.length; i++) {
      final code = systemLocales[i].languageCode.toLowerCase();
      if (code == 'ko') {
        return SupportedAppLocale.ko;
      }
      if (code == 'en') {
        return SupportedAppLocale.en;
      }
    }
    return defaultFallbackLocale;
  }

  /// 단일 [Locale]을 해석한다.
  static SupportedAppLocale resolveLocale(Locale? locale) {
    if (locale == null) {
      return defaultFallbackLocale;
    }
    return resolveSystemLocales(<Locale>[locale]);
  }

  /// `MaterialApp.localeListResolutionCallback`에 직접 연결할 수 있는 콜백.
  static Locale localeListResolutionCallback(
    List<Locale>? locales,
    Iterable<Locale> supportedLocales,
  ) => resolveSystemLocales(locales).locale;
}

/// 역 식별자 불변성을 유지한 채 로케일별 표시 역명과 스크린리더 읽기 라벨을 담는 값 객체.
@immutable
final class StationLocalizedIdentity {
  const StationLocalizedIdentity({
    required this.stationId,
    required this.displayName,
    required this.semanticsLabel,
    required this.resolvedLocale,
    required this.usedOfficialEnglishName,
  });

  final String stationId;
  final String displayName;
  final String semanticsLabel;
  final SupportedAppLocale resolvedLocale;
  final bool usedOfficialEnglishName;
}

/// 공공 철도 카탈로그의 국문·공식 영문 역명을 로케일에 따라 해석한다.
///
/// 영문 역명이 비어 있거나 임의 음차(`isFabricatedRomanization: true`)이면
/// 영문 표기를 지어내지 않고 공식 국문 역명을 그대로 유지한다.
abstract final class OfficialStationDisplayNamePolicy {
  static const int maxStationIdLength = 128;
  static const int maxStationNameLength = 256;

  static StationLocalizedIdentity resolve({
    required String stationId,
    required String koreanName,
    String? officialEnglishName,
    required SupportedAppLocale locale,
    bool isFabricatedRomanization = false,
  }) {
    _validateBoundedCleanText(
      stationId,
      fieldName: 'stationId',
      maxLength: maxStationIdLength,
    );
    _validateBoundedCleanText(
      koreanName,
      fieldName: 'koreanName',
      maxLength: maxStationNameLength,
    );
    if (officialEnglishName != null) {
      if (officialEnglishName.length > maxStationNameLength ||
          _containsControlChars(officialEnglishName)) {
        throw ArgumentError.value(
          officialEnglishName,
          'officialEnglishName',
          'Station English name exceeds length budget or contains control characters.',
        );
      }
    }

    final cleanKorean = koreanName.trim();
    if (locale == SupportedAppLocale.ko) {
      return StationLocalizedIdentity(
        stationId: stationId,
        displayName: cleanKorean,
        semanticsLabel: _koreanStationSemantics(cleanKorean),
        resolvedLocale: locale,
        usedOfficialEnglishName: false,
      );
    }

    final cleanEnglish = officialEnglishName?.trim() ?? '';
    final canUseOfficialEnglish =
        !isFabricatedRomanization &&
        cleanEnglish.isNotEmpty &&
        _containsAsciiLetter(cleanEnglish);

    if (canUseOfficialEnglish) {
      return StationLocalizedIdentity(
        stationId: stationId,
        displayName: cleanEnglish,
        semanticsLabel: _englishStationSemantics(cleanEnglish),
        resolvedLocale: locale,
        usedOfficialEnglishName: true,
      );
    }

    return StationLocalizedIdentity(
      stationId: stationId,
      displayName: cleanKorean,
      semanticsLabel: _koreanStationSemantics(cleanKorean),
      resolvedLocale: locale,
      usedOfficialEnglishName: false,
    );
  }

  static String _koreanStationSemantics(String name) =>
      name.endsWith('역') ? name : '$name역';

  static String _englishStationSemantics(String name) =>
      name.toLowerCase().endsWith('station') ? name : '$name Station';

  static void _validateBoundedCleanText(
    String value, {
    required String fieldName,
    required int maxLength,
  }) {
    final trimmed = value.trim();
    if (trimmed.isEmpty ||
        value.length > maxLength ||
        _containsControlChars(value)) {
      throw ArgumentError.value(
        value,
        fieldName,
        '$fieldName must be non-empty, within $maxLength chars, and free of control characters.',
      );
    }
  }

  static bool _containsControlChars(String value) {
    for (var i = 0; i < value.length; i++) {
      final unit = value.codeUnitAt(i);
      if (unit <= 0x1F || unit == 0x7F) {
        return true;
      }
    }
    return false;
  }

  static bool _containsAsciiLetter(String value) {
    for (var i = 0; i < value.length; i++) {
      final unit = value.codeUnitAt(i);
      if ((unit >= 0x41 && unit <= 0x5A) || (unit >= 0x61 && unit <= 0x7A)) {
        return true;
      }
    }
    return false;
  }
}

/// 앱 크롬 및 길찾기 오류 복구 행동 종류.
enum JourneyV3AppAction {
  retry,
  changeStations,
  editMobilityProfile,
  close,
  searchRoute,
}

/// 로케일별 행동 버튼 라벨과 스크린리더 시맨틱 라벨.
@immutable
final class JourneyV3LocalizedActionEntry {
  const JourneyV3LocalizedActionEntry({
    required this.action,
    required this.locale,
    required this.label,
    required this.semanticsLabel,
  });

  final JourneyV3AppAction action;
  final SupportedAppLocale locale;
  final String label;
  final String semanticsLabel;
}

/// Journey V3 오류 코드에 대한 로케일별 안내 문구 및 처분 규격.
@immutable
final class JourneyV3LocalizedErrorEntry {
  const JourneyV3LocalizedErrorEntry({
    required this.code,
    required this.locale,
    required this.retryable,
    required this.correctiveActionRequired,
    required this.primaryAction,
    required this.title,
    required this.guidance,
    required this.actionLabel,
    required this.semanticsLabel,
  }) : fallbackAllowed = false;

  final String code;
  final SupportedAppLocale locale;
  final bool retryable;
  final bool correctiveActionRequired;
  final bool fallbackAllowed;
  final JourneyV3AppAction primaryAction;
  final String title;
  final String guidance;
  final String actionLabel;
  final String semanticsLabel;
}

/// Journey V3 오류·행동(Action) 한·영 1:1 패리티 카탈로그.
abstract final class JourneyV3LocalizedCatalog {
  static const int maxErrorCodeLength = 64;

  static const List<String> supportedErrorCodes = <String>[
    'INVALID_REQUEST',
    'ROUTE_SCOPE_INVALID',
    'NO_ROUTE_FOUND',
    'SERVICE_ENDED',
    'ARTIFACT_UNAVAILABLE',
    'NETWORK_TIMEOUT',
    'UPGRADE_REQUIRED',
    'UNKNOWN_FAILURE',
  ];

  static const Map<JourneyV3AppAction, JourneyV3LocalizedActionEntry>
  _koActions = <JourneyV3AppAction, JourneyV3LocalizedActionEntry>{
    JourneyV3AppAction.retry: JourneyV3LocalizedActionEntry(
      action: JourneyV3AppAction.retry,
      locale: SupportedAppLocale.ko,
      label: '다시 시도',
      semanticsLabel: '다시 시도 버튼',
    ),
    JourneyV3AppAction.changeStations: JourneyV3LocalizedActionEntry(
      action: JourneyV3AppAction.changeStations,
      locale: SupportedAppLocale.ko,
      label: '출발·도착역 다시 선택',
      semanticsLabel: '출발역과 도착역 다시 선택 버튼',
    ),
    JourneyV3AppAction.editMobilityProfile: JourneyV3LocalizedActionEntry(
      action: JourneyV3AppAction.editMobilityProfile,
      locale: SupportedAppLocale.ko,
      label: '이동 조건 바꾸기',
      semanticsLabel: '이동 조건 바꾸기 버튼',
    ),
    JourneyV3AppAction.close: JourneyV3LocalizedActionEntry(
      action: JourneyV3AppAction.close,
      locale: SupportedAppLocale.ko,
      label: '닫기',
      semanticsLabel: '닫기 버튼',
    ),
    JourneyV3AppAction.searchRoute: JourneyV3LocalizedActionEntry(
      action: JourneyV3AppAction.searchRoute,
      locale: SupportedAppLocale.ko,
      label: '경로 찾기',
      semanticsLabel: '경로 찾기 버튼',
    ),
  };

  static const Map<JourneyV3AppAction, JourneyV3LocalizedActionEntry>
  _enActions = <JourneyV3AppAction, JourneyV3LocalizedActionEntry>{
    JourneyV3AppAction.retry: JourneyV3LocalizedActionEntry(
      action: JourneyV3AppAction.retry,
      locale: SupportedAppLocale.en,
      label: 'Try again',
      semanticsLabel: 'Try again button',
    ),
    JourneyV3AppAction.changeStations: JourneyV3LocalizedActionEntry(
      action: JourneyV3AppAction.changeStations,
      locale: SupportedAppLocale.en,
      label: 'Change stations',
      semanticsLabel: 'Change origin and destination stations button',
    ),
    JourneyV3AppAction.editMobilityProfile: JourneyV3LocalizedActionEntry(
      action: JourneyV3AppAction.editMobilityProfile,
      locale: SupportedAppLocale.en,
      label: 'Change mobility options',
      semanticsLabel: 'Change mobility options button',
    ),
    JourneyV3AppAction.close: JourneyV3LocalizedActionEntry(
      action: JourneyV3AppAction.close,
      locale: SupportedAppLocale.en,
      label: 'Close',
      semanticsLabel: 'Close button',
    ),
    JourneyV3AppAction.searchRoute: JourneyV3LocalizedActionEntry(
      action: JourneyV3AppAction.searchRoute,
      locale: SupportedAppLocale.en,
      label: 'Find route',
      semanticsLabel: 'Find route button',
    ),
  };

  static const Map<String, JourneyV3LocalizedErrorEntry>
  _koErrors = <String, JourneyV3LocalizedErrorEntry>{
    'INVALID_REQUEST': JourneyV3LocalizedErrorEntry(
      code: 'INVALID_REQUEST',
      locale: SupportedAppLocale.ko,
      retryable: false,
      correctiveActionRequired: true,
      primaryAction: JourneyV3AppAction.changeStations,
      title: '출발역과 도착역을 다시 살펴봐 주세요',
      guidance: '같은 역을 골랐거나 입력 조건이 맞지 않아요. 역을 다시 고른 뒤 찾아 주세요.',
      actionLabel: '출발·도착역 다시 선택',
      semanticsLabel:
          '출발역과 도착역을 다시 살펴봐 주세요. 같은 역을 골랐거나 입력 조건이 맞지 않아요. 역을 다시 고른 뒤 찾아 주세요.',
    ),
    'ROUTE_SCOPE_INVALID': JourneyV3LocalizedErrorEntry(
      code: 'ROUTE_SCOPE_INVALID',
      locale: SupportedAppLocale.ko,
      retryable: false,
      correctiveActionRequired: true,
      primaryAction: JourneyV3AppAction.changeStations,
      title: '열차로 이어지는 경로를 찾기 어려운 구간이에요',
      guidance: '출발역과 도착역이 같은 도시철도·광역철도 권역에 있는지 살펴봐 주세요.',
      actionLabel: '출발·도착역 다시 선택',
      semanticsLabel:
          '열차로 이어지는 경로를 찾기 어려운 구간이에요. 출발역과 도착역이 같은 도시철도·광역철도 권역에 있는지 살펴봐 주세요.',
    ),
    'NO_ROUTE_FOUND': JourneyV3LocalizedErrorEntry(
      code: 'NO_ROUTE_FOUND',
      locale: SupportedAppLocale.ko,
      retryable: false,
      correctiveActionRequired: true,
      primaryAction: JourneyV3AppAction.editMobilityProfile,
      title: '조건에 맞는 경로를 찾지 못했어요',
      guidance: '출발 시각이나 이동 조건을 바꾸어 다시 찾아 보세요.',
      actionLabel: '이동 조건 바꾸기',
      semanticsLabel: '조건에 맞는 경로를 찾지 못했어요. 출발 시각이나 이동 조건을 바꾸어 다시 찾아 보세요.',
    ),
    'SERVICE_ENDED': JourneyV3LocalizedErrorEntry(
      code: 'SERVICE_ENDED',
      locale: SupportedAppLocale.ko,
      retryable: false,
      correctiveActionRequired: true,
      primaryAction: JourneyV3AppAction.changeStations,
      title: '선택한 시각에는 열차 운행이 끝났어요',
      guidance: '첫차 이후 시각으로 바꾸거나 다른 출발 시각을 골라 주세요.',
      actionLabel: '출발·도착역 다시 선택',
      semanticsLabel: '선택한 시각에는 열차 운행이 끝났어요. 첫차 이후 시각으로 바꾸거나 다른 출발 시각을 골라 주세요.',
    ),
    'ARTIFACT_UNAVAILABLE': JourneyV3LocalizedErrorEntry(
      code: 'ARTIFACT_UNAVAILABLE',
      locale: SupportedAppLocale.ko,
      retryable: true,
      correctiveActionRequired: false,
      primaryAction: JourneyV3AppAction.retry,
      title: '운행 시간표 자료를 지금 불러올 수 없어요',
      guidance: '잠시 후 다시 시도해 주세요.',
      actionLabel: '다시 시도',
      semanticsLabel: '운행 시간표 자료를 지금 불러올 수 없어요. 잠시 후 다시 시도해 주세요.',
    ),
    'NETWORK_TIMEOUT': JourneyV3LocalizedErrorEntry(
      code: 'NETWORK_TIMEOUT',
      locale: SupportedAppLocale.ko,
      retryable: true,
      correctiveActionRequired: false,
      primaryAction: JourneyV3AppAction.retry,
      title: '연결 시간이 지연되고 있어요',
      guidance: '네트워크 연결 상태를 살펴본 뒤 다시 시도해 주세요.',
      actionLabel: '다시 시도',
      semanticsLabel: '연결 시간이 지연되고 있어요. 네트워크 연결 상태를 살펴본 뒤 다시 시도해 주세요.',
    ),
    'UPGRADE_REQUIRED': JourneyV3LocalizedErrorEntry(
      code: 'UPGRADE_REQUIRED',
      locale: SupportedAppLocale.ko,
      retryable: false,
      correctiveActionRequired: true,
      primaryAction: JourneyV3AppAction.close,
      title: '앱을 최신 버전으로 업데이트해 주세요',
      guidance: '스토어에서 최신 버전으로 업데이트하면 길찾기를 계속 이용할 수 있어요.',
      actionLabel: '닫기',
      semanticsLabel:
          '앱을 최신 버전으로 업데이트해 주세요. 스토어에서 최신 버전으로 업데이트하면 길찾기를 계속 이용할 수 있어요.',
    ),
    'UNKNOWN_FAILURE': JourneyV3LocalizedErrorEntry(
      code: 'UNKNOWN_FAILURE',
      locale: SupportedAppLocale.ko,
      retryable: true,
      correctiveActionRequired: false,
      primaryAction: JourneyV3AppAction.retry,
      title: '경로를 찾지 못했어요',
      guidance: '일시적인 문제가 생겼어요. 잠시 후 다시 시도해 주세요.',
      actionLabel: '다시 시도',
      semanticsLabel: '경로를 찾지 못했어요. 일시적인 문제가 생겼어요. 잠시 후 다시 시도해 주세요.',
    ),
  };

  static const Map<String, JourneyV3LocalizedErrorEntry>
  _enErrors = <String, JourneyV3LocalizedErrorEntry>{
    'INVALID_REQUEST': JourneyV3LocalizedErrorEntry(
      code: 'INVALID_REQUEST',
      locale: SupportedAppLocale.en,
      retryable: false,
      correctiveActionRequired: true,
      primaryAction: JourneyV3AppAction.changeStations,
      title: 'Check your origin and destination',
      guidance:
          'The selected stations or search options are not valid. Please choose the stations again.',
      actionLabel: 'Change stations',
      semanticsLabel:
          'Check your origin and destination. The selected stations or search options are not valid. Please choose the stations again.',
    ),
    'ROUTE_SCOPE_INVALID': JourneyV3LocalizedErrorEntry(
      code: 'ROUTE_SCOPE_INVALID',
      locale: SupportedAppLocale.en,
      retryable: false,
      correctiveActionRequired: true,
      primaryAction: JourneyV3AppAction.changeStations,
      title: 'Stations are outside the connected rail network',
      guidance:
          'Please check whether the origin and destination are within a connected rail region.',
      actionLabel: 'Change stations',
      semanticsLabel:
          'Stations are outside the connected rail network. Please check whether the origin and destination are within a connected rail region.',
    ),
    'NO_ROUTE_FOUND': JourneyV3LocalizedErrorEntry(
      code: 'NO_ROUTE_FOUND',
      locale: SupportedAppLocale.en,
      retryable: false,
      correctiveActionRequired: true,
      primaryAction: JourneyV3AppAction.editMobilityProfile,
      title: 'No matching route found',
      guidance:
          'Try changing the departure time or mobility options and search again.',
      actionLabel: 'Change mobility options',
      semanticsLabel:
          'No matching route found. Try changing the departure time or mobility options and search again.',
    ),
    'SERVICE_ENDED': JourneyV3LocalizedErrorEntry(
      code: 'SERVICE_ENDED',
      locale: SupportedAppLocale.en,
      retryable: false,
      correctiveActionRequired: true,
      primaryAction: JourneyV3AppAction.changeStations,
      title: 'Train service has ended for the selected time',
      guidance: 'Please select a departure time after the first train.',
      actionLabel: 'Change stations',
      semanticsLabel:
          'Train service has ended for the selected time. Please select a departure time after the first train.',
    ),
    'ARTIFACT_UNAVAILABLE': JourneyV3LocalizedErrorEntry(
      code: 'ARTIFACT_UNAVAILABLE',
      locale: SupportedAppLocale.en,
      retryable: true,
      correctiveActionRequired: false,
      primaryAction: JourneyV3AppAction.retry,
      title: 'Timetable data is temporarily unavailable',
      guidance: 'Please try again in a moment.',
      actionLabel: 'Try again',
      semanticsLabel:
          'Timetable data is temporarily unavailable. Please try again in a moment.',
    ),
    'NETWORK_TIMEOUT': JourneyV3LocalizedErrorEntry(
      code: 'NETWORK_TIMEOUT',
      locale: SupportedAppLocale.en,
      retryable: true,
      correctiveActionRequired: false,
      primaryAction: JourneyV3AppAction.retry,
      title: 'The connection timed out',
      guidance: 'Please check your network connection and try again.',
      actionLabel: 'Try again',
      semanticsLabel:
          'The connection timed out. Please check your network connection and try again.',
    ),
    'UPGRADE_REQUIRED': JourneyV3LocalizedErrorEntry(
      code: 'UPGRADE_REQUIRED',
      locale: SupportedAppLocale.en,
      retryable: false,
      correctiveActionRequired: true,
      primaryAction: JourneyV3AppAction.close,
      title: 'Please update the app to the latest version',
      guidance: 'Update the app from the store to continue using route search.',
      actionLabel: 'Close',
      semanticsLabel:
          'Please update the app to the latest version. Update the app from the store to continue using route search.',
    ),
    'UNKNOWN_FAILURE': JourneyV3LocalizedErrorEntry(
      code: 'UNKNOWN_FAILURE',
      locale: SupportedAppLocale.en,
      retryable: true,
      correctiveActionRequired: false,
      primaryAction: JourneyV3AppAction.retry,
      title: 'Unable to find a route',
      guidance: 'A temporary problem occurred. Please try again shortly.',
      actionLabel: 'Try again',
      semanticsLabel:
          'Unable to find a route. A temporary problem occurred. Please try again shortly.',
    ),
  };

  static JourneyV3LocalizedActionEntry actionEntry(
    JourneyV3AppAction action, {
    required SupportedAppLocale locale,
  }) => switch (locale) {
    SupportedAppLocale.ko => _koActions[action]!,
    SupportedAppLocale.en => _enActions[action]!,
  };

  /// 오류 코드를 로케일별 안내 문구로 매핑한다.
  ///
  /// [rawBackendMessage]가 함께 전달되더라도 사용자 문구나 시맨틱 라벨에는
  /// 절대 포함하지 않으며, 미등록 코드는 `UNKNOWN_FAILURE`로 안전하게 매핑한다.
  static JourneyV3LocalizedErrorEntry resolveError(
    String? rawErrorCode, {
    required SupportedAppLocale locale,
    String? rawBackendMessage,
  }) {
    final table = switch (locale) {
      SupportedAppLocale.ko => _koErrors,
      SupportedAppLocale.en => _enErrors,
    };
    if (rawErrorCode == null) {
      return table['UNKNOWN_FAILURE']!;
    }
    final normalized = rawErrorCode.trim();
    if (normalized.isEmpty || normalized.length > maxErrorCodeLength) {
      return table['UNKNOWN_FAILURE']!;
    }
    return table[normalized] ?? table['UNKNOWN_FAILURE']!;
  }
}

/// 로케일에 맞춰 포맷된 시각적 표시 문자열과 스크린리더 시맨틱 문자열 쌍.
@immutable
final class LocalizedFormattedValue {
  const LocalizedFormattedValue({
    required this.visualText,
    required this.semanticsLabel,
    required this.locale,
  });

  final String visualText;
  final String semanticsLabel;
  final SupportedAppLocale locale;
}

/// 시간·소요시간·거리·요금을 로케일에 맞게 결정론적으로 포맷하는 도구.
///
/// 누락(`null`)·음수·상한 초과 입력은 `0`이나 더미 문자열로 합성하지 않고
/// 명시적으로 `null`을 반환한다.
abstract final class LocaleValueFormatter {
  static const int maxDurationMinutes = 14400;
  static const int maxDistanceMeters = 1000000;
  static const int maxFareWon = 10000000;

  static LocalizedFormattedValue? formatDurationMinutes(
    int? minutes, {
    required SupportedAppLocale locale,
  }) {
    if (minutes == null || minutes < 0 || minutes > maxDurationMinutes) {
      return null;
    }
    final hours = minutes ~/ 60;
    final rest = minutes % 60;

    if (locale == SupportedAppLocale.ko) {
      final body = switch ((hours, rest)) {
        (0, final m) => '$m분',
        (final h, 0) => '$h시간',
        (final h, final m) => '$h시간 $m분',
      };
      return LocalizedFormattedValue(
        visualText: body,
        semanticsLabel: '소요 시간 $body',
        locale: locale,
      );
    }

    final visual = switch ((hours, rest)) {
      (0, final m) => '$m min',
      (final h, 0) => '$h hr',
      (final h, final m) => '$h hr $m min',
    };
    final spoken = switch ((hours, rest)) {
      (0, final m) => 'Duration $m ${m == 1 ? 'minute' : 'minutes'}',
      (final h, 0) => 'Duration $h ${h == 1 ? 'hour' : 'hours'}',
      (final h, final m) =>
        'Duration $h ${h == 1 ? 'hour' : 'hours'} $m ${m == 1 ? 'minute' : 'minutes'}',
    };
    return LocalizedFormattedValue(
      visualText: visual,
      semanticsLabel: spoken,
      locale: locale,
    );
  }

  static LocalizedFormattedValue? formatDistanceMeters(
    int? meters, {
    required SupportedAppLocale locale,
  }) {
    if (meters == null || meters < 0 || meters > maxDistanceMeters) {
      return null;
    }
    final grouped = _groupThousands(meters);
    if (locale == SupportedAppLocale.ko) {
      return LocalizedFormattedValue(
        visualText: '${grouped}m',
        semanticsLabel: '이동 거리 $grouped미터',
        locale: locale,
      );
    }
    final unit = meters == 1 ? 'meter' : 'meters';
    return LocalizedFormattedValue(
      visualText: '$grouped m',
      semanticsLabel: 'Walking distance $grouped $unit',
      locale: locale,
    );
  }

  static LocalizedFormattedValue? formatFareWon(
    int? won, {
    required SupportedAppLocale locale,
  }) {
    if (won == null || won < 0 || won > maxFareWon) {
      return null;
    }
    final grouped = _groupThousands(won);
    if (locale == SupportedAppLocale.ko) {
      return LocalizedFormattedValue(
        visualText: '$grouped원',
        semanticsLabel: '요금 $grouped원',
        locale: locale,
      );
    }
    return LocalizedFormattedValue(
      visualText: 'KRW $grouped',
      semanticsLabel: 'Fare $grouped Korean won',
      locale: locale,
    );
  }

  static LocalizedFormattedValue? formatWallClockTime({
    required int? hour,
    required int? minute,
    required SupportedAppLocale locale,
  }) {
    if (hour == null ||
        minute == null ||
        hour < 0 ||
        hour > 23 ||
        minute < 0 ||
        minute > 59) {
      return null;
    }
    final twelveHour = hour % 12 == 0 ? 12 : hour % 12;
    final paddedMinute = minute < 10 ? '0$minute' : '$minute';
    if (locale == SupportedAppLocale.ko) {
      final period = hour < 12 ? '오전' : '오후';
      return LocalizedFormattedValue(
        visualText: '$period $twelveHour:$paddedMinute',
        semanticsLabel: '$period $twelveHour시 $minute분',
        locale: locale,
      );
    }
    final period = hour < 12 ? 'AM' : 'PM';
    final text = '$twelveHour:$paddedMinute $period';
    return LocalizedFormattedValue(
      visualText: text,
      semanticsLabel: text,
      locale: locale,
    );
  }

  static String _groupThousands(int value) {
    final digits = value.toString();
    if (digits.length <= 3) {
      return digits;
    }
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) {
        buffer.write(',');
      }
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }
}

/// 큰 글자(200%) 및 좁은 화면(320dp)에서도 줄바꿈으로 잘림 없이 역명을 그리는 타일.
class LocalizedStationReadingTile extends StatelessWidget {
  const LocalizedStationReadingTile({required this.identity, super.key});

  final StationLocalizedIdentity identity;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: identity.semanticsLabel,
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(identity.displayName, softWrap: true),
          ),
        ),
      ),
    );
  }
}

/// 로케일별 Journey V3 오류 안내와 복구 행동 버튼을 표시하는 배너.
class LocalizedJourneyErrorBanner extends StatelessWidget {
  const LocalizedJourneyErrorBanner({
    required this.entry,
    required this.onActionPressed,
    super.key,
  });

  final JourneyV3LocalizedErrorEntry entry;
  final VoidCallback? onActionPressed;

  @override
  Widget build(BuildContext context) {
    final actionSemantics = JourneyV3LocalizedCatalog.actionEntry(
      entry.primaryAction,
      locale: entry.locale,
    ).semanticsLabel;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            container: true,
            label: entry.semanticsLabel,
            excludeSemantics: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(entry.title, softWrap: true),
                const SizedBox(height: 4),
                Text(entry.guidance, softWrap: true),
              ],
            ),
          ),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Semantics(
              button: true,
              label: actionSemantics,
              excludeSemantics: true,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                ),
                onPressed: onActionPressed,
                child: Text(
                  entry.actionLabel,
                  textAlign: TextAlign.center,
                  softWrap: true,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
