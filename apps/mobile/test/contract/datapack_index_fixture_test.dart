import 'dart:convert';
import 'dart:io';

import 'package:easysubway_mobile/core/datapack/data_pack_index.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('번들 datapack index fixture를 DataPackIndex가 decode한다', () {
    final raw = File(
      '../../apps/mobile/assets/datapacks/index.json',
    ).readAsStringSync();
    final decoded = jsonDecode(raw) as Map<String, Object?>;

    final index = DataPackIndex.fromJson(decoded);

    expect(index.schemaVersion, 1);
    expect(index.builtAt, DateTime.utc(2026, 9, 24, 3, 34, 28));
    expect(index.qualityAsOf, DateTime.utc(2026, 9, 9, 3, 16, 8, 98));
    expect(index.freshnessExpiresAt, DateTime.utc(2026, 10, 9, 3, 16, 8, 98));
    expect(
      index.sourceSnapshotSetHash,
      'a7b44bed6999142d6b716814a22071f890af2b341e2f27d898ebeb2e55d5716f',
    );
    expect(index.schemaIdentity, 'catalog-schema-v1');
    expect(index.packs.map((pack) => pack.id), contains('nationwide'));
  });

  test('schemaVersion 2 인덱스는 명시적으로 거부한다', () {
    final future = <String, Object?>{'schemaVersion': 2, 'packs': <Object?>[]};

    expect(
      () => DataPackIndex.fromJson(future),
      throwsA(isA<UnsupportedDatapackSchemaException>()),
    );
  });

  test('지원하지 않는 schema identity를 거부한다', () {
    final decoded =
        jsonDecode(
              File(
                '../../apps/mobile/assets/datapacks/index.json',
              ).readAsStringSync(),
            )
            as Map<String, Object?>;
    decoded['schemaIdentity'] = 'catalog-schema-v2';

    expect(() => DataPackIndex.fromJson(decoded), throwsFormatException);
  });

  test('실재하지 않는 UTC 시각을 거부한다', () {
    final decoded =
        jsonDecode(
              File(
                '../../apps/mobile/assets/datapacks/index.json',
              ).readAsStringSync(),
            )
            as Map<String, Object?>;
    decoded['builtAt'] = '2026-02-31T00:00:00.000Z';

    expect(() => DataPackIndex.fromJson(decoded), throwsFormatException);
  });

  test('freshnessExpiresAt은 qualityAsOf보다 뒤여야 한다', () {
    final fixture =
        jsonDecode(
              File(
                '../../apps/mobile/assets/datapacks/index.json',
              ).readAsStringSync(),
            )
            as Map<String, Object?>;

    for (final expiresAt in [
      '2026-07-12T00:00:00.000Z',
      '2026-07-11T23:59:59.999Z',
    ]) {
      final decoded = Map<String, Object?>.from(fixture)
        ..['freshnessExpiresAt'] = expiresAt;

      expect(() => DataPackIndex.fromJson(decoded), throwsFormatException);
    }
  });
}
