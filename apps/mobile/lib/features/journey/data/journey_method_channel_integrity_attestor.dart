import 'package:flutter/services.dart';

import '../application/journey_search_controller.dart';

class JourneyMethodChannelIntegrityAttestor
    implements JourneyV3IntegrityAttestor {
  JourneyMethodChannelIntegrityAttestor({
    MethodChannel? channel,
    this.cloudProjectNumber = const String.fromEnvironment(
      'EASYSUBWAY_PLAY_INTEGRITY_CLOUD_PROJECT_NUMBER',
    ),
  }) : _channel =
           channel ??
           const MethodChannel(
             'com.easysubway.easysubway_mobile/play_integrity',
           );

  final MethodChannel _channel;
  final String cloudProjectNumber;

  @override
  Future<String> attest(String requestHash) async {
    if (cloudProjectNumber.isEmpty) {
      throw StateError('Play Integrity cloud project is not configured.');
    }
    final token = await _channel.invokeMethod<String>('requestToken', {
      'requestHash': requestHash,
      'cloudProjectNumber': cloudProjectNumber,
    });
    if (token == null || token.isEmpty) {
      throw StateError('Play Integrity token is unavailable.');
    }
    return token;
  }
}
