class NetworkMapStationTapScore
    implements Comparable<NetworkMapStationTapScore> {
  const NetworkMapStationTapScore({
    required this.containsNode,
    required this.containsShape,
    required this.screenDistance,
    required this.stableKey,
  });

  final bool containsNode;
  final bool containsShape;
  final double screenDistance;
  final String stableKey;

  @override
  int compareTo(NetworkMapStationTapScore other) {
    final nodeComparison = _scoreBool(
      containsNode,
    ).compareTo(_scoreBool(other.containsNode));
    if (nodeComparison != 0) {
      return nodeComparison;
    }
    final containsComparison = _scoreBool(
      containsShape,
    ).compareTo(_scoreBool(other.containsShape));
    if (containsComparison != 0) {
      return containsComparison;
    }
    final distanceComparison = screenDistance.compareTo(other.screenDistance);
    if (distanceComparison != 0) {
      return distanceComparison;
    }
    return stableKey.compareTo(other.stableKey);
  }

  static int _scoreBool(bool value) => value ? 0 : 1;
}
