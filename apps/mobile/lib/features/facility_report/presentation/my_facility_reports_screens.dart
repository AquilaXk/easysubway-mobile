import 'dart:async';

import 'package:flutter/material.dart';

import '../../../accessible_design.dart';
import '../../../design_tokens.dart';
import '../domain/facility_report_exception.dart';
import '../domain/facility_report_repository.dart';
import '../domain/facility_report_result.dart';
import 'facility_report_form_components.dart';
import 'facility_report_result_labels.dart';

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
