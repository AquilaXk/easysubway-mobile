import 'dart:io' show File;
import 'dart:typed_data' show ByteData;

import 'package:flutter/services.dart' show FontLoader;

/// 앱은 기기 시스템 서체로 그리지만 flutter test는 시스템 서체를 읽지 못한다.
/// 한글 글자 폭과 골든 픽셀이 필요한 테스트는 저장소에 둔 NanumGothic(SIL OFL
/// 1.1, `test/assets/fonts/OFL-NanumGothic.txt`)을 이 family로 불러 쓴다.
const koreanTestFontFamily = 'NanumGothicGolden';

Future<void> loadKoreanTestFont() async {
  final bytes = await File(
    'test/assets/fonts/NanumGothic-Regular.ttf',
  ).readAsBytes();
  await (FontLoader(
    koreanTestFontFamily,
  )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
}
