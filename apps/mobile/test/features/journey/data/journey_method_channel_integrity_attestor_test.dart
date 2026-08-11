import 'package:easysubway_mobile/features/journey/data/journey_method_channel_integrity_attestor.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('requestHash와 cloud project를 기존 Play Integrity channel에 전달한다', () async {
    const channel = MethodChannel(
      'com.easysubway.easysubway_mobile/play_integrity',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'requestToken');
          expect(call.arguments, {
            'requestHash': 'hash',
            'cloudProjectNumber': '1',
          });
          return 'token';
        });
    final attestor = JourneyMethodChannelIntegrityAttestor(
      channel: channel,
      cloudProjectNumber: '1',
    );
    expect(await attestor.attest('hash'), 'token');
  });

  test('cloud project 또는 token이 없으면 fail closed한다', () async {
    const channel = MethodChannel(
      'com.easysubway.easysubway_mobile/play_integrity',
    );
    var calls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls++;
          return calls == 1 ? null : '';
        });

    await expectLater(
      JourneyMethodChannelIntegrityAttestor(
        channel: channel,
        cloudProjectNumber: '',
      ).attest('hash'),
      throwsStateError,
    );
    expect(calls, 0);
    for (var index = 0; index < 2; index++) {
      await expectLater(
        JourneyMethodChannelIntegrityAttestor(
          channel: channel,
          cloudProjectNumber: '1',
        ).attest('hash'),
        throwsStateError,
      );
    }
    expect(calls, 2);
  });
}
