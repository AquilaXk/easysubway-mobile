enum NetworkMapNearbyPanelStatus { idle, loading, success }

enum NetworkMapNearbyPanelDataSource { realtime, timetable }

class NetworkMapNearbyPanelData<T> {
  const NetworkMapNearbyPanelData._({
    required this.status,
    this.results = const [],
  });

  const NetworkMapNearbyPanelData.idle()
    : this._(status: NetworkMapNearbyPanelStatus.idle);

  const NetworkMapNearbyPanelData.loading()
    : this._(status: NetworkMapNearbyPanelStatus.loading);

  const NetworkMapNearbyPanelData.success(List<T> results)
    : this._(status: NetworkMapNearbyPanelStatus.success, results: results);

  final NetworkMapNearbyPanelStatus status;
  final List<T> results;
}
