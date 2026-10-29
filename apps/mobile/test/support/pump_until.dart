import 'package:flutter_test/flutter_test.dart';

/// [pumpUntil]이 조건을 기다리는 실제 시간 한도. 부하가 큰 러너에서도 비동기 읽기는 이 안에
/// 끝난다.
const Duration pumpUntilTimeout = Duration(seconds: 30);

/// [condition]이 참이 될 때까지 프레임을 돌리며 실제 이벤트 루프를 한 바퀴씩 내준다. 파일
/// 읽기와 디코드는 테스트 시계가 아니라 실제 시간으로 끝나기 때문이다. 시계는 앞으로 돌리지
/// 않는다. 한도 안에 참이 되지 않으면 기다린 [reason]과, 있으면 그때 [observed]가 알려 주는
/// 상태를 밝혀 실패한다.
Future<void> pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  required String reason,
  String Function()? observed,
}) async {
  final elapsed = Stopwatch()..start();
  await tester.pump();
  while (!condition()) {
    if (elapsed.elapsed > pumpUntilTimeout) {
      final state = observed == null ? '' : ' 그때 상태: ${observed()}.';
      fail('${pumpUntilTimeout.inSeconds}초가 지나도 조건이 서지 않았습니다. $reason.$state');
    }
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
  }
}
