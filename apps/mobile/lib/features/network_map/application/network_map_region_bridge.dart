/// 홈 노선도 지역을 역 검색 화면 등 외부에서 바꿀 때 쓰는 브리지.
///
/// Network Map 화면이 attach한 뒤 [selectRegion]으로 지도 지역을 전환한다.
/// 역 검색에서 지역을 바꾸면 홈 노선도도 같은 지역으로 맞춘다.
class NetworkMapRegionBridge {
  void Function(String region)? _apply;

  void attach(void Function(String region) apply) {
    _apply = apply;
  }

  void detach() {
    _apply = null;
  }

  void selectRegion(String region) {
    _apply?.call(region);
  }
}
