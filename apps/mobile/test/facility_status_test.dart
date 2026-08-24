import 'package:easysubway_mobile/features/stations/domain/facility_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('시설 상태 매핑은 severity, 우선순위와 쉬운 문구를 보존한다', () {
    final blocked = facilityStatusPresentation('BROKEN');
    final caution = facilityStatusPresentation('UNDER_CONSTRUCTION');
    final needsInfo = facilityStatusPresentation('NEEDS_CHECK');
    final unknown = facilityStatusPresentation('UNKNOWN');
    final normal = facilityStatusPresentation('OPERATING');

    expect(FacilityStatusSeverity.values, [
      FacilityStatusSeverity.blocked,
      FacilityStatusSeverity.caution,
      FacilityStatusSeverity.needsInfo,
      FacilityStatusSeverity.normal,
    ]);
    expect(
      (blocked.severity, blocked.priority, blocked.severityLabel),
      (FacilityStatusSeverity.blocked, 10, '고장·폐쇄'),
    );
    expect(
      (caution.severity, caution.priority, caution.severityLabel),
      (FacilityStatusSeverity.caution, 20, '가기 전 살펴보기'),
    );
    expect(
      (needsInfo.severity, needsInfo.priority, needsInfo.statusTitle),
      (FacilityStatusSeverity.needsInfo, 30, '상태 미확인'),
    );
    expect(
      (unknown.severity, unknown.priority, unknown.statusTitle),
      (FacilityStatusSeverity.needsInfo, 30, '설치 확인 · 운행상태 미확인'),
    );
    expect(
      (normal.severity, normal.priority, normal.severityLabel),
      (FacilityStatusSeverity.normal, 40, '정상'),
    );
  });

  test('시설 상태 summary와 semantic 문구는 severity 순서와 접근성 의미를 보존한다', () {
    const statuses = ['NEEDS_CHECK', 'BROKEN', 'UNDER_CONSTRUCTION', 'UNKNOWN'];

    expect(
      buildFacilityAttentionSummary(statuses),
      '고장·폐쇄 1개 · 가기 전 살펴보기 1개 · 미확인 1개 · 미확인 1개',
    );
    expect(
      buildFacilityAttentionSemanticLabel(statuses),
      '살펴볼 시설, 고장·폐쇄 1개, 가기 전 살펴보기 1개, 미확인 1개, 미확인 1개',
    );
    expect(buildFacilityAttentionSummary(const ['OPEN']), '');
    expect(buildFacilityAttentionSemanticLabel(const ['OPEN']), '살펴볼 시설이 없어요');
  });

  test('시설 상태 표시와 semantic 문구는 동일 라벨 중복을 만들지 않는다', () {
    expect(
      facilityStatusDisplayLabel(statusLabel: '정상', severityLabel: '정상'),
      '정상',
    );
    expect(
      facilityStatusDisplayLabel(statusLabel: '점검 중', severityLabel: '미확인'),
      '미확인 · 점검 중',
    );
    expect(
      facilityStatusSemanticLabel(statusLabel: '점검 중', severityLabel: '미확인'),
      '점검 중, 미확인',
    );
  });
}
