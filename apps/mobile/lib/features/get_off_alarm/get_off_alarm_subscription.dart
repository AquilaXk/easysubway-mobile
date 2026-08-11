import '../../generated/journey_v3/journey_v3_contract.dart';
import 'get_off_alarm_schedule_mode.dart';

const String journeyAlarmSubscriptionSchemaVersion =
    'JOURNEY_ALARM_SUBSCRIPTION_V1';

/// Journey V3에서 선택한 한 후보를 다른 검색 결과와 구별하는 불변 identity.
class JourneyAlarmSubscriptionIdentity {
  const JourneyAlarmSubscriptionIdentity({
    required this.contractVersion,
    required this.requestId,
    required this.queryId,
    required this.journeyId,
    required this.calculatedAt,
    required this.validUntil,
    required this.effectiveDepartureTime,
    required this.serviceDate,
    required this.serviceTimezone,
    required this.sourceIdentity,
    required this.requestPolicy,
  });

  final JourneyContractVersion contractVersion;
  final String requestId;
  final String queryId;
  final String journeyId;
  final DateTime calculatedAt;
  final DateTime validUntil;
  final DateTime effectiveDepartureTime;
  final JourneyDate serviceDate;
  final String serviceTimezone;
  final JourneySourceIdentity sourceIdentity;
  final JourneyRequestPolicy requestPolicy;

  Map<String, Object?> toJson() => {
    'contractVersion': contractVersion.wire,
    'requestId': requestId,
    'queryId': queryId,
    'journeyId': journeyId,
    'calculatedAt': JourneyV3Validation.rfc3339Wire(calculatedAt),
    'validUntil': JourneyV3Validation.rfc3339Wire(validUntil),
    'effectiveDepartureTime': JourneyV3Validation.rfc3339Wire(
      effectiveDepartureTime,
    ),
    'serviceDate': serviceDate.toString(),
    'serviceTimezone': serviceTimezone,
    'sourceIdentity': sourceIdentity.toJson(),
    'requestPolicy': requestPolicy.toJson(),
  };

  static JourneyAlarmSubscriptionIdentity? fromJson(Object? value) {
    if (value is! Map<String, Object?>) return null;
    try {
      JourneyV3Validation.exactKeys(value, const {
        'contractVersion',
        'requestId',
        'queryId',
        'journeyId',
        'calculatedAt',
        'validUntil',
        'effectiveDepartureTime',
        'serviceDate',
        'serviceTimezone',
        'sourceIdentity',
        'requestPolicy',
      });
      final source = value['sourceIdentity'];
      final policy = value['requestPolicy'];
      if (source is! Map<String, Object?> || policy is! Map<String, Object?>) {
        return null;
      }
      final identity = JourneyAlarmSubscriptionIdentity(
        contractVersion: JourneyContractVersionWire.fromWire(
          value['contractVersion'],
        ),
        requestId: JourneyV3Validation.ulid(value['requestId'], 'requestId'),
        queryId: JourneyV3Validation.nonBlank(value['queryId'], 'queryId'),
        journeyId: JourneyV3Validation.nonBlank(
          value['journeyId'],
          'journeyId',
        ),
        calculatedAt: JourneyV3Validation.rfc3339(
          value['calculatedAt'],
          'calculatedAt',
        ),
        validUntil: JourneyV3Validation.rfc3339(
          value['validUntil'],
          'validUntil',
        ),
        effectiveDepartureTime: JourneyV3Validation.rfc3339(
          value['effectiveDepartureTime'],
          'effectiveDepartureTime',
        ),
        serviceDate: JourneyDate.parse(value['serviceDate']),
        serviceTimezone: JourneyV3Validation.enumWire(
          value['serviceTimezone'],
          'serviceTimezone',
          (candidate) {
            if (candidate != 'Asia/Seoul') throw const FormatException();
            return 'Asia/Seoul';
          },
        ),
        sourceIdentity: JourneySourceIdentity.fromJson(source),
        requestPolicy: JourneyRequestPolicy.fromJson(policy),
      );
      if (identity.validUntil.isBefore(identity.calculatedAt) ||
          !_sourceMatchesPolicy(identity)) {
        return null;
      }
      return identity;
    } on FormatException {
      return null;
    }
  }

  static bool _sourceMatchesPolicy(JourneyAlarmSubscriptionIdentity identity) {
    final realtimeSnapshotId = identity.sourceIdentity.realtimeSnapshotId;
    return switch (identity.requestPolicy.timePolicy) {
      TimePolicy.timetableRequired => realtimeSnapshotId == null,
      TimePolicy.realtimeRequired => realtimeSnapshotId != null,
    };
  }

  @override
  bool operator ==(Object other) =>
      other is JourneyAlarmSubscriptionIdentity &&
      contractVersion == other.contractVersion &&
      requestId == other.requestId &&
      queryId == other.queryId &&
      journeyId == other.journeyId &&
      calculatedAt == other.calculatedAt &&
      validUntil == other.validUntil &&
      effectiveDepartureTime == other.effectiveDepartureTime &&
      serviceDate.toString() == other.serviceDate.toString() &&
      serviceTimezone == other.serviceTimezone &&
      sourceIdentity.routeBundleId == other.sourceIdentity.routeBundleId &&
      sourceIdentity.routeBundleSha256 ==
          other.sourceIdentity.routeBundleSha256 &&
      sourceIdentity.timetableSnapshotId ==
          other.sourceIdentity.timetableSnapshotId &&
      sourceIdentity.accessibilitySnapshotId ==
          other.sourceIdentity.accessibilitySnapshotId &&
      sourceIdentity.realtimeSnapshotId ==
          other.sourceIdentity.realtimeSnapshotId &&
      requestPolicy.timePolicy == other.requestPolicy.timePolicy &&
      requestPolicy.mobilityProfile == other.requestPolicy.mobilityProfile &&
      requestPolicy.constraintMode == other.requestPolicy.constraintMode &&
      requestPolicy.maxTransfers == other.requestPolicy.maxTransfers &&
      requestPolicy.alternativeCount == other.requestPolicy.alternativeCount;

  @override
  int get hashCode => Object.hashAll([
    contractVersion,
    requestId,
    queryId,
    journeyId,
    calculatedAt,
    validUntil,
    effectiveDepartureTime,
    serviceDate.toString(),
    serviceTimezone,
    sourceIdentity.routeBundleId,
    sourceIdentity.routeBundleSha256,
    sourceIdentity.timetableSnapshotId,
    sourceIdentity.accessibilitySnapshotId,
    sourceIdentity.realtimeSnapshotId,
    requestPolicy.timePolicy,
    requestPolicy.mobilityProfile,
    requestPolicy.constraintMode,
    requestPolicy.maxTransfers,
    requestPolicy.alternativeCount,
  ]);
}

/// 활성 경로 하나에 대한 하차 알림 구독 상태.
///
/// 앱 재시작 후에도 "알림 켜짐" 상태를 복원하고 새 경로 탐색 시 이전 알림을
/// 취소할 수 있도록, 활성 구독을 로컬에 영속 저장한다(단일 경로 원칙).
class GetOffAlarmSubscription {
  const GetOffAlarmSubscription({
    required this.routeId,
    this.journeyIdentity,
    required this.transferAlarmEnabled,
    required this.scheduledCount,
    required this.scheduleMode,
    required this.inexactNotice,
    required this.destination,
    required this.transfers,
  });

  final String routeId;
  final JourneyAlarmSubscriptionIdentity? journeyIdentity;
  final bool transferAlarmEnabled;
  final int scheduledCount;
  final GetOffAlarmScheduleMode scheduleMode;
  final String? inexactNotice;
  final GetOffAlarmStopRef destination;
  final List<GetOffAlarmStopRef> transfers;

  Map<String, Object?> toJson() {
    final identity = journeyIdentity;
    if (identity != null) {
      return {
        'schemaVersion': journeyAlarmSubscriptionSchemaVersion,
        'selectedJourneyId': routeId,
        'journeyIdentity': identity.toJson(),
        'transferAlarmEnabled': transferAlarmEnabled,
        'scheduledCount': scheduledCount,
        'scheduleMode': scheduleMode.name,
        'inexactNotice': inexactNotice,
        'destination': destination.toJson(),
        'transfers': transfers.map((stop) => stop.toJson()).toList(),
      };
    }
    return {
      'routeId': routeId,
      'transferAlarmEnabled': transferAlarmEnabled,
      'scheduledCount': scheduledCount,
      'scheduleMode': scheduleMode.name,
      'inexactNotice': inexactNotice,
      'destination': destination.toJson(),
      'transfers': transfers.map((stop) => stop.toJson()).toList(),
    };
  }

  /// JSON에서 복원한다. 형식이 어긋나면 null(강등 사다리: 무음 실패 대신 없음).
  static GetOffAlarmSubscription? fromJson(Object? json) {
    if (json is! Map<String, Object?>) {
      return null;
    }
    try {
      JourneyV3Validation.exactKeys(json, const {
        'schemaVersion',
        'selectedJourneyId',
        'journeyIdentity',
        'transferAlarmEnabled',
        'scheduledCount',
        'scheduleMode',
        'inexactNotice',
        'destination',
        'transfers',
      });
    } on FormatException {
      return null;
    }
    if (json['schemaVersion'] != journeyAlarmSubscriptionSchemaVersion) {
      return null;
    }
    final routeId = json['selectedJourneyId'];
    final journeyIdentity = JourneyAlarmSubscriptionIdentity.fromJson(
      json['journeyIdentity'],
    );
    final destination = GetOffAlarmStopRef.fromJson(json['destination']);
    if (routeId is! String ||
        routeId.trim().isEmpty ||
        journeyIdentity == null ||
        routeId != journeyIdentity.journeyId ||
        destination == null) {
      return null;
    }
    final transfersJson = json['transfers'];
    if (transfersJson is! List) {
      return null;
    }
    final transfers = <GetOffAlarmStopRef>[];
    for (final entry in transfersJson) {
      final stop = GetOffAlarmStopRef.fromJson(entry);
      if (stop == null) {
        return null;
      }
      transfers.add(stop);
    }
    final transferAlarmEnabled = json['transferAlarmEnabled'];
    if (transferAlarmEnabled is! bool) {
      return null;
    }
    final maxScheduledCount = 1 + (transferAlarmEnabled ? transfers.length : 0);
    final scheduledCount = json['scheduledCount'];
    if (scheduledCount is! int ||
        scheduledCount <= 0 ||
        scheduledCount > maxScheduledCount) {
      return null;
    }
    final scheduleMode = switch (json['scheduleMode']) {
      'exact' => GetOffAlarmScheduleMode.exact,
      'inexact' => GetOffAlarmScheduleMode.inexact,
      _ => null,
    };
    final Object? rawInexactNotice = json['inexactNotice'];
    final String? inexactNotice;
    if (rawInexactNotice == null) {
      inexactNotice = null;
    } else if (rawInexactNotice is String) {
      inexactNotice = rawInexactNotice;
    } else {
      return null;
    }
    if (scheduleMode == null ||
        (scheduleMode == GetOffAlarmScheduleMode.exact &&
            inexactNotice != null) ||
        (scheduleMode == GetOffAlarmScheduleMode.inexact &&
            (inexactNotice == null || inexactNotice.isEmpty))) {
      return null;
    }
    return GetOffAlarmSubscription(
      routeId: routeId,
      journeyIdentity: journeyIdentity,
      transferAlarmEnabled: transferAlarmEnabled,
      scheduledCount: scheduledCount,
      scheduleMode: scheduleMode,
      inexactNotice: inexactNotice,
      destination: destination,
      transfers: transfers,
    );
  }
}

/// 하차 알림 대상 정차역의 최소 참조(역·도착 시각).
class GetOffAlarmStopRef {
  const GetOffAlarmStopRef({
    required this.stationId,
    required this.stationName,
    required this.arrivalAt,
  });

  final String stationId;
  final String stationName;
  final DateTime arrivalAt;

  Map<String, Object?> toJson() {
    return {
      'stationId': stationId,
      'stationName': stationName,
      'arrivalAtEpochMs': arrivalAt.toUtc().millisecondsSinceEpoch,
    };
  }

  static GetOffAlarmStopRef? fromJson(Object? json) {
    if (json is! Map<String, Object?>) {
      return null;
    }
    final stationId = json['stationId'];
    final stationName = json['stationName'];
    final epochMs = json['arrivalAtEpochMs'];
    if (stationId is! String ||
        stationId.trim().isEmpty ||
        stationName is! String ||
        stationName.trim().isEmpty ||
        epochMs is! int) {
      return null;
    }
    return GetOffAlarmStopRef(
      stationId: stationId,
      stationName: stationName,
      arrivalAt: DateTime.fromMillisecondsSinceEpoch(epochMs, isUtc: true),
    );
  }
}
