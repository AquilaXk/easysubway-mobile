import 'dart:async';

import 'package:flutter/material.dart';
import 'accessible_design.dart';
import 'app/easy_subway_family_app_bar.dart';
import 'design_tokens.dart';
import 'features/facility_report/application/facility_report_controller.dart';
import 'features/facility_report/application/facility_report_state.dart';
import 'features/facility_report/data/image_picker_facility_report_photo_picker.dart';
import 'features/facility_report/domain/facility_report_exception.dart';
import 'features/facility_report/domain/facility_report_location.dart';
import 'features/facility_report/domain/facility_report_photo.dart';
import 'features/facility_report/domain/facility_report_repository.dart';
import 'features/facility_report/domain/facility_report_result.dart';
import 'features/facility_report/domain/facility_report_target.dart';
import 'features/facility_report/domain/facility_report_type.dart';
import 'features/facility_report/presentation/facility_report_form_components.dart';
import 'features/facility_report/presentation/facility_report_result_labels.dart';
import 'features/facility_report/presentation/facility_report_type_options.dart';
import 'mobile_error_reporter.dart';

const _facilityReportLocationDisabledMessage =
    '휴대전화의 위치 기능을 켜 주세요. 가까운 역을 찾는 데 필요합니다.';
const _facilityReportLocationPermissionMessage = '현재 위치를 사용할 수 없어요.';
const _facilityReportLocationRationaleTitle = '현재 위치 사용';
const _facilityReportLocationRationalePurpose =
    '가까운 역 찾기와 시설 제보 위치 확인에만 현재 위치를 사용합니다.';
const _facilityReportLocationRationaleFallback =
    '위치 사용을 허용하지 않아도 역명 검색, 즐겨찾기, 엘리베이터와 시설 안내는 계속 사용할 수 있습니다.';
const _facilityReportUploadDisclosureTitle = '사진·위치 확인';
const _facilityReportUploadDisclosurePurpose = '사진과 제보 위치는 시설 제보 확인에만 사용됩니다.';
const _facilityReportUploadDisclosureScope =
    '제보 내용은 접수 담당자에게 전달되며 앱 사용자에게 공개되지 않습니다.';
const _facilityReportPagePadding = EdgeInsets.only(bottom: 32);
const _facilityReportContentPadding = EdgeInsets.symmetric(horizontal: 20);

class FacilityReportScreen extends StatefulWidget {
  const FacilityReportScreen({
    required this.repository,
    required this.target,
    this.locationLoader,
    this.needsLocationPermissionRequest,
    this.openLocationSettings,
    this.photoPicker,
    this.deviceCameraPhotoPicker,
    this.deviceGalleryPhotoPicker,
    this.lostPhotoRestorer,
    this.draftTargetStore,
    this.initialPhotoAttachment,
    super.key,
  });

  final FacilityReportRepository repository;
  final FacilityReportTarget target;
  final FacilityReportLocationLoader? locationLoader;
  final FacilityReportLocationPermissionRequestChecker?
  needsLocationPermissionRequest;
  final FacilityReportLocationSettingsOpener? openLocationSettings;
  final FacilityReportPhotoPicker? photoPicker;
  final FacilityReportPhotoPicker? deviceCameraPhotoPicker;
  final FacilityReportPhotoPicker? deviceGalleryPhotoPicker;
  final FacilityReportLostPhotoRestorer? lostPhotoRestorer;
  final FacilityReportDraftTargetStore? draftTargetStore;
  final FacilityReportPhotoAttachment? initialPhotoAttachment;

  @override
  State<FacilityReportScreen> createState() => _FacilityReportScreenState();
}

class MyFacilityReportListScreen extends StatefulWidget {
  const MyFacilityReportListScreen({required this.repository, super.key});

  final FacilityReportRepository repository;

  @override
  State<MyFacilityReportListScreen> createState() =>
      _MyFacilityReportListScreenState();
}

class _MyFacilityReportListScreenState
    extends State<MyFacilityReportListScreen> {
  late Future<List<FacilityReportResult>> _reportsFuture;

  @override
  void initState() {
    super.initState();
    _reportsFuture = widget.repository.listMyReports();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('myReportsScreen'),
      backgroundColor: EasySubwayAccessibleColors.surface,
      appBar: AppBar(
        key: const Key('myReportsAppBar'),
        title: const Text('내 제보'),
        toolbarHeight: 60,
        backgroundColor: EasySubwayAccessibleColors.topBarSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        leading: IconButton(
          key: const Key('myReportsBackButton'),
          tooltip: '뒤로',
          onPressed: () => Navigator.of(context).maybePop(),
          style: IconButton.styleFrom(
            minimumSize: const Size.square(EasySubwayTouchTarget.general),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            padding: EdgeInsets.zero,
          ),
          icon: const Icon(
            Icons.arrow_back,
            size: 26,
            color: EasySubwayAccessibleColors.contentPrimary,
          ),
        ),
        flexibleSpace: const Align(
          alignment: Alignment.bottomCenter,
          child: EasySubwayHeaderDivider(key: Key('myReportsHeaderDivider')),
        ),
      ),
      body: SafeArea(
        child: FutureBuilder<List<FacilityReportResult>>(
          future: _reportsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const _MyReportLoading();
            }
            if (snapshot.hasError) {
              return _MyReportError(onRetry: _retry);
            }

            final reports = snapshot.data ?? const <FacilityReportResult>[];
            if (reports.isEmpty) {
              return const _MyReportEmpty();
            }

            return ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                ColoredBox(
                  key: const Key('myReportsSectionHeader'),
                  color: EasySubwayAccessibleColors.scaffoldSurface,
                  child: SizedBox(
                    width: double.infinity,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
                      child: Semantics(
                        header: true,
                        child: Text(
                          '접수 내역',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: EasySubwayAccessibleColors.secondaryText,
                                fontWeight: FontWeight.w700,
                                height: 1.25,
                              ),
                        ),
                      ),
                    ),
                  ),
                ),
                for (var index = 0; index < reports.length; index++) ...[
                  _MyReportListItem(report: reports[index]),
                  if (index < reports.length - 1)
                    const Divider(
                      height: 1,
                      thickness: 1,
                      indent: 20,
                      endIndent: 20,
                      color: EasySubwayAccessibleColors.line,
                    ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  void _retry() {
    setState(() {
      _reportsFuture = widget.repository.listMyReports();
    });
  }
}

class _MyReportLoading extends StatelessWidget {
  const _MyReportLoading();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '제보 내역 불러오는 중',
      liveRegion: true,
      child: const Center(child: CircularProgressIndicator()),
    );
  }
}

class _MyReportEmpty extends StatelessWidget {
  const _MyReportEmpty();

  // 역 검색 최근 검색 빈 상태와 동일 토큰(아이콘 56·글자 16·disclosure·정렬 -0.55).
  static const _iconSize = 56.0;
  static const _emptyTone = EasySubwayAccessibleColors.disclosure;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: const Alignment(0, -0.55),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.receipt_long_outlined,
              size: _iconSize,
              color: _emptyTone,
            ),
            const SizedBox(height: EasySubwaySpacing.md),
            Text(
              '접수한 제보가 없습니다.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: _emptyTone,
                fontWeight: FontWeight.w600,
                height: 1.35,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MyReportError extends StatelessWidget {
  const _MyReportError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              facilityReportListFailureMessage,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: EasySubwayAccessibleColors.text,
                fontWeight: FontWeight.w700,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              key: const Key('myReportsRetryButton'),
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('다시 시도'),
            ),
          ],
        ),
      ),
    );
  }
}

class _MyReportListItem extends StatelessWidget {
  const _MyReportListItem({required this.report});

  final FacilityReportResult report;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final description = report.description.isEmpty
        ? report.reportTypeLabel
        : report.description;
    final createdAtLabel = report.createdDateLabel;
    void openReportDetail() {
      unawaited(
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => MyFacilityReportDetailScreen(report: report),
          ),
        ),
      );
    }

    return Semantics(
      label:
          '내 제보, ${report.reportTypeLabel}, 제보 번호 ${report.displayReceiptCode}, ${report.statusLabel}, $description, 접수일 $createdAtLabel',
      button: true,
      container: true,
      onTap: openReportDetail,
      child: ExcludeSemantics(
        child: ListTile(
          key: Key('myReport-${report.id}'),
          onTap: openReportDetail,
          minVerticalPadding: 12,
          contentPadding: const EdgeInsets.symmetric(horizontal: 20),
          tileColor: EasySubwayAccessibleColors.surface,
          title: Text(
            report.reportTypeLabel,
            style: textTheme.bodyLarge?.copyWith(
              color: EasySubwayAccessibleColors.text,
              fontWeight: FontWeight.w700,
              height: 1.25,
            ),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  description,
                  style: textTheme.bodyMedium?.copyWith(
                    color: EasySubwayAccessibleColors.text,
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '제보 번호 ${report.displayReceiptCode} · 접수일 $createdAtLabel',
                  style: textTheme.bodyMedium?.copyWith(
                    color: EasySubwayAccessibleColors.mutedText,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _MyReportStatusLabel(
                status: report.status,
                label: report.statusLabel,
              ),
              const SizedBox(width: 4),
              const Icon(
                Icons.chevron_right,
                color: EasySubwayAccessibleColors.disclosure,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class MyFacilityReportDetailScreen extends StatelessWidget {
  const MyFacilityReportDetailScreen({required this.report, super.key});

  final FacilityReportResult report;

  @override
  Widget build(BuildContext context) {
    final description = report.description.isEmpty
        ? report.reportTypeLabel
        : report.description;
    final createdAtLabel = report.createdDateLabel;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      key: const Key('myReportDetailScreen'),
      backgroundColor: EasySubwayAccessibleColors.surface,
      appBar: AppBar(
        key: const Key('myReportDetailAppBar'),
        title: const Text('제보 상세'),
        toolbarHeight: 60,
        backgroundColor: EasySubwayAccessibleColors.topBarSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        leading: IconButton(
          key: const Key('myReportDetailBackButton'),
          tooltip: '뒤로',
          onPressed: () => Navigator.of(context).maybePop(),
          style: IconButton.styleFrom(
            minimumSize: const Size.square(EasySubwayTouchTarget.general),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            padding: EdgeInsets.zero,
          ),
          icon: const Icon(
            Icons.arrow_back,
            size: 26,
            color: EasySubwayAccessibleColors.contentPrimary,
          ),
        ),
        flexibleSpace: const Align(
          alignment: Alignment.bottomCenter,
          child: EasySubwayHeaderDivider(
            key: Key('myReportDetailHeaderDivider'),
          ),
        ),
      ),
      body: SafeArea(
        child: Semantics(
          label:
              '내 제보 상세, ${report.reportTypeLabel}, 현재 상태 ${report.statusLabel}, 제보 번호 ${report.displayReceiptCode}',
          child: ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              ColoredBox(
                color: EasySubwayAccessibleColors.scaffoldSurface,
                child: SizedBox(
                  width: double.infinity,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
                    child: Semantics(
                      header: true,
                      child: Text(
                        '진행 상태',
                        style: textTheme.bodyMedium?.copyWith(
                          color: EasySubwayAccessibleColors.secondaryText,
                          fontWeight: FontWeight.w700,
                          height: 1.25,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              ColoredBox(
                color: EasySubwayAccessibleColors.surface,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        report.reportTypeLabel,
                        style: textTheme.bodyLarge?.copyWith(
                          color: EasySubwayAccessibleColors.text,
                          fontWeight: FontWeight.w700,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 10),
                      _MyReportDetailStatus(
                        status: report.status,
                        label: report.statusLabel,
                      ),
                    ],
                  ),
                ),
              ),
              ColoredBox(
                color: EasySubwayAccessibleColors.scaffoldSurface,
                child: SizedBox(
                  width: double.infinity,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
                    child: Semantics(
                      header: true,
                      child: Text(
                        '제보 정보',
                        style: textTheme.bodyMedium?.copyWith(
                          color: EasySubwayAccessibleColors.secondaryText,
                          fontWeight: FontWeight.w700,
                          height: 1.25,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              _MyReportDetailRow(
                label: '제보 번호',
                value: report.displayReceiptCode,
              ),
              const Divider(
                height: 1,
                thickness: 1,
                indent: 20,
                endIndent: 20,
                color: EasySubwayAccessibleColors.line,
              ),
              _MyReportDetailRow(label: '접수일', value: createdAtLabel),
              const Divider(
                height: 1,
                thickness: 1,
                indent: 20,
                endIndent: 20,
                color: EasySubwayAccessibleColors.line,
              ),
              _MyReportDetailRow(label: '제보 내용', value: description),
            ],
          ),
        ),
      ),
    );
  }
}

class _MyReportDetailStatus extends StatelessWidget {
  const _MyReportDetailStatus({required this.status, required this.label});

  final String status;
  final String label;

  @override
  Widget build(BuildContext context) {
    final color = facilityReportStatusColor(status);
    return Align(
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _MyReportDetailRow extends StatelessWidget {
  const _MyReportDetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return ColoredBox(
      color: EasySubwayAccessibleColors.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: textTheme.bodyMedium?.copyWith(
                color: EasySubwayAccessibleColors.mutedText,
                fontWeight: FontWeight.w700,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: textTheme.bodyLarge?.copyWith(
                color: EasySubwayAccessibleColors.text,
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MyReportStatusLabel extends StatelessWidget {
  const _MyReportStatusLabel({required this.status, required this.label});

  final String status;
  final String label;

  @override
  Widget build(BuildContext context) {
    final color = facilityReportStatusColor(status);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: color,
            fontWeight: FontWeight.w700,
            height: 1.2,
          ),
        ),
      ],
    );
  }
}

class _FacilityReportScreenState extends State<FacilityReportScreen> {
  late final FacilityReportController _controller;
  late final ImagePickerFacilityReportPhotoPicker _defaultPhotoPicker;
  final TextEditingController _descriptionController = TextEditingController();
  late final List<FacilityReportTypeOption> _reportTypeOptions;
  late FacilityReportTypeOption _selectedType;
  FacilityReportLocation? _attachedLocation;
  FacilityReportPhotoAttachment? _photoAttachment;
  String _photoMessage = '';
  String _locationMessage = '';
  bool _isLoadingLocation = false;
  bool _isPreparingLocationAttachment = false;
  bool _isLocationFailure = false;
  bool _isOpeningLocationSettings = false;
  bool _isPhotoFailure = false;
  bool _isConfirmingPhotoUse = false;
  bool _isPickingPhoto = false;

  @override
  void initState() {
    super.initState();
    // 대상 시설 타입·현재 상태에 유효한 제보 유형만 노출한다(서버 enum은 그대로).
    _reportTypeOptions = facilityReportTypeOptionsFor(
      facilityTypeLabel: widget.target.facilityTypeLabel,
      facilityStatusLabel: widget.target.facilityStatusLabel,
    );
    _selectedType = _reportTypeOptions.first;
    _controller = FacilityReportController(repository: widget.repository)
      ..addListener(_onReportStateChanged);
    _defaultPhotoPicker = ImagePickerFacilityReportPhotoPicker();
    _photoAttachment = widget.initialPhotoAttachment;
    if (_photoAttachment != null) {
      _photoMessage = '사진 1장 추가됨';
    }
    // 위치는 선택 정보이므로 진입 즉시 요청하지 않는다. 사용자가 "현재 위치
    // 첨부"를 켤 때 1회 요청한다(진입 마찰 축소).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(_restoreLostPhoto());
      }
    });
  }

  @override
  void dispose() {
    _controller.removeListener(_onReportStateChanged);
    _controller.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = _controller.state;
    final isLoading = state.status == FacilityReportViewStatus.loading;
    final reportResult = state.result;
    final hasSubmittedReport = reportResult != null;
    final isLocationBusy = _isLoadingLocation || _isPreparingLocationAttachment;
    // 위치는 선택 정보다. 위치를 첨부하지 않아도 제보를 보낼 수 있다.
    // 위치 권한 안내/확인 또는 로딩 중일 때만 잠시 비활성화한다.
    final isSubmitDisabled = isLoading || hasSubmittedReport || isLocationBusy;

    return Scaffold(
      key: const Key('facilityReportScreen'),
      backgroundColor: EasySubwayAccessibleColors.surface,
      appBar: const EasySubwayFamilyAppBar(
        key: Key('facilityReportAppBar'),
        title: Text('시설 제보'),
        backButtonKey: Key('facilityReportBackButton'),
        dividerKey: Key('facilityReportHeaderDivider'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: _facilityReportPagePadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const FacilityReportSectionTitle(title: '대상'),
              FacilityReportHeader(target: widget.target),
              const FacilityReportSectionTitle(title: '어떤 일인가요?'),
              for (final option in _reportTypeOptions) ...[
                FacilityReportTypeRow(
                  option: option,
                  selected: option == _selectedType,
                  onTap: isLoading || hasSubmittedReport
                      ? null
                      : () => setState(() => _selectedType = option),
                ),
                if (option != _reportTypeOptions.last)
                  const Divider(
                    height: 1,
                    thickness: 1,
                    indent: 20,
                    endIndent: 20,
                    color: EasySubwayAccessibleColors.line,
                  ),
              ],
              const FacilityReportSectionTitle(title: '내용'),
              Padding(
                padding: _facilityReportContentPadding,
                child: TextField(
                  key: const Key('facilityReportDescriptionInput'),
                  controller: _descriptionController,
                  enabled: !isLoading && !hasSubmittedReport,
                  minLines: 3,
                  maxLines: 5,
                  textInputAction: TextInputAction.newline,
                  style: const TextStyle(fontSize: 18, height: 1.35),
                  decoration: const InputDecoration(
                    hintText: '상황을 짧게 적어 주세요',
                    border: OutlineInputBorder(
                      borderRadius: facilityReportCardRadius,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: _facilityReportContentPadding,
                child: OutlinedButton.icon(
                  key: const Key('facilityReportAddPhotoButton'),
                  onPressed:
                      isLoading ||
                          hasSubmittedReport ||
                          _isConfirmingPhotoUse ||
                          _isPickingPhoto
                      ? null
                      : _pickPhoto,
                  icon: _isPickingPhoto
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        )
                      : const Icon(Icons.add_a_photo),
                  label: Text(_photoAttachment == null ? '사진 추가' : '사진 바꾸기'),
                ),
              ),
              if (_photoMessage.isNotEmpty) ...[
                const SizedBox(height: 10),
                Padding(
                  padding: _facilityReportContentPadding,
                  child: FacilityReportLocationMessage(
                    message: _photoMessage,
                    isFailure: _isPhotoFailure,
                  ),
                ),
              ],
              if (widget.locationLoader != null) ...[
                const SizedBox(height: 16),
                Padding(
                  padding: _facilityReportContentPadding,
                  child: _attachedLocation != null
                      ? Row(
                          children: [
                            const Icon(
                              Icons.location_on_outlined,
                              color: EasySubwayAccessibleColors.primary,
                              size: 24,
                            ),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text(
                                '현재 위치를 첨부했어요',
                                style: TextStyle(
                                  color: EasySubwayAccessibleColors.text,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            TextButton(
                              key: const Key(
                                'facilityReportRemoveLocationButton',
                              ),
                              onPressed: isLoading || hasSubmittedReport
                                  ? null
                                  : () {
                                      setState(() {
                                        _attachedLocation = null;
                                        _locationMessage = '';
                                        _isLocationFailure = false;
                                      });
                                    },
                              child: const Text('지우기'),
                            ),
                          ],
                        )
                      : OutlinedButton.icon(
                          key: const Key('facilityReportAttachLocationButton'),
                          onPressed:
                              isLoading ||
                                  hasSubmittedReport ||
                                  isLocationBusy ||
                                  _isOpeningLocationSettings
                              ? null
                              : _requestCurrentLocation,
                          icon: _isLoadingLocation
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                  ),
                                )
                              : const Icon(Icons.my_location),
                          label: Text(
                            _isLocationFailure ? '위치 다시 찾기' : '현재 위치 첨부 (선택)',
                          ),
                        ),
                ),
                if (_locationMessage.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Padding(
                    padding: _facilityReportContentPadding,
                    child: FacilityReportLocationMessage(
                      message: _locationMessage,
                      isFailure: _isLocationFailure,
                    ),
                  ),
                ],
                // 실패 시 행동은 1개만: GPS가 꺼져 있으면 설정 열기, 아니면 위 버튼으로
                // 다시 시도. 위치 없이도 제보를 보낼 수 있어 "위치 없이 제보" 버튼은 없앤다.
                if (_isLocationFailure &&
                    !hasSubmittedReport &&
                    _canOpenLocationSettings) ...[
                  const SizedBox(height: 10),
                  Padding(
                    padding: _facilityReportContentPadding,
                    child: OutlinedButton.icon(
                      key: const Key(
                        'facilityReportOpenLocationSettingsButton',
                      ),
                      onPressed:
                          isLoading ||
                              _isOpeningLocationSettings ||
                              isLocationBusy
                          ? null
                          : _openLocationSettings,
                      icon: _isOpeningLocationSettings
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                              ),
                            )
                          : const Icon(Icons.settings),
                      label: const Text('위치 설정 열기'),
                    ),
                  ),
                ],
              ],
              if (state.message.isNotEmpty) ...[
                const SizedBox(height: 16),
                Padding(
                  padding: _facilityReportContentPadding,
                  child: FacilityReportMessage(state: state),
                ),
              ],
              if (reportResult != null) ...[
                const SizedBox(height: 16),
                Padding(
                  padding: _facilityReportContentPadding,
                  child: FacilityReportStatusPanel(
                    result: reportResult,
                    isLoading: isLoading,
                    onRefresh: _controller.refreshCurrentReport,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Padding(
                padding: _facilityReportContentPadding,
                child: SizedBox(
                  height: EasySubwayTouchTarget.primary,
                  width: double.infinity,
                  child: FilledButton.icon(
                    key: const Key('facilityReportSubmitButton'),
                    onPressed: isSubmitDisabled ? null : _submit,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(
                        EasySubwayTouchTarget.primary,
                      ),
                    ),
                    icon: isLoading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.5),
                          )
                        : const Icon(Icons.send),
                    label: Text(hasSubmittedReport ? '제보 완료' : '보내기'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _onReportStateChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  bool get _canOpenLocationSettings =>
      widget.openLocationSettings != null &&
      _locationMessage == _facilityReportLocationDisabledMessage;

  Future<void> _submit() async {
    if (_photoAttachment != null || _attachedLocation != null) {
      final confirmed = await _confirmReportUpload();
      if (!confirmed) {
        return;
      }
    }
    if (_attachedLocation == null && _isLocationFailure) {
      setState(() {
        _locationMessage = '';
        _isLocationFailure = false;
      });
    }
    unawaited(
      _controller.submit(
        target: widget.target,
        selectedType: _selectedType,
        description: _descriptionController.text,
        photoAttachment: _photoAttachment,
        latitude: _attachedLocation?.latitude,
        longitude: _attachedLocation?.longitude,
      ),
    );
  }

  Future<bool> _confirmReportUpload() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(_facilityReportUploadDisclosureTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(_facilityReportUploadDisclosurePurpose),
            const SizedBox(height: 8),
            const Text(_facilityReportUploadDisclosureScope),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            key: const Key('facilityReportUploadConfirmButton'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('보내기'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Future<bool> _confirmPhotoUse() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('사진 확인'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('사진은 제보 내용을 확인하는 데만 사용해요.'),
            SizedBox(height: 8),
            Text('얼굴이나 전화번호가 보이면 가려 주세요.'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('계속'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Future<void> _requestCurrentLocation() async {
    if (widget.locationLoader == null ||
        _isLoadingLocation ||
        _isPreparingLocationAttachment) {
      return;
    }
    setState(() => _isPreparingLocationAttachment = true);
    final shouldContinue = await _confirmLocationUseIfNeeded();
    if (mounted) {
      setState(() => _isPreparingLocationAttachment = false);
    }
    if (!mounted) {
      return;
    }
    if (!shouldContinue) {
      // 사용자가 위치 첨부를 취소한 것은 오류가 아니다. 조용히 첨부하지 않는다.
      setState(() {
        _attachedLocation = null;
        _locationMessage = '';
        _isLocationFailure = false;
      });
      return;
    }
    await _loadCurrentLocation();
  }

  Future<bool> _confirmLocationUseIfNeeded() async {
    final checker = widget.needsLocationPermissionRequest;
    if (checker == null) {
      return true;
    }
    var needsPermissionRequest = true;
    try {
      needsPermissionRequest = await checker();
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '시설 제보 위치 권한 사전 확인 중 예외가 발생했습니다.',
      );
    }
    if (!needsPermissionRequest) {
      return true;
    }
    if (!mounted) {
      return false;
    }
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text(_facilityReportLocationRationaleTitle),
            content: const Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_facilityReportLocationRationalePurpose),
                SizedBox(height: 8),
                Text(_facilityReportLocationRationaleFallback),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('취소'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('계속'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _openLocationSettings() async {
    final openLocationSettings = widget.openLocationSettings;
    if (openLocationSettings == null || _isOpeningLocationSettings) {
      return;
    }
    setState(() => _isOpeningLocationSettings = true);
    try {
      await openLocationSettings();
    } finally {
      if (mounted) {
        setState(() => _isOpeningLocationSettings = false);
      }
    }
  }

  Future<void> _pickPhoto() async {
    if (_isConfirmingPhotoUse || _isPickingPhoto) {
      return;
    }
    setState(() => _isConfirmingPhotoUse = true);
    final confirmed = await _confirmPhotoUse();
    if (!mounted) {
      return;
    }
    if (!confirmed) {
      setState(() => _isConfirmingPhotoUse = false);
      return;
    }
    setState(() {
      _isConfirmingPhotoUse = false;
      _isPickingPhoto = true;
      _photoMessage = '';
      _isPhotoFailure = false;
    });
    try {
      await _saveDraftTargetForPhotoPicker();
      final picker = widget.photoPicker ?? _pickPhotoWithDevicePicker;
      final photo = await picker();
      if (!mounted || photo == null) {
        return;
      }
      setState(() {
        _photoAttachment = photo;
        _photoMessage = '사진 1장 추가됨';
        _isPhotoFailure = false;
      });
    } on FacilityReportPhotoException catch (error) {
      if (mounted) {
        setState(() {
          _photoAttachment = null;
          _photoMessage = error.message;
          _isPhotoFailure = true;
        });
      }
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '시설 제보 사진 첨부 중 예외가 발생했습니다.',
      );
      if (mounted) {
        setState(() {
          _photoAttachment = null;
          _photoMessage = '사진을 추가하지 못했어요.';
          _isPhotoFailure = true;
        });
      }
    } finally {
      await _clearDraftTargetForPhotoPicker();
      if (mounted) {
        setState(() => _isPickingPhoto = false);
      }
    }
  }

  Future<void> _restoreLostPhoto() async {
    if (_photoAttachment != null) {
      return;
    }
    final restorer = widget.lostPhotoRestorer;
    if (restorer == null) {
      return;
    }
    try {
      final photo = await restorer();
      if (!mounted || photo == null || _photoAttachment != null) {
        return;
      }
      setState(() {
        _photoAttachment = photo;
        _photoMessage = '사진 1장 추가됨';
        _isPhotoFailure = false;
      });
    } on FacilityReportPhotoException catch (error) {
      if (mounted) {
        setState(() {
          _photoMessage = error.message;
          _isPhotoFailure = true;
        });
      }
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '시설 제보 사진 선택 복구 중 예외가 발생했습니다.',
      );
      if (mounted) {
        setState(() {
          _photoMessage = '사진을 다시 선택해 주세요.';
          _isPhotoFailure = true;
        });
      }
    }
  }

  Future<void> _saveDraftTargetForPhotoPicker() async {
    try {
      await widget.draftTargetStore?.saveTarget(widget.target);
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '시설 제보 사진 선택 대상 저장 중 예외가 발생했습니다.',
      );
    }
  }

  Future<void> _clearDraftTargetForPhotoPicker() async {
    try {
      await widget.draftTargetStore?.clearTarget();
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '시설 제보 사진 선택 대상 정리 중 예외가 발생했습니다.',
      );
    }
  }

  Future<FacilityReportPhotoAttachment?> _pickPhotoWithDevicePicker() async {
    final takePhoto =
        widget.deviceCameraPhotoPicker ?? _defaultPhotoPicker.takePhoto;
    final pickFromGallery =
        widget.deviceGalleryPhotoPicker ?? _defaultPhotoPicker.pickFromGallery;
    final picker = await showModalBottomSheet<FacilityReportPhotoPicker>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: const Text('사진 찍기'),
              onTap: () => Navigator.of(context).pop(takePhoto),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('앨범에서 선택'),
              onTap: () => Navigator.of(context).pop(pickFromGallery),
            ),
          ],
        ),
      ),
    );
    return picker?.call();
  }

  Future<void> _loadCurrentLocation() async {
    final locationLoader = widget.locationLoader;
    if (locationLoader == null || _isLoadingLocation) {
      return;
    }
    setState(() {
      _isLoadingLocation = true;
      _locationMessage = '';
      _isLocationFailure = false;
    });

    try {
      final location = await locationLoader();
      if (!mounted) {
        return;
      }
      setState(() {
        _attachedLocation = location;
        _locationMessage = '';
        _isLocationFailure = false;
      });
    } on FacilityReportLocationException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _attachedLocation = null;
        _locationMessage = _friendlyFacilityReportLocationMessage(
          error.message,
        );
        _isLocationFailure = true;
      });
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '시설 제보 현재 위치 확인 중 예외가 발생했습니다.',
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _attachedLocation = null;
        _locationMessage = '현재 위치를 확인하지 못했어요.';
        _isLocationFailure = true;
      });
    } finally {
      if (mounted) {
        setState(() => _isLoadingLocation = false);
      }
    }
  }
}

String _friendlyFacilityReportLocationMessage(String message) {
  if (message.contains('권한')) {
    return _facilityReportLocationPermissionMessage;
  }
  return message.isEmpty ? '현재 위치를 확인하지 못했어요.' : message;
}
