class NetworkMapNearbyRealtimeDisplay<T> {
  const NetworkMapNearbyRealtimeDisplay({
    required this.stationId,
    required this.lineId,
    required this.snapshot,
  });

  final String stationId;
  final String lineId;
  final T snapshot;
}

class NetworkMapNearbyTimetableDisplay<T> {
  const NetworkMapNearbyTimetableDisplay({
    required this.stationId,
    required this.lineId,
    required this.timetable,
  });

  final String stationId;
  final String lineId;
  final T timetable;
}
