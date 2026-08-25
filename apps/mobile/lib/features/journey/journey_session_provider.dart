import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import '../../generated/journey_v3/journey_v3_contract.dart';
import 'domain/journey_repository.dart';

abstract interface class JourneyV3IntegrityAttestor {
  Future<String> attest(String requestHash);
}

/// One process-scoped Journey session owner. Search and timetable consumers
/// share its cached, expiry-checked token; it never retries a rejected call.
class JourneySessionProvider {
  JourneySessionProvider({
    required JourneyRepository repository,
    required JourneyV3IntegrityAttestor attestor,
    DateTime Function()? now,
    String Function(int entropyBytes)? nonceGenerator,
  }) : this._(
         repository,
         attestor,
         now ?? DateTime.now,
         nonceGenerator ?? _secureNonce,
         _JourneyV3SessionIntegritySpec.fromGeneratedArtifact(),
       );

  JourneySessionProvider._(
    this._repository,
    this._attestor,
    this._now,
    this._nonceGenerator,
    this._spec,
  );

  final JourneyRepository _repository;
  final JourneyV3IntegrityAttestor _attestor;
  final DateTime Function() _now;
  final String Function(int entropyBytes) _nonceGenerator;
  final _JourneyV3SessionIntegritySpec _spec;

  JourneySessionResponse? _session;
  Future<JourneySessionResponse>? _inFlight;
  Object? _inFlightToken;
  int _epoch = 0;

  Future<JourneySessionResponse> session() {
    final cached = _session;
    if (cached != null && cached.expiresAt.isAfter(_now())) {
      return Future<JourneySessionResponse>.value(cached);
    }
    _session = null;
    final current = _inFlight;
    if (current != null) return current;
    final token = Object();
    final issued = _issue(_epoch, token);
    _inFlight = issued;
    _inFlightToken = token;
    return issued;
  }

  void invalidate() {
    _epoch++;
    _session = null;
    _inFlight = null;
    _inFlightToken = null;
  }

  Future<JourneySessionResponse> _issue(int epoch, Object token) async {
    try {
      final nonce = _nonceGenerator(_spec.nonceEntropyBytes);
      if (!_spec.noncePattern.hasMatch(nonce)) {
        throw const JourneySessionInvalid();
      }
      final integrityToken = await _attestor.attest(_requestHash(nonce));
      if (epoch != _epoch) throw const JourneySessionInvalid();
      final issued = await _repository.issueSession(
        JourneySessionRequest(
          integrityToken: integrityToken,
          clientNonce: nonce,
        ),
      );
      final now = _now();
      if (epoch != _epoch ||
          issued.scope.wire != _spec.scope ||
          !issued.expiresAt.isAfter(now) ||
          issued.expiresAt.isAfter(
            now.add(Duration(seconds: _spec.ttlSeconds)),
          )) {
        throw const JourneySessionInvalid();
      }
      _session = issued;
      return issued;
    } catch (_) {
      if (epoch == _epoch) _session = null;
      rethrow;
    } finally {
      if (identical(_inFlightToken, token)) {
        _inFlight = null;
        _inFlightToken = null;
      }
    }
  }

  String _requestHash(String nonce) {
    final canonical = _spec.canonicalPayloadTemplate.replaceAll(
      '<clientNonce>',
      nonce,
    );
    final hash = base64Url
        .encode(sha256.convert(utf8.encode(canonical)).bytes)
        .replaceAll('=', '');
    if (!_spec.requestHashPattern.hasMatch(hash)) {
      throw const JourneySessionInvalid();
    }
    return hash;
  }

  static String _secureNonce(int entropyBytes) {
    final random = Random.secure();
    return base64Url
        .encode(List<int>.generate(entropyBytes, (_) => random.nextInt(256)))
        .replaceAll('=', '');
  }
}

class JourneySessionInvalid implements Exception {
  const JourneySessionInvalid();
}

class _JourneyV3SessionIntegritySpec {
  const _JourneyV3SessionIntegritySpec({
    required this.nonceEntropyBytes,
    required this.noncePattern,
    required this.requestHashPattern,
    required this.canonicalPayloadTemplate,
    required this.scope,
    required this.ttlSeconds,
  });
  final int nonceEntropyBytes;
  final RegExp noncePattern;
  final RegExp requestHashPattern;
  final String canonicalPayloadTemplate;
  final String scope;
  final int ttlSeconds;

  factory _JourneyV3SessionIntegritySpec.fromGeneratedArtifact() {
    try {
      final root = jsonDecode(journeyV3SessionIntegritySpecJson);
      if (root is! Map<String, Object?>) throw const FormatException();
      final nonce = root['nonce'];
      final requestHash = root['requestHash'];
      final session = root['session'];
      if (nonce is! Map<String, Object?> ||
          requestHash is! Map<String, Object?> ||
          session is! Map<String, Object?> ||
          root['schemaVersion'] != 'JOURNEY_V3_SESSION_INTEGRITY_V1' ||
          root['operationId'] != 'issueJourneySession' ||
          nonce['source'] != 'CSPRNG' ||
          nonce['encoding'] != 'BASE64URL_NO_PADDING' ||
          nonce['entropyBytes'] != 16 ||
          requestHash['algorithm'] != 'SHA-256' ||
          requestHash['encoding'] != 'BASE64URL_NO_PADDING' ||
          requestHash['purpose'] != 'journey:v3:session' ||
          requestHash['version'] != 1 ||
          session['scope'] != 'journey:v3' ||
          session['ttlSeconds'] != 600) {
        throw const FormatException();
      }
      final noncePattern = nonce['pattern'];
      final requestHashPattern = requestHash['pattern'];
      final template = requestHash['canonicalPayloadUtf8Template'];
      if (noncePattern is! String ||
          requestHashPattern is! String ||
          template is! String ||
          template !=
              '{"clientNonce":"<clientNonce>","purpose":"journey:v3:session","version":1}') {
        throw const FormatException();
      }
      return _JourneyV3SessionIntegritySpec(
        nonceEntropyBytes: nonce['entropyBytes']! as int,
        noncePattern: RegExp(noncePattern),
        requestHashPattern: RegExp(requestHashPattern),
        canonicalPayloadTemplate: template,
        scope: session['scope']! as String,
        ttlSeconds: session['ttlSeconds']! as int,
      );
    } catch (_) {
      throw const FormatException('Invalid generated Journey V3 session spec');
    }
  }
}
