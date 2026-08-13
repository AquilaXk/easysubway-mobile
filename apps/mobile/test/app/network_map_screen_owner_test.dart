import 'dart:io';

import 'package:easysubway_mobile/app/network_map_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Network Map screen has one app owner and no root entrypoint', () {
    expect(NetworkMapScreen, isA<Type>());
    expect(File('lib/app/network_map_screen.dart').existsSync(), isTrue);
    expect(File('lib/network_map.dart').existsSync(), isFalse);

    final home = File(
      'lib/features/home/presentation/home_screen.dart',
    ).readAsStringSync();
    expect(home, contains("import '../../../app/network_map_screen.dart';"));
    expect(home, isNot(contains("import '../../../network_map.dart';")));
  });
}
