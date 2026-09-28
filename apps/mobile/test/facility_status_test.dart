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
      (FacilityStatusSeverity.normal, 40, '정상 운행'),
    );
    expect(
      (unknown.severity, unknown.priority, unknown.statusTitle),
      (FacilityStatusSeverity.normal, 40, '정상 운행'),
    );
    expect(
      (normal.severity, normal.priority, normal.severityLabel),
      (FacilityStatusSeverity.normal, 40, '정상'),
    );
  });

  test('시설 상태 summary와 semantic 문구는 severity 순서와 접근성 의미를 보존한다', () {
    const statuses = ['NEEDS_CHECK', 'BROKEN', 'UNDER_CONSTRUCTION', 'UNKNOWN'];

    expect(buildFacilityAttentionSummary(statuses), '고장·폐쇄 1개, 가기 전 살펴보기 1개');
    expect(
      buildFacilityAttentionSemanticLabel(statuses),
      '살펴볼 시설, 고장·폐쇄 1개, 가기 전 살펴보기 1개',
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
      facilityStatusDisplayLabel(statusLabel: '점검 중', severityLabel: '주의'),
      '주의, 점검 중',
    );
    expect(
      facilityStatusSemanticLabel(statusLabel: '점검 중', severityLabel: '주의'),
      '점검 중, 주의',
    );
    expect(
      facilityStatusDisplayLabel(statusLabel: '정상 운행', severityLabel: '정상'),
      '정상 운행',
    );
    expect(
      facilityStatusSemanticLabel(statusLabel: '정상 운행', severityLabel: '정상'),
      '정상 운행',
    );
  });

  test('formatFacilityDisplayName은 raw 영문 식별자를 한국어 친화 명칭으로 정규화한다', () {
    // 1. 상록수역 ELEVATOR 2 (사용자 구체 지적 사례)
    expect(
      formatFacilityDisplayName(
        name: '상록수역 ELEVATOR 2',
        type: 'ELEVATOR',
        description: '(1층)표내는곳내한대앞방향계단옆',
      ),
      '한대앞 방면 승강기 2호기',
    );

    // 2. 상록수역 반월 방면 엘리베이터
    expect(
      formatFacilityDisplayName(
        name: '상록수역 ELEVATOR 1',
        type: 'ELEVATOR',
        description: '(1층)표내는곳내반월방향계단옆',
      ),
      '반월 방면 승강기 1호기',
    );

    // 3. 층간 이동 정보가 있는 경우
    expect(
      formatFacilityDisplayName(
        name: 'ELEVATOR 3',
        type: 'ELEVATOR',
        floorFrom: 'B1',
        floorTo: '1F',
      ),
      '승강기 3호기 (지하 1층 ↔ 지상 1층)',
    );

    // 4. 출구 번호가 포함된 경우
    expect(
      formatFacilityDisplayName(
        name: 'ELEVATOR 1',
        type: 'ELEVATOR',
        description: '2번 출구 앞',
      ),
      '2번 출구 엘리베이터 (1호기)',
    );

    // 5. 이미 잘 정제된 명칭은 원형 보존
    expect(
      formatFacilityDisplayName(name: '1번 출구 엘리베이터', type: 'ELEVATOR'),
      '1번 출구 엘리베이터',
    );
    expect(
      formatFacilityDisplayName(name: '1,2번 출구 엘리베이터', type: 'ELEVATOR'),
      '1, 2번 출구 엘리베이터',
    );

    // 6. 층간 동선 (지상 ↔ 대합실, 대합실 ↔ 승강장)
    expect(
      formatFacilityDisplayName(
        name: 'ELEVATOR 2',
        type: 'ELEVATOR',
        description: '지상 대합실 연결',
      ),
      '승강기 2호기 (지상 ↔ 대합실)',
    );
    expect(
      formatFacilityDisplayName(
        name: 'ELEVATOR 2',
        type: 'ELEVATOR',
        description: '대합실 승강장 연결',
      ),
      '승강기 2호기 (대합실 ↔ 승강장)',
    );

    // 7. 설치 정보 및 대수
    expect(
      formatFacilityDisplayName(
        name: '엘리베이터 설치 정보',
        type: 'ELEVATOR',
        description: '3대 설치 운영',
      ),
      '역내 엘리베이터 (3대 설치)',
    );

    // 8. 호기 번호 단독 및 raw ELEVATOR 단독
    expect(
      formatFacilityDisplayName(name: '승강기 5호기', type: 'ELEVATOR'),
      '승강기 5호기',
    );
    expect(
      formatFacilityDisplayName(name: 'ELEVATOR', type: 'ELEVATOR'),
      '역사 엘리베이터',
    );
    expect(formatFacilityDisplayName(name: '특수승강기', type: 'ELEVATOR'), '특수승강기');

    // 9. 에스컬레이터 호기 및 기본 명칭
    expect(
      formatFacilityDisplayName(name: 'ESCALATOR 1', type: 'ESCALATOR'),
      '에스컬레이터 1호기',
    );
    expect(
      formatFacilityDisplayName(name: '외부 에스컬레이터', type: 'ESCALATOR'),
      '외부 에스컬레이터',
    );

    // 10. 휠체어 리프트 호기 및 기본 명칭
    expect(
      formatFacilityDisplayName(name: 'LIFT 1', type: 'WHEELCHAIR_LIFT'),
      '휠체어 리프트 1호기',
    );
    expect(
      formatFacilityDisplayName(name: '계단 리프트', type: 'WHEELCHAIR_LIFT'),
      '계단 리프트',
    );

    // 11. 비표준 층 정보 포맷
    expect(
      formatFacilityDisplayName(
        name: 'ELEVATOR 1',
        type: 'ELEVATOR',
        floorFrom: 'M1',
        floorTo: 'M2',
      ),
      '승강기 1호기 (M1 ↔ M2)',
    );
  });
}
