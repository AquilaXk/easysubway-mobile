import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// 테스트 화면을 [logicalSize] 논리 픽셀, 기기 배율 3.0으로 두고 테스트가 끝나면 되돌린다.
void useLogicalViewport(WidgetTester tester, Size logicalSize) {
  const devicePixelRatio = 3.0;
  tester.view.devicePixelRatio = devicePixelRatio;
  tester.view.physicalSize = logicalSize * devicePixelRatio;
  addTearDown(tester.view.reset);
}
