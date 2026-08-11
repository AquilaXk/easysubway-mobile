import 'dart:convert';

import 'package:image_picker/image_picker.dart';

import '../domain/facility_report_photo.dart';

const _facilityReportPhotoTooLargeMessage = '사진이 너무 큽니다. 다른 사진을 선택해 주세요.';

class ImagePickerFacilityReportPhotoPicker {
  ImagePickerFacilityReportPhotoPicker({ImagePicker? imagePicker})
    : _imagePicker = imagePicker ?? ImagePicker();

  static const int _maxPhotoBytes = 900 * 1024;
  static const double _maxPhotoDimension = 1600;
  static const int _imageQuality = 72;

  final ImagePicker _imagePicker;

  Future<FacilityReportPhotoAttachment?> pickFromGallery() {
    return _pick(ImageSource.gallery);
  }

  Future<FacilityReportPhotoAttachment?> takePhoto() {
    return _pick(ImageSource.camera);
  }

  Future<FacilityReportPhotoAttachment?> retrieveLostPhoto() async {
    final response = await _imagePicker.retrieveLostData();
    if (response.isEmpty) {
      return null;
    }
    if (response.exception != null) {
      throw const FacilityReportPhotoException('사진을 다시 선택해 주세요.');
    }
    if (response.type != RetrieveType.image || response.file == null) {
      return null;
    }
    return _attachmentFromFile(response.file!);
  }

  Future<FacilityReportPhotoAttachment?> _pick(ImageSource source) async {
    final image = await _imagePicker.pickImage(
      source: source,
      maxWidth: _maxPhotoDimension,
      maxHeight: _maxPhotoDimension,
      imageQuality: _imageQuality,
    );
    if (image == null) {
      return null;
    }
    return _attachmentFromFile(image);
  }

  Future<FacilityReportPhotoAttachment> _attachmentFromFile(XFile image) async {
    final bytes = await image.readAsBytes();
    if (bytes.lengthInBytes > _maxPhotoBytes) {
      throw const FacilityReportPhotoException(
        _facilityReportPhotoTooLargeMessage,
      );
    }
    return FacilityReportPhotoAttachment(
      fileName: image.name.isEmpty ? 'facility-report.jpg' : image.name,
      contentType: _contentTypeFromName(image.name),
      dataBase64: base64Encode(bytes),
    );
  }

  String _contentTypeFromName(String fileName) {
    final lowerName = fileName.toLowerCase();
    if (lowerName.endsWith('.png')) {
      return 'image/png';
    }
    if (lowerName.endsWith('.webp')) {
      return 'image/webp';
    }
    return 'image/jpeg';
  }
}
