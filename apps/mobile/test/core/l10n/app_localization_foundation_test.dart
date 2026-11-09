import 'package:easysubway_mobile/core/l10n/app_localization_foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../user_copy_guard.dart';

void main() {
  group('AppLocalePolicy 시스템 로케일 해석 및 결정론적 폴백', () {
    test('지원 로케일은 ko와 en 두 가지이며 순서가 고정된다', () {
      expect(AppLocalePolicy.supportedLocales, const [
        Locale('ko'),
        Locale('en'),
      ]);
      expect(SupportedAppLocale.ko.locale, const Locale('ko'));
      expect(SupportedAppLocale.en.locale, const Locale('en'));
      expect(SupportedAppLocale.ko.isKorean, isTrue);
      expect(SupportedAppLocale.en.isEnglish, isTrue);
    });

    test('시스템 로케일 목록에서 첫 번째로 일치하는 ko 또는 en을 선택한다', () {
      expect(
        AppLocalePolicy.resolveSystemLocales(const [
          Locale('en', 'US'),
          Locale('ko', 'KR'),
        ]),
        SupportedAppLocale.en,
      );
      expect(
        AppLocalePolicy.resolveSystemLocales(const [
          Locale('ko', 'KR'),
          Locale('en', 'US'),
        ]),
        SupportedAppLocale.ko,
      );
      expect(
        AppLocalePolicy.resolveSystemLocales(const [
          Locale('ja', 'JP'),
          Locale('en', 'GB'),
          Locale('ko', 'KR'),
        ]),
        SupportedAppLocale.en,
      );
    });

    test('미지원 로케일만 있거나 빈 목록·null이면 결정론적으로 ko로 폴백한다', () {
      expect(AppLocalePolicy.resolveSystemLocales(null), SupportedAppLocale.ko);
      expect(
        AppLocalePolicy.resolveSystemLocales(const []),
        SupportedAppLocale.ko,
      );
      expect(
        AppLocalePolicy.resolveSystemLocales(const [
          Locale('ja', 'JP'),
          Locale('zh', 'TW'),
          Locale('fr', 'FR'),
        ]),
        SupportedAppLocale.ko,
      );
      expect(AppLocalePolicy.resolveLocale(null), SupportedAppLocale.ko);
      expect(
        AppLocalePolicy.resolveLocale(const Locale('de', 'DE')),
        SupportedAppLocale.ko,
      );
      expect(
        AppLocalePolicy.localeListResolutionCallback(const [
          Locale('es', 'ES'),
          Locale('en', 'CA'),
        ], AppLocalePolicy.supportedLocales),
        const Locale('en'),
      );
    });

    test('로케일 후보 목록이 상한(64개)을 초과하면 Fail-Closed로 거부한다', () {
      final oversized = List<Locale>.filled(
        AppLocalePolicy.maxLocaleCandidates + 1,
        const Locale('en'),
      );
      expect(
        () => AppLocalePolicy.resolveSystemLocales(oversized),
        throwsArgumentError,
      );
    });
  });

  group('OfficialStationDisplayNamePolicy 공식 역명 영문/국문 표기 해석', () {
    test('ko 로케일에서는 공식 영문 역명이 있어도 항상 공식 국문 역명을 반환한다', () {
      final resolved = OfficialStationDisplayNamePolicy.resolve(
        stationId: 'st_seoul_0222',
        koreanName: '강남',
        officialEnglishName: 'Gangnam',
        locale: SupportedAppLocale.ko,
      );

      expect(resolved.stationId, 'st_seoul_0222');
      expect(resolved.displayName, '강남');
      expect(resolved.usedOfficialEnglishName, isFalse);
      expect(resolved.semanticsLabel, '강남역');
    });

    test('en 로케일에서는 검증된 공식 영문 역명이 있을 때만 영문 역명을 반환한다', () {
      final resolved = OfficialStationDisplayNamePolicy.resolve(
        stationId: 'st_seoul_0222',
        koreanName: '강남',
        officialEnglishName: 'Gangnam',
        locale: SupportedAppLocale.en,
      );

      expect(resolved.stationId, 'st_seoul_0222');
      expect(resolved.displayName, 'Gangnam');
      expect(resolved.usedOfficialEnglishName, isTrue);
      expect(resolved.semanticsLabel, 'Gangnam Station');
    });

    test('en 로케일에서 공식 영문 역명이 없거나 빈 문자열·추정 로마자이면 국문 역명을 그대로 유지한다', () {
      final missingEnglish = OfficialStationDisplayNamePolicy.resolve(
        stationId: 'st_seoul_9901',
        koreanName: '청량리',
        officialEnglishName: null,
        locale: SupportedAppLocale.en,
      );
      final blankEnglish = OfficialStationDisplayNamePolicy.resolve(
        stationId: 'st_seoul_9901',
        koreanName: '청량리',
        officialEnglishName: '   ',
        locale: SupportedAppLocale.en,
      );
      final fabricatedRomanization = OfficialStationDisplayNamePolicy.resolve(
        stationId: 'st_seoul_9901',
        koreanName: '청량리',
        officialEnglishName: 'Cheongnyangni-guessed',
        locale: SupportedAppLocale.en,
        isFabricatedRomanization: true,
      );

      expect(missingEnglish.displayName, '청량리');
      expect(missingEnglish.usedOfficialEnglishName, isFalse);
      expect(blankEnglish.displayName, '청량리');
      expect(blankEnglish.usedOfficialEnglishName, isFalse);
      expect(fabricatedRomanization.displayName, '청량리');
      expect(fabricatedRomanization.usedOfficialEnglishName, isFalse);
    });

    test('로케일이 바뀌어도 역 선택 식별자(stationId)는 절대 변하지 않는다', () {
      const stationId = 'KRIC:SEOUL:LINE2:0222';
      final koIdentity = OfficialStationDisplayNamePolicy.resolve(
        stationId: stationId,
        koreanName: '강남',
        officialEnglishName: 'Gangnam',
        locale: SupportedAppLocale.ko,
      );
      final enIdentity = OfficialStationDisplayNamePolicy.resolve(
        stationId: stationId,
        koreanName: '강남',
        officialEnglishName: 'Gangnam',
        locale: SupportedAppLocale.en,
      );

      expect(koIdentity.stationId, stationId);
      expect(enIdentity.stationId, stationId);
      expect(koIdentity.stationId, equals(enIdentity.stationId));
    });

    test('비어 있거나 제어문자·길이 상한을 넘는 역 식별자/역명은 Fail-Closed로 거부한다', () {
      expect(
        () => OfficialStationDisplayNamePolicy.resolve(
          stationId: '',
          koreanName: '강남',
          locale: SupportedAppLocale.ko,
        ),
        throwsArgumentError,
      );
      expect(
        () => OfficialStationDisplayNamePolicy.resolve(
          stationId: 'st_1',
          koreanName: '   ',
          locale: SupportedAppLocale.ko,
        ),
        throwsArgumentError,
      );
      expect(
        () => OfficialStationDisplayNamePolicy.resolve(
          stationId: 'st_1\u0000',
          koreanName: '강남',
          locale: SupportedAppLocale.ko,
        ),
        throwsArgumentError,
      );
      expect(
        () => OfficialStationDisplayNamePolicy.resolve(
          stationId:
              'a' * (OfficialStationDisplayNamePolicy.maxStationIdLength + 1),
          koreanName: '강남',
          locale: SupportedAppLocale.ko,
        ),
        throwsArgumentError,
      );
    });
  });

  group('JourneyV3LocalizedCatalog 한·영 1:1 패리티 및 원시 서버 메시지 차단', () {
    test('8개 핵심 오류 처분 코드가 ko와 en에서 동일한 처분 카테고리와 비어 있지 않은 문구를 갖는다', () {
      const expectedCodes = <String>[
        'INVALID_REQUEST',
        'ROUTE_SCOPE_INVALID',
        'NO_ROUTE_FOUND',
        'SERVICE_ENDED',
        'ARTIFACT_UNAVAILABLE',
        'NETWORK_TIMEOUT',
        'UPGRADE_REQUIRED',
        'UNKNOWN_FAILURE',
      ];

      expect(JourneyV3LocalizedCatalog.supportedErrorCodes, expectedCodes);

      for (final code in expectedCodes) {
        final koEntry = JourneyV3LocalizedCatalog.resolveError(
          code,
          locale: SupportedAppLocale.ko,
        );
        final enEntry = JourneyV3LocalizedCatalog.resolveError(
          code,
          locale: SupportedAppLocale.en,
        );

        expect(koEntry.code, code);
        expect(enEntry.code, code);
        expect(koEntry.retryable, enEntry.retryable, reason: '$code retryable');
        expect(
          koEntry.correctiveActionRequired,
          enEntry.correctiveActionRequired,
          reason: '$code correctiveActionRequired',
        );
        expect(koEntry.fallbackAllowed, isFalse, reason: '$code ko fallback');
        expect(enEntry.fallbackAllowed, isFalse, reason: '$code en fallback');
        expect(koEntry.primaryAction, enEntry.primaryAction);
        expect(koEntry.title.trim(), isNotEmpty);
        expect(enEntry.title.trim(), isNotEmpty);
        expect(koEntry.guidance.trim(), isNotEmpty);
        expect(enEntry.guidance.trim(), isNotEmpty);
        expect(koEntry.actionLabel.trim(), isNotEmpty);
        expect(enEntry.actionLabel.trim(), isNotEmpty);
        expect(koEntry.semanticsLabel, contains(koEntry.title));
        expect(enEntry.semanticsLabel, contains(enEntry.title));
      }
    });

    test('5개 앱 크롬 액션이 ko와 en 모두에서 비어 있지 않은 라벨과 시맨틱 라벨을 제공한다', () {
      for (final action in JourneyV3AppAction.values) {
        final koAction = JourneyV3LocalizedCatalog.actionEntry(
          action,
          locale: SupportedAppLocale.ko,
        );
        final enAction = JourneyV3LocalizedCatalog.actionEntry(
          action,
          locale: SupportedAppLocale.en,
        );

        expect(koAction.action, action);
        expect(enAction.action, action);
        expect(koAction.label.trim(), isNotEmpty);
        expect(enAction.label.trim(), isNotEmpty);
        expect(koAction.semanticsLabel.trim(), isNotEmpty);
        expect(enAction.semanticsLabel.trim(), isNotEmpty);
        expect(koAction.label, isNot(equals(enAction.label)));
      }
    });

    test('알 수 없는 오류 코드나 원시 백엔드 예외 메시지는 노출하지 않고 UNKNOWN_FAILURE로 매핑한다', () {
      const rawBackendSecret =
          'org.postgresql.util.PSQLException: FATAL: connection refused at 10.0.14.9:5432';

      final koFallback = JourneyV3LocalizedCatalog.resolveError(
        'INTERNAL_SQL_STACKTRACE_500',
        locale: SupportedAppLocale.ko,
        rawBackendMessage: rawBackendSecret,
      );
      final enFallback = JourneyV3LocalizedCatalog.resolveError(
        null,
        locale: SupportedAppLocale.en,
        rawBackendMessage: rawBackendSecret,
      );

      expect(koFallback.code, 'UNKNOWN_FAILURE');
      expect(enFallback.code, 'UNKNOWN_FAILURE');
      expect(koFallback.title, isNot(contains('PSQLException')));
      expect(koFallback.guidance, isNot(contains('10.0.14.9')));
      expect(koFallback.semanticsLabel, isNot(contains('PSQLException')));
      expect(enFallback.title, isNot(contains('PSQLException')));
      expect(enFallback.guidance, isNot(contains('10.0.14.9')));
      expect(enFallback.semanticsLabel, isNot(contains('PSQLException')));
    });
  });

  group('LocaleValueFormatter 시간·소요시간·거리·요금 결정론적 포맷 및 합성 금지', () {
    test('유효한 소요시간·거리·요금·시각을 ko와 en 포맷 및 시맨틱 라벨로 변환한다', () {
      final koDuration = LocaleValueFormatter.formatDurationMinutes(
        12,
        locale: SupportedAppLocale.ko,
      );
      final enDuration = LocaleValueFormatter.formatDurationMinutes(
        12,
        locale: SupportedAppLocale.en,
      );
      expect(koDuration?.visualText, '12분');
      expect(koDuration?.semanticsLabel, '소요 시간 12분');
      expect(enDuration?.visualText, '12 min');
      expect(enDuration?.semanticsLabel, 'Duration 12 minutes');

      final koDistance = LocaleValueFormatter.formatDistanceMeters(
        180,
        locale: SupportedAppLocale.ko,
      );
      final enDistance = LocaleValueFormatter.formatDistanceMeters(
        180,
        locale: SupportedAppLocale.en,
      );
      expect(koDistance?.visualText, '180m');
      expect(koDistance?.semanticsLabel, '이동 거리 180미터');
      expect(enDistance?.visualText, '180 m');
      expect(enDistance?.semanticsLabel, 'Walking distance 180 meters');

      final koFare = LocaleValueFormatter.formatFareWon(
        1400,
        locale: SupportedAppLocale.ko,
      );
      final enFare = LocaleValueFormatter.formatFareWon(
        1400,
        locale: SupportedAppLocale.en,
      );
      expect(koFare?.visualText, '1,400원');
      expect(koFare?.semanticsLabel, '요금 1,400원');
      expect(enFare?.visualText, 'KRW 1,400');
      expect(enFare?.semanticsLabel, 'Fare 1,400 Korean won');

      final koClock = LocaleValueFormatter.formatWallClockTime(
        hour: 14,
        minute: 5,
        locale: SupportedAppLocale.ko,
      );
      final enClock = LocaleValueFormatter.formatWallClockTime(
        hour: 14,
        minute: 5,
        locale: SupportedAppLocale.en,
      );
      expect(koClock?.visualText, '오후 2:05');
      expect(koClock?.semanticsLabel, '오후 2시 5분');
      expect(enClock?.visualText, '2:05 PM');
      expect(enClock?.semanticsLabel, '2:05 PM');
    });

    test('null·음수·상한 초과 입력은 0이나 더미 문자열로 합성하지 않고 null을 반환한다', () {
      expect(
        LocaleValueFormatter.formatDurationMinutes(
          null,
          locale: SupportedAppLocale.ko,
        ),
        isNull,
      );
      expect(
        LocaleValueFormatter.formatDurationMinutes(
          -1,
          locale: SupportedAppLocale.en,
        ),
        isNull,
      );
      expect(
        LocaleValueFormatter.formatDurationMinutes(
          LocaleValueFormatter.maxDurationMinutes + 1,
          locale: SupportedAppLocale.ko,
        ),
        isNull,
      );

      expect(
        LocaleValueFormatter.formatDistanceMeters(
          null,
          locale: SupportedAppLocale.en,
        ),
        isNull,
      );
      expect(
        LocaleValueFormatter.formatDistanceMeters(
          -50,
          locale: SupportedAppLocale.ko,
        ),
        isNull,
      );

      expect(
        LocaleValueFormatter.formatFareWon(null, locale: SupportedAppLocale.ko),
        isNull,
      );
      expect(
        LocaleValueFormatter.formatFareWon(-100, locale: SupportedAppLocale.en),
        isNull,
      );

      expect(
        LocaleValueFormatter.formatWallClockTime(
          hour: 24,
          minute: 0,
          locale: SupportedAppLocale.ko,
        ),
        isNull,
      );
      expect(
        LocaleValueFormatter.formatWallClockTime(
          hour: 9,
          minute: -1,
          locale: SupportedAppLocale.en,
        ),
        isNull,
      );
    });
  });

  group('320x640 컴팩트 폭 및 200% 큰 글자(TextScaler.linear(2.0)) 위젯·시맨틱 검증', () {
    for (final locale in SupportedAppLocale.values) {
      testWidgets(
        '${locale.languageCode} 로케일에서 역명 타일과 모든 오류 배너가 320x640·200% 글자 크기에서 오버플로 없이 그려지고 Semantics가 일치한다',
        (tester) async {
          final semanticsHandle = tester.ensureSemantics();
          try {
            tester.view.physicalSize = const Size(320, 640);
            tester.view.devicePixelRatio = 1.0;
            addTearDown(() {
              tester.view.resetPhysicalSize();
              tester.view.resetDevicePixelRatio();
            });

            final stationIdentity = OfficialStationDisplayNamePolicy.resolve(
              stationId: 'st_seoul_0222',
              koreanName: '동대문역사문화공원',
              officialEnglishName: 'Dongdaemun History & Culture Park',
              locale: locale,
            );
            final entries = [
              for (final code in JourneyV3LocalizedCatalog.supportedErrorCodes)
                JourneyV3LocalizedCatalog.resolveError(code, locale: locale),
            ];

            var actionTapCount = 0;

            await tester.pumpWidget(
              MaterialApp(
                locale: locale.locale,
                home: MediaQuery(
                  data: const MediaQueryData(
                    size: Size(320, 640),
                    textScaler: TextScaler.linear(2.0),
                  ),
                  child: Scaffold(
                    body: SingleChildScrollView(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          LocalizedStationReadingTile(
                            identity: stationIdentity,
                          ),
                          for (final entry in entries) ...[
                            const SizedBox(height: 8),
                            LocalizedJourneyErrorBanner(
                              entry: entry,
                              onActionPressed: () => actionTapCount++,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();

            expect(tester.takeException(), isNull);
            expectNoForbiddenUserCopy(tester);

            expect(find.text(stationIdentity.displayName), findsOneWidget);
            expect(
              tester.getSemantics(find.byType(LocalizedStationReadingTile)),
              matchesSemantics(label: stationIdentity.semanticsLabel),
            );

            final firstEntry = entries.first;
            expect(find.text(firstEntry.title), findsOneWidget);
            expect(find.text(firstEntry.guidance), findsOneWidget);

            final firstActionButton = find
                .descendant(
                  of: find.byType(LocalizedJourneyErrorBanner).first,
                  matching: find.byType(OutlinedButton),
                )
                .first;
            expect(
              tester.getSize(firstActionButton).height,
              greaterThanOrEqualTo(48),
            );
            await tester.ensureVisible(firstActionButton);
            await tester.pumpAndSettle();
            await tester.tap(firstActionButton);
            await tester.pump();
            expect(actionTapCount, 1);
          } finally {
            semanticsHandle.dispose();
          }
        },
      );
    }
  });
}
