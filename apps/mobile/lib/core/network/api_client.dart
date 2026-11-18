import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kReleaseMode;

import 'api_error.dart';

export 'api_error.dart';

const defaultApiTimeout = Duration(seconds: 8);
const defaultMaxApiResponseBytes = 8 * 1024 * 1024;

class ApiClient {
  ApiClient({
    required this.baseUri,
    HttpClient? httpClient,
    this.timeout = defaultApiTimeout,
    this.maxResponseBytes = defaultMaxApiResponseBytes,
    this.isReleaseMode = kReleaseMode,
  }) : _httpClient = httpClient ?? HttpClient(),
       _ownsHttpClient = httpClient == null {
    _validateTransportUri(baseUri, isReleaseMode: isReleaseMode);
  }

  final Uri baseUri;
  final Duration timeout;
  final int maxResponseBytes;
  final bool isReleaseMode;
  final HttpClient _httpClient;
  final bool _ownsHttpClient;

  void close({bool force = false}) {
    if (_ownsHttpClient) {
      _httpClient.close(force: force);
    }
  }

  Future<ApiResponse> getJson(
    String path, {
    Map<String, String> headers = const {},
  }) {
    return _requestJson(HttpMethod.get, path, headers: headers);
  }

  Future<ApiResponse> deleteJson(
    String path, {
    Map<String, String> headers = const {},
  }) {
    return _requestJson(HttpMethod.delete, path, headers: headers);
  }

  Future<ApiResponse> postJson(
    String path, {
    required Map<String, Object?> body,
    Map<String, String> headers = const {},
  }) {
    return _requestJson(
      HttpMethod.post,
      path,
      headers: headers,
      requestBody: body,
    );
  }

  Future<ApiResponse> putJson(
    String path, {
    Map<String, Object?>? body,
    Map<String, String> headers = const {},
  }) {
    return _requestJson(
      HttpMethod.put,
      path,
      headers: headers,
      requestBody: body,
    );
  }

  Future<ApiResponse> putBytes(
    Uri uri, {
    required List<int> body,
    required ContentType contentType,
    Map<String, String> headers = const {},
  }) async {
    _validateTransportUri(uri, isReleaseMode: isReleaseMode);
    try {
      final request = await _httpClient.putUrl(uri).timeout(timeout);
      request.followRedirects = false;
      headers.forEach(request.headers.set);
      request.headers.contentType = contentType;
      request.contentLength = body.length;
      request.add(body);

      final response = await request.close().timeout(timeout);
      await response.drain<void>().timeout(timeout);
      if (_isRedirectStatus(response.statusCode)) {
        throw ApiException(
          '리다이렉트 응답은 허용되지 않습니다.',
          statusCode: response.statusCode,
          path: uri.path,
        );
      }
      return ApiResponse(statusCode: response.statusCode, jsonBody: null);
    } on ApiException {
      rethrow;
    } on TimeoutException catch (error, stackTrace) {
      throw ApiException(
        '연결 시간이 초과되었습니다. 잠시 후 다시 시도해 주세요.',
        path: uri.path,
        cause: error,
        causeStackTrace: stackTrace,
      );
    } on SocketException catch (error, stackTrace) {
      throw ApiException(
        '인터넷 연결을 확인하지 못했어요. 연결 상태를 확인해 주세요.',
        path: uri.path,
        cause: error,
        causeStackTrace: stackTrace,
      );
    } catch (error, stackTrace) {
      throw ApiException(
        '요청을 완료하지 못했어요. 잠시 후 다시 시도해 주세요.',
        path: uri.path,
        cause: error,
        causeStackTrace: stackTrace,
      );
    }
  }

  Future<ApiResponse> _requestJson(
    HttpMethod method,
    String path, {
    required Map<String, String> headers,
    Map<String, Object?>? requestBody,
  }) async {
    final uri = _resolveSameOriginUri(path);
    try {
      final request = await _open(method, uri).timeout(timeout);
      request.headers.set(HttpHeaders.acceptHeader, ContentType.json.mimeType);
      headers.forEach(request.headers.set);
      if (requestBody != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(requestBody));
      }

      final response = await request.close().timeout(timeout);
      if (_isRedirectStatus(response.statusCode)) {
        await response.drain<void>().timeout(timeout);
        throw ApiException(
          '리다이렉트 응답은 허용되지 않습니다.',
          statusCode: response.statusCode,
          path: uri.path,
        );
      }
      final etag = response.headers.value(HttpHeaders.etagHeader);
      final responseBody = await _readResponseBody(response, uri);
      if (!_isSuccessStatus(response.statusCode)) {
        return ApiResponse(
          statusCode: response.statusCode,
          jsonBody: _tryDecodeJson(responseBody),
          etag: etag,
        );
      }
      if (response.statusCode == HttpStatus.noContent) {
        return ApiResponse(
          statusCode: response.statusCode,
          jsonBody: null,
          etag: etag,
        );
      }
      final decoded = _decodeJson(
        responseBody,
        statusCode: response.statusCode,
        uri: uri,
      );
      return ApiResponse(
        statusCode: response.statusCode,
        jsonBody: decoded,
        etag: etag,
      );
    } on ApiException {
      rethrow;
    } on TimeoutException catch (error, stackTrace) {
      throw ApiException(
        '연결 시간이 초과되었습니다. 잠시 후 다시 시도해 주세요.',
        path: uri.path,
        cause: error,
        causeStackTrace: stackTrace,
      );
    } on SocketException catch (error, stackTrace) {
      throw ApiException(
        '인터넷 연결을 확인하지 못했어요. 연결 상태를 확인해 주세요.',
        path: uri.path,
        cause: error,
        causeStackTrace: stackTrace,
      );
    } catch (error, stackTrace) {
      throw ApiException(
        '요청을 완료하지 못했어요. 잠시 후 다시 시도해 주세요.',
        path: uri.path,
        cause: error,
        causeStackTrace: stackTrace,
      );
    }
  }

  Future<String> _readResponseBody(HttpClientResponse response, Uri uri) async {
    final builder = BytesBuilder(copy: false);
    final completer = Completer<Uint8List>();
    var totalBytes = 0;
    late final StreamSubscription<List<int>> subscription;
    subscription = response.listen(
      (chunk) {
        totalBytes += chunk.length;
        if (totalBytes > maxResponseBytes) {
          unawaited(subscription.cancel());
          completer.completeError(
            ApiException(
              '받은 정보가 너무 커서 처리하지 못했어요.',
              statusCode: response.statusCode,
              path: uri.path,
            ),
          );
          return;
        }
        builder.add(chunk);
      },
      onError: completer.completeError,
      onDone: () => completer.complete(builder.takeBytes()),
      cancelOnError: true,
    );
    final Uint8List bytes;
    try {
      bytes = await completer.future.timeout(timeout);
    } on TimeoutException {
      await subscription.cancel();
      rethrow;
    }
    try {
      return utf8.decode(bytes);
    } on FormatException catch (error, stackTrace) {
      throw ApiException(
        '받은 정보를 읽지 못했어요. 잠시 후 다시 시도해 주세요.',
        statusCode: response.statusCode,
        path: uri.path,
        cause: error,
        causeStackTrace: stackTrace,
      );
    }
  }

  Object? _tryDecodeJson(String responseBody) {
    if (responseBody.trim().isEmpty) return null;
    try {
      return jsonDecode(responseBody);
    } on FormatException {
      return null;
    }
  }

  Uri _resolveSameOriginUri(String path) {
    final Uri uri;
    try {
      uri = baseUri.resolve(path);
    } on FormatException catch (error, stackTrace) {
      throw ApiException(
        '허용되지 않은 요청 경로입니다.',
        path: path,
        cause: error,
        causeStackTrace: stackTrace,
      );
    }
    if (uri.scheme != baseUri.scheme ||
        uri.host != baseUri.host ||
        uri.port != baseUri.port ||
        uri.userInfo.isNotEmpty) {
      throw ApiException('허용되지 않은 요청 대상입니다.', path: uri.path);
    }
    return uri;
  }

  Future<HttpClientRequest> _open(HttpMethod method, Uri uri) async {
    final Future<HttpClientRequest> pending;
    switch (method) {
      case HttpMethod.get:
        pending = _httpClient.getUrl(uri);
      case HttpMethod.delete:
        pending = _httpClient.deleteUrl(uri);
      case HttpMethod.post:
        pending = _httpClient.postUrl(uri);
      case HttpMethod.put:
        pending = _httpClient.putUrl(uri);
    }
    final request = await pending;
    request.followRedirects = false;
    return request;
  }
}

void _validateTransportUri(Uri uri, {required bool isReleaseMode}) {
  if (!uri.hasAuthority || uri.host.isEmpty || uri.userInfo.isNotEmpty) {
    throw ApiException('안전하지 않은 연결 주소입니다.', path: uri.path);
  }
  if (uri.scheme == 'https') {
    return;
  }
  if (!isReleaseMode && uri.scheme == 'http' && _isLoopbackHost(uri.host)) {
    return;
  }
  throw ApiException('HTTPS 연결이 필요합니다.', path: uri.path);
}

bool _isLoopbackHost(String host) {
  final normalized = host.toLowerCase();
  return normalized == 'localhost' ||
      normalized == '127.0.0.1' ||
      normalized == '::1' ||
      normalized == '[::1]';
}

bool _isRedirectStatus(int statusCode) => statusCode >= 300 && statusCode < 400;

class ApiResponse {
  const ApiResponse({
    required this.statusCode,
    required this.jsonBody,
    this.etag,
  });

  final int statusCode;
  final Object? jsonBody;

  /// 응답 ETag 헤더(있으면). 조건부 GET(If-None-Match) 캐시에 쓴다.
  final String? etag;

  bool get isNotModified => statusCode == HttpStatus.notModified;

  bool get isUnauthorized => statusCode == HttpStatus.unauthorized;
  bool get isOk => statusCode == HttpStatus.ok;
  bool get isSuccess => _isSuccessStatus(statusCode);

  Object? requireSuccessData({
    required Object Function() errorFactory,
    int? expectedStatusCode,
  }) {
    final statusMatches = expectedStatusCode == null
        ? isSuccess
        : statusCode == expectedStatusCode;
    if (!statusMatches) {
      throw errorFactory();
    }

    final decoded = jsonBody;
    if (decoded is! Map<String, Object?> || decoded['success'] != true) {
      throw errorFactory();
    }
    return decoded['data'];
  }
}

enum HttpMethod { get, delete, post, put }

Object? _decodeJson(String body, {required int statusCode, required Uri uri}) {
  try {
    return jsonDecode(body);
  } on FormatException catch (error, stackTrace) {
    throw ApiException(
      '받은 정보를 읽지 못했어요. 잠시 후 다시 시도해 주세요.',
      statusCode: statusCode,
      path: uri.path,
      cause: error,
      causeStackTrace: stackTrace,
    );
  }
}

bool _isSuccessStatus(int statusCode) {
  return statusCode >= HttpStatus.ok && statusCode < HttpStatus.multipleChoices;
}
