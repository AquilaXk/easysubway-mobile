import 'dart:async';

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

  test(
    'MethodChannel timeout 및 PlatformException 시 재시도 후 fail closed한다',
    () async {
      const channel = MethodChannel(
        'com.easysubway.easysubway_mobile/play_integrity',
      );
      var calls = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls++;
            if (calls == 1) {
              return Completer<String>().future;
            }
            return 'recovered-token';
          });

      final retried = await JourneyMethodChannelIntegrityAttestor(
        channel: channel,
        cloudProjectNumber: '1',
        timeout: const Duration(milliseconds: 20),
        maxAttempts: 2,
      ).attest('hash');
      expect(retried, 'recovered-token');
      expect(calls, 2);

      calls = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls++;
            return Completer<String>().future;
          });
      await expectLater(
        JourneyMethodChannelIntegrityAttestor(
          channel: channel,
          cloudProjectNumber: '1',
          timeout: const Duration(milliseconds: 15),
          maxAttempts: 1,
        ).attest('hash'),
        throwsStateError,
      );
      expect(calls, 1);

      calls = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls++;
            throw PlatformException(
              code: 'integrityUnavailable',
              message: 'secret-internal-platform-detail',
            );
          });
      await expectLater(
        JourneyMethodChannelIntegrityAttestor(
          channel: channel,
          cloudProjectNumber: '1',
          maxAttempts: 2,
        ).attest('hash'),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            isNot(contains('secret-internal-platform-detail')),
          ),
        ),
      );
      expect(calls, 2);

      calls = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls++;
            throw MissingPluginException('missing');
          });
      await expectLater(
        JourneyMethodChannelIntegrityAttestor(
          channel: channel,
          cloudProjectNumber: '1',
          maxAttempts: 2,
        ).attest('hash'),
        throwsStateError,
      );
      expect(calls, 1);
    },
  );
}
