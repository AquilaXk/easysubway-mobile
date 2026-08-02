import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `contracts/mobile/crashlytics-secret-injection.json`를 실행 디렉터리와
/// 무관하게 찾는다. 저장소 루트를 위로 탐색하므로 `apps/mobile` 밖에서
/// `flutter test`를 실행해도 해석된다.
File crashlyticsContractFile() {
  const relativePath = 'contracts/mobile/crashlytics-secret-injection.json';
  var directory = Directory.current;
  while (true) {
    final candidate = File('${directory.path}/$relativePath');
    if (candidate.existsSync()) {
      return candidate;
    }
    final parent = directory.parent;
    if (parent.path == directory.path) {
      fail('crashlytics 계약 파일을 찾지 못했습니다: $relativePath');
    }
    directory = parent;
  }
}

Map<String, Object?> crashlyticsContract() {
  return jsonDecode(crashlyticsContractFile().readAsStringSync())
      as Map<String, Object?>;
}

Map<String, Object?> crashlyticsRedactionContract() {
  return crashlyticsContract()['redaction']! as Map<String, Object?>;
}
