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
    final rootBuild = File('${root.path}/android/build.gradle.kts').readAsStringSync();
    final appBuild = File('${root.path}/android/app/build.gradle.kts').readAsStringSync();
    final pluginBuild = File(
      '${root.path}/packages/play_integrity_channel/android/build.gradle',
    ).readAsStringSync();

    expect(appPubspec, contains('play_integrity_channel:'));
    expect(appPubspec, contains('path: packages/play_integrity_channel'));
    expect(pluginPubspec, contains('pluginClass: PlayIntegrityMethodChannelPlugin'));
    expect(pluginPubspec, contains('package: com.easysubway.play_integrity_channel'));
    expect(
      generatedRegistrant,
      contains('com.easysubway.play_integrity_channel.PlayIntegrityMethodChannelPlugin'),
    );
    expect(rootBuild, contains('extra["easysubwayJvmVersion"] = 17'));
    expect(appBuild, contains('rootProject.extra["easysubwayJvmVersion"]'));
    expect(appBuild, contains('jvmToolchain(easysubwayJvmVersion)'));
    expect(pluginBuild, contains('rootProject.ext.easysubwayJvmVersion'));
    expect(pluginBuild, contains('jvmToolchain(easysubwayJvmVersion)'));
  });
}
