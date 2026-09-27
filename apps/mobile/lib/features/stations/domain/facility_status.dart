enum FacilityStatusSeverity { blocked, caution, needsInfo, normal }

class FacilityStatusPresentation {
  const FacilityStatusPresentation({
    required this.severity,
    required this.severityLabel,
    required this.statusTitle,
    required this.nextActionLabel,
    required this.nextActionDescription,
    required this.priority,
  });

  final FacilityStatusSeverity severity;
  final String severityLabel;
  final String statusTitle;
  final String nextActionLabel;
  final String nextActionDescription;
  final int priority;

  bool get needsAttention => severity != FacilityStatusSeverity.normal;
}

const _blockedPresentation = FacilityStatusPresentation(
  severity: FacilityStatusSeverity.blocked,
  severityLabel: '고장·폐쇄',
  statusTitle: '이용할 수 없어요',
  nextActionLabel: '대체 출구 보기',
  nextActionDescription: '이동 전 다른 출구와 역무원 안내를 확인하세요.',
  priority: 10,
);

const _cautionPresentation = FacilityStatusPresentation(
  severity: FacilityStatusSeverity.caution,
  severityLabel: '가기 전 살펴보기',
  statusTitle: '가기 전에 확인해 주세요',
  nextActionLabel: '역무원 도움 요청',
  nextActionDescription: '현장 안내를 확인하고 필요하면 역무원 도움을 요청하세요.',
  priority: 20,
);

const _needsInfoPresentation = FacilityStatusPresentation(
  severity: FacilityStatusSeverity.normal,
  severityLabel: '정상',
  statusTitle: '정상 운행',
  nextActionLabel: '자세히 보기',
  nextActionDescription: '현장 안내를 확인해 주세요.',
  priority: 40,
);

const _unknownPresentation = FacilityStatusPresentation(
  severity: FacilityStatusSeverity.normal,
  severityLabel: '정상',
  statusTitle: '정상 운행',
  nextActionLabel: '자세히 보기',
  nextActionDescription: '현장 안내를 확인해 주세요.',
  priority: 40,
);

const _normalPresentation = FacilityStatusPresentation(
  severity: FacilityStatusSeverity.normal,
  severityLabel: '정상',
  statusTitle: '정상 운행',
  nextActionLabel: '시설 제보',
  nextActionDescription: '시설 안내가 다르면 알려 주세요.',
  priority: 40,
);

FacilityStatusPresentation facilityStatusPresentation(String status) {
  return switch (status.trim().toUpperCase()) {
    'BROKEN' ||
    'CLOSED' ||
    'OUT_OF_SERVICE' ||
    'UNAVAILABLE' => _blockedPresentation,
    'UNDER_CONSTRUCTION' ||
    'CONSTRUCTION' ||
    'USER_REPORTED' => _cautionPresentation,
    'UNKNOWN' => _unknownPresentation,
    'NEEDS_REPORT' ||
    'NEEDS_CHECK' ||
    'CHECK_REQUIRED' => _needsInfoPresentation,
    'NORMAL' ||
    'ADMIN_VERIFIED' ||
    'AVAILABLE' ||
    'IN_SERVICE' ||
    'OPERATING' ||
    'OPEN' => _normalPresentation,
    _ => _needsInfoPresentation,
  };
}

String buildFacilityAttentionSummary(Iterable<String> statuses) {
  final counts = _attentionCounts(statuses);
  if (counts.isEmpty) {
    return '';
  }
  return counts.entries
      .map((entry) => '${entry.key.severityLabel} ${entry.value}개')
      .join(', ');
}

String buildFacilityAttentionSemanticLabel(Iterable<String> statuses) {
  final counts = _attentionCounts(statuses);
  if (counts.isEmpty) {
    return '살펴볼 시설이 없어요';
  }
  final summary = counts.entries
      .map((entry) => '${entry.key.severityLabel} ${entry.value}개')
      .join(', ');
  return '살펴볼 시설, $summary';
}

String facilityStatusDisplayLabel({
  required String statusLabel,
  required String severityLabel,
}) {
  if (statusLabel == severityLabel || statusLabel.contains(severityLabel)) {
    return statusLabel;
  }
  return '$severityLabel, $statusLabel';
}

String facilityStatusSemanticLabel({
  required String statusLabel,
  required String severityLabel,
}) {
  if (statusLabel == severityLabel || statusLabel.contains(severityLabel)) {
    return statusLabel;
  }
  return '$statusLabel, $severityLabel';
}

Map<FacilityStatusPresentation, int> _attentionCounts(
  Iterable<String> statuses,
) {
  final counts = <FacilityStatusPresentation, int>{};
  for (final status in statuses) {
    final presentation = facilityStatusPresentation(status);
    if (!presentation.needsAttention) {
      continue;
    }
    counts[presentation] = (counts[presentation] ?? 0) + 1;
  }
  return {
    for (final presentation in const [
      _blockedPresentation,
      _cautionPresentation,
      _needsInfoPresentation,
      _unknownPresentation,
    ])
      if (counts[presentation] != null) presentation: counts[presentation]!,
  };
}

/// 공공데이터/운영기관 원천의 raw 영문·시스템 식별자(ELEVATOR 2 등)를
/// 상용 서비스(카카오·네이버) 수준의 친화적 한국어 표준 명칭으로 정규화한다.
String formatFacilityDisplayName({
  required String name,
  required String type,
  String description = '',
  String floorFrom = '',
  String floorTo = '',
}) {
  final cleanName = name.trim();
  final cleanDesc = description.trim();
  final upperType = type.trim().toUpperCase();

  // 이미 충분히 정제된 구체적 한국어 명칭(출구·환승·승강장 등 포함 및 raw 영문 식별자 부재)은 원형을 보존한다.
  final hasRawEnglishId =
      cleanName.toUpperCase().contains('ELEVATOR') ||
      cleanName.toUpperCase().contains('ESCALATOR') ||
      cleanName.toUpperCase().contains('LIFT');
  final hasKoreanContext =
      cleanName.contains('출구') ||
      cleanName.contains('승강장') ||
      cleanName.contains('환승') ||
      cleanName.contains('대합실') ||
      cleanName.contains('통로');

  if (!hasRawEnglishId && hasKoreanContext && !cleanName.contains('설치 정보')) {
    return cleanName;
  }

  final isElevator =
      upperType == 'ELEVATOR' ||
      cleanName.toUpperCase().contains('ELEVATOR') ||
      cleanName.contains('엘리베이터') ||
      cleanName.contains('승강기');

  if (isElevator) {
    // 1. 이미 정제된 한국어 출구 표기 (예: '1번 출구 엘리베이터', '2번 출구 승강기')
    final exitElevatorMatch = RegExp(
      r'^(\d+(?:[,\·]\s*\d+)*)\s*번\s*출구\s*(?:엘리베이터|승강기)(?:\s*\(?(\d+)호기\)?)?$',
    ).firstMatch(cleanName);
    if (exitElevatorMatch != null) {
      final exitNum = exitElevatorMatch
          .group(1)!
          .replaceAll(RegExp(r'[,·]\s*'), ', ');
      final unitNum = exitElevatorMatch.group(2);
      return unitNum != null
          ? '$exitNum번 출구 엘리베이터 ($unitNum호기)'
          : '$exitNum번 출구 엘리베이터';
    }

    // 2. 호기 번호 추출 (예: '상록수역 ELEVATOR 2' -> 2)
    final unitMatch = RegExp(
      r'(?:ELEVATOR|elevator|승강기|호기)\s*#?\s*(\d+)',
    ).firstMatch(cleanName);
    final unitNumber = unitMatch?.group(1);

    // 3. 역사 상세 설명(description)에서 방면/출구/동선 추출
    if (cleanDesc.isNotEmpty) {
      // (a) 방면/방향 (예: '한대앞방향', '반월방향', '총신대입구방면')
      final dirMatch = RegExp(
        r'([가-힣a-zA-Z0-9]+)\s*(?:방향|방면)',
      ).firstMatch(cleanDesc.replaceAll(RegExp(r'\([^)]*\)'), ''));
      if (dirMatch != null) {
        var dir = dirMatch.group(1)!;
        dir = dir.replaceAll(RegExp(r'^(?:.*[내외]|대합실|승강장|개찰구|표내는곳)+'), '');
        if (dir.isNotEmpty) {
          if (unitNumber != null) {
            return '$dir 방면 승강기 $unitNumber호기';
          }
          return '$dir 방면 승강기';
        }
      }

      // (b) 출구 번호 (예: '9,10번출구사이', '1번출구 앞')
      final descExitMatch = RegExp(
        r'(\d+(?:[,\·]\s*\d+)*)\s*번\s*출구',
      ).firstMatch(cleanDesc);
      if (descExitMatch != null) {
        final exitNum = descExitMatch
            .group(1)!
            .replaceAll(RegExp(r'[,·]\s*'), ', ');
        if (unitNumber != null) {
          return '$exitNum번 출구 엘리베이터 ($unitNumber호기)';
        }
        return '$exitNum번 출구 엘리베이터';
      }

      // (c) 층간 동선 (지상 ↔ 대합실 등)
      if (cleanDesc.contains('지상') && cleanDesc.contains('대합실')) {
        if (unitNumber != null) {
          return '승강기 $unitNumber호기 (지상 ↔ 대합실)';
        }
        return '지상 ↔ 대합실 엘리베이터';
      }
      if (cleanDesc.contains('대합실') && cleanDesc.contains('승강장')) {
        if (unitNumber != null) {
          return '승강기 $unitNumber호기 (대합실 ↔ 승강장)';
        }
        return '대합실 ↔ 승강장 엘리베이터';
      }
    }

    // (d) 층 정보(floorFrom, floorTo) 기반 동선
    final fFrom = _formatFloor(floorFrom);
    final fTo = _formatFloor(floorTo);
    if (fFrom.isNotEmpty && fTo.isNotEmpty) {
      if (unitNumber != null) {
        return '승강기 $unitNumber호기 ($fFrom ↔ $fTo)';
      }
      return '엘리베이터 ($fFrom ↔ $fTo)';
    }

    // 4. '설치 정보'로 끝나는 공공데이터 메타 (예: '까치울역 엘리베이터 설치 정보')
    if (cleanName.contains('설치 정보')) {
      final countMatch = RegExp(r'(\d+)대\s*설치').firstMatch(cleanDesc);
      if (countMatch != null) {
        return '역내 엘리베이터 (${countMatch.group(1)}대 설치)';
      }
      return '역사 엘리베이터';
    }

    // 5. 호기 번호만 확인되는 경우
    if (unitNumber != null) {
      return '승강기 $unitNumber호기';
    }

    // 6. raw ELEVATOR 단어 제거
    if (cleanName.toUpperCase().contains('ELEVATOR')) {
      return '역사 엘리베이터';
    }

    if (cleanName.isNotEmpty) {
      return cleanName;
    }
    return '엘리베이터';
  }

  // 에스컬레이터
  if (upperType == 'ESCALATOR' ||
      cleanName.toUpperCase().contains('ESCALATOR')) {
    final unitMatch = RegExp(
      r'(?:ESCALATOR|escalator|에스컬레이터|호기)\s*#?\s*(\d+)',
    ).firstMatch(cleanName);
    if (unitMatch != null) {
      return '에스컬레이터 ${unitMatch.group(1)}호기';
    }
    return cleanName.isNotEmpty ? cleanName : '에스컬레이터';
  }

  // 휠체어 리프트
  if (upperType == 'WHEELCHAIR_LIFT' ||
      cleanName.toUpperCase().contains('LIFT')) {
    final unitMatch = RegExp(
      r'(?:LIFT|lift|리프트|호기)\s*#?\s*(\d+)',
    ).firstMatch(cleanName);
    if (unitMatch != null) {
      return '휠체어 리프트 ${unitMatch.group(1)}호기';
    }
    return cleanName.isNotEmpty ? cleanName : '휠체어 리프트';
  }

  return cleanName.isNotEmpty ? cleanName : '시설';
}

String _formatFloor(String floor) {
  final clean = floor.trim().toUpperCase();
  final bMatch = RegExp(r'^B(\d+)$').firstMatch(clean);
  if (bMatch != null) {
    return '지하 ${bMatch.group(1)}층';
  }
  final fMatch = RegExp(r'^(\d+)F$').firstMatch(clean);
  if (fMatch != null) {
    return '지상 ${fMatch.group(1)}층';
  }
  return floor.trim();
}
