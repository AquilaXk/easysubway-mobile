import 'package:easysubway_mobile/features/stations/data/station_api_base_uri.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('릴리즈 빌드는 API 기본 주소를 반드시 설정해야 한다', () {
    expect(
      () => stationApiBaseUriForEnvironment(
        configuredBaseUrl: '',
        isAndroid: true,
        isReleaseMode: true,
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('릴리즈 빌드는 주소가 없으면 optional helper에서만 null을 반환한다', () {
    expect(
      optionalStationApiBaseUriForEnvironment(
        configuredBaseUrl: '',
        isAndroid: true,
        isReleaseMode: true,
      ),
      isNull,
    );
  });

  test('릴리즈 빌드는 HTTPS와 호스트를 요구한다', () {
    expect(
      () => stationApiBaseUriForEnvironment(
        configuredBaseUrl: 'http://api.easysubway.example',
        isAndroid: false,
        isReleaseMode: true,
      ),
      throwsA(isA<StateError>()),
    );
    expect(
      () => stationApiBaseUriForEnvironment(
        configuredBaseUrl: 'https://',
        isAndroid: false,
        isReleaseMode: true,
      ),
      throwsA(isA<StateError>()),
    );
    expect(
      stationApiBaseUriForEnvironment(
        configuredBaseUrl: 'https://api.easysubway.example',
        isAndroid: false,
        isReleaseMode: true,
      ),
      Uri.parse('https://api.easysubway.example'),
    );
  });

  test('개발 빌드는 Android와 다른 플랫폼의 로컬 주소를 구분한다', () {
    expect(
      stationApiBaseUriForEnvironment(
        configuredBaseUrl: '',
        isAndroid: true,
        isReleaseMode: false,
      ),
      Uri.parse('http://10.0.2.2:8080'),
    );
    expect(
      stationApiBaseUriForEnvironment(
        configuredBaseUrl: '',
        isAndroid: false,
        isReleaseMode: false,
      ),
      Uri.parse('http://127.0.0.1:8080'),
    );
  });
}
