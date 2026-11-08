import 'dart:io' show File;
import 'dart:typed_data' show ByteData;

import 'package:flutter/services.dart' show FontLoader;

/// 앱은 기기 시스템 서체로 그리지만 flutter test는 시스템 서체를 읽지 못한다.
/// 한글 글자 폭과 골든 픽셀이 필요한 테스트는 저장소에 둔 NanumGothic(SIL OFL
/// 1.1, `test/assets/fonts/OFL-NanumGothic.txt`)을 이 family로 불러 쓴다.
///
/// CI 골든 게이트(`.github/workflows/mobile-golden.yml:19`)의 정본 기준 호스트는
/// GitHub Actions `macos-15` (macOS 15 Sequoia, Flutter `3.44.0`)다. 다른 macOS
/// 메이저 버전 호스트(예: `macOS 27.0.1`)에서는 CoreGraphics/Skia 폰트·아이콘
/// 서브픽셀 안티에일리어싱 차이로 0.10~0.51% 픽셀 차이가 발생할 수 있다.
const koreanTestFontFamily = 'NanumGothicGolden';

Future<void> loadKoreanTestFont() async {
  final bytes = await File(
    'test/assets/fonts/NanumGothic-Regular.ttf',
  ).readAsBytes();
  await (FontLoader(
    koreanTestFontFamily,
  )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
}
