import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:easysubway_mobile/core/database/catalog/catalog_database_opener.dart';
import 'package:easysubway_mobile/core/database/user/user_database.dart'
    as user_db;
import 'package:easysubway_mobile/core/datapack/data_pack_client.dart';
import 'package:easysubway_mobile/core/datapack/data_pack_installer.dart';
import 'package:easysubway_mobile/core/datapack/data_pack_manifest.dart';
import 'package:easysubway_mobile/core/datapack/data_pack_update_state.dart';
import 'package:easysubway_mobile/core/datapack/data_pack_updater.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Mobile #33 DataPack Exception, Cleanup & Atomic Recovery', () {
    test('다운로드 실패 시 임시 partial 파일을 정리하고 primary failure를 보존한다', () async {
      final directory = await Directory.systemTemp.createTemp(
        'easysubway-test-dl-fail-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final userDatabase = user_db.UserDatabase.memory();
      addTearDown(userDatabase.close);
      final catalogDir = Directory('${directory.path}/catalog');
      await catalogDir.create(recursive: true);

      final installer = DataPackInstaller(
        catalogDirectory: catalogDir,
        userDatabase: userDatabase,
      );

      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));

      const fakeCompressedSha =
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
      const fakeSqliteSha =
          'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

      server.listen((HttpRequest request) async {
        if (request.uri.path == '/manifest.json') {
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.json
            ..write(
              jsonEncode({
                'ttlSeconds': 60,
                'packs': [
                  {
                    'id': 'nationwide',
                    'version': '18',
                    'url': 'pack.sqlite.gz',
                    'sha256': fakeCompressedSha,
                    'sqliteSha256': fakeSqliteSha,
                    'sizeBytes': 20,
                    ..._fixtureManifestMetadata(
                      id: 'nationwide',
                      version: '18',
                      compressedSha256: fakeCompressedSha,
                      sqliteSha256: fakeSqliteSha,
                      sizeBytes: 20,
                    ),
                    'schemaVersion': '1',
                    'requiredTables': ['catalog_metadata'],
                  },
                ],
              }),
            );
          await request.response.close();
          return;
        }

        // 다운로드 중 오류 유발 (청크 분할 전송으로 파일 생성 후 크기 초과 유발)
        request.response.headers.chunkedTransferEncoding = true;
        request.response.statusCode = HttpStatus.ok;
        request.response.add(List.filled(5, 1));
        await request.response.flush();
        request.response.add(List.filled(25, 1));
        await request.response.close();
      });

      await HttpOverrides.runWithHttpOverrides(() async {
        final updater = DataPackUpdater(
          client: DataPackClient(
            manifestUri: Uri.parse(
              'http://${server.address.address}:${server.port}/manifest.json',
            ),
            stateRepository: DataPackUpdateStateRepository(
              userDatabase: userDatabase,
              now: () => DateTime.utc(2026, 6, 19, 10),
            ),
          ),
          installer: installer,
        );

        await expectLater(
          () => updater.checkForUpdates(),
          throwsA(isA<DataPackClientException>()),
        );
      }, _RealHttpOverrides());

      // catalog 디렉토리에 .downloading 파일이 남아있지 않음을 검증
      final partials = catalogDir
          .listSync()
          .where((e) => e.path.endsWith('.downloading'))
          .toList();
      expect(partials, isEmpty);
    });

    test(
      'SQLite 검증 실패 시 생성된 candidate 임시 파일을 즉시 제거하고 active pointer를 보존한다',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'easysubway-test-val-fail-',
        );
        addTearDown(() => directory.delete(recursive: true));
        final userDatabase = user_db.UserDatabase.memory();
        addTearDown(userDatabase.close);
        final catalogDir = Directory('${directory.path}/catalog');
        await catalogDir.create(recursive: true);

        // 기존 활성 팩 설정
        final oldPack = File('${catalogDir.path}/capital-v17.sqlite');
        await oldPack.writeAsString('old valid pack');
        final currentFile = File('${catalogDir.path}/current.json');
        await currentFile.writeAsString(
          jsonEncode({
            'id': 'capital',
            'version': '17',
            'path': oldPack.path,
            'sha256': 'old-sha',
            'generation': 1,
          }),
        );

        final installer = DataPackInstaller(
          catalogDirectory: catalogDir,
          userDatabase: userDatabase,
        );

        // 유효하지 않은 SQLite 헤더의 바이트
        final corruptBytes = [
          1,
          2,
          3,
          4,
          5,
          6,
          7,
          8,
          9,
          10,
          11,
          12,
          13,
          14,
          15,
          16,
        ];
        final compressedBytes = gzip.encode(corruptBytes);

        final result = await installer.install(
          pack: _testPack(
            id: 'capital',
            version: '18',
            compressedSha256: sha256.convert(compressedBytes).toString(),
            sqliteSha256: sha256.convert(corruptBytes).toString(),
            sizeBytes: compressedBytes.length,
            url: Uri.parse('http://127.0.0.1/dummy'),
          ),
          compressedBytes: compressedBytes,
        );

        expect(result.status, DataPackInstallStatus.rejected);
        // 임시 파일 .tmp가 정리되었는지 검증
        expect(
          File('${catalogDir.path}/capital-v18.sqlite.tmp').existsSync(),
          isFalse,
        );
        expect(
          File('${catalogDir.path}/capital-v18.sqlite').existsSync(),
          isFalse,
        );

        // active pointer는 기존 17 버전을 가리키며 손상되지 않음
        final currentPointer = await installer.readCurrentPointer();
        expect(currentPointer?.version, '17');
        expect(currentPointer?.generation, 1);
      },
    );

    test('동시 mutation 요청은 직렬화되며 이전 세대의 늦은 커밋(late completion)은 거부된다', () async {
      final directory = await Directory.systemTemp.createTemp(
        'easysubway-test-concurrency-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final userDatabase = user_db.UserDatabase.memory();
      addTearDown(userDatabase.close);
      final catalogDir = Directory('${directory.path}/catalog');
      await catalogDir.create(recursive: true);

      final installer = DataPackInstaller(
        catalogDirectory: catalogDir,
        userDatabase: userDatabase,
      );

      // Transaction 1이 먼저 pointer 18을 세대 1로 커밋
      final pointer18 = InstalledDataPackPointer(
        id: 'capital',
        version: '18',
        path: '${catalogDir.path}/capital-v18.sqlite',
        sha256: 'sha-18',
        generation: 1,
      );
      await installer.activateCurrentPointer(pointer18, transactionId: 1);

      // Transaction 2가 pointer 19를 세대 2로 커밋
      final pointer19 = InstalledDataPackPointer(
        id: 'capital',
        version: '19',
        path: '${catalogDir.path}/capital-v19.sqlite',
        sha256: 'sha-19',
        generation: 2,
      );
      await installer.activateCurrentPointer(pointer19, transactionId: 2);

      final current = await installer.readCurrentPointer();
      expect(current?.version, '19');
      expect(current?.generation, 2);

      // 늦게 완료된 Transaction 1 (stale transaction)이 뒤늦게 activate 시도 시 거부되어야 함
      expect(
        () => installer.activateCurrentPointer(pointer18, transactionId: 1),
        throwsA(isA<DataPackLateCompletionException>()),
      );

      // Pointer는 여전히 세대 2의 v19로 유지됨
      final afterStale = await installer.readCurrentPointer();
      expect(afterStale?.version, '19');
      expect(afterStale?.generation, 2);
    });

    test(
      'Reader generation pinning: 활성 reader가 고정한 generation은 prune에서 삭제되지 않는다',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'easysubway-test-pinning-',
        );
        addTearDown(() => directory.delete(recursive: true));
        final userDatabase = user_db.UserDatabase.memory();
        addTearDown(userDatabase.close);
        final catalogDir = Directory('${directory.path}/catalog');
        await catalogDir.create(recursive: true);

        final installer = DataPackInstaller(
          catalogDirectory: catalogDir,
          userDatabase: userDatabase,
        );

        // 파일 생성: v16, v17, v18
        final f16 = File('${catalogDir.path}/capital-v16.sqlite');
        final f17 = File('${catalogDir.path}/capital-v17.sqlite');
        final f18 = File('${catalogDir.path}/capital-v18.sqlite');
        await f16.writeAsString('v16 data');
        await f17.writeAsString('v17 data');
        await f18.writeAsString('v18 data');

        // v18을 활성 포인터로 설정
        await installer.activateCurrentPointer(
          InstalledDataPackPointer(
            id: 'capital',
            version: '18',
            path: f18.path,
            sha256: 'sha-18',
            generation: 3,
          ),
        );

        // Reader가 오래된 v16 generation을 핀 고정
        installer.pinGeneration(1, version: '16');

        // keepVersionCount가 1일 때 일반 규칙이라면 v18만 남기고 v17, v16은 삭제 대상이나,
        // v16은 핀 고정되어 있으므로 삭제되지 않아야 함
        await installer.pruneObsoletePacks(
          'capital',
          keepVersionCount: 1,
          protectedVersions: const {},
        );

        expect(await f18.exists(), isTrue);
        expect(
          await f16.exists(),
          isTrue,
          reason: 'Pinned generation 16 must not be pruned',
        );
        expect(
          await f17.exists(),
          isFalse,
          reason: 'Unpinned and obsolete v17 is pruned',
        );

        // Reader가 unpin한 뒤 다시 prune 실행 시 v16도 정상 삭제됨
        installer.unpinGeneration(1);
        await installer.pruneObsoletePacks(
          'capital',
          keepVersionCount: 1,
          protectedVersions: const {},
        );
        expect(await f16.exists(), isFalse);
      },
    );

    test(
      'Pair invariant: map과 catalog가 둘 다 온전해야 원자적 전환되며 깨진 pair는 거부된다',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'easysubway-test-pair-swap-',
        );
        addTearDown(() => directory.delete(recursive: true));
        final userDatabase = user_db.UserDatabase.memory();
        addTearDown(userDatabase.close);
        final catalogDir = Directory('${directory.path}/catalog');
        await catalogDir.create(recursive: true);

        // 기존 1세대 유효 pair
        final oldCatalog = File('${catalogDir.path}/capital-v17.sqlite');
        final oldMap = File('${catalogDir.path}/map-v17.svg');
        await oldCatalog.writeAsString('catalog v17');
        await oldMap.writeAsString('map v17');
        final oldCatalogSha = sha256
            .convert(await oldCatalog.readAsBytes())
            .toString();
        final oldMapSha = sha256.convert(await oldMap.readAsBytes()).toString();

        final installer = DataPackInstaller(
          catalogDirectory: catalogDir,
          userDatabase: userDatabase,
        );

        await installer.activateCurrentPointer(
          InstalledDataPackPointer(
            id: 'capital',
            version: '17',
            path: oldCatalog.path,
            sha256: oldCatalogSha,
            companionPackId: 'map',
            companionVersion: '17',
            companionPath: oldMap.path,
            companionSha256: oldMapSha,
            stationSetSha256: 'stations-v17-sha',
            generation: 1,
          ),
        );

        final initialPointer = await installer.readCurrentPointer();
        expect(initialPointer?.isPair, isTrue);
        expect(initialPointer?.generation, 1);

        // 새 candidate pair 준비: catalog v18은 존재하지만 map v18이 누락된 불완전(mixed) 상태
        final newCatalog = File('${catalogDir.path}/capital-v18.sqlite');
        await newCatalog.writeAsString('catalog v18');
        final newCatalogSha = sha256
            .convert(await newCatalog.readAsBytes())
            .toString();

        // journal에 불완전 pair 작성 (map 파일 부재)
        final journal = File('${catalogDir.path}/current.json.installing');
        await journal.writeAsString(
          jsonEncode({
            'id': 'capital',
            'version': '18',
            'path': newCatalog.path,
            'sha256': newCatalogSha,
            'companionPackId': 'map',
            'companionVersion': '18',
            'companionPath': '${catalogDir.path}/map-v18-missing.svg',
            'companionSha256': 'dummy-sha',
            'stationSetSha256': 'stations-v18-sha',
            'generation': 2,
          }),
        );

        // recoverInstallJournal 실행 시 companion 부재로 journal은 파기되고 기존 v17이 유지되어야 함
        await installer.recoverInstallJournal();

        expect(await journal.exists(), isFalse);
        final recoveredPointer = await installer.readCurrentPointer();
        expect(recoveredPointer?.version, '17');
        expect(recoveredPointer?.generation, 1);
      },
    );

    test(
      'Kill Rehearsal Boundary 1: candidate write 전 프로세스 kill 시 stale partial 정리 및 기존 포인터 보존',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'easysubway-test-kill-boundary-1-',
        );
        addTearDown(() => directory.delete(recursive: true));
        final userDatabase = user_db.UserDatabase.memory();
        addTearDown(userDatabase.close);
        final catalogDir = Directory('${directory.path}/catalog');
        await catalogDir.create(recursive: true);

        // 이전 활성 상태
        final oldPack = File('${catalogDir.path}/nationwide-v17.sqlite');
        await oldPack.writeAsString('nationwide v17');
        await File('${catalogDir.path}/current.json').writeAsString(
          jsonEncode({
            'id': 'nationwide',
            'version': '17',
            'path': oldPack.path,
            'sha256': 'sha-17',
            'generation': 1,
          }),
        );

        // Boundary 1: Candidate write 전 다운로드/압축해제 도중 kill 발생 시뮬레이션
        // .downloading, .gz.tmp, .sqlite.tmp 파일들이 디스크에 방치됨
        final staleDownloading = File(
          '${catalogDir.path}/nationwide-v18.sqlite.gz.downloading',
        );
        final staleGzTmp = File(
          '${catalogDir.path}/nationwide-v18.sqlite.gz.tmp',
        );
        final staleSqliteTmp = File(
          '${catalogDir.path}/nationwide-v18.sqlite.tmp',
        );
        await staleDownloading.writeAsString('partial downloading bytes');
        await staleGzTmp.writeAsString('partial gz bytes');
        await staleSqliteTmp.writeAsString('partial sqlite bytes');

        // 앱 재실행(Relaunch) 시뮬레이션
        final relaunchInstaller = DataPackInstaller(
          catalogDirectory: catalogDir,
          userDatabase: userDatabase,
        );

        await relaunchInstaller.recoverInstallJournal();

        // 검증: 방치된 모든 stale partial이 깨끗이 정리됨
        expect(await staleDownloading.exists(), isFalse);
        expect(await staleGzTmp.exists(), isFalse);
        expect(await staleSqliteTmp.exists(), isFalse);

        // 검증: 기존 active pointer와 데이터는 온전히 보존됨
        final activePointer = await relaunchInstaller.readCurrentPointer();
        expect(activePointer?.version, '17');
        expect(activePointer?.generation, 1);
        expect(await oldPack.exists(), isTrue);
      },
    );

    test(
      'Kill Rehearsal Boundary 2: active pointer 직전 프로세스 kill 시 journal 검증을 통한 결정론적 복구',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'easysubway-test-kill-boundary-2-',
        );
        addTearDown(() => directory.delete(recursive: true));
        final userDatabase = user_db.UserDatabase.memory();
        addTearDown(userDatabase.close);
        final catalogDir = Directory('${directory.path}/catalog');
        await catalogDir.create(recursive: true);

        // 기존 활성 상태 (v17, gen 1)
        final oldPack = File('${catalogDir.path}/nationwide-v17.sqlite');
        await oldPack.writeAsString('nationwide v17');
        await File('${catalogDir.path}/current.json').writeAsString(
          jsonEncode({
            'id': 'nationwide',
            'version': '17',
            'path': oldPack.path,
            'sha256': 'sha-17',
            'generation': 1,
          }),
        );

        // Boundary 2: Candidate 파일 검증 및 기록 완료 후, journal(current.json.installing)을 flush했으나
        // 아직 current.json 원자 교체가 일어나기 직전에 kill 발생
        final newPack = File('${catalogDir.path}/nationwide-v18.sqlite');
        await newPack.writeAsString('nationwide v18 verified content');
        final newSha = sha256.convert(await newPack.readAsBytes()).toString();

        final journal = File('${catalogDir.path}/current.json.installing');
        await journal.writeAsString(
          jsonEncode({
            'id': 'nationwide',
            'version': '18',
            'path': newPack.path,
            'sha256': newSha,
            'generation': 2,
          }),
          flush: true,
        );

        // 앱 재실행(Relaunch) 시뮬레이션
        final relaunchInstaller = DataPackInstaller(
          catalogDirectory: catalogDir,
          userDatabase: userDatabase,
        );

        // recoverInstallJournal이 실행되어 완결된 journal을 current.json으로 안전하게 승격
        await relaunchInstaller.recoverInstallJournal();

        // 검증: journal 파일은 current.json으로 원자적 승격 완료
        expect(await journal.exists(), isFalse);
        final activePointer = await relaunchInstaller.readCurrentPointer();
        expect(activePointer?.version, '18');
        expect(activePointer?.generation, 2);
        expect(activePointer?.sha256, newSha);

        // 반복 복구(idempotent) 확인: 다시 호출해도 상태가 변하지 않음
        await relaunchInstaller.recoverInstallJournal();
        final recheckPointer = await relaunchInstaller.readCurrentPointer();
        expect(recheckPointer?.version, '18');
        expect(recheckPointer?.generation, 2);
      },
    );

    test(
      'Kill Rehearsal Boundary 2 (Corrupt Candidate): journal에 등록된 candidate가 손상된 경우 승격 거부 및 rollback 유지',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'easysubway-test-kill-boundary-2-corrupt-',
        );
        addTearDown(() => directory.delete(recursive: true));
        final userDatabase = user_db.UserDatabase.memory();
        addTearDown(userDatabase.close);
        final catalogDir = Directory('${directory.path}/catalog');
        await catalogDir.create(recursive: true);

        // 기존 활성 상태 (v17, gen 1)
        final oldPack = File('${catalogDir.path}/nationwide-v17.sqlite');
        await oldPack.writeAsString('nationwide v17');
        await File('${catalogDir.path}/current.json').writeAsString(
          jsonEncode({
            'id': 'nationwide',
            'version': '17',
            'path': oldPack.path,
            'sha256': 'sha-17',
            'generation': 1,
          }),
        );

        // Candidate 파일이 중간에 훼손됨 (해시 불일치)
        final newPack = File('${catalogDir.path}/nationwide-v18.sqlite');
        await newPack.writeAsString('corrupted candidate content');

        final journal = File('${catalogDir.path}/current.json.installing');
        await journal.writeAsString(
          jsonEncode({
            'id': 'nationwide',
            'version': '18',
            'path': newPack.path,
            'sha256': 'expected-correct-sha-which-does-not-match',
            'generation': 2,
          }),
          flush: true,
        );

        final relaunchInstaller = DataPackInstaller(
          catalogDirectory: catalogDir,
          userDatabase: userDatabase,
        );

        await relaunchInstaller.recoverInstallJournal();

        // 검증: 손상된 candidate의 journal은 삭제되고 active pointer는 이전 v17 유지
        expect(await journal.exists(), isFalse);
        final activePointer = await relaunchInstaller.readCurrentPointer();
        expect(activePointer?.version, '17');
        expect(activePointer?.generation, 1);
      },
    );

    test(
      'Kill Rehearsal Boundary 3: pointer commit 직후 프로세스 kill 시 신규 generation 안착 및 rollback pair 보존',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'easysubway-test-kill-boundary-3-',
        );
        addTearDown(() => directory.delete(recursive: true));
        final userDatabase = user_db.UserDatabase.memory();
        addTearDown(userDatabase.close);
        final catalogDir = Directory('${directory.path}/catalog');
        await catalogDir.create(recursive: true);

        // 롤백 대상 v17 팩
        final rollbackPack = File('${catalogDir.path}/nationwide-v17.sqlite');
        await rollbackPack.writeAsString('nationwide v17');

        // 새 v18 팩
        final newPack = File('${catalogDir.path}/nationwide-v18.sqlite');
        await newPack.writeAsString('nationwide v18');
        final newSha = sha256.convert(await newPack.readAsBytes()).toString();

        // Boundary 3: current.json은 v18(gen 2)로 이미 commit되었으나,
        // 임시 .previous 백업 파일 정리 또는 후속 prune 작업 도중에 kill 발생
        await File('${catalogDir.path}/current.json').writeAsString(
          jsonEncode({
            'id': 'nationwide',
            'version': '18',
            'path': newPack.path,
            'sha256': newSha,
            'generation': 2,
          }),
        );
        final stalePreviousBackup = File(
          '${catalogDir.path}/current.json.previous',
        );
        await stalePreviousBackup.writeAsString('previous backup');

        // 앱 재실행
        final relaunchInstaller = DataPackInstaller(
          catalogDirectory: catalogDir,
          userDatabase: userDatabase,
        );

        await relaunchInstaller.recoverInstallJournal();

        // 검증: .previous 잔재는 제거되고, current.json은 v18(gen 2)을 안정적으로 유지
        expect(await stalePreviousBackup.exists(), isFalse);
        final activePointer = await relaunchInstaller.readCurrentPointer();
        expect(activePointer?.version, '18');
        expect(activePointer?.generation, 2);

        // 롤백 가능한 이전 버전(v17) 파일도 디스크에 보존되어 있음
        expect(await rollbackPack.exists(), isTrue);
      },
    );

    test('DataPackLateCompletionException format verification', () {
      const ex = DataPackLateCompletionException('sample err');
      expect(ex.toString(), 'DataPackLateCompletionException: sample err');
    });

    test('pinnedGenerations 및 동시 mutation serialization 검증', () async {
      final directory = await Directory.systemTemp.createTemp(
        'pin-concurrency-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final userDatabase = user_db.UserDatabase.memory();
      addTearDown(userDatabase.close);
      final catalogDir = Directory('${directory.path}/catalog');
      await catalogDir.create(recursive: true);
      final installer = DataPackInstaller(
        catalogDirectory: catalogDir,
        userDatabase: userDatabase,
      );
      installer.pinGeneration(5, version: '5');
      expect(installer.pinnedGenerations, contains(5));
      installer.unpinGeneration(5);
      expect(installer.pinnedGenerations, isNot(contains(5)));

      final p1 = InstalledDataPackPointer(
        id: 'c',
        version: '1',
        path: '${catalogDir.path}/1',
        generation: 1,
      );
      final p2 = InstalledDataPackPointer(
        id: 'c',
        version: '2',
        path: '${catalogDir.path}/2',
        generation: 2,
      );
      final f1 = installer.activateCurrentPointer(p1);
      final f2 = installer.activateCurrentPointer(p2);
      await Future.wait([f1, f2]);
      final cur = await installer.readCurrentPointer();
      expect(cur?.generation, 2);
    });

    test('installFromCompressedFile에서 sqliteSha256Mismatch 검증', () async {
      final directory = await Directory.systemTemp.createTemp(
        'sqlite-mismatch-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final userDatabase = user_db.UserDatabase.memory();
      addTearDown(userDatabase.close);
      final catalogDir = Directory('${directory.path}/catalog');
      await catalogDir.create(recursive: true);
      final installer = DataPackInstaller(
        catalogDirectory: catalogDir,
        userDatabase: userDatabase,
      );
      final bytes = [1, 2, 3, 4];
      final compressed = gzip.encode(bytes);
      final result = await installer.install(
        pack: _testPack(
          id: 'test',
          version: '1',
          compressedSha256: sha256.convert(compressed).toString(),
          sqliteSha256: 'wrong-hash',
          sizeBytes: compressed.length,
          url: Uri.parse('http://127.0.0.1/dummy'),
        ),
        compressedBytes: compressed,
      );
      expect(result.status, DataPackInstallStatus.rejected);
      expect(
        result.reason,
        DataPackInstallRejectionReason.sqliteSha256Mismatch,
      );
    });

    test('recoverInstallJournal에서 companion 파일 해시 불일치 시 journal 삭제', () async {
      final directory = await Directory.systemTemp.createTemp(
        'comp-sha-mismatch-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final userDatabase = user_db.UserDatabase.memory();
      addTearDown(userDatabase.close);
      final catalogDir = Directory('${directory.path}/catalog');
      await catalogDir.create(recursive: true);
      final catFile = File('${catalogDir.path}/cat-v1.sqlite');
      await catFile.writeAsString('cat');
      final mapFile = File('${catalogDir.path}/map-v1.svg');
      await mapFile.writeAsString('map');
      final journal = File('${catalogDir.path}/current.json.installing');
      await journal.writeAsString(
        jsonEncode({
          'id': 'cap',
          'version': '1',
          'path': catFile.path,
          'sha256': sha256.convert(await catFile.readAsBytes()).toString(),
          'companionPackId': 'map',
          'companionVersion': '1',
          'companionPath': mapFile.path,
          'companionSha256': 'wrong-sha',
          'generation': 1,
        }),
      );
      final installer = DataPackInstaller(
        catalogDirectory: catalogDir,
        userDatabase: userDatabase,
      );
      await installer.recoverInstallJournal();
      expect(await journal.exists(), isFalse);
    });

    test(
      'InstalledDataPackPointer String generation/releaseSequence 및 copyWith',
      () {
        final ptr = InstalledDataPackPointer.fromJson({
          'id': 'cap',
          'version': '1',
          'path': '/some/path',
          'generation': '42',
          'releaseSequence': '10',
          'manifestSha256': 'manifest-sha',
        });
        expect(ptr.generation, 42);
        expect(ptr.releaseSequence, 10);
        expect(ptr.manifestSha256, 'manifest-sha');
        final copyWithGen = ptr.copyWith(generation: 43);
        expect(copyWithGen.generation, 43);
        final copyWithoutGen = ptr.copyWith(id: 'cap2');
        expect(copyWithoutGen.generation, 42);
        expect(copyWithoutGen.id, 'cap2');
      },
    );

    test('CatalogDatabaseOpener openedGeneration 및 companion 검증', () async {
      final directory = await Directory.systemTemp.createTemp('opener-test-');
      addTearDown(() => directory.delete(recursive: true));
      final catalogDir = Directory('${directory.path}/catalog');
      await catalogDir.create(recursive: true);
      final pack = File('${catalogDir.path}/capital-v18.sqlite');
      await pack.writeAsString('data');

      // 1. journal에 존재하는 companion 누락 시 삭제
      final journal = File('${catalogDir.path}/current.json.installing');
      await journal.writeAsString(
        jsonEncode({
          'id': 'capital',
          'version': '18',
          'path': pack.path,
          'sha256': sha256.convert(await pack.readAsBytes()).toString(),
          'companionPath': '${catalogDir.path}/missing.svg',
        }),
      );
      final opener = CatalogDatabaseOpener(
        databaseDirectory: directory,
        assetBundle: rootBundle,
      );
      await opener.open();
      expect(await journal.exists(), isFalse);

      // 2. journal에 존재하는 companion 해시 불일치 시 삭제
      final mapFile = File('${catalogDir.path}/map-v18.svg');
      await mapFile.writeAsString('map');
      await journal.writeAsString(
        jsonEncode({
          'id': 'capital',
          'version': '18',
          'path': pack.path,
          'sha256': sha256.convert(await pack.readAsBytes()).toString(),
          'companionPath': mapFile.path,
          'companionSha256': 'wrong-sha',
        }),
      );
      await opener.open();
      expect(await journal.exists(), isFalse);

      // 3. current.json에 companion 파일 부재 시 null fallback
      final current = File('${catalogDir.path}/current.json');
      await current.writeAsString(
        jsonEncode({
          'id': 'capital',
          'version': '18',
          'path': pack.path,
          'sha256': sha256.convert(await pack.readAsBytes()).toString(),
          'companionPath': '${catalogDir.path}/missing.svg',
          'generation': 7,
        }),
      );
      expect(opener.openedGeneration, isNull);
      final db1 = await opener.open();
      addTearDown(db1.close);
      expect(opener.openedBundledDataPack, isTrue);

      // 4. string generation 역직렬화
      await current.writeAsString(
        jsonEncode({
          'id': 'capital',
          'version': '18',
          'path': pack.path,
          'sha256': sha256.convert(await pack.readAsBytes()).toString(),
          'generation': '7',
        }),
      );
      final db2 = await opener.open();
      addTearDown(db2.close);
      expect(opener.openedGeneration, 7);
    });
  });
}

const _representativeRouteRegressions = [
  {
    'id': 'direct-local-capital',
    'pattern': 'DIRECT',
    'fromNodeId': 'station-a-line-1',
    'toNodeId': 'station-b-line-1',
    'requiredEdgeIds': ['edge-a-b'],
  },
  {
    'id': 'transfer-capital',
    'pattern': 'TRANSFER',
    'fromNodeId': 'station-a-line-1',
    'toNodeId': 'station-c-line-2',
    'requiredEdgeIds': ['edge-a-b', 'edge-b-transfer', 'edge-b-c'],
  },
  {
    'id': 'multi-transfer-capital',
    'pattern': 'MULTI_TRANSFER',
    'fromNodeId': 'station-a-line-1',
    'toNodeId': 'station-d-line-3',
    'requiredEdgeIds': [
      'edge-a-b',
      'edge-b-transfer',
      'edge-c-transfer',
      'edge-c-d',
    ],
  },
  {
    'id': 'loop-branch-capital',
    'pattern': 'LOOP_BRANCH',
    'fromNodeId': 'station-branch-line-2',
    'toNodeId': 'station-c-line-2',
    'requiredEdgeIds': ['edge-branch-loop', 'edge-loop-c'],
  },
  {
    'id': 'express-local-capital',
    'pattern': 'EXPRESS_LOCAL',
    'fromNodeId': 'station-a-line-1-express',
    'toNodeId': 'station-b-line-1-express',
    'requiredEdgeIds': ['edge-a-b-express'],
  },
];

Map<String, Object?> _fixtureManifestMetadata({
  String id = 'nationwide',
  required String version,
  required String compressedSha256,
  required String sqliteSha256,
  required int sizeBytes,
}) {
  return {
    'artifactKind': 'fixture',
    'representativeRouteRegressions': _representativeRouteRegressions,
    'representativeRouteRegressionSignature': {
      'algorithm': 'sha256-route-regression-v1',
      'value': _routeRegressionSignatureValue(
        id,
        version,
        compressedSha256,
        sqliteSha256,
        sizeBytes,
      ),
    },
    'signature': {
      'algorithm': 'sha256-pack-manifest-v1',
      'value': _signatureValue(
        id,
        version,
        compressedSha256,
        sqliteSha256,
        sizeBytes,
      ),
    },
    'sourceInventory': [
      {
        'id': 'fixture-capital-catalog',
        'owner': '테스트',
        'url': 'https://example.invalid/fixture',
        'license': 'fixture-only',
        'licenseStatus': 'fixture-only',
        'redistributionAllowed': false,
        'updateFrequency': 'manual',
        'updatedAt': '2026-06-19T00:00:00.000Z',
        'fields': ['stations'],
      },
    ],
    'regionalQualityMetrics': {
      'stationCount': 2,
      'facilityCoverageRatio': 0.5,
      'edgeCount': 2,
      'unknownAccessibilityRatio': 0.0,
    },
  };
}

String _signatureValue(
  String id,
  String version,
  String compressedSha256,
  String sqliteSha256,
  int sizeBytes,
) {
  return sha256
      .convert(
        utf8.encode('$id:$version:$compressedSha256:$sqliteSha256:$sizeBytes'),
      )
      .toString();
}

String _routeRegressionSignatureValue(
  String id,
  String version,
  String compressedSha256,
  String sqliteSha256,
  int sizeBytes,
) {
  return sha256
      .convert(
        utf8.encode(
          '$id:$version:$compressedSha256:$sqliteSha256:$sizeBytes:${jsonEncode(_representativeRouteRegressions)}',
        ),
      )
      .toString();
}

DataPackManifestEntry _testPack({
  required String id,
  required String version,
  required String compressedSha256,
  required String sqliteSha256,
  required int sizeBytes,
  required Uri url,
}) {
  return DataPackManifestEntry(
    id: id,
    version: version,
    url: url,
    compressedSha256: compressedSha256,
    sqliteSha256: sqliteSha256,
    sizeBytes: sizeBytes,
    artifactKind: DataPackArtifactKind.fixture,
    signature: const DataPackSignature(
      algorithm: 'sha256-fixture-v1',
      value: 'dummy-sig',
    ),
    sourceInventory: const [],
    regionalQualityMetrics: const RegionalQualityMetrics(
      stationCount: 2,
      facilityCoverageRatio: 0.5,
      edgeCount: 2,
      unknownAccessibilityRatio: 0.0,
    ),
    representativeRouteRegressions: const [],
    representativeRouteRegressionSignature: const DataPackSignature(
      algorithm: 'sha256-route-regression-v1',
      value: '0000000000000000000000000000000000000000000000000000000000000000',
    ),
    schemaVersion: '1',
    requiredTables: const ['catalog_metadata'],
  );
}

class _RealHttpOverrides extends HttpOverrides {}
