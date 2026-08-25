import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('clean Flutter plugin registration includes Play Integrity channel plugin', () {
    final root = Directory.current;
    final appPubspec = File('${root.path}/pubspec.yaml').readAsStringSync();
    final pluginPubspec = File(
      '${root.path}/packages/play_integrity_channel/pubspec.yaml',
    ).readAsStringSync();
    final generatedRegistrant = File(
      '${root.path}/android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java',
    ).readAsStringSync();

    expect(appPubspec, contains('play_integrity_channel:'));
    expect(appPubspec, contains('path: packages/play_integrity_channel'));
    expect(pluginPubspec, contains('pluginClass: PlayIntegrityMethodChannelPlugin'));
    expect(pluginPubspec, contains('package: com.easysubway.play_integrity_channel'));
    expect(
      generatedRegistrant,
      contains('com.easysubway.play_integrity_channel.PlayIntegrityMethodChannelPlugin'),
    );
  });
}
