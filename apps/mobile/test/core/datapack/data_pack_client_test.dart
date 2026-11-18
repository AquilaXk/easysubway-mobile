import 'dart:convert';
import 'dart:io';

import 'package:easysubway_mobile/core/database/user/user_database.dart'
    as user_db;
import 'package:easysubway_mobile/core/datapack/data_pack_client.dart';
import 'package:easysubway_mobile/core/datapack/data_pack_update_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('manifest 요청은 Cache-Control: no-cache 헤더를 포함한다', () async {
    final capturedCacheControl = <String?>[];

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    server.listen((request) async {
      if (request.uri.path == '/manifest.json') {
        capturedCacheControl.add(
          request.headers.value(HttpHeaders.cacheControlHeader),
        );
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({'ttlSeconds': 60, 'packs': <Object?>[]}));
        await request.response.close();
        return;
      }
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
    });

    final userDatabase = user_db.UserDatabase.memory();
    addTearDown(userDatabase.close);
    final stateRepository = DataPackUpdateStateRepository(
      userDatabase: userDatabase,
      now: () => DateTime.utc(2026, 7, 6, 10),
    );
    final client = DataPackClient(
      manifestUri: Uri.parse(
        'http://${server.address.host}:${server.port}/manifest.json',
      ),
      stateRepository: stateRepository,
      now: () => DateTime.utc(2026, 7, 6, 10),
    );

    await client.fetchManifestIfNeeded();

    expect(capturedCacheControl, hasLength(1));
    expect(capturedCacheControl.single, 'no-cache');
  });

  // 이슈 #2528: jsonEncode의 JsonUnsupportedObjectError는 Error라서 fetchManifest의
  // `on FormatException` 핸들러를 우회하고 app_bootstrap의 광역 catch까지 새어 나갔다.
  // 정준화가 FormatException으로 정규화하면 여기서 DataPackClientException이 된다.
  test('유한하지 않은 숫자가 든 매니페스트는 DataPackClientException으로 분류된다', () async {
    const body =
        '{"manifestVersion":2,"ttlSeconds":60,"packs":[],"keyId":"production-v1",'
        '"overflow":1e400,'
        '"signature":{"algorithm":"sha256-manifest-v2","value":"deadbeef"}}';

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    server.listen((request) async {
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(body);
      await request.response.close();
    });

    final userDatabase = user_db.UserDatabase.memory();
    addTearDown(userDatabase.close);
    final client = DataPackClient(
      manifestUri: Uri.parse(
        'http://${server.address.host}:${server.port}/manifest.json',
      ),
      stateRepository: DataPackUpdateStateRepository(
        userDatabase: userDatabase,
        now: () => DateTime.utc(2026, 7, 6, 10),
      ),
      now: () => DateTime.utc(2026, 7, 6, 10),
    );

    await expectLater(
      client.fetchManifestIfNeeded(),
      throwsA(isA<DataPackClientException>()),
    );
  });

  test(
    '매니페스트 크기가 maxResponseBytes를 넘거나 UTF-8이 잘못되면 예외를 던지고 304/500 응답을 정리한다',
    () async {
      final userDatabase = user_db.UserDatabase.memory();
      addTearDown(userDatabase.close);
      var currentTime = DateTime.utc(2026, 7, 6, 10);
      final stateRepository = DataPackUpdateStateRepository(
        userDatabase: userDatabase,
        now: () => currentTime,
      );
      var mode = 'oversized';
      var serverHits = 0;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      server.listen((request) async {
        serverHits += 1;
        switch (mode) {
          case 'oversized':
            request.response
              ..statusCode = HttpStatus.ok
              ..add(utf8.encode('{"payload":"${'a' * 64}"}'));
          case 'invalid-utf8':
            request.response
              ..statusCode = HttpStatus.ok
              ..add([0xff, 0xfe]);
          case 'not-modified':
            request.response
              ..statusCode = HttpStatus.notModified
              ..write('ignored body');
          case 'server-error':
            request.response
              ..statusCode = HttpStatus.internalServerError
              ..write('server error body');
        }
        await request.response.close();
      });

      final manifestUri = Uri.parse(
        'http://${server.address.host}:${server.port}/manifest.json',
      );
      final boundedClient = DataPackClient(
        manifestUri: manifestUri,
        stateRepository: stateRepository,
        now: () => currentTime,
        maxResponseBytes: 16,
      );

      await expectLater(
        boundedClient.fetchManifestIfNeeded(),
        throwsA(isA<DataPackClientException>()),
      );

      mode = 'invalid-utf8';
      await expectLater(
        boundedClient.fetchManifestIfNeeded(),
        throwsA(isA<DataPackClientException>()),
      );

      mode = 'not-modified';
      await stateRepository.saveManifestCache(
        etag: '"e1"',
        checkedAt: currentTime.subtract(const Duration(hours: 2)),
        ttl: const Duration(minutes: 5),
      );
      final notModifiedResult = await boundedClient.fetchManifestIfNeeded();
      expect(notModifiedResult.manifest, isNull);

      currentTime = currentTime.add(const Duration(minutes: 10));
      mode = 'server-error';
      await expectLater(
        boundedClient.fetchManifestIfNeeded(),
        throwsA(isA<DataPackClientException>()),
      );
      expect(serverHits, 4);

      boundedClient.close(force: true);
      await expectLater(
        boundedClient.fetchManifestIfNeeded(),
        throwsA(isA<StateError>()),
      );

      final externalHttpClient = HttpClient();
      addTearDown(() => externalHttpClient.close(force: true));
      final injectedClient = DataPackClient(
        manifestUri: manifestUri,
        stateRepository: stateRepository,
        httpClient: externalHttpClient,
        now: () => currentTime,
      );
      injectedClient.close(force: true);
      mode = 'not-modified';
      final injectedResult = await injectedClient.fetchManifestIfNeeded();
      expect(injectedResult.manifest, isNull);
      expect(serverHits, 5);
    },
  );

  test('DataPackClient는 3xx 리다이렉트와 안전하지 않은 HTTP manifestUri를 거부한다', () async {
    final userDatabase = user_db.UserDatabase.memory();
    addTearDown(userDatabase.close);
    final stateRepository = DataPackUpdateStateRepository(
      userDatabase: userDatabase,
      now: () => DateTime.utc(2026, 7, 6, 10),
    );

    expect(
      () => DataPackClient(
        manifestUri: Uri.parse('http://cdn.easysubway.example/manifest.json'),
        stateRepository: stateRepository,
      ),
      throwsArgumentError,
    );
    expect(
      () => DataPackClient(
        manifestUri: Uri.parse('http://127.0.0.1:8080/manifest.json'),
        stateRepository: stateRepository,
        isReleaseMode: true,
      ),
      throwsArgumentError,
    );

    var targetHits = 0;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    server.listen((request) async {
      if (request.uri.path == '/manifest.json') {
        request.response
          ..statusCode = HttpStatus.movedPermanently
          ..headers.set(HttpHeaders.locationHeader, '/target.json');
        await request.response.close();
        return;
      }
      targetHits += 1;
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'ttlSeconds': 60, 'packs': <Object?>[]}));
      await request.response.close();
    });

    final client = DataPackClient(
      manifestUri: Uri.parse(
        'http://${server.address.host}:${server.port}/manifest.json',
      ),
      stateRepository: stateRepository,
      now: () => DateTime.utc(2026, 7, 6, 10),
    );
    addTearDown(() => client.close(force: true));

    await expectLater(
      client.fetchManifestIfNeeded(),
      throwsA(isA<DataPackClientException>()),
    );
    expect(targetHits, 0);
  });
}
