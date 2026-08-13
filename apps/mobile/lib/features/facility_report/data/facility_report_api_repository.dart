import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';

import '../../../auth_headers.dart';
import '../../../core/network/api_client.dart';
import '../../../mobile_error_reporter.dart';
import '../domain/facility_report_exception.dart';
import '../domain/facility_report_receipt.dart';
import '../domain/facility_report_repository.dart';
import '../domain/facility_report_request.dart';
import '../domain/facility_report_result.dart';
import 'facility_report_photo_upload_intent.dart';
import 'facility_report_result_projection.dart';

const _facilityReportTimeout = Duration(seconds: 8);
const _facilityReportPhotoUploadMaxAttempts = 2;

class FacilityReportApiRepository implements FacilityReportRepository {
  FacilityReportApiRepository({
    required this.baseUri,
    this.authProvider,
    this.receiptStore,
    ApiClient? apiClient,
    HttpClient? httpClient,
  }) : _apiClient =
           apiClient ?? ApiClient(baseUri: baseUri, httpClient: httpClient);

  final Uri baseUri;
  final AuthorizationHeaderProvider? authProvider;
  final FacilityReportReceiptStore? receiptStore;
  final ApiClient _apiClient;

  @override
  Future<FacilityReportResult> createReport(
    FacilityReportRequest reportRequest,
  ) async {
    try {
      return await _postReportWithAuthorizationRetry(reportRequest);
    } on FacilityReportException {
      rethrow;
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '시설 제보 접수 응답 처리 중 예외가 발생했습니다.',
      );
      throw const FacilityReportException(facilityReportSubmitFailureMessage);
    }
  }

  Future<FacilityReportResult> _postReportWithAuthorizationRetry(
    FacilityReportRequest reportRequest,
  ) async {
    final preparedRequest = await _prepareReportRequest(reportRequest);
    for (var attempt = 0; attempt < 2; attempt++) {
      final authorizationHeader = await authProvider
          ?.authorizationHeader()
          .timeout(_facilityReportTimeout);
      final response = await _apiClient.postJson(
        '/api/v1/reports',
        body: preparedRequest.toJson(),
        headers: authorizationHeader == null
            ? const {}
            : {HttpHeaders.authorizationHeader: authorizationHeader},
      );

      if (response.isUnauthorized &&
          authorizationHeader != null &&
          attempt == 0) {
        // 만료된 인증은 비우고 한 번만 다시 시도한다.
        await authProvider!.invalidateAuthorization().timeout(
          _facilityReportTimeout,
        );
        continue;
      }

      if (response.statusCode != HttpStatus.created && !response.isOk) {
        throw const FacilityReportException(facilityReportSubmitFailureMessage);
      }

      final result = facilityReportResultFromJsonEnvelope(
        response.jsonBody,
        errorMessage: facilityReportSubmitFailureMessage,
      );
      await _saveReceiptIfPresentSafely(result);
      return result;
    }
    throw const FacilityReportException(facilityReportSubmitFailureMessage);
  }

  Future<FacilityReportRequest> _prepareReportRequest(
    FacilityReportRequest reportRequest,
  ) async {
    final request = reportRequest.trimmed();
    final clientSubmissionId = request.clientSubmissionId?.isNotEmpty == true
        ? request.clientSubmissionId!
        : _newClientSubmissionId();
    if (request.photoDataBase64 == null || request.photoDataBase64!.isEmpty) {
      return request.withClientSubmissionId(clientSubmissionId);
    }
    final photoBytes = base64Decode(request.photoDataBase64!);
    final photoSha256 = sha256.convert(photoBytes).toString();
    final uploadIntent = await _createPhotoUploadIntent(
      clientSubmissionId: clientSubmissionId,
      request: request,
      photoSha256: photoSha256,
      photoSizeBytes: photoBytes.length,
    );
    await _uploadPhoto(uploadIntent, request.photoContentType!, photoBytes);
    return request.withUploadedPhoto(
      clientSubmissionId: clientSubmissionId,
      photoObjectKey: uploadIntent.objectKey,
      photoSha256: photoSha256,
      photoSizeBytes: photoBytes.length,
    );
  }

  Future<FacilityReportPhotoUploadIntent> _createPhotoUploadIntent({
    required String clientSubmissionId,
    required FacilityReportRequest request,
    required String photoSha256,
    required int photoSizeBytes,
  }) async {
    final uploadResponse = await _apiClient.postJson(
      '/api/v1/report-uploads',
      body: {
        'clientSubmissionId': clientSubmissionId,
        'photoFileName': request.photoFileName,
        'photoContentType': request.photoContentType,
        'photoSha256': photoSha256,
        'photoSizeBytes': photoSizeBytes,
      },
    );

    if (uploadResponse.statusCode != HttpStatus.created &&
        !uploadResponse.isOk) {
      throw const FacilityReportException(facilityReportSubmitFailureMessage);
    }
    return FacilityReportPhotoUploadIntent.fromJson(
      uploadResponse.jsonBody,
      errorMessage: facilityReportSubmitFailureMessage,
    );
  }

  Future<void> _uploadPhoto(
    FacilityReportPhotoUploadIntent uploadIntent,
    String contentType,
    List<int> photoBytes,
  ) async {
    if (uploadIntent.uploadMethod.trim().toUpperCase() != 'PUT') {
      throw const FacilityReportException(facilityReportSubmitFailureMessage);
    }

    for (
      var attempt = 0;
      attempt < _facilityReportPhotoUploadMaxAttempts;
      attempt++
    ) {
      try {
        final uploadResponse = await _apiClient.putBytes(
          uploadIntent.uploadUri(baseUri),
          body: photoBytes,
          contentType: ContentType.parse(contentType),
          headers: uploadIntent.uploadHeaders,
        );
        if (uploadResponse.isSuccess) {
          return;
        }
        if (!_isRetryablePhotoUploadStatus(uploadResponse.statusCode) ||
            attempt == _facilityReportPhotoUploadMaxAttempts - 1) {
          throw const FacilityReportException(
            facilityReportSubmitFailureMessage,
          );
        }
      } on ApiException {
        if (attempt == _facilityReportPhotoUploadMaxAttempts - 1) {
          rethrow;
        }
      }
    }
    throw const FacilityReportException(facilityReportSubmitFailureMessage);
  }

  Future<void> _saveReceiptIfPresentSafely(FacilityReportResult result) async {
    try {
      await _saveReceiptIfPresent(result).timeout(_facilityReportTimeout);
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '시설 제보 receipt token 저장 중 예외가 발생했습니다.',
      );
    }
  }

  Future<void> _saveReceiptIfPresent(FacilityReportResult result) async {
    final receiptToken = result.receiptToken;
    if (receiptToken == null || receiptToken.isEmpty || receiptStore == null) {
      return;
    }
    await receiptStore!.saveReceipt(
      FacilityReportReceipt(
        receiptId: result.id,
        reportId: result.id,
        publicReceiptCode: result.publicReceiptCode,
        status: result.status,
        receiptToken: receiptToken,
        createdAt: DateTime.now(),
      ),
    );
  }

  String _newClientSubmissionId() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  @override
  Future<FacilityReportResult> getReport(String reportId) async {
    final trimmedReportId = reportId.trim();
    if (trimmedReportId.isEmpty) {
      throw const FacilityReportException(facilityReportStatusFailureMessage);
    }

    try {
      final receiptToken = await receiptStore
          ?.receiptTokenForReport(trimmedReportId)
          .timeout(_facilityReportTimeout);
      final response = await _apiClient.getJson(
        '/api/v1/reports/${Uri.encodeComponent(trimmedReportId)}',
        headers: receiptToken == null || receiptToken.isEmpty
            ? const {}
            : {'X-Easysubway-Report-Receipt-Token': receiptToken},
      );

      if (!response.isOk) {
        throw const FacilityReportException(facilityReportStatusFailureMessage);
      }

      return facilityReportResultFromJsonEnvelope(
        response.jsonBody,
        errorMessage: facilityReportStatusFailureMessage,
      );
    } on FacilityReportException {
      rethrow;
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '시설 제보 진행 상황 응답 처리 중 예외가 발생했습니다.',
      );
      throw const FacilityReportException(facilityReportStatusFailureMessage);
    }
  }

  @override
  Future<List<FacilityReportResult>> listMyReports() async {
    try {
      final receipts =
          await receiptStore?.listReceipts().timeout(_facilityReportTimeout) ??
          const <FacilityReportReceipt>[];
      if (receipts.isEmpty) {
        return const [];
      }

      return Future.wait(
        receipts.map((receipt) async {
          try {
            final report = await getReport(receipt.reportId);
            final reportWithReceiptCode =
                facilityReportResultWithReceiptCodeFallback(report, receipt);
            await _refreshReceiptIfPossible(receipt, reportWithReceiptCode);
            return reportWithReceiptCode;
          } catch (error, stackTrace) {
            reportMobileError(
              error,
              stackTrace,
              context: '시설 제보 receipt 기반 상태 조회 중 예외가 발생했습니다.',
            );
            return facilityReportResultFromReceipt(receipt);
          }
        }),
      );
    } on FacilityReportException {
      rethrow;
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '내 시설 제보 목록 응답 처리 중 예외가 발생했습니다.',
      );
      throw const FacilityReportException(facilityReportListFailureMessage);
    }
  }

  Future<void> _refreshReceiptIfPossible(
    FacilityReportReceipt receipt,
    FacilityReportResult report,
  ) async {
    try {
      await receiptStore
          ?.saveReceipt(
            FacilityReportReceipt(
              receiptId: receipt.receiptId,
              reportId: receipt.reportId,
              publicReceiptCode:
                  nonBlankFacilityReportString(report.publicReceiptCode) ??
                  nonBlankFacilityReportString(receipt.publicReceiptCode),
              status: report.status,
              receiptToken: receipt.receiptToken,
              createdAt: receipt.createdAt,
            ),
          )
          .timeout(_facilityReportTimeout);
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '시설 제보 receipt 상태 갱신 중 예외가 발생했습니다.',
      );
    }
  }
}

bool _isRetryablePhotoUploadStatus(int statusCode) {
  return statusCode == HttpStatus.requestTimeout ||
      statusCode == HttpStatus.tooManyRequests ||
      statusCode >= HttpStatus.internalServerError;
}
