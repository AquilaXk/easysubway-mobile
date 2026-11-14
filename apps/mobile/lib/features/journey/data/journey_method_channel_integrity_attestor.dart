import 'dart:async';

import 'package:flutter/services.dart';

import '../application/journey_search_controller.dart';

class JourneyMethodChannelIntegrityAttestor
    implements JourneyV3IntegrityAttestor {
  JourneyMethodChannelIntegrityAttestor({
    MethodChannel? channel,
    this.cloudProjectNumber = const String.fromEnvironment(
      'EASYSUBWAY_PLAY_INTEGRITY_CLOUD_PROJECT_NUMBER',
    ),
    this.timeout = const Duration(seconds: 8),
    this.maxAttempts = 2,
  }) : assert(maxAttempts >= 1),
       _channel =
           channel ??
           const MethodChannel(
             'com.easysubway.easysubway_mobile/play_integrity',
           );

  final MethodChannel _channel;
  final String cloudProjectNumber;
  final Duration timeout;
  final int maxAttempts;

  @override
  Future<String> attest(String requestHash) async {
    if (cloudProjectNumber.trim().isEmpty) {
      throw StateError('Play Integrity cloud project is not configured.');
    }
    for (var attempt = 1; ; attempt++) {
      try {
        final token = await _channel
            .invokeMethod<String>('requestToken', {
              'requestHash': requestHash,
              'cloudProjectNumber': cloudProjectNumber,
            })
            .timeout(timeout);
        if (token == null || token.isEmpty) {
          throw StateError('Play Integrity token is unavailable.');
        }
        return token;
      } on TimeoutException {
        if (attempt < maxAttempts) {
          continue;
        }
        throw StateError('Play Integrity token request timed out.');
      } on MissingPluginException {
        throw StateError('Play Integrity channel is unavailable.');
      } on PlatformException catch (error) {
        if (attempt < maxAttempts) {
          continue;
        }
        throw StateError(
          'Play Integrity token request failed (${error.code}).',
        );
      }
    }
  }
}
