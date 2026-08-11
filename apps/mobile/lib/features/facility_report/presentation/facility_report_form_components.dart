import 'package:flutter/material.dart';

import '../../../accessible_design.dart';
import '../../../design_tokens.dart';
import '../application/facility_report_state.dart';
import '../domain/facility_report_result.dart';
import '../domain/facility_report_target.dart';
import '../domain/facility_report_type.dart';
import 'facility_report_result_labels.dart';
import 'facility_report_type_options.dart';

const facilityReportCardRadius = BorderRadius.all(
  Radius.circular(EasySubwayRadius.sheet),
);

const _facilityReportFailureNextAction = '내용을 확인한 뒤 네트워크 상태를 보고 다시 보내 주세요.';

Color facilityReportStatusColor(String status) {
  return switch (status) {
    'SUBMITTED' => EasySubwayAccessibleColors.statusInfoContent,
    'UNDER_REVIEW' => EasySubwayAccessibleColors.amber,
    'ACCEPTED' || 'RESOLVED' => EasySubwayAccessibleColors.mintDark,
    'REJECTED' => EasySubwayAccessibleColors.red,
    'DUPLICATE' => EasySubwayAccessibleColors.mutedText,
    _ => EasySubwayAccessibleColors.mutedText,
  };
}

class FacilityReportStatusPanel extends StatelessWidget {
  const FacilityReportStatusPanel({
    required this.result,
    required this.isLoading,
    required this.onRefresh,
    super.key,
  });

  final FacilityReportResult result;
  final bool isLoading;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: EasySubwayAccessibleColors.surface,
        borderRadius: facilityReportCardRadius,
        border: Border.all(color: EasySubwayAccessibleColors.line),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              // 제보 번호와 상태를 한 문장으로 묶어 스크린리더가 상태 변화를 읽게 한다.
              label:
                  '제보 번호 ${result.displayReceiptCode}, 현재 상태 ${result.statusLabel}',
              liveRegion: true,
              child: ExcludeSemantics(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _FacilityReportStatusRow(
                      label: '제보 번호',
                      value: result.displayReceiptCode,
                    ),
                    const SizedBox(height: 10),
                    _FacilityReportStatusRow(
                      label: '진행 상황',
                      value: result.statusLabel,
                      valueColor: facilityReportStatusColor(result.status),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              key: const Key('facilityReportRefreshButton'),
              onPressed: isLoading ? null : onRefresh,
              icon: const Icon(Icons.refresh),
              label: Text(isLoading ? '확인 중' : '진행 상황 확인'),
            ),
          ],
        ),
      ),
    );
  }
}

class _FacilityReportStatusRow extends StatelessWidget {
  const _FacilityReportStatusRow({
    required this.label,
    required this.value,
    this.valueColor,
  });

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: textTheme.labelLarge?.copyWith(
            color: EasySubwayAccessibleColors.mutedText,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: textTheme.titleMedium?.copyWith(
            color: valueColor ?? EasySubwayAccessibleColors.text,
            fontWeight: FontWeight.w700,
            height: 1.25,
          ),
        ),
      ],
    );
  }
}

class FacilityReportHeader extends StatelessWidget {
  const FacilityReportHeader({required this.target, super.key});

  final FacilityReportTarget target;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Semantics(
      label:
          '${target.stationName}역, ${target.facilityName}, ${target.facilityTypeLabel}, 현재 ${target.facilityStatusLabel}',
      child: ExcludeSemantics(
        child: ColoredBox(
          color: EasySubwayAccessibleColors.surface,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${target.stationName}역',
                  style: textTheme.bodyLarge?.copyWith(
                    color: EasySubwayAccessibleColors.text,
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  target.facilityName,
                  style: textTheme.bodyLarge?.copyWith(
                    color: EasySubwayAccessibleColors.text,
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${target.facilityTypeLabel} · ${target.facilityStatusLabel}',
                  style: textTheme.bodyMedium?.copyWith(
                    color: EasySubwayAccessibleColors.mutedText,
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class FacilityReportSectionTitle extends StatelessWidget {
  const FacilityReportSectionTitle({required this.title, super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: EasySubwayAccessibleColors.scaffoldSurface,
      child: SizedBox(
        width: double.infinity,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
          child: Semantics(
            header: true,
            child: Text(
              title,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: EasySubwayAccessibleColors.secondaryText,
                fontWeight: FontWeight.w700,
                height: 1.25,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class FacilityReportTypeRow extends StatelessWidget {
  const FacilityReportTypeRow({
    required this.option,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final FacilityReportTypeOption option;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final textColor = selected
        ? EasySubwayAccessibleColors.primary
        : EasySubwayAccessibleColors.text;
    final enabled = onTap != null;
    final stateLabel = !enabled ? '선택 불가' : (selected ? '선택됨' : '선택 가능');
    final semanticsLabel = '${option.label} $stateLabel';

    return Semantics(
      label: semanticsLabel,
      button: true,
      enabled: enabled,
      selected: selected,
      onTap: onTap,
      child: ExcludeSemantics(
        child: ListTile(
          key: Key('facilityReportType-${option.reportType}'),
          onTap: onTap,
          enabled: onTap != null,
          minVerticalPadding: 12,
          contentPadding: const EdgeInsets.symmetric(horizontal: 20),
          tileColor: EasySubwayAccessibleColors.surface,
          leading: Icon(option.icon, color: textColor, size: 26),
          title: Text(
            option.label,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: textColor,
              fontWeight: FontWeight.w700,
              height: 1.25,
            ),
          ),
          trailing: selected
              ? const Icon(
                  Icons.check_circle,
                  color: EasySubwayAccessibleColors.primary,
                )
              : const Icon(
                  Icons.circle_outlined,
                  color: EasySubwayAccessibleColors.disclosure,
                ),
        ),
      ),
    );
  }
}

class FacilityReportMessage extends StatelessWidget {
  const FacilityReportMessage({required this.state, super.key});

  final FacilityReportState state;

  @override
  Widget build(BuildContext context) {
    final isFailure = state.status == FacilityReportViewStatus.failure;
    final color = isFailure
        ? EasySubwayAccessibleColors.red
        : EasySubwayAccessibleColors.primary;
    final icon = isFailure ? Icons.error_outline : Icons.check_circle_outline;
    final shouldShowNextAction = _shouldShowFailureNextAction(state);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          container: true,
          label: state.message,
          liveRegion: true,
          child: ExcludeSemantics(
            child: Row(
              children: [
                Icon(icon, color: color, size: 26),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    state.message,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: EasySubwayAccessibleColors.text,
                      fontWeight: FontWeight.w700,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (shouldShowNextAction) ...[
          const SizedBox(height: 8),
          Semantics(
            key: const Key('facilityReportFailureNextAction'),
            container: true,
            excludeSemantics: true,
            liveRegion: true,
            label: '도움말, $_facilityReportFailureNextAction',
            child: Text(
              _facilityReportFailureNextAction,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: EasySubwayAccessibleColors.mutedText,
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

bool _shouldShowFailureNextAction(FacilityReportState state) {
  return state.status == FacilityReportViewStatus.failure &&
      state.result == null;
}

class FacilityReportLocationMessage extends StatelessWidget {
  const FacilityReportLocationMessage({
    required this.message,
    required this.isFailure,
    super.key,
  });

  final String message;
  final bool isFailure;

  @override
  Widget build(BuildContext context) {
    final color = isFailure
        ? EasySubwayAccessibleColors.red
        : EasySubwayAccessibleColors.primary;
    final icon = isFailure ? Icons.error_outline : Icons.check_circle_outline;

    return Semantics(
      label: message,
      liveRegion: true,
      child: ExcludeSemantics(
        child: Row(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: EasySubwayAccessibleColors.text,
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
