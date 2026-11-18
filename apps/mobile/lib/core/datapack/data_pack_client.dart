import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kReleaseMode;

import 'data_pack_manifest.dart';
import 'data_pack_update_state.dart';

const _manifestFetchTimeout = Duration(seconds: 8);
const _defaultMaxManifestBytes = 2 * 1024 * 1024;

class DataPackClient {
  DataPackClient({
    required this.manifestUri,
    required this.stateRepository,
    this.productionSigningPublicKey,
    this.productionSigningPublicKeys,
    this.expectedManifestChannel = 'production',
    this.maxResponseBytes = _defaultMaxManifestBytes,
    this.isReleaseMode = kReleaseMode,
    HttpClient? httpClient,
    DateTime Function()? now,
  }) : _httpClient = httpClient ?? HttpClient(),
       _ownsHttpClient = httpClient == null,
       _now = now ?? DateTime.now {
    if (!isAllowedDataPackTransportUri(
      manifestUri,
      isReleaseMode: isReleaseMode,
    )) {
      throw ArgumentError.value(
        manifestUri,
        'manifestUri',
        'HTTPS manifest URI is required.',
      );
    }
  }

  final Uri manifestUri;
  final DataPackUpdateStateRepository stateRepository;
  final DataPackSigningPublicKey? productionSigningPublicKey;
  final List<DataPackSigningPublicKey>? productionSigningPublicKeys;
  final String expectedManifestChannel;
  final int maxResponseBytes;
  final bool isReleaseMode;
  final HttpClient _httpClient;
  final bool _ownsHttpClient;
  final DateTime Function() _now;

  void close({bool force = false}) {
    if (_ownsHttpClient) {
      _httpClient.close(force: force);
    }
  }

  Future<DataPackManifestFetchResult> fetchManifestIfNeeded() async {
    final cache = await stateRepository.readManifestCache();
    if (cache != null && stateRepository.isFresh(cache)) {
      return const DataPackManifestFetchResult(
        status: DataPackManifestFetchStatus.freshCache,
      );
    }

    final request = await _httpClient
        .getUrl(manifestUri)
        .timeout(_manifestFetchTimeout);
    request.followRedirects = false;
    final etag = cache?.etag;
    if (etag != null && etag.isNotEmpty) {
      request.headers.set(HttpHeaders.ifNoneMatchHeader, etag);
    }
    request.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');

    final response = await request.close().timeout(_manifestFetchTimeout);
    if (response.statusCode == HttpStatus.notModified && cache != null) {
      await response.drain<void>();
      final checkedAt = _now().toUtc();
      await stateRepository.saveManifestCache(
        etag: cache.etag,
        checkedAt: checkedAt,
        ttl: _cacheTtlBoundedByExpiry(cache.ttl, cache.expiresAt, checkedAt),
        expiresAt: cache.expiresAt,
      );
      return const DataPackManifestFetchResult(
        status: DataPackManifestFetchStatus.notModified,
      );
    }
    if (response.statusCode != HttpStatus.ok) {
      await response.drain<void>();
      throw const DataPackClientException('이동 정보를 확인하지 못했어요.');
    }

    final builder = BytesBuilder(copy: false);
    var totalBytes = 0;
    await for (final chunk in response.timeout(_manifestFetchTimeout)) {
      totalBytes += chunk.length;
      if (totalBytes > maxResponseBytes) {
        throw const DataPackClientException('이동 정보가 허용 크기를 초과했습니다.');
      }
      builder.add(chunk);
    }
    final Object? decoded;
    try {
      final body = utf8.decode(builder.takeBytes());
      decoded = jsonDecode(body);
    } on FormatException {
      throw const DataPackClientException('이동 정보 형식이 올바르지 않습니다.');
    }
    if (decoded is! Map<String, Object?>) {
      throw const DataPackClientException('이동 정보 형식이 올바르지 않습니다.');
    }
    final DataPackManifest manifest;
    try {
      manifest = DataPackManifest.fromJson(
        decoded,
        productionSigningPublicKey: productionSigningPublicKey,
        productionSigningPublicKeys: productionSigningPublicKeys,
      );
    } on FormatException {
      throw const DataPackClientException('이동 정보 형식이 올바르지 않습니다.');
    }
    _ensureExpectedManifestChannel(manifest);
    if (manifest.isExpiredAt(_now())) {
      throw const DataPackClientException('이동 정보가 만료되었습니다.');
    }
    try {
      await stateRepository.ensureManifestCanBeAccepted(manifest);
    } on DataPackManifestReplayException catch (error) {
      throw DataPackClientException(error.message);
    }
    return DataPackManifestFetchResult(
      status: DataPackManifestFetchStatus.updated,
      manifest: manifest,
      etag: response.headers.value(HttpHeaders.etagHeader),
      checkedAt: _now().toUtc(),
    );
  }

  Future<void> saveManifestCache(DataPackManifestFetchResult result) async {
    final manifest = result.manifest;
    final checkedAt = result.checkedAt;
    if (manifest == null || checkedAt == null) {
      return;
    }
    _ensureExpectedManifestChannel(manifest);
    final expiresAt = manifest.expiresAt;
    await stateRepository.saveAcceptedManifestState(manifest);
    await stateRepository.saveManifestCache(
      etag: result.etag,
      checkedAt: checkedAt,
      ttl: _cacheTtlBoundedByExpiry(manifest.ttl, expiresAt, checkedAt),
      expiresAt: expiresAt,
    );
  }

  Duration _cacheTtlBoundedByExpiry(
    Duration ttl,
    DateTime? expiresAt,
    DateTime checkedAt,
  ) {
    if (expiresAt == null) {
      return ttl;
    }
    final expiryTtl = expiresAt.difference(checkedAt.toUtc());
    if (expiryTtl <= Duration.zero) {
      throw const DataPackClientException('이동 정보가 만료되었습니다.');
    }
    return expiryTtl < ttl ? expiryTtl : ttl;
  }

  void _ensureExpectedManifestChannel(DataPackManifest manifest) {
    if (!manifest.hasReplayProtection) {
      return;
    }
    final expected = expectedManifestChannel.trim().isEmpty
        ? 'production'
        : expectedManifestChannel.trim();
    if (manifest.channel != expected) {
      throw const DataPackClientException('이동 정보가 앱과 맞지 않습니다.');
    }
  }
}

class DataPackManifestFetchResult {
  const DataPackManifestFetchResult({
    required this.status,
    this.manifest,
    this.etag,
    this.checkedAt,
  });

  final DataPackManifestFetchStatus status;
  final DataPackManifest? manifest;
  final String? etag;
  final DateTime? checkedAt;
}

enum DataPackManifestFetchStatus { freshCache, notModified, updated }

class DataPackClientException implements Exception {
  const DataPackClientException(this.message);

  final String message;

  @override
  String toString() => message;
}

bool isAllowedDataPackTransportUri(Uri uri, {required bool isReleaseMode}) {
  if (!uri.hasAuthority || uri.host.isEmpty || uri.userInfo.isNotEmpty) {
    return false;
  }
  if (uri.scheme == 'https') {
    return true;
  }
  if (isReleaseMode || uri.scheme != 'http') {
    return false;
  }
  final host = uri.host.toLowerCase();
  return host == 'localhost' ||
      host == '127.0.0.1' ||
      host == '::1' ||
      host == '[::1]';
}
