// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=200
// Generated closed Journey V3 wire enums.
enum JourneyContractVersion { journeySearchV3 }

extension JourneyContractVersionWire on JourneyContractVersion {
  String get wire => switch (this) {
    JourneyContractVersion.journeySearchV3 => "JOURNEY_SEARCH_V3",
  };
  static JourneyContractVersion fromWire(Object? value) {
    if (value is! String) throw const FormatException('wire value must be string');
    return switch (value) {
      "JOURNEY_SEARCH_V3" => JourneyContractVersion.journeySearchV3,
      _ => throw const FormatException('unrecognized wire value'),
    };
  }
}

enum JourneyErrorContractVersion { journeyErrorV1 }

extension JourneyErrorContractVersionWire on JourneyErrorContractVersion {
  String get wire => switch (this) {
    JourneyErrorContractVersion.journeyErrorV1 => "JOURNEY_ERROR_V1",
  };
  static JourneyErrorContractVersion fromWire(Object? value) {
    if (value is! String) throw const FormatException('wire value must be string');
    return switch (value) {
      "JOURNEY_ERROR_V1" => JourneyErrorContractVersion.journeyErrorV1,
      _ => throw const FormatException('unrecognized wire value'),
    };
  }
}

enum JourneySessionScope { journeyV3 }

extension JourneySessionScopeWire on JourneySessionScope {
  String get wire => switch (this) {
    JourneySessionScope.journeyV3 => "journey:v3",
  };
  static JourneySessionScope fromWire(Object? value) {
    if (value is! String) throw const FormatException('wire value must be string');
    return switch (value) {
      "journey:v3" => JourneySessionScope.journeyV3,
      _ => throw const FormatException('unrecognized wire value'),
    };
  }
}

enum JourneyDepartureMode { now, scheduled }

extension JourneyDepartureModeWire on JourneyDepartureMode {
  String get wire => switch (this) {
    JourneyDepartureMode.now => "NOW",
    JourneyDepartureMode.scheduled => "SCHEDULED",
  };
  static JourneyDepartureMode fromWire(Object? value) {
    if (value is! String) throw const FormatException('wire value must be string');
    return switch (value) {
      "NOW" => JourneyDepartureMode.now,
      "SCHEDULED" => JourneyDepartureMode.scheduled,
      _ => throw const FormatException('unrecognized wire value'),
    };
  }
}

enum JourneyStatus { found }

extension JourneyStatusWire on JourneyStatus {
  String get wire => switch (this) {
    JourneyStatus.found => "FOUND",
  };
  static JourneyStatus fromWire(Object? value) {
    if (value is! String) throw const FormatException('wire value must be string');
    return switch (value) {
      "FOUND" => JourneyStatus.found,
      _ => throw const FormatException('unrecognized wire value'),
    };
  }
}

enum JourneyPlanSource { serverTimetableRaptor }

extension JourneyPlanSourceWire on JourneyPlanSource {
  String get wire => switch (this) {
    JourneyPlanSource.serverTimetableRaptor => "SERVER_TIMETABLE_RAPTOR",
  };
  static JourneyPlanSource fromWire(Object? value) {
    if (value is! String) throw const FormatException('wire value must be string');
    return switch (value) {
      "SERVER_TIMETABLE_RAPTOR" => JourneyPlanSource.serverTimetableRaptor,
      _ => throw const FormatException('unrecognized wire value'),
    };
  }
}

enum JourneyTimeSource { timetable, realtime }

extension JourneyTimeSourceWire on JourneyTimeSource {
  String get wire => switch (this) {
    JourneyTimeSource.timetable => "TIMETABLE",
    JourneyTimeSource.realtime => "REALTIME",
  };
  static JourneyTimeSource fromWire(Object? value) {
    if (value is! String) throw const FormatException('wire value must be string');
    return switch (value) {
      "TIMETABLE" => JourneyTimeSource.timetable,
      "REALTIME" => JourneyTimeSource.realtime,
      _ => throw const FormatException('unrecognized wire value'),
    };
  }
}

enum JourneyAccessibilityResult { verified }

extension JourneyAccessibilityResultWire on JourneyAccessibilityResult {
  String get wire => switch (this) {
    JourneyAccessibilityResult.verified => "VERIFIED",
  };
  static JourneyAccessibilityResult fromWire(Object? value) {
    if (value is! String) throw const FormatException('wire value must be string');
    return switch (value) {
      "VERIFIED" => JourneyAccessibilityResult.verified,
      _ => throw const FormatException('unrecognized wire value'),
    };
  }
}

enum JourneyLegType { entry, ride, transfer, exit }

extension JourneyLegTypeWire on JourneyLegType {
  String get wire => switch (this) {
    JourneyLegType.entry => "ENTRY",
    JourneyLegType.ride => "RIDE",
    JourneyLegType.transfer => "TRANSFER",
    JourneyLegType.exit => "EXIT",
  };
  static JourneyLegType fromWire(Object? value) {
    if (value is! String) throw const FormatException('wire value must be string');
    return switch (value) {
      "ENTRY" => JourneyLegType.entry,
      "RIDE" => JourneyLegType.ride,
      "TRANSFER" => JourneyLegType.transfer,
      "EXIT" => JourneyLegType.exit,
      _ => throw const FormatException('unrecognized wire value'),
    };
  }
}

enum JourneyOperation { issueJourneySession, searchJourneys, searchStationTimetables }

extension JourneyOperationWire on JourneyOperation {
  String get wire => switch (this) {
    JourneyOperation.issueJourneySession => "issueJourneySession",
    JourneyOperation.searchJourneys => "searchJourneys",
    JourneyOperation.searchStationTimetables => "searchStationTimetables",
  };
  static JourneyOperation fromWire(Object? value) {
    if (value is! String) throw const FormatException('wire value must be string');
    return switch (value) {
      "issueJourneySession" => JourneyOperation.issueJourneySession,
      "searchJourneys" => JourneyOperation.searchJourneys,
      "searchStationTimetables" => JourneyOperation.searchStationTimetables,
      _ => throw const FormatException('unrecognized wire value'),
    };
  }
}

enum StationTimetableSelectorKind { serviceDate, dayType, nextDepartures }

extension StationTimetableSelectorKindWire on StationTimetableSelectorKind {
  String get wire => switch (this) {
    StationTimetableSelectorKind.serviceDate => "SERVICE_DATE",
    StationTimetableSelectorKind.dayType => "DAY_TYPE",
    StationTimetableSelectorKind.nextDepartures => "NEXT_DEPARTURES",
  };
  static StationTimetableSelectorKind fromWire(Object? value) {
    if (value is! String) throw const FormatException('wire value must be string');
    return switch (value) {
      "SERVICE_DATE" => StationTimetableSelectorKind.serviceDate,
      "DAY_TYPE" => StationTimetableSelectorKind.dayType,
      "NEXT_DEPARTURES" => StationTimetableSelectorKind.nextDepartures,
      _ => throw const FormatException('unrecognized wire value'),
    };
  }
}

enum StationTimetableDayType { weekday, saturday, sundayHoliday }

extension StationTimetableDayTypeWire on StationTimetableDayType {
  String get wire => switch (this) {
    StationTimetableDayType.weekday => "WEEKDAY",
    StationTimetableDayType.saturday => "SATURDAY",
    StationTimetableDayType.sundayHoliday => "SUNDAY_HOLIDAY",
  };
  static StationTimetableDayType fromWire(Object? value) {
    if (value is! String) throw const FormatException('wire value must be string');
    return switch (value) {
      "WEEKDAY" => StationTimetableDayType.weekday,
      "SATURDAY" => StationTimetableDayType.saturday,
      "SUNDAY_HOLIDAY" => StationTimetableDayType.sundayHoliday,
      _ => throw const FormatException('unrecognized wire value'),
    };
  }
}

enum StationTimetableServicePattern { local, express }

extension StationTimetableServicePatternWire on StationTimetableServicePattern {
  String get wire => switch (this) {
    StationTimetableServicePattern.local => "LOCAL",
    StationTimetableServicePattern.express => "EXPRESS",
  };
  static StationTimetableServicePattern fromWire(Object? value) {
    if (value is! String) throw const FormatException('wire value must be string');
    return switch (value) {
      "LOCAL" => StationTimetableServicePattern.local,
      "EXPRESS" => StationTimetableServicePattern.express,
      _ => throw const FormatException('unrecognized wire value'),
    };
  }
}

enum StationTimetableServiceClass { subway, itxCheongchun }

extension StationTimetableServiceClassWire on StationTimetableServiceClass {
  String get wire => switch (this) {
    StationTimetableServiceClass.subway => "SUBWAY",
    StationTimetableServiceClass.itxCheongchun => "ITX_CHEONGCHUN",
  };
  static StationTimetableServiceClass fromWire(Object? value) {
    if (value is! String) throw const FormatException('wire value must be string');
    return switch (value) {
      "SUBWAY" => StationTimetableServiceClass.subway,
      "ITX_CHEONGCHUN" => StationTimetableServiceClass.itxCheongchun,
      _ => throw const FormatException('unrecognized wire value'),
    };
  }
}

enum StationTimetableSearchContractVersion { stationTimetableSearchV3 }

extension StationTimetableSearchContractVersionWire on StationTimetableSearchContractVersion {
  String get wire => switch (this) {
    StationTimetableSearchContractVersion.stationTimetableSearchV3 => "STATION_TIMETABLE_SEARCH_V3",
  };
  static StationTimetableSearchContractVersion fromWire(Object? value) {
    if (value is! String) throw const FormatException('wire value must be string');
    return switch (value) {
      "STATION_TIMETABLE_SEARCH_V3" => StationTimetableSearchContractVersion.stationTimetableSearchV3,
      _ => throw const FormatException('unrecognized wire value'),
    };
  }
}

enum StationTimetableServiceTimezone { asiaSeoul }

extension StationTimetableServiceTimezoneWire on StationTimetableServiceTimezone {
  String get wire => switch (this) {
    StationTimetableServiceTimezone.asiaSeoul => "Asia/Seoul",
  };
  static StationTimetableServiceTimezone fromWire(Object? value) {
    if (value is! String) throw const FormatException('wire value must be string');
    return switch (value) {
      "Asia/Seoul" => StationTimetableServiceTimezone.asiaSeoul,
      _ => throw const FormatException('unrecognized wire value'),
    };
  }
}

enum JourneyErrorSemanticCategory {
  requestCorrection,
  routeAbsent,
  accessibilityUnsatisfied,
  routingDataUnavailable,
  routingDataStale,
  routingIdentityFailure,
  serviceUnavailable,
  searchTimeout,
  sessionAuthentication,
  rateLimit,
}

extension JourneyErrorSemanticCategoryWire on JourneyErrorSemanticCategory {
  String get wire => switch (this) {
    JourneyErrorSemanticCategory.requestCorrection => "REQUEST_CORRECTION",
    JourneyErrorSemanticCategory.routeAbsent => "ROUTE_ABSENT",
    JourneyErrorSemanticCategory.accessibilityUnsatisfied => "ACCESSIBILITY_UNSATISFIED",
    JourneyErrorSemanticCategory.routingDataUnavailable => "ROUTING_DATA_UNAVAILABLE",
    JourneyErrorSemanticCategory.routingDataStale => "ROUTING_DATA_STALE",
    JourneyErrorSemanticCategory.routingIdentityFailure => "ROUTING_IDENTITY_FAILURE",
    JourneyErrorSemanticCategory.serviceUnavailable => "SERVICE_UNAVAILABLE",
    JourneyErrorSemanticCategory.searchTimeout => "SEARCH_TIMEOUT",
    JourneyErrorSemanticCategory.sessionAuthentication => "SESSION_AUTHENTICATION",
    JourneyErrorSemanticCategory.rateLimit => "RATE_LIMIT",
  };
  static JourneyErrorSemanticCategory fromWire(Object? value) {
    if (value is! String) throw const FormatException('wire value must be string');
    return switch (value) {
      "REQUEST_CORRECTION" => JourneyErrorSemanticCategory.requestCorrection,
      "ROUTE_ABSENT" => JourneyErrorSemanticCategory.routeAbsent,
      "ACCESSIBILITY_UNSATISFIED" => JourneyErrorSemanticCategory.accessibilityUnsatisfied,
      "ROUTING_DATA_UNAVAILABLE" => JourneyErrorSemanticCategory.routingDataUnavailable,
      "ROUTING_DATA_STALE" => JourneyErrorSemanticCategory.routingDataStale,
      "ROUTING_IDENTITY_FAILURE" => JourneyErrorSemanticCategory.routingIdentityFailure,
      "SERVICE_UNAVAILABLE" => JourneyErrorSemanticCategory.serviceUnavailable,
      "SEARCH_TIMEOUT" => JourneyErrorSemanticCategory.searchTimeout,
      "SESSION_AUTHENTICATION" => JourneyErrorSemanticCategory.sessionAuthentication,
      "RATE_LIMIT" => JourneyErrorSemanticCategory.rateLimit,
      _ => throw const FormatException('unrecognized wire value'),
    };
  }
}

enum JourneyErrorActionKey { journeyActionEditRequest, journeyActionReselectStation, journeyActionEditAccessibility, journeyActionNewSearch, journeyActionReauthenticate }

extension JourneyErrorActionKeyWire on JourneyErrorActionKey {
  String get wire => switch (this) {
    JourneyErrorActionKey.journeyActionEditRequest => "journey.action.editRequest",
    JourneyErrorActionKey.journeyActionReselectStation => "journey.action.reselectStation",
    JourneyErrorActionKey.journeyActionEditAccessibility => "journey.action.editAccessibility",
    JourneyErrorActionKey.journeyActionNewSearch => "journey.action.newSearch",
    JourneyErrorActionKey.journeyActionReauthenticate => "journey.action.reauthenticate",
  };
  static JourneyErrorActionKey fromWire(Object? value) {
    if (value is! String) throw const FormatException('wire value must be string');
    return switch (value) {
      "journey.action.editRequest" => JourneyErrorActionKey.journeyActionEditRequest,
      "journey.action.reselectStation" => JourneyErrorActionKey.journeyActionReselectStation,
      "journey.action.editAccessibility" => JourneyErrorActionKey.journeyActionEditAccessibility,
      "journey.action.newSearch" => JourneyErrorActionKey.journeyActionNewSearch,
      "journey.action.reauthenticate" => JourneyErrorActionKey.journeyActionReauthenticate,
      _ => throw const FormatException('unrecognized wire value'),
    };
  }
}

enum TimePolicy { timetableRequired, realtimeRequired }

extension TimePolicyWire on TimePolicy {
  String get wire => switch (this) {
    TimePolicy.timetableRequired => "TIMETABLE_REQUIRED",
    TimePolicy.realtimeRequired => "REALTIME_REQUIRED",
  };
  static TimePolicy fromWire(Object? value) {
    if (value is! String) throw const FormatException('wire value must be string');
    return switch (value) {
      "TIMETABLE_REQUIRED" => TimePolicy.timetableRequired,
      "REALTIME_REQUIRED" => TimePolicy.realtimeRequired,
      _ => throw const FormatException('unrecognized wire value'),
    };
  }
}

enum WalkingPace { slow, standard, fast }

extension WalkingPaceWire on WalkingPace {
  String get wire => switch (this) {
    WalkingPace.slow => "SLOW",
    WalkingPace.standard => "STANDARD",
    WalkingPace.fast => "FAST",
  };
  static WalkingPace fromWire(Object? value) {
    if (value is! String) throw const FormatException('wire value must be string');
    return switch (value) {
      "SLOW" => WalkingPace.slow,
      "STANDARD" => WalkingPace.standard,
      "FAST" => WalkingPace.fast,
      _ => throw const FormatException('unrecognized wire value'),
    };
  }
}

enum MobilityProfile { standard, slow, noStairs, stepFree }

extension MobilityProfileWire on MobilityProfile {
  String get wire => switch (this) {
    MobilityProfile.standard => "STANDARD",
    MobilityProfile.slow => "SLOW",
    MobilityProfile.noStairs => "NO_STAIRS",
    MobilityProfile.stepFree => "STEP_FREE",
  };
  static MobilityProfile fromWire(Object? value) {
    if (value is! String) throw const FormatException('wire value must be string');
    return switch (value) {
      "STANDARD" => MobilityProfile.standard,
      "SLOW" => MobilityProfile.slow,
      "NO_STAIRS" => MobilityProfile.noStairs,
      "STEP_FREE" => MobilityProfile.stepFree,
      _ => throw const FormatException('unrecognized wire value'),
    };
  }
}

enum ConstraintMode { none, requireStepFree }

extension ConstraintModeWire on ConstraintMode {
  String get wire => switch (this) {
    ConstraintMode.none => "NONE",
    ConstraintMode.requireStepFree => "REQUIRE_STEP_FREE",
  };
  static ConstraintMode fromWire(Object? value) {
    if (value is! String) throw const FormatException('wire value must be string');
    return switch (value) {
      "NONE" => ConstraintMode.none,
      "REQUIRE_STEP_FREE" => ConstraintMode.requireStepFree,
      _ => throw const FormatException('unrecognized wire value'),
    };
  }
}

enum JourneyErrorCode {
  invalidJourneyRequest,
  stationNotFound,
  routeNotFound,
  accessibilityConstraintUnsatisfied,
  routingBundleUnavailable,
  routingBundleStale,
  timetableUnavailable,
  timetableStale,
  realtimeRequiredUnavailable,
  routingIdentityMismatch,
  routeServiceUnavailable,
  journeySearchTimeout,
  stationLineNotFound,
  timetableNotCovered,
  timetableIdentityMismatch,
  routeSessionRequired,
  routeRateLimited,
  invalidJourneySessionRequest,
  routeSessionAttestationRejected,
  routeSessionAttestationUnavailable,
}

extension JourneyErrorCodeWire on JourneyErrorCode {
  String get wire => switch (this) {
    JourneyErrorCode.invalidJourneyRequest => "INVALID_JOURNEY_REQUEST",
    JourneyErrorCode.stationNotFound => "STATION_NOT_FOUND",
    JourneyErrorCode.routeNotFound => "ROUTE_NOT_FOUND",
    JourneyErrorCode.accessibilityConstraintUnsatisfied => "ACCESSIBILITY_CONSTRAINT_UNSATISFIED",
    JourneyErrorCode.routingBundleUnavailable => "ROUTING_BUNDLE_UNAVAILABLE",
    JourneyErrorCode.routingBundleStale => "ROUTING_BUNDLE_STALE",
    JourneyErrorCode.timetableUnavailable => "TIMETABLE_UNAVAILABLE",
    JourneyErrorCode.timetableStale => "TIMETABLE_STALE",
    JourneyErrorCode.realtimeRequiredUnavailable => "REALTIME_REQUIRED_UNAVAILABLE",
    JourneyErrorCode.routingIdentityMismatch => "ROUTING_IDENTITY_MISMATCH",
    JourneyErrorCode.routeServiceUnavailable => "ROUTE_SERVICE_UNAVAILABLE",
    JourneyErrorCode.journeySearchTimeout => "JOURNEY_SEARCH_TIMEOUT",
    JourneyErrorCode.stationLineNotFound => "STATION_LINE_NOT_FOUND",
    JourneyErrorCode.timetableNotCovered => "TIMETABLE_NOT_COVERED",
    JourneyErrorCode.timetableIdentityMismatch => "TIMETABLE_IDENTITY_MISMATCH",
    JourneyErrorCode.routeSessionRequired => "ROUTE_SESSION_REQUIRED",
    JourneyErrorCode.routeRateLimited => "ROUTE_RATE_LIMITED",
    JourneyErrorCode.invalidJourneySessionRequest => "INVALID_JOURNEY_SESSION_REQUEST",
    JourneyErrorCode.routeSessionAttestationRejected => "ROUTE_SESSION_ATTESTATION_REJECTED",
    JourneyErrorCode.routeSessionAttestationUnavailable => "ROUTE_SESSION_ATTESTATION_UNAVAILABLE",
  };
  static JourneyErrorCode fromWire(Object? value) {
    if (value is! String) throw const FormatException('wire value must be string');
    return switch (value) {
      "INVALID_JOURNEY_REQUEST" => JourneyErrorCode.invalidJourneyRequest,
      "STATION_NOT_FOUND" => JourneyErrorCode.stationNotFound,
      "ROUTE_NOT_FOUND" => JourneyErrorCode.routeNotFound,
      "ACCESSIBILITY_CONSTRAINT_UNSATISFIED" => JourneyErrorCode.accessibilityConstraintUnsatisfied,
      "ROUTING_BUNDLE_UNAVAILABLE" => JourneyErrorCode.routingBundleUnavailable,
      "ROUTING_BUNDLE_STALE" => JourneyErrorCode.routingBundleStale,
      "TIMETABLE_UNAVAILABLE" => JourneyErrorCode.timetableUnavailable,
      "TIMETABLE_STALE" => JourneyErrorCode.timetableStale,
      "REALTIME_REQUIRED_UNAVAILABLE" => JourneyErrorCode.realtimeRequiredUnavailable,
      "ROUTING_IDENTITY_MISMATCH" => JourneyErrorCode.routingIdentityMismatch,
      "ROUTE_SERVICE_UNAVAILABLE" => JourneyErrorCode.routeServiceUnavailable,
      "JOURNEY_SEARCH_TIMEOUT" => JourneyErrorCode.journeySearchTimeout,
      "STATION_LINE_NOT_FOUND" => JourneyErrorCode.stationLineNotFound,
      "TIMETABLE_NOT_COVERED" => JourneyErrorCode.timetableNotCovered,
      "TIMETABLE_IDENTITY_MISMATCH" => JourneyErrorCode.timetableIdentityMismatch,
      "ROUTE_SESSION_REQUIRED" => JourneyErrorCode.routeSessionRequired,
      "ROUTE_RATE_LIMITED" => JourneyErrorCode.routeRateLimited,
      "INVALID_JOURNEY_SESSION_REQUEST" => JourneyErrorCode.invalidJourneySessionRequest,
      "ROUTE_SESSION_ATTESTATION_REJECTED" => JourneyErrorCode.routeSessionAttestationRejected,
      "ROUTE_SESSION_ATTESTATION_UNAVAILABLE" => JourneyErrorCode.routeSessionAttestationUnavailable,
      _ => throw const FormatException('unrecognized wire value'),
    };
  }
}
