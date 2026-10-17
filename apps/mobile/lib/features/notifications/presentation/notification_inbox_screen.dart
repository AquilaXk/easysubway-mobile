import 'dart:async';

import 'package:flutter/material.dart';

import '../../../accessible_design.dart';
import '../../../app/app_components.dart';
import '../../stations/domain/facility_status.dart';
import '../../favorites/favorite_facility.dart';
import '../../../mobile_error_reporter.dart';
import '../notification_settings.dart';
import '../../facility_report/domain/facility_report_repository.dart';
import '../../facility_report/domain/facility_report_result.dart';

typedef OpenFacilityReport = void Function(FacilityReportResult report);

class NotificationInboxScreen extends StatefulWidget {
  const NotificationInboxScreen({
    required this.favoriteFacilityRepository,
    required this.reportRepository,
    required this.notificationRepository,
    required this.notificationPermissionProvider,
    required this.onOpenReport,
    super.key,
  });

  final FavoriteFacilityRepository? favoriteFacilityRepository;
  final FacilityReportRepository reportRepository;
  final NotificationSettingsRepository? notificationRepository;
  final NotificationPermissionProvider? notificationPermissionProvider;
  final OpenFacilityReport onOpenReport;

  @override
  State<NotificationInboxScreen> createState() =>
      _NotificationInboxScreenState();
}

class _NotificationInboxScreenState extends State<NotificationInboxScreen> {
  late _InboxSection _facilities;
  var _reports = const _InboxSection.loading();

  @override
  void initState() {
    super.initState();
    _facilities = widget.favoriteFacilityRepository == null
        ? const _InboxSection.loaded([])
        : const _InboxSection.loading();
    unawaited(_loadFacilities());
    unawaited(_loadReports());
  }

  @override
  Widget build(BuildContext context) {
    final sections = [_facilities, _reports];
    final loading = sections.any((section) => section.loading);
    final items = [for (final section in sections) ...section.items];
    final anyFailed = sections.any((section) => section.failed);
    return Scaffold(
      appBar: AppBar(
        title: const Text('알림'),
        flexibleSpace: const Align(
          alignment: Alignment.bottomCenter,
          child: EasySubwayHeaderDivider.mapChrome(),
        ),
        actions: [
          if (widget.notificationRepository != null)
            IconButton(
              tooltip: '알림 설정',
              onPressed: _openSettings,
              icon: const Icon(Icons.settings_outlined),
            ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => Future.wait([_loadFacilities(), _loadReports()]),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: mainListPagePadding,
            children: [
              if (loading) const LinearProgressIndicator(minHeight: 3),
              if (!loading && items.isEmpty && anyFailed)
                HomeStateCard(
                  key: const Key('notificationInboxErrorState'),
                  icon: Icons.error_outline,
                  title: '알림을 불러오지 못했어요',
                  subtitle: '잠시 후 다시 시도해 주세요.',
                  actionLabel: '다시 시도',
                  onAction: _retryFailed,
                )
              else if (!loading && items.isEmpty)
                const _NotificationInboxEmptyState()
              else ...[
                if (items.isNotEmpty) _NotificationInboxChips(items: items),
                ..._sectionRows(
                  _facilities,
                  errorKey: const Key('notificationInboxFacilityErrorRow'),
                  errorTitle: '시설을 불러오지 못했어요',
                  onRetry: _loadFacilities,
                ),
                ..._sectionRows(
                  _reports,
                  errorKey: const Key('notificationInboxReportErrorRow'),
                  errorTitle: '제보를 불러오지 못했어요',
                  onRetry: _loadReports,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _sectionRows(
    _InboxSection section, {
    required Key errorKey,
    required String errorTitle,
    required Future<void> Function() onRetry,
  }) {
    return [
      for (final item in section.items)
        _NotificationInboxRow(item: item, onOpenReport: widget.onOpenReport),
      if (section.failed)
        HomeStateCard(
          key: errorKey,
          icon: Icons.error_outline,
          title: errorTitle,
          subtitle: '잠시 후 다시 시도해 주세요.',
          actionLabel: '다시 시도',
          onAction: () => unawaited(onRetry()),
        ),
    ];
  }

  /// 실패한 구역만 다시 조회한다.
  void _retryFailed() {
    if (_facilities.failed) {
      unawaited(_loadFacilities());
    }
    if (_reports.failed) {
      unawaited(_loadReports());
    }
  }

  Future<void> _loadFacilities() async {
    final repository = widget.favoriteFacilityRepository;
    if (repository == null) {
      return;
    }
    _setFacilities(const _InboxSection.loading());
    try {
      final facilities = await repository.listFavoriteFacilities();
      _setFacilities(
        _InboxSection.loaded([
          for (final facility in facilities.where(isFacilityAlert))
            _NotificationInboxItem.facility(facility),
        ]),
      );
    } catch (error, stackTrace) {
      _setFacilities(const _InboxSection.failed());
      reportMobileError(
        error,
        stackTrace,
        context: '알림함 즐겨찾기 시설 상태를 불러오는 중 예외가 발생했습니다.',
      );
    }
  }

  Future<void> _loadReports() async {
    _setReports(const _InboxSection.loading());
    try {
      final reports = await widget.reportRepository.listMyReports();
      _setReports(
        _InboxSection.loaded([
          for (final report in reports) _NotificationInboxItem.report(report),
        ]),
      );
    } catch (error, stackTrace) {
      _setReports(const _InboxSection.failed());
      reportMobileError(
        error,
        stackTrace,
        context: '알림함 제보 상태를 불러오는 중 예외가 발생했습니다.',
      );
    }
  }

  void _setFacilities(_InboxSection section) {
    if (mounted) {
      setState(() => _facilities = section);
    }
  }

  void _setReports(_InboxSection section) {
    if (mounted) {
      setState(() => _reports = section);
    }
  }

  void _openSettings() {
    final repository = widget.notificationRepository;
    if (repository == null) {
      return;
    }
    unawaited(
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => NotificationSettingsScreen(
            repository: repository,
            notificationPermissionProvider:
                widget.notificationPermissionProvider,
          ),
        ),
      ),
    );
  }
}

/// 알림함의 조회 구역(시설·제보) 하나의 상태. 구역마다 따로 실패하고 다시 조회한다.
class _InboxSection {
  const _InboxSection.loading()
    : items = const [],
      loading = true,
      failed = false;

  const _InboxSection.loaded(this.items) : loading = false, failed = false;

  const _InboxSection.failed()
    : items = const [],
      loading = false,
      failed = true;

  final List<_NotificationInboxItem> items;
  final bool loading;
  final bool failed;
}

class _NotificationInboxEmptyState extends StatelessWidget {
  const _NotificationInboxEmptyState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 80),
      child: Column(
        children: [
          const Icon(
            Icons.notifications_none,
            size: 44,
            color: EasySubwayAccessibleColors.mutedText,
          ),
          const SizedBox(height: 12),
          const Text(
            '새 알림이 없습니다',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: EasySubwayAccessibleColors.text,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            '즐겨찾기 시설과 제보 상태가 바뀌면 여기에서 볼 수 있어요.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: EasySubwayAccessibleColors.mutedText,
              fontSize: 13,
              fontWeight: FontWeight.w500,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _NotificationInboxItem {
  const _NotificationInboxItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.semanticLabel,
    required this.kind,
    this.report,
    this.severity = FacilityStatusSeverity.normal,
    this.actionLabel = '',
  });

  factory _NotificationInboxItem.facility(FavoriteFacility facility) {
    final name = facility.displayName.trim().isEmpty
        ? facility.typeLabel
        : facility.displayName;
    // 출처 라벨이 비어 있을 수 있어(무표시) 빈 값은 걸러 Semantics에 ", ," 유령
    // 세그먼트를 남기지 않는다(#2078).
    final semanticParts = <String>[
      '${facility.stationLabel} $name',
      '${facility.typeLabel} ${facility.statusLabel}',
      facility.severityLabel,
      facility.updatedLabel,
      facility.dataSourceLabel,
      facility.nextActionLabel,
    ].where((part) => part.trim().isNotEmpty);
    return _NotificationInboxItem(
      icon: _facilityIcon(facility.type),
      title: '${facility.stationLabel} $name',
      subtitle:
          '${facility.severityLabel} · ${facility.typeLabel} ${facility.statusLabel}',
      semanticLabel: semanticParts.join(', '),
      kind: '시설',
      severity: facility.statusPresentation.severity,
      actionLabel: facility.nextActionLabel,
    );
  }

  factory _NotificationInboxItem.report(FacilityReportResult report) {
    final statusLabel = _reportStatusLabel(report.status);
    final receiptCode = _reportReceiptCode(report.publicReceiptCode);
    return _NotificationInboxItem(
      icon: Icons.report_outlined,
      title: '제보 $statusLabel',
      subtitle: '제보 번호 $receiptCode',
      semanticLabel: '제보 $statusLabel, 제보 번호 $receiptCode',
      kind: '제보',
      report: report,
    );
  }

  final IconData icon;
  final String title;
  final String subtitle;
  final String semanticLabel;
  final String kind;
  final FacilityReportResult? report;
  final FacilityStatusSeverity severity;
  final String actionLabel;
}

class _NotificationInboxChips extends StatelessWidget {
  const _NotificationInboxChips({required this.items});

  final List<_NotificationInboxItem> items;

  @override
  Widget build(BuildContext context) {
    final facilityCount = items.where((item) => item.kind == '시설').length;
    final reportCount = items.length - facilityCount;
    final parts = <String>[
      '전체 ${items.length}',
      if (facilityCount > 0) '시설 $facilityCount',
      if (reportCount > 0) '제보 $reportCount',
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 4, top: 4),
      child: Text(
        parts.join('  ·  '),
        style: const TextStyle(
          color: EasySubwayAccessibleColors.mutedText,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _NotificationInboxRow extends StatelessWidget {
  const _NotificationInboxRow({required this.item, required this.onOpenReport});

  final _NotificationInboxItem item;
  final OpenFacilityReport onOpenReport;

  @override
  Widget build(BuildContext context) {
    void open() {
      final report = item.report;
      if (report == null) {
        return;
      }
      onOpenReport(report);
    }

    final accent = _facilitySeverityAccent(item.severity);
    final row = Ink(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: accent.backgroundColor,
        border: Border(bottom: BorderSide(color: accent.borderColor)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(item.icon, color: accent.iconColor, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        item.title,
                        style: const TextStyle(
                          color: EasySubwayAccessibleColors.text,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          height: 1.25,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      item.kind,
                      style: const TextStyle(
                        color: EasySubwayAccessibleColors.contentSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  item.subtitle,
                  style: TextStyle(
                    color: accent.iconColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    height: 1.4,
                  ),
                ),
                if (item.actionLabel.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    item.actionLabel,
                    style: const TextStyle(
                      color: EasySubwayAccessibleColors.text,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
    if (item.report == null) {
      return Semantics(
        label: item.semanticLabel,
        child: ExcludeSemantics(child: row),
      );
    }
    return Semantics(
      button: true,
      label: item.semanticLabel,
      onTap: open,
      child: ExcludeSemantics(
        child: InkWell(onTap: open, child: row),
      ),
    );
  }
}

String _reportStatusLabel(String status) {
  return switch (status) {
    'SUBMITTED' => '접수됨',
    'UNDER_REVIEW' => '확인 중',
    'ACCEPTED' => '반영됨',
    'REJECTED' => '반려됨',
    'DUPLICATE' => '중복 제보',
    'RESOLVED' => '확인 완료',
    _ => '접수 상태를 불러오지 못했어요',
  };
}

String _reportReceiptCode(String? publicReceiptCode) {
  final code = publicReceiptCode?.trim();
  return code == null || code.isEmpty ? '발급 전' : code;
}

class _FacilitySeverityAccent {
  const _FacilitySeverityAccent({
    required this.backgroundColor,
    required this.borderColor,
    required this.iconColor,
  });

  final Color backgroundColor;
  final Color borderColor;
  final Color iconColor;
}

_FacilitySeverityAccent _facilitySeverityAccent(
  FacilityStatusSeverity severity,
) {
  return switch (severity) {
    FacilityStatusSeverity.blocked => const _FacilitySeverityAccent(
      backgroundColor: EasySubwayAccessibleColors.redSoft,
      borderColor: EasySubwayAccessibleColors.red,
      iconColor: EasySubwayAccessibleColors.red,
    ),
    FacilityStatusSeverity.caution => const _FacilitySeverityAccent(
      backgroundColor: EasySubwayAccessibleColors.amberSoft,
      borderColor: EasySubwayAccessibleColors.amberBorder,
      iconColor: EasySubwayAccessibleColors.amber,
    ),
    FacilityStatusSeverity.needsInfo => const _FacilitySeverityAccent(
      backgroundColor: EasySubwayAccessibleColors.statusInfoSurface,
      borderColor: EasySubwayAccessibleColors.statusInfoContent,
      iconColor: EasySubwayAccessibleColors.statusInfoContent,
    ),
    FacilityStatusSeverity.normal => const _FacilitySeverityAccent(
      backgroundColor: EasySubwayAccessibleColors.surfaceDefault,
      borderColor: EasySubwayAccessibleColors.line,
      iconColor: EasySubwayAccessibleColors.mintDark,
    ),
  };
}

IconData _facilityIcon(String type) {
  return switch (type) {
    'ELEVATOR' => Icons.elevator_outlined,
    'ESCALATOR' => Icons.escalator_warning_outlined,
    'WHEELCHAIR_LIFT' => Icons.accessible_forward,
    'RAMP' => Icons.accessible,
    'ACCESSIBLE_TOILET' || 'TOILET' => Icons.wc_outlined,
    _ => Icons.warning_amber_outlined,
  };
}
