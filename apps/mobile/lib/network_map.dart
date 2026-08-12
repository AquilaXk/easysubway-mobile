import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;

import 'accessible_design.dart';
import 'ad_slot.dart';
import 'design_tokens.dart';
import 'facility_report.dart';
import 'features/ads/ad_repository.dart';
import 'features/facility_report/domain/facility_report_target.dart';
import 'features/network_map/application/network_map_load_result.dart';
import 'features/network_map/application/nearby_panel_request_key.dart';
import 'features/network_map/application/network_map_region_bridge.dart';
import 'features/network_map/data/network_map_attribution_cache.dart';
import 'features/network_map/data/network_map_owner_labels_cache.dart';
import 'features/network_map/domain/map_camera.dart';
import 'features/network_map/domain/nearby_adjacent_stations.dart';
import 'features/network_map/domain/network_map_edge_topology.dart';
import 'features/network_map/domain/network_map_models.dart';
import 'features/network_map/domain/network_map_station_selection.dart';
import 'features/network_map/domain/route_map_design_space.dart';
import 'features/network_map/domain/route_map_label_polygon.dart';
import 'features/network_map/domain/route_map_min_scale.dart';
import 'features/network_map/domain/route_map_owner_labels.dart';
import 'features/network_map/domain/structured_route_map.dart';
import 'features/network_map/infrastructure/cached_route_map_path.dart';
import 'features/network_map/presentation/nearby_arrival_panel.dart';
import 'features/network_map/presentation/nearby_data_source_toggle.dart';
import 'features/network_map/presentation/nearby_station_line_bar.dart';
import 'features/network_map/presentation/nearby_timetable_panel.dart';
import 'features/network_map/presentation/network_map_camera_policy.dart';
import 'features/network_map/presentation/network_map_chrome_controls.dart';
import 'features/network_map/presentation/network_map_menu_panel.dart';
import 'features/network_map/presentation/network_map_unavailable_states.dart';
import 'features/network_map/presentation/region_menu.dart';
import 'features/network_map/presentation/route_map_owner_label_bounds.dart';
import 'features/network_map/presentation/station_fan_menu.dart';
import 'features/network_map/presentation/station_fan_menu_policy.dart';
import 'features/network_map/presentation/station_hit_target.dart';
import 'features/network_map/presentation/route_map_basemap_view.dart';
import 'features/network_map/presentation/structured_route_map_painter.dart';
import 'features/realtime/realtime_repository.dart';
import 'features/route_draft/application/route_draft_controller.dart';
import 'features/route_draft/domain/route_draft.dart';
import 'features/stations/presentation/service_pattern_badge.dart';
import 'features/stations/presentation/station_detail_body.dart';
import 'features/stations/presentation/station_detail_screen.dart';
import 'features/stations/presentation/station_line_badges.dart';
import 'internal_route.dart';
import 'mobile_error_reporter.dart';
import 'search_field.dart';
import 'station_search.dart';

const _networkMapTopBarHeight = easySubwayTopBarContentHeight;

class NetworkMapScreen extends StatefulWidget {
  const NetworkMapScreen({
    required this.repository,
    required this.routeDraftController,
    required this.onOpenStationSearch,
    this.onStationSearchClosed,
    this.onPickStationForSlot,
    this.stationSearchRepository,
    this.reportRepository,
    this.favoriteRepository,
    this.adRepository,
    this.searchHistoryRepository,
    this.facilityReportDraftTargetStore,
    this.internalRouteRepository,
    this.internalRouteMobilityType = 'SENIOR',
    this.locationProvider,
    this.viewportRepository,
    this.realtimeRepository,
    this.onOpenSavedItems,
    this.onOpenTrainSearch,
    this.onOpenSettings,
    this.onOpenServiceNotices,
    this.notificationAction,
    this.disruptionBanner,
    this.bottomNavigationBar,
    this.focusStationRequest,
    this.focusStationRequestId,
    this.onFocusStationRequestHandled,
    this.regionBridge,
    this.onRegionLabelChanged,
    super.key,
  });

  final NetworkMapRepository repository;
  final RouteDraftController routeDraftController;

  /// 역 검색 등 외부에서 노선도 지역을 바꿀 때 연결한다.
  final NetworkMapRegionBridge? regionBridge;

  /// 역 검색을 열 때 현재 선택 지역 표시명(예: '수도권', '부산')과, 이 지도가
  /// 아는 지역 표시명 전체 목록을 함께 전달한다. #2090에서 검색 화면에 지역
  /// 표시가 추가됐는데 호출부가 이를 안 넘겨 기본값 '수도권'이 고정 표시되던
  /// 결함을 고치려 파라미터 없는 VoidCallback에서 `ValueChanged<String>`으로
  /// 바꿨고, 리뷰 finding(#2419)로 지역 목록도 함께 넘기도록 다시 확장했다 —
  /// 맵에만 있는 지역이 검색 화면 지역 메뉴 기본 목록에 없으면 누락됐다.
  final void Function(String regionLabel, List<String> availableRegions)
  onOpenStationSearch;

  /// #1933 홈 in-place 역 검색 모드를 빠져나올 때(← 또는 시스템 back) 호출된다.
  /// 셸이 알림/신고 상태를 다시 불러오도록 하기 위한 훅이다. 라우트 기반 검색이
  /// 반환 후 하던 refreshHomeState와 같은 역할을 in-place 종료에도 유지한다.
  final VoidCallback? onStationSearchClosed;

  /// 상단 draft 오버레이의 출발/도착 칸을 탭했을 때, 그 칸을 채우려고 기존 역 검색을
  /// 여는 콜백. 지도 탭과 같은 [routeDraftController]로 수렴한다. null이면 오버레이
  /// 칸은 탭할 수 없다(둘러보기 검색만 메뉴로 제공). 두 번째 인자는 현재 선택 지역
  /// 표시명(#2090 검색 화면 지역 표시 배선), 세 번째 인자는 이 지도가 아는 지역
  /// 표시명 전체 목록(#2419 리뷰 finding).
  final void Function(
    RouteDraftSlot slot,
    String regionLabel,
    List<String> availableRegions,
  )?
  onPickStationForSlot;
  final StationSearchRepository? stationSearchRepository;

  /// #1933 홈 노선도 위에서 역 검색을 in-place로 열 때, 결과 탭 → 역 상세로
  /// 이동하려면 필요한 저장소들. 검색 모드는 [stationSearchRepository]가 있을 때만
  /// 진입 가능하다.
  final FacilityReportRepository? reportRepository;
  final FavoriteStationRepository? favoriteRepository;

  final AdRepository? adRepository;
  final SearchHistoryRepository? searchHistoryRepository;
  final FacilityReportDraftTargetStore? facilityReportDraftTargetStore;
  final InternalRouteRepository? internalRouteRepository;
  final String internalRouteMobilityType;
  final CurrentLocationProvider? locationProvider;
  final NetworkMapViewportRepository? viewportRepository;
  final RealtimeRepository? realtimeRepository;
  final VoidCallback? onOpenSavedItems;
  final VoidCallback? onOpenTrainSearch;
  final VoidCallback? onOpenSettings;

  /// 좌측 메뉴 "운행 공지" 목록 화면 열기.
  final VoidCallback? onOpenServiceNotices;
  final Widget? notificationAction;

  /// 상단 disruption 공지 1줄 배너. 표시할 공지가 없으면 스스로 빈 위젯이 된다.
  final Widget? disruptionBanner;
  final Widget? bottomNavigationBar;

  /// 풀페이지 검색 결과를 노선도에 전달하는 채널. 역 ID뿐 아니라 노선 정보를
  /// 보존해 팬 메뉴와 해당 역 하단 정보 패널을 함께 갱신한다.
  final StationSearchResult? focusStationRequest;

  /// #2109 풀페이지 검색(햄버거 메뉴 경유) 결과 탭으로 반환된 역 id. 설정되면
  /// 노선도가 그 역으로 카메라를 이동하고 팬 메뉴를 띄운다. 임베디드 검색의
  /// _searchFanMenuStationId와 같은 메커니즘을 재사용한다.
  final String? focusStationRequestId;

  /// [focusStationRequestId]를 소비했음을 부모에게 알린다(같은 id로 재요청되지
  /// 않도록 부모가 필드를 비우게 한다).
  final VoidCallback? onFocusStationRequestHandled;

  /// #2419 Fix: 노선도 지역이 로드·전환될 때 현재 지역 표시명을 부모(홈)에
  /// 알린다. 노선 탭(길찾기 draft 자동검색)이 draft 역의 지역 폴백으로 쓴다.
  final ValueChanged<String>? onRegionLabelChanged;

  @override
  State<NetworkMapScreen> createState() => _NetworkMapScreenState();
}

class _NetworkMapScreenState extends State<NetworkMapScreen> {
  String? _selectedRegion;
  // #2419 리뷰 finding: 역 검색 메뉴가 항상 기본 지역 목록만 알아, 이 지도에만
  // 있는 지역이 검색 화면 지역 메뉴에서 빠졌다. 로드된 지도의 지역 표시명을
  // 캐싱해 검색을 열 때 함께 넘긴다.
  List<String> _availableRegionLabels = const ['수도권'];
  bool _nearbyPanelVisible = false;
  bool _nearbyPanelExpanded = false;
  _NetworkMapNearbyPanelData _nearbyPanelData =
      const _NetworkMapNearbyPanelData.idle();
  String? _nearbySelectedStationId;
  String? _nearbySelectedLineId;
  // #2109: 인플레이스 검색 결과 탭으로 연 팬 메뉴의 대상 역 id. 캔버스의
  // selectedStationId(팬 메뉴)와 focusedStationId(카메라 이동)에 함께 실린다.
  String? _searchFanMenuStationId;
  bool _preserveFocusedStationScale = false;
  String? _nearbyLookupMessage;
  Timer? _nearbyLookupMessageTimer;
  bool _initialNearbyFocusStarted = false;
  int _selectionClearRevision = 0;
  int _nearestStationRequestToken = 0;

  /// 하단 패널 데이터 요청 generation. 역·호선과 함께 [NearbyPanelRequestKey]로
  /// 늦은 응답을 걸러 낸다(#2453 Task 3).
  int _nearbyDataRequestToken = 0;
  // #2200: 캔버스 역 탭 → StationSearchResult 해석은 비동기라 연속 탭 시 마지막
  // 탭만 패널에 반영되도록 토큰으로 앞선 요청을 무효화한다.
  int _canvasTapPanelToken = 0;

  /// #2436: 인접 역 탭 해석도 비동기라 연타·닫기 후 늦은 응답을 토큰으로 버린다.
  int _neighborSelectPanelToken = 0;

  /// 성공한 실시간만 stationId+lineId 키로 보관. unavailable/loading/empty로 덮지 않는다.
  _NearbyRealtimeDisplay? _nearbyRealtimeDisplay;

  /// 성공한 시간표만 stationId+lineId 키로 보관. 실패로 성공 캐시를 지우지 않는다.
  _NearbyTimetableDisplay? _nearbyTimetableDisplay;
  _NearbyPanelDataSource _nearbyDataSource = _NearbyPanelDataSource.realtime;

  /// 요청 중복 방지용 in-flight. UI 렌더 분기에는 쓰지 않는다(#2453).
  /// 채널별 generation을 함께 두어, stale 완료도 자기 generation의 플래그만 내린다
  /// (토글이 한쪽만 재조회해도 반대 채널이 고아 in-flight로 남지 않게).
  bool _nearbyRealtimeRequestInFlight = false;
  bool _nearbyTimetableRequestInFlight = false;
  int? _nearbyRealtimeInFlightGeneration;
  int? _nearbyTimetableInFlightGeneration;

  void _markNearbyRealtimeInFlight(NearbyPanelRequestKey request) {
    _nearbyRealtimeRequestInFlight = true;
    _nearbyRealtimeInFlightGeneration = request.generation;
  }

  void _markNearbyTimetableInFlight(NearbyPanelRequestKey request) {
    _nearbyTimetableRequestInFlight = true;
    _nearbyTimetableInFlightGeneration = request.generation;
  }

  void _clearNearbyRealtimeInFlightIf(NearbyPanelRequestKey request) {
    if (_nearbyRealtimeInFlightGeneration != request.generation) {
      return;
    }
    _nearbyRealtimeRequestInFlight = false;
    _nearbyRealtimeInFlightGeneration = null;
  }

  void _clearNearbyTimetableInFlightIf(NearbyPanelRequestKey request) {
    if (_nearbyTimetableInFlightGeneration != request.generation) {
      return;
    }
    _nearbyTimetableRequestInFlight = false;
    _nearbyTimetableInFlightGeneration = null;
  }

  /// 하단 패널 실시간은 API 기본 8초보다 짧게 끊고 시간표로 넘긴다.
  static const _nearbyRealtimeTimeout = Duration(seconds: 2);
  int _mapLoadGeneration = 0;
  late Future<NetworkMapLoadResult> _future = _startMapLoad();

  /// 지도 탭 → draft 슬롯 지정 시 역의 [NetworkMapStation.lineId]로 노선
  /// 이름·색을 채우기 위해 마지막으로 로드된 맵 데이터를 캐시한다.
  NetworkMapData? _latestMapData;

  // #1933/#1915 홈 노선도 위 in-place 역 검색 모드. 모드 플래그만 이 화면에
  // 남는다. 검색 컨트롤러·디바운스·최근 검색어·결과 본문 등 키 입력마다 바뀌는
  // 상태는 [_NetworkMapSearchSession]으로 격리해 타이핑이 지도 canvas/chrome을
  // 재빌드하지 않게 한다.
  bool _searchMode = false;

  /// 상단바 편집 필드는 이 화면이 소유하는 컨트롤러/포커스로 그린다(키 입력은
  /// setState를 일으키지 않고 필드가 컨트롤러를 직접 구독해 갱신된다). 검색
  /// 로직은 세션이 소유하므로, 필드 제출은 이 키로 세션에 위임한다.
  final TextEditingController _searchQueryController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final GlobalKey<_NetworkMapSearchSessionState> _searchSessionKey =
      GlobalKey<_NetworkMapSearchSessionState>();

  @override
  void initState() {
    super.initState();
    widget.routeDraftController.addListener(_handleDraftChangedForSearch);
    widget.regionBridge?.attach(_selectRegionFromBridge);
    // #2068 트랙 QA 후속: 오너 라벨 sidecar를 노선도 데이터 로드(_future)와
    // **동시에** 시작한다. 종전에는 캔버스가 마운트된 뒤에야(=데이터 로드 완료
    // 후) 로드가 시작돼 직렬화됐고, 초기 카메라 가독 배율이 sidecar에 의존하게
    // 된 지금은 그 지연이 그대로 줌 팝으로 보인다. 데이터 로드가 끝날 때쯤 값이
    // 준비돼 캔버스 첫 build가 동기 캐시로 이를 집어간다.
    //
    // [cold start 성질 — 정확히] 이 호출은 **대기 게이트가 아니다**(unawaited라
    // _future를 막지 않는다). 다만 노선도는 홈 기본 탭이라 이 선행 로드가 앱 시작
    // 직후 걸리므로, "cold start 경로에 아무 영향이 없다"는 뜻은 아니다 — 정확한
    // 성질은 "UI isolate 작업을 늘리지 않는다"이며, 그 근거는
    // [loadNetworkMapOwnerLabelsByRegion]이 디코드·파싱 전체를 compute 워커로
    // 넘기기 때문이다(그 함수 주석의 리뷰 finding 참고). UI isolate에는 asset
    // 바이트 읽기와 결과 대입만 남는다.
    //
    // 실패는 캔버스의 _loadOwnerLabels가 리포팅·재시도를 담당하므로 여기서는
    // 삼킨다(중복 리포트 방지).
    unawaited(
      loadNetworkMapOwnerLabelsByRegion().catchError(
        (Object _, StackTrace _) =>
            const <String, Map<String, List<RouteMapOwnerLabelEntry>>>{},
      ),
    );
  }

  void _selectRegionFromBridge(String region) {
    if (!mounted) {
      return;
    }
    // 출발·도착·경유 중 하나라도 있으면 경로 지역을 고정한다.
    if (!widget.routeDraftController.draft.isEmpty) {
      return;
    }
    final next = region.trim();
    if (next.isEmpty) {
      return;
    }
    // 이미 같은 표시 지역이면 불필요한 지도 재로드를 피한다.
    if (_displayRegionName(next) == _displayRegionName(_selectedRegion ?? '')) {
      return;
    }
    _reload(region: next);
  }

  /// #2109 Fix: 풀페이지 검색(햄버거 메뉴 경유) 결과 탭으로 반환된
  /// [NetworkMapScreen.focusStationRequestId]를 인플레이스 검색과 같은 팬 메뉴
  /// 채널(_searchFanMenuStationId)로 수렴시킨다. 부모([onFocusStationRequestHandled])의
  /// setState를 이 build 사이클 안에서 직접 호출하면 "build 중 setState" 예외가
  /// 나므로(부모가 이 위젯을 빌드하는 도중 didUpdateWidget이 실행됨), 다음
  /// 프레임으로 미룬다.
  @override
  void didUpdateWidget(covariant NetworkMapScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.regionBridge != widget.regionBridge) {
      oldWidget.regionBridge?.detach();
      widget.regionBridge?.attach(_selectRegionFromBridge);
    }
    final request = widget.focusStationRequest;
    if (request != null && request != oldWidget.focusStationRequest) {
      _openNearbyStationPanel(request);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.onFocusStationRequestHandled?.call();
      });
      return;
    }
    final requestId = widget.focusStationRequestId;
    if (requestId != null && requestId != oldWidget.focusStationRequestId) {
      setState(() {
        _searchFanMenuStationId = requestId;
        // #2109 Fix: 풀페이지 검색으로 팬 메뉴를 여는데 하단 주변 역 패널이 열려
        // 있던 상태(현재 위치 버튼 → 패널 → 햄버거 검색 → 결과 탭 경로)면 팬 메뉴와
        // 패널이 동시에 뜨고 bottomNavigationBar도 계속 억제된다. 팬 메뉴로
        // 수렴하므로 주변 역 패널을 함께 닫아 상호배제한다.
        _resetNearbyPanelState();
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.onFocusStationRequestHandled?.call();
      });
    }
  }

  /// 검색 모드 중 draft가 채워지면(출발/도착 설정 등) OD 상단바가 이겨야 하므로
  /// 검색 모드를 자동 종료한다(co-existence). draft 변경은 키 입력이 아니므로
  /// 이 리스너는 이 화면에 남아도 입력 지연에 영향을 주지 않는다.
  void _handleDraftChangedForSearch() {
    if (_searchMode && !widget.routeDraftController.draft.isEmpty) {
      _exitSearchMode();
    }
  }

  void _enterSearchMode() {
    final repository = widget.stationSearchRepository;
    if (repository == null) {
      return;
    }
    if (!widget.routeDraftController.draft.isEmpty) {
      return;
    }
    // 첫 글자 전에 카탈로그 인덱스를 올려 입력 체감 지연을 줄인다.
    unawaited(warmStationSearchCacheIfSupported(repository));
    setState(() => _searchMode = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _searchMode) {
        FocusScope.of(context).requestFocus(_searchFocusNode);
      }
    });
  }

  void _exitSearchMode() {
    _searchQueryController.clear();
    if (mounted) {
      setState(() => _searchMode = false);
    } else {
      _searchMode = false;
    }
    widget.onStationSearchClosed?.call();
  }

  /// #2109 일반(비픽) 모드의 인플레이스 검색 결과 탭: 검색을 닫고 해당 역으로
  /// 카메라를 이동한 뒤 부채꼴 팬 메뉴와 해당 역 하단 정보 패널을 띄운다.
  void _focusStationFromSearch(
    StationSearchResult result,
    StationSearchLine? line,
  ) {
    // 결과에서 고른 호선만 최근 검색에 남긴다(환승역 전 호선 마크 방지).
    unawaited(_recordSelectedStationSearch(result, line));
    // _exitSearchMode 가 이미 setState 로 검색을 닫으므로, 선택 역 상태는 그 뒤
    // 별도 setState 로 세팅해 검색 종료에 덮이지 않도록 한다.
    _exitSearchMode();
    if (!mounted) {
      return;
    }
    _openNearbyStationPanel(result, preferredLine: line);
  }

  Future<void> _recordSelectedStationSearch(
    StationSearchResult result,
    StationSearchLine? line,
  ) async {
    final repository = widget.searchHistoryRepository;
    if (repository == null) {
      return;
    }
    final selected = line ?? result.lines.firstOrNull;
    try {
      await repository.recordSearch(
        result.nameKo,
        region: _displayRegionName(_selectedRegion ?? result.region),
        stationId: result.id,
        line: selected,
      );
    } catch (error, stackTrace) {
      reportMobileError(error, stackTrace, context: '최근 검색 저장 중 예외가 발생했습니다.');
    }
  }

  /// 검색·GPS·캔버스(신원 해석 후) 공통 오픈. 패널을 즉시 표시하고
  /// 실시간/시간표 조회는 백그라운드에서만 시작한다(표시 전 await 금지).
  void _openNearbyStationPanel(
    StationSearchResult station, {
    StationSearchLine? preferredLine,
    bool preserveFocusedStationScale = false,
  }) {
    // 인접 역 해석 중 다른 경로로 패널이 열리면 늦은 neighbor 응답을 버린다.
    _neighborSelectPanelToken++;
    final selectedLine = preferredLine ?? station.lines.firstOrNull;
    // generation을 먼저 올려 이전 요청을 무효화한 뒤 패널을 연다.
    final generation = ++_nearbyDataRequestToken;
    final request = selectedLine == null
        ? null
        : NearbyPanelRequestKey(
            stationId: station.id,
            lineId: selectedLine.id,
            generation: generation,
          );
    setState(() {
      _nearestStationRequestToken++;
      _selectionClearRevision++;
      _nearbyPanelVisible = true;
      _nearbySelectedStationId = station.id;
      _nearbySelectedLineId = selectedLine?.id;
      _nearbyPanelData = _NetworkMapNearbyPanelData.success([station]);
      // 모든 오픈 경로 기본 탭은 시간표. 실시간은 백그라운드 prefetch.
      // keyed display는 지우지 않는다 — 키 불일치면 미표시, 일치하면 즉시 재사용.
      _nearbyDataSource = _NearbyPanelDataSource.timetable;
      if (request != null) {
        _markNearbyRealtimeInFlight(request);
        _markNearbyTimetableInFlight(request);
      } else {
        _nearbyRealtimeRequestInFlight = false;
        _nearbyTimetableRequestInFlight = false;
        _nearbyRealtimeInFlightGeneration = null;
        _nearbyTimetableInFlightGeneration = null;
      }
      _searchFanMenuStationId = station.id;
      _preserveFocusedStationScale = preserveFocusedStationScale;
    });
    if (request != null && selectedLine != null) {
      _startNearbyPanelDataLoads(station, selectedLine, request);
    }
  }

  /// 현재 패널에 반영해도 되는 최신 요청인지 검사한다.
  /// `mounted`만으로 setState 하지 않도록 완료 경로에서 반드시 호출한다.
  bool _isCurrentNearbyRequest(NearbyPanelRequestKey request) {
    return mounted &&
        _nearbyPanelVisible &&
        request.matches(
          stationId: _nearbySelectedStationId,
          lineId: _nearbySelectedLineId,
          generation: _nearbyDataRequestToken,
        );
  }

  bool _nearbyRealtimeDisplayMatchesCurrent() {
    final display = _nearbyRealtimeDisplay;
    return display != null &&
        display.stationId == _nearbySelectedStationId &&
        display.lineId == _nearbySelectedLineId;
  }

  bool _nearbyTimetableDisplayMatchesCurrent() {
    final display = _nearbyTimetableDisplay;
    return display != null &&
        display.stationId == _nearbySelectedStationId &&
        display.lineId == _nearbySelectedLineId;
  }

  /// 현재 역·호선 키와 맞는 성공 캐시만 넘긴다. 없으면 loading → 방면 골격.
  RealtimeSnapshot get _nearbyRealtimeForDisplay {
    final display = _nearbyRealtimeDisplay;
    if (display != null &&
        display.stationId == _nearbySelectedStationId &&
        display.lineId == _nearbySelectedLineId) {
      return display.snapshot;
    }
    return const RealtimeSnapshot.loading();
  }

  StationTimetable? get _nearbyTimetableForDisplay {
    final display = _nearbyTimetableDisplay;
    if (display != null &&
        display.stationId == _nearbySelectedStationId &&
        display.lineId == _nearbySelectedLineId) {
      return display.timetable;
    }
    return null;
  }

  /// #2200 캔버스에서 역을 탭하면(팬 메뉴는 canvas가 이미 띄운다) 그 역을
  /// 검색과 동일한 방식([StationSearchRepository.searchStations])으로
  /// [StationSearchResult]로 해석해 [_openNearbyStationPanel]로 하단 역 정보
  /// 패널을 연다. 해석에 실패하면(저장소 없음·데이터 없음) 패널을 열지 않고
  /// canvas가 띄운 팬 메뉴만 유지한다. 신원 해석 await는 허용되며, 해석 후
  /// 데이터 로드는 fire-and-forget이다.
  Future<void> _handleCanvasStationTapped(NetworkMapStation station) async {
    final repository = widget.stationSearchRepository;
    if (repository == null) {
      return;
    }
    final token = ++_canvasTapPanelToken;
    List<StationSearchResult> results;
    try {
      results = await repository.searchStations(station.nameKo);
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '노선도 역 탭 패널 해석 중 예외가 발생했습니다.',
      );
      // 해석 실패 → 팬 메뉴만 유지(패널 없음).
      return;
    }
    if (!mounted || token != _canvasTapPanelToken) {
      return;
    }
    final match = results
        .where((result) => result.id == station.id)
        .firstOrNull;
    if (match == null) {
      // 데이터 없음 → 팬 메뉴만 유지(크래시·빈 패널 금지).
      return;
    }
    final preferredLine = match.lines
        .where((line) => line.id == station.lineId)
        .firstOrNull;
    _openNearbyStationPanel(match, preferredLine: preferredLine);
  }

  /// #2109 검색 결과 탭으로 연 팬 메뉴가 닫히면(액션 선택·닫기·배경 탭·팬) 이
  /// 화면이 들고 있는 대상 역 id도 비운다. 그러지 않으면 canvas의
  /// selectedStationId prop이 계속 팬 메뉴를 다시 띄운다.
  void _dismissSearchFanMenu() {
    if (_searchFanMenuStationId == null) {
      return;
    }
    setState(() => _searchFanMenuStationId = null);
  }

  /// 상단바 편집 필드의 제출(엔터/검색 액션)을 검색 세션으로 위임한다.
  void _submitSearch(String query) {
    _searchSessionKey.currentState?.submitSearch(query);
  }

  /// 검색 모드일 때만 세션을 만든다. 세션이 검색 상태를 소유하므로 모드 진입
  /// 시 mount·모드 이탈 시 unmount되며, 세션의 initState가 최근 검색어 로드와
  /// 디바운스 구독을 처리한다.
  Widget? _buildSearchBody() {
    if (!_searchMode) {
      return null;
    }
    final searchRepository = widget.stationSearchRepository;
    if (searchRepository == null) {
      return null;
    }
    return _NetworkMapSearchSession(
      key: _searchSessionKey,
      onResultFocus: _focusStationFromSearch,
      searchQueryController: _searchQueryController,
      stationSearchRepository: searchRepository,
      searchHistoryRepository: widget.searchHistoryRepository,
      favoriteRepository: widget.favoriteRepository,
      routeDraftController: widget.routeDraftController,
      regionLabel: _displayRegionName(_selectedRegion ?? '수도권'),
    );
  }

  @override
  void dispose() {
    _nearbyLookupMessageTimer?.cancel();
    widget.regionBridge?.detach();
    widget.routeDraftController.removeListener(_handleDraftChangedForSearch);
    _searchQueryController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Future<NetworkMapLoadResult> _startMapLoad() {
    return _loadMap(++_mapLoadGeneration);
  }

  Future<NetworkMapLoadResult> _loadMap(int generation) async {
    var requestedRegion = _selectedRegion;
    var restoringSavedRegion = false;
    final viewportRepository = widget.viewportRepository;
    if (requestedRegion == null && viewportRepository != null) {
      try {
        requestedRegion = await viewportRepository.loadSelectedRegion();
        restoringSavedRegion = requestedRegion != null;
      } catch (error, stackTrace) {
        reportMobileError(
          error,
          stackTrace,
          context: '노선도 최근 지역 불러오기 중 예외가 발생했습니다.',
        );
      }
    }
    var data = await widget.repository.getNetworkMap(region: requestedRegion);
    if (restoringSavedRegion &&
        !data.regions.any(
          (region) =>
              region.displayName == _displayRegionName(data.selectedRegion),
        )) {
      data = await widget.repository.getNetworkMap();
    }
    if (generation != _mapLoadGeneration) {
      return NetworkMapLoadResult(data: data, initialViewport: null);
    }
    // #2082/#2083 후속: 저장된(persisted) 지역이 있는 사용자는 세션 중
    // 지역 선택기를 조작하지 않는 한 _selectedRegion이 계속 null이라, 로드된
    // 실제 지역(data.selectedRegion)을 여기서 동기화해둔다. 사용자가 이미
    // _reload(region: ...)로 _selectedRegion을 명시 설정한 경우는 그 값이
    // 그대로 리포지토리 요청에 반영되어 data.selectedRegion과 같아지므로
    // 값이 보존된다(덮어써도 동일).
    _selectedRegion = data.selectedRegion;
    _cacheAvailableRegionLabels(data.regions);
    if (mounted) {
      _notifyRegionLabelChanged();
    }
    await _saveSelectedRegion(data.selectedRegion);
    final viewport = await _loadSavedViewport(data.selectedRegion);
    return NetworkMapLoadResult(data: data, initialViewport: viewport);
  }

  Future<NetworkMapLoadResult> _loadMapForRegion(
    String region, {
    bool loadStoredViewport = true,
  }) async {
    final data = await widget.repository.getNetworkMap(region: region);
    _cacheAvailableRegionLabels(data.regions);
    final viewport = loadStoredViewport
        ? await _loadSavedViewport(data.selectedRegion)
        : null;
    return NetworkMapLoadResult(data: data, initialViewport: viewport);
  }

  Future<void> _saveSelectedRegion(String region) async {
    try {
      await widget.viewportRepository?.saveSelectedRegion(region);
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '노선도 최근 지역 저장 중 예외가 발생했습니다.',
      );
    }
  }

  Future<Rect?> _loadSavedViewport(String region) async {
    try {
      return await widget.viewportRepository?.loadViewport(
        _displayRegionName(region),
      );
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '노선도 최근 화면 위치 불러오기 중 예외가 발생했습니다.',
      );
      return null;
    }
  }

  void _cacheAvailableRegionLabels(List<NetworkMapRegion> regions) {
    _availableRegionLabels = regions.isEmpty
        ? const ['수도권']
        : regions.map((region) => region.displayName).toList(growable: false);
  }

  void _reload({String? region}) {
    // 출발·도착·경유 중 하나라도 있으면 지역 전환을 막는다.
    if (region != null && !widget.routeDraftController.draft.isEmpty) {
      return;
    }
    _nearestStationRequestToken++;
    setState(() {
      _selectedRegion = region ?? _selectedRegion;
      _resetNearbyPanelState();
      _initialNearbyFocusStarted = false;
      _future = _startMapLoad();
    });
    _notifyRegionLabelChanged();
  }

  /// #2419 Fix: 노선 탭(길찾기 draft 자동검색)이 draft 역의 지역 폴백으로 쓸 수
  /// 있도록, 지역이 로드·전환될 때마다 현재 지역 표시명을 부모(홈)에 알린다.
  void _notifyRegionLabelChanged() {
    widget.onRegionLabelChanged?.call(_currentRegionDisplayName);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_searchMode,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _searchMode) {
          _exitSearchMode();
        }
      },
      child: Scaffold(
        key: const Key('networkMapScreen'),
        backgroundColor: EasySubwayAccessibleColors.surface,
        body: FutureBuilder<NetworkMapLoadResult>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return _NetworkMapChrome(
                regions: const [NetworkMapRegion(name: '수도권')],
                selectedRegion: _selectedRegion ?? '수도권',
                notificationAction: widget.notificationAction,
                disruptionBanner: widget.disruptionBanner,
                onMenuTap: _openMapMenu,
                onSearchTap: _enterSearchMode,
                searchMode: _searchMode,
                searchBody: _buildSearchBody(),
                onSearchBack: _exitSearchMode,
                searchQueryController: _searchQueryController,
                searchFocusNode: _searchFocusNode,
                onSearchSubmitted: _submitSearch,
                onSearchClear: _searchQueryController.clear,
                onRegionSelected: (region) => _reload(region: region),
                nearbyPanelVisible: _nearbyPanelVisible,
                nearbyPanelExpanded: _nearbyPanelExpanded,
                nearbyPanelData: _nearbyPanelData,
                realtime: _nearbyRealtimeForDisplay,
                nearbySelectedLineId: _nearbySelectedLineId,
                nearbyDataSource: _nearbyDataSource,
                nearbyTimetable: _nearbyTimetableForDisplay,
                nearbyLookupMessage: _nearbyLookupMessage,
                adjacentStations: const NearbyAdjacentStations(),
                onCurrentLocationTap: _showNearestStationFanMenu,
                onCloseNearbyPanel: _hideNearbyPanel,
                onNearbyLineSelected: _selectNearbyLine,
                onNearbyDataSourceToggle: _toggleNearbyDataSource,
                onOpenNearbyStationDetail: _nearbyStationDetailAction,
                onSelectNearbyNeighbor: _selectNearbyNeighborStation,
                stationSearchRepository: widget.stationSearchRepository,
                reportRepository: widget.reportRepository,
                favoriteRepository: widget.favoriteRepository,
                adRepository: widget.adRepository,
                realtimeRepository: widget.realtimeRepository,
                locationProvider: widget.locationProvider,
                facilityReportDraftTargetStore:
                    widget.facilityReportDraftTargetStore,
                internalRouteRepository: widget.internalRouteRepository,
                internalRouteMobilityType: widget.internalRouteMobilityType,
                routeDraftController: widget.routeDraftController,
                onClearOrigin: _clearOriginStation,
                onClearDestination: _clearDestinationStation,
                onClearWaypoint: _clearWaypointStation,
                onReorderDraft: _reorderDraftStations,
                onPickOrigin: widget.onPickStationForSlot == null
                    ? null
                    : _pickOriginStation,
                onPickDestination: widget.onPickStationForSlot == null
                    ? null
                    : _pickDestinationStation,
                onPickWaypoint: widget.onPickStationForSlot == null
                    ? null
                    : _pickWaypointStation,
                child: const Center(child: CircularProgressIndicator()),
              );
            }
            if (snapshot.hasError || !snapshot.hasData) {
              return _NetworkMapChrome(
                regions: const [NetworkMapRegion(name: '수도권')],
                selectedRegion: _selectedRegion ?? '수도권',
                notificationAction: widget.notificationAction,
                disruptionBanner: widget.disruptionBanner,
                onMenuTap: _openMapMenu,
                onSearchTap: _enterSearchMode,
                searchMode: _searchMode,
                searchBody: _buildSearchBody(),
                onSearchBack: _exitSearchMode,
                searchQueryController: _searchQueryController,
                searchFocusNode: _searchFocusNode,
                onSearchSubmitted: _submitSearch,
                onSearchClear: _searchQueryController.clear,
                onRegionSelected: (region) => _reload(region: region),
                nearbyPanelVisible: _nearbyPanelVisible,
                nearbyPanelExpanded: _nearbyPanelExpanded,
                nearbyPanelData: _nearbyPanelData,
                realtime: _nearbyRealtimeForDisplay,
                nearbySelectedLineId: _nearbySelectedLineId,
                nearbyDataSource: _nearbyDataSource,
                nearbyTimetable: _nearbyTimetableForDisplay,
                nearbyLookupMessage: _nearbyLookupMessage,
                adjacentStations: const NearbyAdjacentStations(),
                onCurrentLocationTap: _showNearestStationFanMenu,
                onCloseNearbyPanel: _hideNearbyPanel,
                onNearbyLineSelected: _selectNearbyLine,
                onNearbyDataSourceToggle: _toggleNearbyDataSource,
                onOpenNearbyStationDetail: _nearbyStationDetailAction,
                onSelectNearbyNeighbor: _selectNearbyNeighborStation,
                stationSearchRepository: widget.stationSearchRepository,
                reportRepository: widget.reportRepository,
                favoriteRepository: widget.favoriteRepository,
                adRepository: widget.adRepository,
                realtimeRepository: widget.realtimeRepository,
                locationProvider: widget.locationProvider,
                facilityReportDraftTargetStore:
                    widget.facilityReportDraftTargetStore,
                internalRouteRepository: widget.internalRouteRepository,
                internalRouteMobilityType: widget.internalRouteMobilityType,
                routeDraftController: widget.routeDraftController,
                onClearOrigin: _clearOriginStation,
                onClearDestination: _clearDestinationStation,
                onClearWaypoint: _clearWaypointStation,
                onReorderDraft: _reorderDraftStations,
                onPickOrigin: widget.onPickStationForSlot == null
                    ? null
                    : _pickOriginStation,
                onPickDestination: widget.onPickStationForSlot == null
                    ? null
                    : _pickDestinationStation,
                onPickWaypoint: widget.onPickStationForSlot == null
                    ? null
                    : _pickWaypointStation,
                child: NetworkMapLoadFailure(onRetry: () => _reload()),
              );
            }
            final loadResult = snapshot.data!;
            final data = loadResult.data;
            // #2068: 노선도는 일반/급행 선택 없는 단일 통합 지도다. LOCAL/EXPRESS는
            // 시간표·길찾기 trip 속성으로만 유지되고, 지도는 항상 원본 data 전체를
            // 렌더한다(운행종별 필터 없음).
            _startInitialNearbyFocus();
            _latestMapData = data;
            return _NetworkMapChrome(
              regions: data.regions,
              selectedRegion: data.selectedRegion,
              notificationAction: widget.notificationAction,
              disruptionBanner: widget.disruptionBanner,
              onMenuTap: _openMapMenu,
              onSearchTap: _enterSearchMode,
              searchMode: _searchMode,
              searchBody: _buildSearchBody(),
              onSearchBack: _exitSearchMode,
              searchQueryController: _searchQueryController,
              searchFocusNode: _searchFocusNode,
              onSearchSubmitted: _submitSearch,
              onSearchClear: _searchQueryController.clear,
              onRegionSelected: (region) => _reload(region: region),
              nearbyPanelVisible: _nearbyPanelVisible,
              nearbyPanelExpanded: _nearbyPanelExpanded,
              nearbyPanelData: _nearbyPanelData,
              realtime: _nearbyRealtimeForDisplay,
              nearbySelectedLineId: _nearbySelectedLineId,
              nearbyDataSource: _nearbyDataSource,
              nearbyTimetable: _nearbyTimetableForDisplay,
              nearbyLookupMessage: _nearbyLookupMessage,
              adjacentStations: _adjacentStationsFor(data),
              onCurrentLocationTap: _showNearestStationFanMenu,
              onCloseNearbyPanel: _hideNearbyPanel,
              onNearbyLineSelected: _selectNearbyLine,
              onNearbyDataSourceToggle: _toggleNearbyDataSource,
              onOpenNearbyStationDetail: _nearbyStationDetailAction,
              onSelectNearbyNeighbor: _selectNearbyNeighborStation,
              stationSearchRepository: widget.stationSearchRepository,
              reportRepository: widget.reportRepository,
              favoriteRepository: widget.favoriteRepository,
              adRepository: widget.adRepository,
              realtimeRepository: widget.realtimeRepository,
              locationProvider: widget.locationProvider,
              facilityReportDraftTargetStore:
                  widget.facilityReportDraftTargetStore,
              internalRouteRepository: widget.internalRouteRepository,
              internalRouteMobilityType: widget.internalRouteMobilityType,
              routeDraftController: widget.routeDraftController,
              onClearOrigin: _clearOriginStation,
              onClearDestination: _clearDestinationStation,
              onClearWaypoint: _clearWaypointStation,
              onReorderDraft: _reorderDraftStations,
              onPickOrigin: widget.onPickStationForSlot == null
                  ? null
                  : _pickOriginStation,
              onPickDestination: widget.onPickStationForSlot == null
                  ? null
                  : _pickDestinationStation,
              onPickWaypoint: widget.onPickStationForSlot == null
                  ? null
                  : _pickWaypointStation,
              // #1933: _setOriginStation은 routeDraftController만 갱신하고 이
              // State에서 setState를 호출하지 않으므로, canvas를 좁게
              // ListenableBuilder로 감싸 draft 변경 시 하위 트리가 다시
              // 계산되게 한다(그래야 슬롯 배정 상태가 즉시 반영됨).
              child: ListenableBuilder(
                listenable: widget.routeDraftController,
                builder: (context, _) {
                  return _NetworkMapCanvas(
                    data: data,
                    initialViewport: loadResult.initialViewport,
                    focusedStationId:
                        _searchFanMenuStationId ?? _nearbySelectedStationId,
                    preserveFocusedStationScale: _preserveFocusedStationScale,
                    selectedStationId: _searchFanMenuStationId,
                    selectionClearRevision: _selectionClearRevision,
                    onSelectionDismissed: _dismissSearchFanMenu,
                    onStationTapped: _handleCanvasStationTapped,
                    originStationId:
                        widget.routeDraftController.draft.origin?.id,
                    waypointStationId:
                        widget.routeDraftController.draft.waypoint?.id,
                    destinationStationId:
                        widget.routeDraftController.draft.destination?.id,
                    onSetOrigin: _setOriginStation,
                    onSetWaypoint: _setWaypointStation,
                    onSetDestination: _setDestinationStation,
                    onClearOrigin: _clearOriginStation,
                    onClearWaypoint: _clearWaypointStation,
                    onClearDestination: _clearDestinationStation,
                    onViewportChanged: (viewport) {
                      _saveRecentViewport(data.selectedRegion, viewport);
                    },
                  );
                },
              ),
            );
          },
        ),
        bottomNavigationBar: _searchMode || _nearbyPanelVisible
            ? null
            : const NetworkMapBottomAdBanner(),
      ),
    );
  }

  Future<void> _showNearestStationFanMenu() async {
    final requestToken = ++_nearestStationRequestToken;
    _nearbyLookupMessageTimer?.cancel();
    _nearbyLookupMessageTimer = null;
    setState(() {
      _nearbyLookupMessage = null;
      _searchFanMenuStationId = null;
      _selectionClearRevision++;
      _resetNearbyPanelState();
      _nearbyPanelData = const _NetworkMapNearbyPanelData.loading();
      // 이 setState로 rebuild되는 동안 자동 초기 위치 조회가 중복 실행되지 않게
      // 한다. GPS 요청이 다른 지역을 로드한 뒤에도 이 값은 유지한다.
      _initialNearbyFocusStarted = true;
    });
    bool isCurrentRequest() =>
        mounted && requestToken == _nearestStationRequestToken;

    final locationProvider = widget.locationProvider;
    final stationRepository = widget.stationSearchRepository;
    if (locationProvider == null || stationRepository == null) {
      if (!isCurrentRequest()) {
        return;
      }
      _showNearbyLookupMessage('현재 위치를 확인하지 못했어요.');
      return;
    }
    try {
      final location = await locationProvider.currentLocation();
      if (!isCurrentRequest()) {
        return;
      }
      final blockedMessage = location.nearbySearchBlockedMessage();
      if (blockedMessage != null) {
        _showNearbyLookupMessage(blockedMessage);
        return;
      }
      final results = await stationRepository.searchNearbyStations(
        location,
        limit: 1,
      );
      if (!isCurrentRequest()) {
        return;
      }
      if (results.isEmpty) {
        _showNearbyLookupMessage('주변 역을 찾지 못했어요.');
        return;
      }

      final pendingResult = results.first;
      var targetMap = await _future;
      var regionChanged = false;
      if (!isCurrentRequest()) {
        return;
      }

      if (_displayRegionName(targetMap.data.selectedRegion) !=
          pendingResult.region) {
        // 경로 칸이 하나라도 있으면 지역을 바꾸지 않는다.
        if (!widget.routeDraftController.draft.isEmpty) {
          _showNearbyLookupMessage('경로를 정한 뒤에는 지역을 바꿀 수 없어요.');
          return;
        }
        final matchingRegions = targetMap.data.regions
            .where((region) => region.displayName == pendingResult.region)
            .toList(growable: false);
        if (matchingRegions.length != 1) {
          _showNearbyLookupMessage('주변 역을 불러오지 못했어요.');
          return;
        }
        targetMap = await _loadMapForRegion(
          matchingRegions.single.name,
          loadStoredViewport: false,
        );
        if (!isCurrentRequest()) {
          return;
        }
        regionChanged = true;
      }

      if (!targetMap.data.stations.any(
        (station) => station.id == pendingResult.id,
      )) {
        _showNearbyLookupMessage('주변 역을 불러오지 못했어요.');
        return;
      }

      if (regionChanged) {
        if (!widget.routeDraftController.draft.isEmpty) {
          _showNearbyLookupMessage('경로를 정한 뒤에는 지역을 바꿀 수 없어요.');
          return;
        }
        setState(() {
          _selectedRegion = targetMap.data.selectedRegion;
          _future = Future.value(targetMap);
          _initialNearbyFocusStarted = true;
        });
        _notifyRegionLabelChanged();
        unawaited(_saveSelectedRegion(targetMap.data.selectedRegion));
      }
      // 역 확정 후 공통 오픈으로 즉시 표시(기본 탭 시간표). 실시간/시간표 await 금지.
      _openNearbyStationPanel(
        pendingResult,
        preferredLine: pendingResult.lines.firstOrNull,
        preserveFocusedStationScale: true,
      );
    } on CurrentLocationException catch (error) {
      if (!isCurrentRequest()) {
        return;
      }
      _showNearbyLookupMessage(error.message);
    } on StationSearchException catch (error) {
      if (!isCurrentRequest()) {
        return;
      }
      _showNearbyLookupMessage(error.message);
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '노선도 주변 역 확인 중 예외가 발생했습니다.',
      );
      if (!isCurrentRequest()) {
        return;
      }
      _showNearbyLookupMessage('주변 역을 불러오지 못했어요.');
    }
  }

  void _showNearbyLookupMessage(String message) {
    _nearbyLookupMessageTimer?.cancel();
    setState(() {
      _resetNearbyPanelState();
      _nearbyLookupMessage = message;
    });
    _nearbyLookupMessageTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted) {
        return;
      }
      setState(() => _nearbyLookupMessage = null);
    });
  }

  void _startInitialNearbyFocus() {
    if (_initialNearbyFocusStarted ||
        _nearbySelectedStationId != null ||
        _nearbyPanelVisible) {
      return;
    }
    if (widget.viewportRepository == null) {
      return;
    }
    final locationProvider = widget.locationProvider;
    final stationRepository = widget.stationSearchRepository;
    if (locationProvider == null || stationRepository == null) {
      return;
    }
    _initialNearbyFocusStarted = true;
    unawaited(_focusInitialNearbyStation(locationProvider, stationRepository));
  }

  Future<void> _focusInitialNearbyStation(
    CurrentLocationProvider locationProvider,
    StationSearchRepository stationRepository,
  ) async {
    final mapFuture = _future;
    try {
      if (await locationProvider.needsLocationPermissionRequest()) {
        return;
      }
      final location = await locationProvider.currentLocation();
      if (location.nearbySearchBlockedMessage() != null) {
        return;
      }
      final results = await stationRepository.searchNearbyStations(
        location,
        limit: 1,
      );
      if (!mounted ||
          results.isEmpty ||
          _nearbyPanelVisible ||
          _future != mapFuture) {
        return;
      }

      final result = results.first;
      var targetMap = await mapFuture;
      var regionChanged = false;
      if (_displayRegionName(targetMap.data.selectedRegion) != result.region) {
        if (!widget.routeDraftController.draft.isEmpty) {
          return;
        }
        final matchingRegions = targetMap.data.regions
            .where((region) => region.displayName == result.region)
            .toList(growable: false);
        if (matchingRegions.length != 1) {
          return;
        }
        targetMap = await _loadMapForRegion(
          matchingRegions.single.name,
          loadStoredViewport: false,
        );
        regionChanged = true;
      }
      if (!mounted ||
          _nearbyPanelVisible ||
          _future != mapFuture ||
          (regionChanged && !widget.routeDraftController.draft.isEmpty)) {
        return;
      }
      if (!targetMap.data.stations.any((station) => station.id == result.id)) {
        return;
      }
      setState(() {
        if (regionChanged) {
          _selectedRegion = targetMap.data.selectedRegion;
          _future = Future.value(targetMap);
        }
        _nearbySelectedStationId = result.id;
        _preserveFocusedStationScale = true;
      });
      if (regionChanged) {
        _notifyRegionLabelChanged();
        unawaited(_saveSelectedRegion(targetMap.data.selectedRegion));
      }
    } on CurrentLocationException {
      return;
    } on StationSearchException {
      return;
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '노선도 초기 주변 역 확인 중 예외가 발생했습니다.',
      );
    }
  }

  void _saveRecentViewport(String region, Rect viewport) {
    final repository = widget.viewportRepository;
    if (repository == null) {
      return;
    }
    unawaited(
      repository
          .saveViewport(region: _displayRegionName(region), viewport: viewport)
          .catchError((Object error, StackTrace stackTrace) {
            reportMobileError(
              error,
              stackTrace,
              context: '노선도 최근 화면 위치 저장 중 예외가 발생했습니다.',
            );
          }),
    );
  }

  void _resetNearbyPanelState() {
    // 닫힌 뒤 완료되는 요청이 UI를 건드리지 않도록 generation을 무효화한다.
    _nearbyDataRequestToken++;
    _neighborSelectPanelToken++;
    _nearbyPanelVisible = false;
    _nearbyPanelExpanded = false;
    _nearbySelectedStationId = null;
    _preserveFocusedStationScale = false;
    _nearbySelectedLineId = null;
    _nearbyPanelData = const _NetworkMapNearbyPanelData.idle();
    _nearbyRealtimeDisplay = null;
    _nearbyDataSource = _NearbyPanelDataSource.realtime;
    _nearbyTimetableDisplay = null;
    _nearbyRealtimeRequestInFlight = false;
    _nearbyTimetableRequestInFlight = false;
    _nearbyRealtimeInFlightGeneration = null;
    _nearbyTimetableInFlightGeneration = null;
  }

  /// 실시간과 시간표를 같은 요청 키로 병렬 로드한다. 실시간 실패 시 즉시 시간표로 넘긴다.
  void _startNearbyPanelDataLoads(
    StationSearchResult station,
    StationSearchLine line,
    NearbyPanelRequestKey request,
  ) {
    unawaited(_loadNearbyRealtime(station, line, request: request));
    unawaited(_loadNearbyTimetable(station, line, request: request));
  }

  Future<void> _loadNearbyRealtime(
    StationSearchResult station,
    StationSearchLine line, {
    required NearbyPanelRequestKey request,
  }) async {
    final repository = widget.realtimeRepository;
    if (repository == null) {
      if (mounted) {
        setState(() => _clearNearbyRealtimeInFlightIf(request));
      } else {
        _clearNearbyRealtimeInFlightIf(request);
      }
      if (!_isCurrentNearbyRequest(request)) {
        return;
      }
      unawaited(
        _handleNearbyRealtimeUnavailable(station, line, request: request),
      );
      return;
    }
    try {
      final snapshot = await repository
          .arrivals(
            RealtimeStationQuery(
              stationId: station.id,
              lineId: line.id,
              providerLineId: line.stationCode.isEmpty
                  ? line.id
                  : line.stationCode,
              stationQueryName: station.nameKo,
            ),
          )
          .timeout(
            _nearbyRealtimeTimeout,
            onTimeout: () => const RealtimeSnapshot.unavailable(),
          );
      if (!_isCurrentNearbyRequest(request)) {
        if (mounted) {
          setState(() => _clearNearbyRealtimeInFlightIf(request));
        } else {
          _clearNearbyRealtimeInFlightIf(request);
        }
        return;
      }
      if (_isCacheableNearbyRealtime(snapshot)) {
        setState(() {
          _nearbyRealtimeDisplay = _NearbyRealtimeDisplay(
            stationId: request.stationId,
            lineId: request.lineId,
            snapshot: snapshot,
          );
          _clearNearbyRealtimeInFlightIf(request);
        });
        return;
      }
      // unavailable/empty/loading 등은 성공 캐시를 덮지 않는다.
      setState(() => _clearNearbyRealtimeInFlightIf(request));
      unawaited(
        _handleNearbyRealtimeUnavailable(station, line, request: request),
      );
    } on RealtimeException {
      if (!_isCurrentNearbyRequest(request)) {
        if (mounted) {
          setState(() => _clearNearbyRealtimeInFlightIf(request));
        } else {
          _clearNearbyRealtimeInFlightIf(request);
        }
        return;
      }
      setState(() => _clearNearbyRealtimeInFlightIf(request));
      unawaited(
        _handleNearbyRealtimeUnavailable(station, line, request: request),
      );
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '노선도 최근접 역 실시간 정보 조회 중 예외가 발생했습니다.',
      );
      if (!_isCurrentNearbyRequest(request)) {
        if (mounted) {
          setState(() => _clearNearbyRealtimeInFlightIf(request));
        } else {
          _clearNearbyRealtimeInFlightIf(request);
        }
        return;
      }
      setState(() => _clearNearbyRealtimeInFlightIf(request));
      unawaited(
        _handleNearbyRealtimeUnavailable(station, line, request: request),
      );
    }
  }

  /// fresh/stale + 도착 ≥1만 display cache에 저장한다.
  bool _isCacheableNearbyRealtime(RealtimeSnapshot snapshot) {
    return (snapshot.status == RealtimeSnapshotStatus.fresh ||
            snapshot.status == RealtimeSnapshotStatus.stale) &&
        snapshot.arrivals.isNotEmpty;
  }

  /// 현재 실시간 탭 + 최신 요청의 unavailable/empty/timeout일 때만 시간표로 전환한다.
  /// 시간표 탭 prefetch 실패·이전 역/호선·닫힌 패널은 no-op.
  Future<void> _handleNearbyRealtimeUnavailable(
    StationSearchResult station,
    StationSearchLine line, {
    required NearbyPanelRequestKey request,
  }) async {
    final shouldFallbackToTimetable =
        mounted &&
        _isCurrentNearbyRequest(request) &&
        _nearbyDataSource == _NearbyPanelDataSource.realtime;
    if (!shouldFallbackToTimetable) {
      return;
    }
    final hasTimetable = _nearbyTimetableDisplayMatchesCurrent();
    setState(() {
      _nearbyDataSource = _NearbyPanelDataSource.timetable;
      if (!hasTimetable) {
        _markNearbyTimetableInFlight(request);
      }
    });
    if (!hasTimetable) {
      await _loadNearbyTimetable(station, line, request: request);
    }
  }

  Future<void> _loadNearbyTimetable(
    StationSearchResult station,
    StationSearchLine line, {
    required NearbyPanelRequestKey request,
  }) async {
    final repository = widget.stationSearchRepository;
    if (repository is! StationTimetableRepository) {
      if (mounted) {
        setState(() => _clearNearbyTimetableInFlightIf(request));
      } else {
        _clearNearbyTimetableInFlightIf(request);
      }
      return;
    }
    final timetableRepository = repository as StationTimetableRepository;
    try {
      final timetable = await timetableRepository.loadStationTimetableForDate(
        stationId: station.id,
        lineId: line.id,
        date: DateTime.now(),
      );
      if (!_isCurrentNearbyRequest(request)) {
        if (mounted) {
          setState(() => _clearNearbyTimetableInFlightIf(request));
        } else {
          _clearNearbyTimetableInFlightIf(request);
        }
        return;
      }
      setState(() {
        _nearbyTimetableDisplay = _NearbyTimetableDisplay(
          stationId: request.stationId,
          lineId: request.lineId,
          timetable: timetable,
        );
        _clearNearbyTimetableInFlightIf(request);
      });
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '노선도 최근접 역 시간표 조회 중 예외가 발생했습니다.',
      );
      if (!_isCurrentNearbyRequest(request)) {
        if (mounted) {
          setState(() => _clearNearbyTimetableInFlightIf(request));
        } else {
          _clearNearbyTimetableInFlightIf(request);
        }
        return;
      }
      // 실패로 성공 캐시를 지우지 않는다.
      setState(() => _clearNearbyTimetableInFlightIf(request));
    }
  }

  void _selectNearbyLine(StationSearchLine line) {
    if (_nearbySelectedLineId == line.id || _nearbyPanelData.results.isEmpty) {
      return;
    }
    final station = _nearbyPanelData.results.first;
    final request = NearbyPanelRequestKey(
      stationId: station.id,
      lineId: line.id,
      generation: ++_nearbyDataRequestToken,
    );
    // 호선 변경 시 모드 유지. 이전 호선 display는 키 불일치로 미표시.
    setState(() {
      _nearbySelectedLineId = line.id;
      _markNearbyRealtimeInFlight(request);
      _markNearbyTimetableInFlight(request);
    });
    _startNearbyPanelDataLoads(station, line, request);
  }

  void _toggleNearbyDataSource() {
    if (_nearbyPanelData.results.isEmpty) {
      return;
    }
    final station = _nearbyPanelData.results.first;
    final line = station.lines
        .where((candidate) => candidate.id == _nearbySelectedLineId)
        .firstOrNull;
    if (line == null) {
      return;
    }
    final next = _nearbyDataSource == _NearbyPanelDataSource.realtime
        ? _NearbyPanelDataSource.timetable
        : _NearbyPanelDataSource.realtime;
    setState(() {
      _nearbyDataSource = next;
    });
    if (next == _NearbyPanelDataSource.realtime) {
      // 현재 키 캐시가 있으면 즉시 표시만 하고 재요청하지 않는다.
      if (_nearbyRealtimeDisplayMatchesCurrent()) {
        return;
      }
      // 오픈 시 prefetch가 진행 중이면 재사용해 세대만 올리지 않는다.
      if (_nearbyRealtimeRequestInFlight) {
        return;
      }
      final request = NearbyPanelRequestKey(
        stationId: station.id,
        lineId: line.id,
        generation: ++_nearbyDataRequestToken,
      );
      setState(() {
        _markNearbyRealtimeInFlight(request);
        // generation을 올린 뒤 반대 채널 이전 요청은 무효 — 고아 in-flight로
        // 재요청이 영구 스킵되지 않게 플래그를 함께 정리한다.
        _nearbyTimetableRequestInFlight = false;
        _nearbyTimetableInFlightGeneration = null;
      });
      unawaited(_loadNearbyRealtime(station, line, request: request));
      return;
    }
    if (_nearbyTimetableDisplayMatchesCurrent()) {
      return;
    }
    if (_nearbyTimetableRequestInFlight) {
      return;
    }
    final request = NearbyPanelRequestKey(
      stationId: station.id,
      lineId: line.id,
      generation: ++_nearbyDataRequestToken,
    );
    setState(() {
      _markNearbyTimetableInFlight(request);
      _nearbyRealtimeRequestInFlight = false;
      _nearbyRealtimeInFlightGeneration = null;
    });
    unawaited(_loadNearbyTimetable(station, line, request: request));
  }

  void _hideNearbyPanel() {
    final preserveFocusedStationScale = _preserveFocusedStationScale;
    setState(() {
      _resetNearbyPanelState();
      _preserveFocusedStationScale = preserveFocusedStationScale;
    });
  }

  /// 저장소가 있을 때만 "상세 보기"를 탭 가능 컨트롤로 노출한다.
  VoidCallback? get _nearbyStationDetailAction =>
      widget.stationSearchRepository != null && widget.reportRepository != null
      ? _openNearbyStationDetail
      : null;

  void _openNearbyStationDetail() {
    final results = _nearbyPanelData.results;
    if (results.isEmpty) {
      return;
    }
    final stationRepository = widget.stationSearchRepository;
    final reportRepository = widget.reportRepository;
    if (stationRepository == null || reportRepository == null) {
      return;
    }
    setState(() => _nearbyPanelExpanded = true);
  }

  /// 확장 패널 이전/다음 역 탭. 패널 역을 바꾸고 확장을 유지한다.
  Future<void> _selectNearbyNeighborStation(
    StationDetailNeighbor neighbor,
  ) async {
    final repository = widget.stationSearchRepository;
    if (repository == null) {
      return;
    }
    final token = ++_neighborSelectPanelToken;
    List<StationSearchResult> results;
    try {
      results = await repository.searchStations(neighbor.nameKo);
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '노선도 인접 역 패널 해석 중 예외가 발생했습니다.',
      );
      return;
    }
    // 연타·닫기 후 늦은 응답은 패널을 다시 열거나 잘못된 역으로 덮지 않는다.
    if (!mounted ||
        token != _neighborSelectPanelToken ||
        !_nearbyPanelVisible) {
      return;
    }
    final match = results
        .where((result) => result.id == neighbor.stationId)
        .firstOrNull;
    if (match == null) {
      return;
    }
    final preferredLine = match.lines
        .where((line) => line.id == _nearbySelectedLineId)
        .firstOrNull;
    if (!_nearbyPanelExpanded) {
      setState(() => _nearbyPanelExpanded = true);
    }
    _openNearbyStationPanel(match, preferredLine: preferredLine);
  }

  /// 현재 선택 지역의 표시명(예: '수도권', '부산'). 역 검색 화면을 열 때
  /// [StationSearchScreen.regionLabel]로 그대로 넘긴다(#2090 배선).
  String get _currentRegionDisplayName =>
      _displayRegionName(_selectedRegion ?? '수도권');

  Future<void> _openMapMenu() {
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '메뉴 닫기',
      barrierColor: const Color(0x99000000),
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (context, animation, secondaryAnimation) {
        return NetworkMapMenuPanel(
          bottomBanner: const AdBannerSlot(
            slotKey: Key('networkMapMenuAdBanner'),
          ),
          onOpenStationSearch: () => widget.onOpenStationSearch(
            _currentRegionDisplayName,
            _availableRegionLabels,
          ),
          onOpenSavedItems: widget.onOpenSavedItems,
          onOpenTrainSearch: widget.onOpenTrainSearch,
          onOpenServiceNotices: widget.onOpenServiceNotices,
          onOpenSettings: widget.onOpenSettings,
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return SlideTransition(
          position: Tween<Offset>(begin: const Offset(-1, 0), end: Offset.zero)
              .animate(
                CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
              ),
          child: child,
        );
      },
    );
  }

  void _setOriginStation(NetworkMapStation station) {
    widget.routeDraftController.setOrigin(
      _routeDraftStationFromMapStation(station, _latestMapData),
    );
    _dismissNearbyPanelForDraft();
  }

  void _setDestinationStation(NetworkMapStation station) {
    widget.routeDraftController.setDestination(
      _routeDraftStationFromMapStation(station, _latestMapData),
    );
    _dismissNearbyPanelForDraft();
  }

  void _setWaypointStation(NetworkMapStation station) {
    widget.routeDraftController.setWaypoint(
      _routeDraftStationFromMapStation(station, _latestMapData),
    );
    _dismissNearbyPanelForDraft();
  }

  /// #2200 팬 메뉴로 출발/경유/도착 슬롯을 지정하면 OD 경로 편집 모드로 넘어가므로
  /// #2200에서 역 탭과 함께 열린 단일 역 정보 패널을 닫는다(검색 모드가 draft
  /// 변경 시 닫히는 것과 같은 상호배제). 캔버스 팬 메뉴 대상 역 id도 함께 비워
  /// 다음 프레임 rebuild가 패널을 되살리지 않게 한다. 패널·팬 메뉴가 이미 없으면
  /// 불필요한 setState를 피한다.
  void _dismissNearbyPanelForDraft() {
    if (!_nearbyPanelVisible && _searchFanMenuStationId == null) {
      return;
    }
    setState(() {
      _canvasTapPanelToken++;
      _searchFanMenuStationId = null;
      _resetNearbyPanelState();
    });
  }

  void _clearOriginStation() {
    widget.routeDraftController.clearOrigin();
  }

  void _clearDestinationStation() {
    widget.routeDraftController.clearDestination();
  }

  void _clearWaypointStation() {
    widget.routeDraftController.clearWaypoint();
  }

  /// #1985: draft 행 드래그 재배열. 대상 슬롯이 이미 차 있으면 두 값을 맞바꾸고,
  /// 비어 있으면 값을 옮긴다. 컨트롤러가 어느 경우든 원자적으로 처리한다.
  void _reorderDraftStations(RouteDraftSlot from, RouteDraftSlot to) {
    final draft = widget.routeDraftController.draft;
    final toFilled = switch (to) {
      RouteDraftSlot.origin => draft.origin != null,
      RouteDraftSlot.destination => draft.destination != null,
      RouteDraftSlot.waypoint => draft.waypoint != null,
    };
    if (toFilled) {
      widget.routeDraftController.swapSlots(from, to);
    } else {
      widget.routeDraftController.moveSlot(from, to);
    }
  }

  /// G4: 상단 오버레이 출발 칸 탭 → 기존 역 검색을 "출발역 채우기" 모드로 연다.
  /// 지도 탭 경로와 같은 [routeDraftController]로 수렴한다.
  void _pickOriginStation() {
    widget.onPickStationForSlot?.call(
      RouteDraftSlot.origin,
      _currentRegionDisplayName,
      _availableRegionLabels,
    );
  }

  /// G4: 상단 오버레이 도착 칸 탭 → 기존 역 검색을 "도착역 채우기" 모드로 연다.
  void _pickDestinationStation() {
    widget.onPickStationForSlot?.call(
      RouteDraftSlot.destination,
      _currentRegionDisplayName,
      _availableRegionLabels,
    );
  }

  /// #1948: 상단 오버레이 경유 행·추가 진입점 탭 → 역 검색을 "경유역 채우기" 모드로 연다.
  void _pickWaypointStation() {
    widget.onPickStationForSlot?.call(
      RouteDraftSlot.waypoint,
      _currentRegionDisplayName,
      _availableRegionLabels,
    );
  }

  NearbyAdjacentStations _adjacentStationsFor(NetworkMapData data) {
    final selectedStationId = _nearbySelectedStationId;
    if (selectedStationId == null) {
      return const NearbyAdjacentStations();
    }
    final pair = networkMapAdjacentStationPair(
      stations: data.stations,
      edges: data.edges,
      stationId: selectedStationId,
      lineId: _nearbySelectedLineId,
    );
    return NearbyAdjacentStations(
      leftName: pair.leftName,
      rightName: pair.rightName,
      leftStationId: pair.leftStationId,
      rightStationId: pair.rightStationId,
    );
  }
}

/// 테스트 전용: [_NetworkMapChrome]가 build될 때마다 증가한다. 검색 중 키
/// 입력이 지도 chrome(상단바+지도 canvas를 감싸는 서브트리) 전체를 재빌드하지
/// 않는지(입력 지연 회귀 방지 #1915) 검증하는 회귀 테스트에서만 읽는다.
@visibleForTesting
int debugNetworkMapChromeBuildCount = 0;

class _NetworkMapChrome extends StatelessWidget {
  const _NetworkMapChrome({
    required this.regions,
    required this.selectedRegion,
    required this.notificationAction,
    required this.disruptionBanner,
    required this.onMenuTap,
    required this.onSearchTap,
    required this.onRegionSelected,
    required this.nearbyPanelVisible,
    required this.nearbyPanelExpanded,
    required this.nearbyPanelData,
    required this.realtime,
    required this.nearbySelectedLineId,
    required this.nearbyDataSource,
    required this.nearbyTimetable,
    required this.nearbyLookupMessage,
    required this.adjacentStations,
    required this.onCurrentLocationTap,
    required this.onCloseNearbyPanel,
    required this.onNearbyLineSelected,
    required this.onNearbyDataSourceToggle,
    this.onOpenNearbyStationDetail,
    this.onSelectNearbyNeighbor,
    this.stationSearchRepository,
    this.reportRepository,
    this.favoriteRepository,
    this.adRepository,
    this.realtimeRepository,
    this.locationProvider,
    this.facilityReportDraftTargetStore,
    this.internalRouteRepository,
    this.internalRouteMobilityType = 'SENIOR',
    required this.routeDraftController,
    required this.onClearOrigin,
    required this.onClearDestination,
    required this.onClearWaypoint,
    required this.onReorderDraft,
    this.onPickOrigin,
    this.onPickDestination,
    this.onPickWaypoint,
    this.searchMode = false,
    this.searchBody,
    this.onSearchBack,
    this.searchQueryController,
    this.searchFocusNode,
    this.onSearchSubmitted,
    this.onSearchClear,
    required this.child,
  });

  final List<NetworkMapRegion> regions;
  final String selectedRegion;
  final Widget? notificationAction;
  final Widget? disruptionBanner;
  final VoidCallback onMenuTap;
  final VoidCallback onSearchTap;
  final ValueChanged<String> onRegionSelected;
  final bool nearbyPanelVisible;
  final bool nearbyPanelExpanded;
  final _NetworkMapNearbyPanelData nearbyPanelData;
  final RealtimeSnapshot realtime;
  final String? nearbySelectedLineId;
  final _NearbyPanelDataSource nearbyDataSource;
  final StationTimetable? nearbyTimetable;
  final String? nearbyLookupMessage;
  final NearbyAdjacentStations adjacentStations;
  final VoidCallback onCurrentLocationTap;
  final VoidCallback onCloseNearbyPanel;
  final ValueChanged<StationSearchLine> onNearbyLineSelected;
  final VoidCallback onNearbyDataSourceToggle;
  final VoidCallback? onOpenNearbyStationDetail;
  final ValueChanged<StationDetailNeighbor>? onSelectNearbyNeighbor;
  final StationSearchRepository? stationSearchRepository;
  final FacilityReportRepository? reportRepository;
  final FavoriteStationRepository? favoriteRepository;
  final AdRepository? adRepository;
  final RealtimeRepository? realtimeRepository;
  final CurrentLocationProvider? locationProvider;
  final FacilityReportDraftTargetStore? facilityReportDraftTargetStore;
  final InternalRouteRepository? internalRouteRepository;
  final String internalRouteMobilityType;
  final RouteDraftController routeDraftController;
  final VoidCallback onClearOrigin;
  final VoidCallback onClearDestination;
  final VoidCallback onClearWaypoint;

  /// #1985: draft 행 드래그 재배열 콜백. (from, to) 슬롯을 받아 swap/move를 분기한다.
  final void Function(RouteDraftSlot from, RouteDraftSlot to) onReorderDraft;

  /// 상단바 출발/도착/경유 칸 탭 → 역 검색 열기. null이면 칸을 탭할 수 없다.
  final VoidCallback? onPickOrigin;
  final VoidCallback? onPickDestination;
  final VoidCallback? onPickWaypoint;

  /// #1933 홈 노선도 in-place 역 검색 모드. true면 body를 [searchBody]로 바꾸고
  /// 상단바 좌측 ≡를 ←로, 검색 필드를 실제 TextField로 전환한다. 지역 선택기는
  /// 두 모드에서 모두 유지된다.
  final bool searchMode;
  final Widget? searchBody;
  final VoidCallback? onSearchBack;
  final TextEditingController? searchQueryController;
  final FocusNode? searchFocusNode;
  final ValueChanged<String>? onSearchSubmitted;
  final VoidCallback? onSearchClear;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    debugNetworkMapChromeBuildCount++;
    final topPadding = MediaQuery.paddingOf(context).top;
    final inSearchMode = searchMode && searchBody != null;
    // 지도를 상단바 아래로 약간 겹쳐 그리면, 구분선·짧은 드롭이 흰 배경이 아니라
    // 노선 색 위에 앉아 카카오처럼 닿는 부위가 하얗게 끊기지 않는다.
    const mapUnderTopBarPx = 10.0;
    final mapTop = topPadding + _networkMapTopBarHeight - mapUnderTopBarPx;
    // 상단바 mapChrome 드롭이 지도 위로 그려지려면 이 Stack이 자식을 잘라내면
    // 안 된다(기본 Clip.hardEdge면 그림자만 사라짐).
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          top: mapTop,
          // ClipRect를 쓰면 가장자리 draft 핀의 soft drop·✕가 잘린다.
          child: inSearchMode ? searchBody! : child,
        ),
        Positioned(
          left: 0,
          top: 0,
          right: 0,
          child: _NetworkMapTopBar(
            regions: regions,
            selectedRegion: selectedRegion,
            notificationAction: notificationAction,
            onMenuTap: onMenuTap,
            onSearchTap: onSearchTap,
            searchMode: inSearchMode,
            onSearchBack: onSearchBack,
            searchQueryController: searchQueryController,
            searchFocusNode: searchFocusNode,
            onSearchSubmitted: onSearchSubmitted,
            onSearchClear: onSearchClear,
            onRegionSelected: onRegionSelected,
            // #1933 요구 2: 출발/도착이 하나라도 차면 상단바 자체가 출발/도착
            // 2줄 입력으로 "변신"한다(아래 별도 카드 없음). 지도 탭·검색 어느
            // 경로든 같은 [routeDraftController]로 수렴한다.
            routeDraftController: routeDraftController,
            onClearOrigin: onClearOrigin,
            onClearDestination: onClearDestination,
            onClearWaypoint: onClearWaypoint,
            onReorderDraft: onReorderDraft,
            onPickOrigin: onPickOrigin,
            onPickDestination: onPickDestination,
            onPickWaypoint: onPickWaypoint,
          ),
        ),
        if (disruptionBanner != null && !inSearchMode)
          Positioned(
            left: 0,
            right: 0,
            top: topPadding + _networkMapTopBarHeight,
            child: disruptionBanner!,
          ),
        if (nearbyPanelVisible && !inSearchMode)
          Positioned(
            // 확장 시 상단 검색바까지 덮어 반쯤 열린 슬롭 시트를 막는다.
            left: 0,
            right: 0,
            top: nearbyPanelExpanded ? 0 : null,
            bottom: 0,
            child: _NetworkMapNearbyStationPanel(
              data: nearbyPanelData,
              expanded: nearbyPanelExpanded,
              realtime: realtime,
              selectedLineId: nearbySelectedLineId,
              dataSource: nearbyDataSource,
              timetable: nearbyTimetable,
              adjacentStations: adjacentStations,
              onClose: onCloseNearbyPanel,
              onLineSelected: onNearbyLineSelected,
              onDataSourceToggle: onNearbyDataSourceToggle,
              onOpenStationDetail: onOpenNearbyStationDetail,
              onSelectNeighbor: onSelectNearbyNeighbor,
              stationSearchRepository: stationSearchRepository,
              reportRepository: reportRepository,
              favoriteRepository: favoriteRepository,
              adRepository: adRepository,
              realtimeRepository: realtimeRepository,
              locationProvider: locationProvider,
              facilityReportDraftTargetStore: facilityReportDraftTargetStore,
              internalRouteRepository: internalRouteRepository,
              internalRouteMobilityType: internalRouteMobilityType,
              routeDraftController: routeDraftController,
            ),
          ),
        if (nearbyLookupMessage != null &&
            !inSearchMode &&
            !nearbyPanelExpanded)
          Positioned(
            left: 24,
            right: 24,
            bottom: nearbyPanelVisible ? 318 : 132,
            child: NetworkMapLookupToast(message: nearbyLookupMessage!),
          ),
        if (!inSearchMode && !nearbyPanelExpanded)
          Positioned(
            right: 16,
            bottom: nearbyPanelVisible ? 280 : 26,
            child: NetworkMapCurrentLocationButton(onTap: onCurrentLocationTap),
          ),
      ],
    );
  }
}

class _NetworkMapTopBar extends StatelessWidget {
  const _NetworkMapTopBar({
    required this.regions,
    required this.selectedRegion,
    required this.notificationAction,
    required this.onMenuTap,
    required this.onSearchTap,
    this.searchMode = false,
    this.onSearchBack,
    this.searchQueryController,
    this.searchFocusNode,
    this.onSearchSubmitted,
    this.onSearchClear,
    required this.onRegionSelected,
    required this.routeDraftController,
    required this.onClearOrigin,
    required this.onClearDestination,
    required this.onClearWaypoint,
    required this.onReorderDraft,
    this.onPickOrigin,
    this.onPickDestination,
    this.onPickWaypoint,
  });

  final List<NetworkMapRegion> regions;
  final String selectedRegion;
  final Widget? notificationAction;
  final VoidCallback onMenuTap;
  final VoidCallback onSearchTap;
  final bool searchMode;
  final VoidCallback? onSearchBack;
  final TextEditingController? searchQueryController;
  final FocusNode? searchFocusNode;
  final ValueChanged<String>? onSearchSubmitted;
  final VoidCallback? onSearchClear;
  final ValueChanged<String> onRegionSelected;
  final RouteDraftController routeDraftController;
  final VoidCallback onClearOrigin;
  final VoidCallback onClearDestination;
  final VoidCallback onClearWaypoint;
  final void Function(RouteDraftSlot from, RouteDraftSlot to) onReorderDraft;
  final VoidCallback? onPickOrigin;
  final VoidCallback? onPickDestination;
  final VoidCallback? onPickWaypoint;

  @override
  Widget build(BuildContext context) {
    return Material(
      key: const Key('networkMapTopBar'),
      color: EasySubwayAccessibleColors.topBarSurface,
      elevation: 0,
      // mapChrome 짧은 드롭이 지도 위로 그려지도록 클립하지 않는다.
      clipBehavior: Clip.none,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          SafeArea(
            bottom: false,
            // #1933 요구 2: draft가 비면 검색바, 하나라도 차면 출발/도착 2줄 입력으로
            // 상단바 자체가 변신한다. 별도 카드를 아래에 띄우지 않는다.
            child: ListenableBuilder(
              listenable: routeDraftController,
              builder: (context, _) {
                final draft = routeDraftController.draft;
                if (draft.isEmpty) {
                  return _buildSearchRow(context);
                }
                return _NetworkMapTopBarRouteDraft(
                  key: const Key('networkMapRouteDraftOverlay'),
                  draft: draft,
                  showWaypointRow: routeDraftController.isWaypointRowVisible,
                  regionLabel: _displayRegionName(selectedRegion),
                  onClearDraft: routeDraftController.clear,
                  onOpenWaypointSlot: routeDraftController.openWaypointSlot,
                  onClearOrigin: onClearOrigin,
                  onClearDestination: onClearDestination,
                  onClearWaypoint: onClearWaypoint,
                  onReorderDraft: onReorderDraft,
                  onPickOrigin: onPickOrigin,
                  onPickDestination: onPickDestination,
                  onPickWaypoint: onPickWaypoint,
                );
              },
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            // 노선도 idle/draft만 mapChrome 드롭. 검색 모드(흰 검색 본문)는
            // 역 검색 화면과 같이 선만 둔다.
            child: searchMode
                ? const EasySubwayHeaderDivider(
                    key: Key('networkMapTopBarDivider'),
                  )
                : const EasySubwayHeaderDivider.mapChrome(
                    key: Key('networkMapTopBarDivider'),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchRow(BuildContext context) {
    final currentRegion = _displayRegionName(selectedRegion);
    final availableRegions = regions.isEmpty
        ? const [NetworkMapRegion(name: '수도권')]
        : regions;
    return SizedBox(
      height: _networkMapTopBarHeight,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
        child: Row(
          children: [
            if (searchMode)
              IconButton(
                key: const Key('networkMapSearchBackButton'),
                tooltip: '뒤로',
                onPressed: onSearchBack,
                style: IconButton.styleFrom(
                  minimumSize: const Size.square(EasySubwayTouchTarget.general),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding: EdgeInsets.zero,
                ),
                icon: const Icon(
                  Icons.arrow_back,
                  size: 26,
                  color: EasySubwayAccessibleColors.contentPrimary,
                ),
              )
            else
              IconButton(
                key: const Key('networkMapMenuButton'),
                tooltip: '메뉴',
                onPressed: onMenuTap,
                style: IconButton.styleFrom(
                  minimumSize: const Size.square(EasySubwayTouchTarget.general),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding: EdgeInsets.zero,
                ),
                icon: const Icon(
                  Icons.menu,
                  size: 26,
                  color: EasySubwayAccessibleColors.contentPrimary,
                ),
              ),
            const SizedBox(width: 4),
            Expanded(
              child: searchMode
                  ? EasySubwaySearchField(
                      controller: searchQueryController,
                      focusNode: searchFocusNode,
                      hintText: '역 이름을 입력해 주세요',
                      autofocus: true,
                      onSubmitted: onSearchSubmitted,
                      onClear: onSearchClear,
                    )
                  : NetworkMapSearchEntryButton(onTap: onSearchTap),
            ),
            const SizedBox(width: 8),
            Builder(
              builder: (regionContext) {
                // 검색 행은 draft가 비었을 때만 렌더되지만, 경로 칸이 생기면
                // 지역 변경을 막고 ▾도 숨긴다(표시명만 유지).
                final canChangeRegion = routeDraftController.draft.isEmpty;
                return Semantics(
                  key: const Key('mapRegionTabs'),
                  container: true,
                  button: canChangeRegion,
                  label: canChangeRegion
                      ? '지역: $currentRegion, 지역 변경'
                      : '지역: $currentRegion',
                  onTap: canChangeRegion
                      ? () => _showRegionMenu(regionContext, availableRegions)
                      : null,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 148),
                    child: ExcludeSemantics(
                      child: InkWell(
                        key: const Key('networkMapRegionDropdown'),
                        onTap: canChangeRegion
                            ? () => _showRegionMenu(
                                regionContext,
                                availableRegions,
                              )
                            : null,
                        splashFactory: NoSplash.splashFactory,
                        splashColor: Colors.transparent,
                        highlightColor: Colors.transparent,
                        child: SizedBox(
                          height: EasySubwayTouchTarget.general,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: Text(
                                  currentRegion,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: EasySubwayAccessibleColors
                                        .contentSecondary,
                                    fontSize: 17,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              if (canChangeRegion) ...[
                                const SizedBox(width: 2),
                                const Icon(
                                  Icons.keyboard_arrow_down,
                                  color: EasySubwayAccessibleColors
                                      .contentSecondary,
                                  size: 22,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
            if (notificationAction != null) ...[
              const SizedBox(width: 8),
              notificationAction!,
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _showRegionMenu(
    BuildContext triggerContext,
    List<NetworkMapRegion> availableRegions,
  ) {
    return showEasySubwayRegionMenu(
      triggerContext: triggerContext,
      regions: [
        for (final region in availableRegions)
          EasySubwayRegionMenuItem(id: region.name, label: region.displayName),
      ],
      selectedRegion: selectedRegion,
      onRegionSelected: onRegionSelected,
    );
  }
}

/// #1915 홈 노선도 in-place 역 검색의 "세션" — 검색 컨트롤러·디바운스·최근
/// 검색어·결과 본문 등 키 입력마다 바뀌는 상태를 이 서브트리로 격리한다.
/// 검색 모드로 진입/이탈하는 모드 플래그만 상위 [_NetworkMapScreenState]에
/// 남고, 타이핑으로 인한 재빌드는 이 세션(검색 필드 지우기 버튼·결과 본문)에
/// 국한된다. 그래야 지도 canvas·chrome 서브트리가 키 입력마다 재빌드되지
/// 않아 입력 지연이 사라진다.
///
/// 상단바의 편집 필드는 [_NetworkMapChrome]의 별도 Stack 자식이라 이 세션이
/// 직접 렌더하지 않는다. 대신 필드의 컨트롤러([searchQueryController])를 상위와
/// 공유하고, 세션은 그 컨트롤러를 구독해 디바운스 검색을 돌린다. 필드의 지우기
/// 버튼과 결과 본문은 각각 컨트롤러를 직접 구독(ListenableBuilder/
/// AnimatedBuilder)하므로 상위 setState 없이 자체 갱신된다. 제출(엔터/검색
/// 액션)은 상위가 [GlobalKey]로 [submitSearch]를 호출해 세션 로직으로 넘긴다.
class _NetworkMapSearchSession extends StatefulWidget {
  const _NetworkMapSearchSession({
    super.key,
    required this.onResultFocus,
    required this.searchQueryController,
    required this.stationSearchRepository,
    required this.searchHistoryRepository,
    this.favoriteRepository,
    required this.routeDraftController,
    required this.regionLabel,
  });

  final StationSearchResultTap onResultFocus;
  final TextEditingController searchQueryController;
  final StationSearchRepository stationSearchRepository;
  final SearchHistoryRepository? searchHistoryRepository;
  final FavoriteStationRepository? favoriteRepository;
  final RouteDraftController routeDraftController;
  final String regionLabel;

  @override
  State<_NetworkMapSearchSession> createState() =>
      _NetworkMapSearchSessionState();
}

class _NetworkMapSearchSessionState extends State<_NetworkMapSearchSession> {
  late final StationSearchController _searchController;
  Timer? _searchDebounce;
  List<RecentSearchEntry> _searchRecentEntries = const [];
  bool _searchRecentEntriesReady = false;
  Set<String> _favoriteKeys = const <String>{};

  /// 최근↔결과 레이아웃만 전환. 글자마다 결과 목록을 다시 그리지 않는다.
  bool _layoutHasSearchQuery = false;

  /// 하이라이트용. 검색이 돌아왔을 때의 질의(타이핑 중 매 키입력 반영 안 함).
  String _highlightQuery = '';

  TextEditingController get _queryController => widget.searchQueryController;

  bool get _hasSearchQuery => _queryController.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _searchController = StationSearchController(
      repository: widget.stationSearchRepository,
      searchHistoryRepository: widget.searchHistoryRepository,
    );
    _queryController.addListener(_handleSearchQueryChanged);
    unawaited(_loadSearchRecentEntries());
    unawaited(_loadFavoriteStationIds());
    unawaited(
      warmStationSearchCacheIfSupported(widget.stationSearchRepository),
    );
  }

  @override
  void didUpdateWidget(covariant _NetworkMapSearchSession oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.regionLabel == widget.regionLabel) {
      return;
    }
    // 홈 노선도 지역이 바뀌면 임베디드 검색의 최근 목록·결과 필터도 맞춘다.
    if (_hasSearchQuery) {
      unawaited(_runInPlaceSearch(_queryController.text, recordHistory: false));
    } else {
      unawaited(_loadSearchRecentEntries());
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _queryController.removeListener(_handleSearchQueryChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _handleSearchQueryChanged() {
    if (!mounted) {
      return;
    }
    _searchDebounce?.cancel();
    final hasQuery = _hasSearchQuery;
    if (!hasQuery) {
      _highlightQuery = '';
      if (_searchController.state.status != StationSearchStatus.idle) {
        unawaited(_searchController.search(''));
      }
    } else {
      // 부분 입력·초성(ㅅ)도 검색한다. 첫 글자는 즉시, 이후는 짧게 디바운스.
      final query = _queryController.text;
      if (!_layoutHasSearchQuery) {
        unawaited(_runInPlaceSearch(query, recordHistory: false));
      } else {
        _searchDebounce = Timer(
          const Duration(milliseconds: 180),
          () => unawaited(_runInPlaceSearch(query, recordHistory: false)),
        );
      }
    }
    if (_layoutHasSearchQuery != hasQuery) {
      setState(() => _layoutHasSearchQuery = hasQuery);
    }
  }

  Future<void> _runInPlaceSearch(
    String query, {
    bool recordHistory = true,
  }) async {
    _highlightQuery = query.trim();
    // 노선도 지역과 같은 범위로 결과·기록을 맞춘다. 전국 결과만 보고 현재
    // 지역 라벨로 저장하던 경로가 타 지역 역을 수도권 최근 검색에 남겼다.
    await _searchController.search(
      query,
      region: widget.regionLabel,
      recordRegion: widget.regionLabel,
      recordHistory: recordHistory,
    );
    if (recordHistory) {
      await _loadSearchRecentEntries();
    }
  }

  /// 상위 화면이 상단바 편집 필드의 제출(엔터/검색 액션)에서 [GlobalKey]로
  /// 호출한다. 세션이 검색 로직을 소유하므로 제출도 세션에서 처리한다.
  void submitSearch(String query) {
    // 진행 중 검색은 requestId로 무효화되므로 loading이어도 제출을 막지 않는다.
    _searchDebounce?.cancel();
    unawaited(_runInPlaceSearch(query));
  }

  Future<void> _loadSearchRecentEntries() async {
    final repository = widget.searchHistoryRepository;
    if (repository == null) {
      if (mounted) {
        setState(() => _searchRecentEntriesReady = true);
      } else {
        _searchRecentEntriesReady = true;
      }
      return;
    }
    try {
      final entries = await repository.listRecentEntries(
        region: widget.regionLabel,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _searchRecentEntries = entries;
        _searchRecentEntriesReady = true;
      });
    } catch (error, stackTrace) {
      reportMobileError(error, stackTrace, context: '최근 검색 조회 중 예외가 발생했습니다.');
      if (mounted) {
        setState(() => _searchRecentEntriesReady = true);
      }
    }
  }

  void _searchRecentStationSelected(RecentStationSearchEntry entry) {
    final query = entry.query;
    _queryController.value = TextEditingValue(
      text: query,
      selection: TextSelection.collapsed(offset: query.length),
    );
    submitSearch(query);
  }

  /// 최근 경로 항목을 탭하면 draft에 출발·경유·도착을 채운다. draft가 채워지면
  /// 상위 화면이 검색 모드를 자동 종료하고 홈이 경로 결과 탭으로 전환한다.
  void _searchRecentRouteSelected(RecentRouteSearchEntry entry) {
    final controller = widget.routeDraftController;
    controller.clear();
    controller.setOrigin(
      RouteDraftStation(
        id: entry.originStationId,
        nameKo: entry.originStationName,
      ),
    );
    controller.setDestination(
      RouteDraftStation(
        id: entry.destinationStationId,
        nameKo: entry.destinationStationName,
      ),
    );
    final waypointId = entry.waypointStationId;
    final waypointName = entry.waypointStationName;
    if (waypointId != null &&
        waypointId.isNotEmpty &&
        waypointName != null &&
        waypointName.isNotEmpty) {
      controller.setWaypoint(
        RouteDraftStation(id: waypointId, nameKo: waypointName),
      );
    }
  }

  Future<void> _clearAllSearchRecentEntries() async {
    final repository = widget.searchHistoryRepository;
    if (repository == null) {
      return;
    }
    final confirmed = await confirmClearRecentSearches(context);
    if (confirmed != true || !mounted) {
      return;
    }
    try {
      final entries = await repository.listRecentEntries(
        region: widget.regionLabel,
        limit: 50,
      );
      for (final entry in entries) {
        switch (entry) {
          case RecentStationSearchEntry():
            await repository.removeSearch(entry.query, region: entry.region);
          case RecentRouteSearchEntry():
            await repository.removeRouteSearch(entry);
        }
      }
      await _loadSearchRecentEntries();
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '최근 검색 전체 삭제 중 예외가 발생했습니다.',
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('최근 검색을 지우지 못했어요.')));
      }
    }
  }

  Future<void> _removeSearchRecentEntry(RecentSearchEntry entry) async {
    final repository = widget.searchHistoryRepository;
    if (repository == null) {
      return;
    }
    try {
      switch (entry) {
        case RecentStationSearchEntry():
          await repository.removeSearch(entry.query, region: entry.region);
        case RecentRouteSearchEntry():
          await repository.removeRouteSearch(entry);
      }
      await _loadSearchRecentEntries();
    } catch (error, stackTrace) {
      reportMobileError(error, stackTrace, context: '최근 검색 삭제 중 예외가 발생했습니다.');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('최근 검색을 지우지 못했어요.')));
      }
    }
  }

  Future<void> _loadFavoriteStationIds() async {
    final repository = widget.favoriteRepository;
    if (repository == null) {
      return;
    }
    try {
      final favorites = await repository.listFavoriteStations();
      if (!mounted) {
        return;
      }
      setState(() {
        _favoriteKeys = {
          for (final favorite in favorites)
            favoriteStationLineKey(favorite.stationId, favorite.lineId),
        };
      });
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '노선도 검색 즐겨찾기 조회 중 예외가 발생했습니다.',
      );
    }
  }

  Future<void> _toggleFavoriteStation(
    StationSearchResult result,
    StationSearchLine? line,
  ) async {
    final repository = widget.favoriteRepository;
    if (repository == null) {
      return;
    }
    final stationId = result.id;
    final lineId = line?.id;
    final key = favoriteStationLineKey(stationId, lineId);
    final removing = isFavoriteStationLine(_favoriteKeys, stationId, lineId);
    try {
      if (removing) {
        await repository.removeFavoriteStation(stationId, lineId: lineId);
      } else {
        await repository.saveFavoriteStation(stationId, lineId: lineId);
      }
      if (!mounted) {
        return;
      }
      setState(() {
        final next = Set<String>.from(_favoriteKeys);
        // 레거시 역 전체 키가 있으면 구체 호선 키로 정리한다.
        next.remove(favoriteStationLineKey(stationId, ''));
        if (removing) {
          next.remove(key);
        } else {
          next.add(key);
        }
        _favoriteKeys = next;
      });
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '노선도 검색 즐겨찾기 변경 중 예외가 발생했습니다.',
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(removing ? '즐겨찾기를 해제하지 못했어요.' : '즐겨찾기를 추가하지 못했어요.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // 검색어/결과 상태 변화는 setState 없이 AnimatedBuilder만 갱신한다.
    // searching·여백·배경은 builder 안에서 읽어야 한다. 바깥 build 클로저에
    // 묶으면 타이핑 때는 여백이 남고 즐겨찾기 setState 때만 풀블리드로
    // 바뀌어 화면이 갑자기 넓어진다.
    // 결과 목록은 검색 컨트롤러만 구독한다. queryController를 묶으면
    // 한글 조합 글자마다 배지·행 전체를 다시 그려 입력 자체가 버벅인다.
    final searching = _layoutHasSearchQuery;
    return Semantics(
      container: true,
      child: ColoredBox(
        color: searching
            ? EasySubwayAccessibleColors.surface
            : EasySubwayAccessibleColors.scaffoldSurface,
        child: SafeArea(
          top: false,
          left: !searching,
          right: !searching,
          child: AnimatedBuilder(
            animation: _searchController,
            builder: (context, _) {
              final state = _searchController.state;
              final showRecent = !searching;
              final isSearching = state.status == StationSearchStatus.loading;
              // 최근 검색만 SafeArea(좌우)·패딩. 검색 결과는 가장자리까지.
              return ListView(
                padding: searching
                    ? EdgeInsets.zero
                    : const EdgeInsets.fromLTRB(16, 4, 16, 16),
                children: [
                  if (showRecent && _searchRecentEntriesReady)
                    StationRecentSearchSection(
                      entries: _searchRecentEntries,
                      enabled: !isSearching,
                      onStationSelected: _searchRecentStationSelected,
                      onRouteSelected: _searchRecentRouteSelected,
                      onRemove: (entry) =>
                          unawaited(_removeSearchRecentEntry(entry)),
                      onClearAll: () =>
                          unawaited(_clearAllSearchRecentEntries()),
                    ),
                  StationSearchBody(
                    state: state,
                    query: _highlightQuery,
                    favoriteKeys: _favoriteKeys,
                    onResultTap: widget.onResultFocus,
                    onToggleFavorite: widget.favoriteRepository == null
                        ? null
                        : _toggleFavoriteStation,
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

enum _NetworkMapNearbyPanelStatus { idle, loading, success }

enum _NearbyPanelDataSource { realtime, timetable }

/// 성공한 실시간 스냅샷의 keyed display cache(#2453 Task 4).
class _NearbyRealtimeDisplay {
  const _NearbyRealtimeDisplay({
    required this.stationId,
    required this.lineId,
    required this.snapshot,
  });

  final String stationId;
  final String lineId;
  final RealtimeSnapshot snapshot;
}

/// 성공한 시간표의 keyed display cache(#2453 Task 4).
class _NearbyTimetableDisplay {
  const _NearbyTimetableDisplay({
    required this.stationId,
    required this.lineId,
    required this.timetable,
  });

  final String stationId;
  final String lineId;
  final StationTimetable timetable;
}

class _NetworkMapNearbyPanelData {
  const _NetworkMapNearbyPanelData._({
    required this.status,
    this.results = const [],
  });

  const _NetworkMapNearbyPanelData.idle()
    : this._(status: _NetworkMapNearbyPanelStatus.idle);

  const _NetworkMapNearbyPanelData.loading()
    : this._(status: _NetworkMapNearbyPanelStatus.loading);

  const _NetworkMapNearbyPanelData.success(List<StationSearchResult> results)
    : this._(status: _NetworkMapNearbyPanelStatus.success, results: results);

  final _NetworkMapNearbyPanelStatus status;
  final List<StationSearchResult> results;
}

StationDetailNeighbor? _stationDetailNeighbor(
  NearbyAdjacentStationIdentity? identity,
) {
  if (identity == null) {
    return null;
  }
  return StationDetailNeighbor(
    stationId: identity.stationId,
    nameKo: identity.nameKo,
  );
}

class _NetworkMapNearbyStationPanel extends StatelessWidget {
  const _NetworkMapNearbyStationPanel({
    required this.data,
    required this.expanded,
    required this.realtime,
    required this.selectedLineId,
    required this.dataSource,
    required this.timetable,
    required this.adjacentStations,
    required this.onClose,
    required this.onLineSelected,
    required this.onDataSourceToggle,
    this.onOpenStationDetail,
    this.onSelectNeighbor,
    this.stationSearchRepository,
    this.reportRepository,
    this.favoriteRepository,
    this.adRepository,
    this.realtimeRepository,
    this.locationProvider,
    this.facilityReportDraftTargetStore,
    this.internalRouteRepository,
    this.internalRouteMobilityType = 'SENIOR',
    this.routeDraftController,
  });

  final _NetworkMapNearbyPanelData data;
  final bool expanded;
  final RealtimeSnapshot realtime;
  final String? selectedLineId;
  final _NearbyPanelDataSource dataSource;
  final StationTimetable? timetable;
  final NearbyAdjacentStations adjacentStations;
  final VoidCallback onClose;
  final ValueChanged<StationSearchLine> onLineSelected;
  final VoidCallback onDataSourceToggle;
  final VoidCallback? onOpenStationDetail;
  final ValueChanged<StationDetailNeighbor>? onSelectNeighbor;
  final StationSearchRepository? stationSearchRepository;
  final FacilityReportRepository? reportRepository;
  final FavoriteStationRepository? favoriteRepository;
  final AdRepository? adRepository;
  final RealtimeRepository? realtimeRepository;
  final CurrentLocationProvider? locationProvider;
  final FacilityReportDraftTargetStore? facilityReportDraftTargetStore;
  final InternalRouteRepository? internalRouteRepository;
  final String internalRouteMobilityType;
  final RouteDraftController? routeDraftController;

  @override
  Widget build(BuildContext context) {
    final primary = data.results.isEmpty ? null : data.results.first;
    final dataSourceToggleEnabled = !(primary?.lines.isEmpty ?? true);
    final selectedLine = primary == null
        ? null
        : _nearbySelectedLine(primary, selectedLineId);
    final canExpandDetail =
        expanded &&
        primary != null &&
        stationSearchRepository != null &&
        reportRepository != null;

    final panel = SafeArea(
      top: expanded,
      bottom: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: EasySubwayAccessibleColors.surfaceDefault,
          border: expanded
              ? null
              : const Border(
                  top: BorderSide(
                    color: EasySubwayAccessibleColors.borderSubtle,
                  ),
                ),
        ),
        child: Column(
          mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
          children: [
            SizedBox(
              height: 52,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const SizedBox(width: 14),
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final line
                              in primary?.lines ?? const <StationSearchLine>[])
                            Padding(
                              padding: const EdgeInsets.only(bottom: 2),
                              child: StationLineBadgeTab(
                                line: line,
                                selected: line.id == selectedLineId,
                                onTap: () => onLineSelected(line),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: NearbyDataSourceToggle(
                      isRealtime: dataSource == _NearbyPanelDataSource.realtime,
                      enabled: dataSourceToggleEnabled,
                      onToggle: onDataSourceToggle,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: IconButton(
                      key: const Key('networkMapNearbyPanelCloseButton'),
                      tooltip: '닫기',
                      onPressed: onClose,
                      constraints: const BoxConstraints.tightFor(
                        width: 48,
                        height: 48,
                      ),
                      padding: EdgeInsets.zero,
                      icon: const Icon(
                        Icons.close,
                        color: EasySubwayAccessibleColors.contentPrimary,
                        size: 27,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
              ),
            ),
            const Divider(
              height: 1,
              color: EasySubwayAccessibleColors.borderSubtle,
            ),
            // 접힘·확장 모두 실시간/시간표 요약을 유지한다. 확장에서 Body로
            // 갈아끼우면 이미 뜬 열차 정보가 실패 카드로 사라진다.
            _NetworkMapNearbyPanelBody(
              data: data,
              realtime: realtime,
              selectedLineId: selectedLineId,
              dataSource: dataSource,
              timetable: timetable,
              adjacentStations: adjacentStations,
              onOpenStationDetail: canExpandDetail ? null : onOpenStationDetail,
              onSelectNeighbor: onSelectNeighbor,
            ),
            if (canExpandDetail) ...[
              const Divider(
                height: 1,
                color: EasySubwayAccessibleColors.borderSubtle,
              ),
              Expanded(
                child: StationDetailExpandHost(
                  key: ValueKey('nearbyStationDetailHost-${primary.id}'),
                  repository: stationSearchRepository!,
                  reportRepository: reportRepository!,
                  favoriteRepository: favoriteRepository,
                  adRepository: adRepository,
                  realtimeRepository: realtimeRepository,
                  locationProvider: locationProvider,
                  stationId: primary.id,
                  facilityReportDraftTargetStore:
                      facilityReportDraftTargetStore,
                  internalRouteRepository: internalRouteRepository,
                  internalRouteMobilityType: internalRouteMobilityType,
                  routeDraftController: routeDraftController,
                  // 상단 호선바·실시간/시간표가 맥락·열차를 담당한다.
                  showContextChrome: false,
                  showRealtimeSection: false,
                  onClose: null,
                  previousStation: _stationDetailNeighbor(
                    adjacentStations.previousNeighbor,
                  ),
                  nextStation: _stationDetailNeighbor(
                    adjacentStations.nextNeighbor,
                  ),
                  onSelectNeighbor: onSelectNeighbor,
                  lineForChrome: selectedLine,
                ),
              ),
            ],
          ],
        ),
      ),
    );

    return Material(
      key: const Key('networkMapNearbyStationPanel'),
      color: EasySubwayAccessibleColors.surfaceDefault,
      elevation: 0,
      child: expanded
          ? SizedBox.expand(
              key: const Key('networkMapNearbyStationPanelExpanded'),
              child: panel,
            )
          : panel,
    );
  }
}

class _NetworkMapNearbyPanelBody extends StatelessWidget {
  const _NetworkMapNearbyPanelBody({
    required this.data,
    required this.realtime,
    required this.selectedLineId,
    required this.dataSource,
    required this.timetable,
    required this.adjacentStations,
    this.onOpenStationDetail,
    this.onSelectNeighbor,
  });

  final _NetworkMapNearbyPanelData data;
  final RealtimeSnapshot realtime;
  final String? selectedLineId;
  final _NearbyPanelDataSource dataSource;
  final StationTimetable? timetable;
  final NearbyAdjacentStations adjacentStations;
  final VoidCallback? onOpenStationDetail;
  final ValueChanged<StationDetailNeighbor>? onSelectNeighbor;

  @override
  Widget build(BuildContext context) {
    return switch (data.status) {
      _NetworkMapNearbyPanelStatus.idle ||
      _NetworkMapNearbyPanelStatus.loading => const SizedBox(
        height: 132,
        child: Center(child: CircularProgressIndicator()),
      ),
      _NetworkMapNearbyPanelStatus.success => _NetworkMapNearbySuccessList(
        results: data.results,
        realtime: realtime,
        selectedLineId: selectedLineId,
        dataSource: dataSource,
        timetable: timetable,
        adjacentStations: adjacentStations,
        onOpenStationDetail: onOpenStationDetail,
        onSelectNeighbor: onSelectNeighbor,
      ),
    };
  }
}

/// 주변역 패널의 선택 노선색 단일 소스. 카탈로그 색을 우선하고 값이 없으면
/// 노선 이름·식별자 폴백을 쓴다(2호선 = #00A84D).
Color _nearbySelectedLineColor(StationSearchLine? line) {
  if (line == null) {
    return stationLineColor(stationLineFallbackBrandHex);
  }
  final raw = line.color.trim();
  if (raw.isEmpty) {
    return stationLineColor(
      fallbackLineColorHex(lineId: line.id, lineName: line.name),
    );
  }
  return stationLineColor(raw);
}

StationSearchLine? _nearbySelectedLine(
  StationSearchResult primary,
  String? selectedLineId,
) {
  if (primary.lines.isEmpty) {
    return null;
  }
  for (final line in primary.lines) {
    if (line.id == selectedLineId) {
      return line;
    }
  }
  return primary.lines.first;
}

class _NetworkMapNearbySuccessList extends StatelessWidget {
  const _NetworkMapNearbySuccessList({
    required this.results,
    required this.realtime,
    required this.selectedLineId,
    required this.dataSource,
    required this.timetable,
    required this.adjacentStations,
    this.onOpenStationDetail,
    this.onSelectNeighbor,
  });

  final List<StationSearchResult> results;
  final RealtimeSnapshot realtime;
  final String? selectedLineId;
  final _NearbyPanelDataSource dataSource;
  final StationTimetable? timetable;
  final NearbyAdjacentStations adjacentStations;
  final VoidCallback? onOpenStationDetail;
  final ValueChanged<StationDetailNeighbor>? onSelectNeighbor;

  @override
  Widget build(BuildContext context) {
    final primary = results.first;
    final selectedLine = _nearbySelectedLine(primary, selectedLineId);
    final lineColor = _nearbySelectedLineColor(selectedLine);
    final selectNeighbor = onSelectNeighbor;
    final previous = _stationDetailNeighbor(adjacentStations.previousNeighbor);
    final next = _stationDetailNeighbor(adjacentStations.nextNeighbor);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        NearbyStationLineBar(
          leftName: adjacentStations.leftName,
          rightName: adjacentStations.rightName,
          stationName: primary.nameKo,
          badgeText: selectedLine?.badgeText ?? '',
          lineColor: lineColor,
          onStationNameTap: onOpenStationDetail,
          onLeftNameTap: selectNeighbor == null || previous == null
              ? null
              : () => selectNeighbor(previous),
          onRightNameTap: selectNeighbor == null || next == null
              ? null
              : () => selectNeighbor(next),
        ),
        const SizedBox(height: 17),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
          child: dataSource == _NearbyPanelDataSource.realtime
              ? NearbyArrivalPanel(
                  data: NearbyArrivalPanelData(
                    status: switch (realtime.status) {
                      RealtimeSnapshotStatus.fresh =>
                        NearbyArrivalPanelStatus.fresh,
                      RealtimeSnapshotStatus.stale =>
                        NearbyArrivalPanelStatus.stale,
                      _ => NearbyArrivalPanelStatus.unavailable,
                    },
                    receivedAt: realtime.receivedAt,
                    arrivals: [
                      for (final arrival in realtime.arrivals)
                        NearbyArrivalData(
                          direction: arrival.direction,
                          destination: arrival.destination,
                          etaSeconds: arrival.etaSeconds,
                          message: arrival.message,
                        ),
                    ],
                  ),
                  lineColor: lineColor,
                  leftName: adjacentStations.leftName,
                  rightName: adjacentStations.rightName,
                )
              : NearbyTimetablePanel(
                  data: _nearbyTimetablePanelData(timetable),
                  lineColor: lineColor,
                  leftName: adjacentStations.leftName,
                  rightName: adjacentStations.rightName,
                  expressBadgeBuilder: () =>
                      const ServicePatternBadge.express(),
                ),
        ),
      ],
    );
  }
}

NearbyTimetablePanelData? _nearbyTimetablePanelData(
  StationTimetable? timetable,
) {
  if (timetable == null) {
    return null;
  }
  return NearbyTimetablePanelData(
    directions: [
      for (final direction in timetable.directions)
        NearbyTimetableDirectionData(
          name: direction.name,
          departures: [
            for (final departure in direction.departures)
              NearbyTimetableDepartureData(
                directionName: departure.directionName,
                seconds: departure.seconds,
                timeLabel: departure.timeLabel,
                semanticLabel: departure.semanticLabel,
                isExpress: departure.isExpress,
              ),
          ],
        ),
    ],
  );
}

class _NetworkMapCanvas extends StatefulWidget {
  const _NetworkMapCanvas({
    required this.data,
    required this.initialViewport,
    required this.focusedStationId,
    required this.preserveFocusedStationScale,
    required this.selectedStationId,
    required this.selectionClearRevision,
    required this.onSetOrigin,
    required this.onSetWaypoint,
    required this.onSetDestination,
    required this.onClearOrigin,
    required this.onClearWaypoint,
    required this.onClearDestination,
    required this.onViewportChanged,
    required this.onSelectionDismissed,
    required this.onStationTapped,
    this.originStationId,
    this.waypointStationId,
    this.destinationStationId,
  });

  final NetworkMapData data;
  final Rect? initialViewport;
  final String? focusedStationId;
  final bool preserveFocusedStationScale;
  final String? selectedStationId;
  final int selectionClearRevision;

  /// #1948: draft 핀을 그릴 지정 역 id (없으면 null).
  final String? originStationId;
  final String? waypointStationId;
  final String? destinationStationId;

  final ValueChanged<NetworkMapStation> onSetOrigin;
  final ValueChanged<NetworkMapStation> onSetWaypoint;
  final ValueChanged<NetworkMapStation> onSetDestination;

  /// #2109: 팬 메뉴에서 이미 지정된 슬롯을 재탭하면 해당 슬롯을 비운다. clear는
  /// 슬롯 단위라 역 인자가 불필요(컨트롤러가 슬롯을 비운다).
  final VoidCallback onClearOrigin;
  final VoidCallback onClearWaypoint;
  final VoidCallback onClearDestination;
  final ValueChanged<Rect> onViewportChanged;

  /// #2109 팬 메뉴가 부모(검색 결과 탭 등)에서 [selectedStationId]로 열린 경우,
  /// 메뉴가 닫힐 때(액션 선택·닫기·배경 탭) 부모의 선택 상태도 비워야 한다.
  /// 내부 [_selectedStation]만 null로 두면 prop이 다시 메뉴를 띄운다.
  final VoidCallback onSelectionDismissed;

  /// #2200 캔버스에서 역 노드를 탭하면(팬 메뉴 표시와 동시에) 부모가 그 역을
  /// 해석해 하단 역 정보 패널을 함께 열도록 통지한다. 검색·focus 채널로 열린
  /// 팬 메뉴([selectedStationId] prop 경로)는 이 콜백을 태우지 않는다.
  final ValueChanged<NetworkMapStation> onStationTapped;

  @override
  State<_NetworkMapCanvas> createState() => _NetworkMapCanvasState();
}

/// #1643 성능 QA: 노선도 프레임의 build/raster/total 시간을 logcat에 기록한다.
/// run-route-map-android-evidence.sh가 'routeMapFrame' 라인을 grep해 jank·P90를
/// 산출한다(Flutter는 dumpsys gfxinfo로 프레임이 안 잡혀 FrameTiming으로 계측).
void _logRouteMapFrameTimings(List<FrameTiming> timings) {
  for (final timing in timings) {
    final buildMs = timing.buildDuration.inMicroseconds / 1000.0;
    final rasterMs = timing.rasterDuration.inMicroseconds / 1000.0;
    final totalMs = timing.totalSpan.inMicroseconds / 1000.0;
    // debugPrint는 throttle(debugPrintThrottled)이라 pan 중 다량의 프레임 로그를
    // 큐잉·드롭해 janky burst 구간을 undercount할 수 있다(jank% 하향 편향). 측정
    // 정확도를 위해 unthrottled synchronous 출력으로 모든 프레임을 남긴다.
    debugPrintSynchronously(
      'routeMapFrame '
      'buildMs=${buildMs.toStringAsFixed(2)} '
      'rasterMs=${rasterMs.toStringAsFixed(2)} '
      'totalMs=${totalMs.toStringAsFixed(2)}',
    );
  }
}

class _NetworkMapCanvasState extends State<_NetworkMapCanvas>
    with WidgetsBindingObserver {
  String? _layoutKey;
  String? _layoutRegion;
  MapCameraState? _camera;
  MapCameraState? _pendingCamera;
  MapCameraState? _requestedRendererCamera;
  MapCameraState? _presentedRendererCamera;
  final _requestedRendererCamerasByRevision = <int, MapCameraState>{};
  bool _routeMapRendererActive = false;
  bool _routeMapBasemapFailed = false;
  DateTime? _lastRendererCameraRequestAt;
  bool _cameraFrameCallbackScheduled = false;
  bool _forceRendererCameraCommit = false;
  bool _gestureActive = false;
  (String, bool)? _cameraFocusedStationKey;
  MapCameraState? _gestureStartCamera;
  Offset? _gestureStartFocalPoint;
  String? _geometryCacheKey;
  _MapGeometry? _geometryCache;
  // 구조화 canvas 렌더러(#1641) 파생 데이터 캐시 — region 단위로 재계산.
  String? _structuredCacheKey;
  StructuredRouteMap? _structuredRouteMapCache;
  Map<String, Color>? _structuredLineColorsCache;
  Map<String, String>? _structuredLabelTextCache;
  Map<String, String>? _structuredLineBadgeLabelCache;
  // 팬 메뉴 환승 앵커(#2192): 렌더 캡슐 중심 유도에 쓰는 파생값. structured 캐시와
  // 같은 키로 무효화한다. designScale은 렌더러 모드 판정과 동일 값이어야 한다.
  double? _structuredDesignScaleCache;
  Map<String, RouteMapTransferGroup>? _structuredTransferGroupCache;
  NetworkMapStation? _selectedStation;
  // region → attribution 표시 문자열(#1951). manifest 로드 전에는 null로 두고
  // attribution을 표시하지 않는다(로드 실패 시에도 동일하게 조용히 미표기).
  Map<String, String>? _attributionTextByRegion;
  // basemap 6차(#2068): asset id(seoul/busan/...) → station명 → 오너 라벨 앵커.
  // 소비처는 (1) geometry bounds 확장(networkMapOwnerLabelSourceRects — 라벨까지
  // 담아 탭 히트·팬 한계를 맞춘다)과 (2) 초기 카메라 가독 배율뿐이다. 라벨 렌더는
  // canonical SVG 바탕층이 담당한다(#2068 SVG 충실도). 로드 전·실패 시 null →
  // 두 소비처 모두 기존(라벨 미반영) 동작으로 안전 폴백한다.
  Map<String, Map<String, List<RouteMapOwnerLabelEntry>>>? _ownerLabelsByRegion;
  // 초기 카메라 가독 배율(#2068 트랙 QA 후속) 캐시 — _readableInitialMapScaleFor.
  double? _readableInitialMapScaleCache;
  String? _readableInitialMapScaleCacheKey;
  // onTapUp 경로에서만 쓰는 stationLinesById를 매 build(팬 프레임)마다 재계산하지 않도록
  // region·stations identity로 캐시한다(#1973). 800역/24노선 재계산이 build 스파이크 원인.
  Map<String, List<NetworkMapLine>>? _stationLinesByIdCache;
  String? _stationLinesByIdCacheKey;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // #1643 성능 QA: 노선도가 떠 있는 동안 프레임 build/raster 시간을 logcat에
    // 기록한다. 구조화 canvas는 Flutter 자체 렌더 파이프라인이라 dumpsys gfxinfo로
    // 프레임이 잡히지 않으므로 FrameTiming으로 계측한다. release에는 넣지 않는다.
    if (!kReleaseMode) {
      SchedulerBinding.instance.addTimingsCallback(_logRouteMapFrameTimings);
    }
    unawaited(_loadAttributionText());
    // #2068 트랙 QA 후속: 초기 카메라 가독 배율이 sidecar에 의존하므로, 이미
    // 해석된 값이 있으면 **첫 build 전에 동기로** 시드해 과축소 → 확대 줌 팝을
    // 없앤다. 값이 없을 때만 비동기 로드를 태운다(선행 로드가 아직 끝나지 않은
    // 경합 케이스 — 도착하면 setState로 카메라가 한 번 재계산된다).
    _ownerLabelsByRegion = cachedNetworkMapOwnerLabelsByRegion;
    if (_ownerLabelsByRegion == null) {
      unawaited(_loadOwnerLabels());
    }
  }

  Future<void> _loadAttributionText() async {
    try {
      final byRegion = await loadNetworkMapAttributionTextByRegion();
      if (!mounted) {
        return;
      }
      setState(() => _attributionTextByRegion = byRegion);
    } catch (error, stackTrace) {
      // asset 로드/파싱 실패는 attribution 미표기로 폴백한다(#1951). 일시 오류가
      // 영구 미표기로 고정되지 않도록 실패한 Future는 캐시에서 비워 다음 마운트
      // 때 재시도되게 한다 — 화면은 죽지 않되, 원인 파악을 위해 예외는 리포터로
      // 남긴다.
      resetNetworkMapAttributionCache();
      reportMobileError(
        error,
        stackTrace,
        context: '지도 datapack manifest에서 attribution 정보를 불러오는 중 예외가 발생했습니다.',
      );
    }
  }

  Future<void> _loadOwnerLabels() async {
    try {
      final byRegion = await loadNetworkMapOwnerLabelsByRegion();
      if (!mounted) {
        return;
      }
      setState(() => _ownerLabelsByRegion = byRegion);
    } catch (error, stackTrace) {
      // #2068 6차: 로드/파싱 실패는 basemap 라벨의 4차 자동 솔버 폴백으로
      // 안전 처리한다(크래시 금지). 재시도를 위해 캐시를 비운다.
      invalidateNetworkMapOwnerLabelsLoad();
      reportMobileError(
        error,
        stackTrace,
        context: '노선도 오너 라벨 sidecar를 불러오는 중 예외가 발생했습니다.',
      );
    }
  }

  @override
  void dispose() {
    if (!kReleaseMode) {
      SchedulerBinding.instance.removeTimingsCallback(_logRouteMapFrameTimings);
    }
    WidgetsBinding.instance.removeObserver(this);
    _pendingCamera = null;
    super.dispose();
  }

  /// #2109 Fix: 검색 채널(인플레이스 `_focusStationFromSearch` + 풀페이지
  /// `focusStationRequestId` 소비)로 팬 메뉴가 [selectedStationId] prop을 통해
  /// 열릴 때도, 지도 탭(`_selectStation`)과 동일하게 화면 경계에서 메뉴가 잘리면
  /// 카메라를 최소 패닝해 전부 노출한다. prop이 null→역 id로 전이하는 순간을
  /// 감지해 카메라 focus가 확정되는 다음 프레임에 패닝을 예약한다.
  @override
  void didUpdateWidget(covariant _NetworkMapCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectionClearRevision != oldWidget.selectionClearRevision) {
      _selectedStation = null;
    }
    final selectedId = widget.selectedStationId;
    if (selectedId != null && selectedId != oldWidget.selectedStationId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || widget.selectedStationId != selectedId) {
          return;
        }
        final station = networkMapStationById(widget.data.stations, selectedId);
        if (station != null) {
          _panCameraToRevealFanMenu(station);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('networkMapSurface'),
      decoration: const BoxDecoration(
        color: EasySubwayAccessibleColors.surfaceDefault,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final geometry = _geometryFor(widget.data);
          final fullBounds = Rect.fromLTWH(
            0,
            0,
            geometry.width,
            geometry.height,
          );
          // #2068 트랙 QA 후속: 저장 viewport가 없을 때의 초기 카메라는
          // 콘텐츠 중앙을 오너 라벨이 읽히는 배율로 연다. 오너 라벨 sidecar는
          // 비동기 로드라 로드 전후로 가독 배율이 바뀌므로 layoutKey에 포함해
          // 로드 완료 시 초기 카메라가 다시 계산되게 한다.
          final readableScale = _readableInitialMapScaleFor(widget.data);
          final initialCameraBounds = networkMapInitialCameraBounds(
            fullBounds: fullBounds,
            regionInitialBounds: geometry.initialBounds,
            viewport: Size(
              constraints.hasBoundedWidth ? constraints.maxWidth : 0,
              constraints.hasBoundedHeight ? constraints.maxHeight : 0,
            ),
            readableScale: readableScale,
          );
          // 축소 하한(#2600)은 초기 화면 배율로 캡해 첫 화면을 절대 확대하지
          // 않게 한다 — sidecar 미로드 프레임처럼 초기 배율이 하한보다 낮은
          // 상태가 있고, 거기서 밀어올리면 #1764 E·#2062 계약이 깨진다.
          final minScale = networkMapMinimumScaleForRegion(
            widget.data.selectedRegion,
            initialFitScale: networkMapContainFitScale(
              initialCameraBounds,
              constraints,
            ),
          );
          final initialCamera = networkMapCameraForBounds(
            widget.initialViewport ?? initialCameraBounds,
            constraints,
            sourceBounds: fullBounds,
            contain: true,
            minScale: minScale,
          );
          final layoutKey =
              '${widget.data.selectedRegion}:${geometry.width}:${geometry.height}:${constraints.maxWidth}:${constraints.maxHeight}:$readableScale';
          if (_layoutKey != layoutKey) {
            final previousCamera = _camera;
            final preserveCamera =
                widget.preserveFocusedStationScale &&
                widget.focusedStationId != null &&
                _layoutRegion == widget.data.selectedRegion &&
                previousCamera != null;
            _layoutKey = layoutKey;
            _layoutRegion = widget.data.selectedRegion;
            _routeMapBasemapFailed = false;
            _pendingCamera = null;
            _requestedRendererCamera = null;
            _presentedRendererCamera = null;
            _requestedRendererCamerasByRevision.clear();
            _routeMapRendererActive = widget.data.stations.isNotEmpty;
            _gestureActive = false;
            _cameraFocusedStationKey = null;
            _camera = preserveCamera
                ? previousCamera
                      .copyWith(
                        sourceBounds: fullBounds,
                        viewportSize: Size(
                          constraints.hasBoundedWidth
                              ? constraints.maxWidth
                              : 0,
                          constraints.hasBoundedHeight
                              ? constraints.maxHeight
                              : 0,
                        ),
                        minScale: math.min(previousCamera.scale, minScale),
                        initialScale: initialCamera.initialScale,
                        revision: previousCamera.revision + 1,
                      )
                      .clamped(viewportMargin: 220)
                : initialCamera;
          }
          // 같은 build에서 새 layoutKey의 카메라를 항상 초기화한다.
          var camera = _camera!;
          final selectedStation =
              networkMapStationByIdentity(
                widget.data.stations,
                _selectedStation,
              ) ??
              networkMapStationById(
                widget.data.stations,
                widget.selectedStationId,
              );
          final originStation = networkMapStationById(
            widget.data.stations,
            widget.originStationId,
          );
          final waypointStation = networkMapStationById(
            widget.data.stations,
            widget.waypointStationId,
          );
          final destinationStation = networkMapStationById(
            widget.data.stations,
            widget.destinationStationId,
          );
          final focusedStation = widget.focusedStationId == null
              ? null
              : networkMapStationById(
                  widget.data.stations,
                  widget.focusedStationId,
                );
          final focusedStationKey = focusedStation == null
              ? null
              : (focusedStation.id, widget.preserveFocusedStationScale);
          if (!_gestureActive &&
              focusedStation != null &&
              _cameraFocusedStationKey != focusedStationKey) {
            final focusedCamera = widget.preserveFocusedStationScale
                ? camera
                      .copyWith(
                        center: Offset(
                          geometry.x(focusedStation),
                          geometry.y(focusedStation),
                        ),
                        revision: camera.revision + 1,
                      )
                      .clamped(viewportMargin: 220)
                : networkMapCameraForBounds(
                    _stationFocusBoundsFor(
                      focusedStation,
                      geometry,
                      initialBounds: initialCameraBounds,
                    ),
                    constraints,
                    sourceBounds: fullBounds,
                    contain: true,
                    minScale: minScale,
                    revision: camera.revision + 1,
                    // 역 focus 후에도 LOD 기준은 지역 초기 화면 baseline을 유지한다.
                    initialScaleOverride: camera.initialScale,
                  );
            _cameraFocusedStationKey = focusedStationKey;
            _pendingCamera = null;
            _camera = focusedCamera;
            _requestedRendererCamera = focusedCamera;
            _requestedRendererCamerasByRevision
              ..clear()
              ..[focusedCamera.revision] = focusedCamera;
            camera = focusedCamera;
            widget.onViewportChanged(focusedCamera.visibleSourceRect);
          } else if (focusedStation == null) {
            _cameraFocusedStationKey = null;
          }
          if (_routeMapBasemapFailed || !_routeMapRendererActive) {
            return const OriginalRouteMapUnavailable();
          }
          final presentedRendererCamera = _presentedRendererCamera;
          final interactionCamera = presentedRendererCamera == null
              ? null
              : networkMapRendererTransformVisualCamera(
                  rendererCamera: presentedRendererCamera,
                  visualCamera: camera,
                );
          final gestureCamera = interactionCamera;
          return Stack(
            children: [
              Positioned.fill(
                child: _buildStructuredRouteMapCanvas(camera, geometry.origin),
              ),
              if (gestureCamera != null)
                Positioned.fill(
                  child: Semantics(
                    label: '노선도',
                    hint: '역을 누르면 출발, 도착, 역 정보 action을 볼 수 있어요',
                    child: Listener(
                      onPointerCancel: (_) => _endScaleGesture(),
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onScaleStart: (details) {
                          if (!_gestureActive) {
                            setState(() {
                              _gestureActive = true;
                              _clearSelectionAndNotify();
                            });
                          }
                          _gestureStartCamera = gestureCamera;
                          _gestureStartFocalPoint = details.localFocalPoint;
                        },
                        onScaleUpdate: (details) {
                          _updateCameraForGesture(details);
                        },
                        onScaleEnd: (_) {
                          _endScaleGesture();
                        },
                        onTapUp: interactionCamera == null
                            ? null
                            : (details) {
                                _openNearestStation(
                                  details.localPosition,
                                  _stationLinesByIdCached(widget.data),
                                  geometry,
                                  interactionCamera,
                                );
                              },
                      ),
                    ),
                  ),
                ),
              if (interactionCamera != null && !_gestureActive)
                for (final station in _visibleCanonicalStations(
                  geometry: geometry,
                  camera: interactionCamera,
                ))
                  Positioned.fromRect(
                    rect: _sourceRectToViewport(
                      _stationHitRect(
                        station,
                        geometry,
                        nodeRadius: 24 / interactionCamera.scale,
                        labelHeight: 40 / interactionCamera.scale,
                      ),
                      interactionCamera,
                    ),
                    child: NetworkMapStationHitTarget(
                      key: Key(
                        'networkMapStation-${station.id.replaceFirst('station-', '')}-${station.lineId}',
                      ),
                      station: station,
                      onTap: () => _selectStation(station),
                    ),
                  ),
              // 드래프트 핀은 줌/팬 중에도 유지한다(역 hit·팬 메뉴와 달리 상태
              // 표시). Positioned는 Stack 직접 자식이어야 하므로, 제스처 중
              // 포인터 통과는 핀 위젯 내부 IgnorePointer로 처리한다.
              if (interactionCamera != null && originStation != null)
                _NetworkMapDraftPin(
                  key: const Key('networkMapDraftPin-origin'),
                  station: originStation,
                  // 환승역은 캡슐 중심, 일반역은 노드 중심(팬 메뉴와 동일 앵커).
                  anchorSource: _fanMenuAnchorSource(originStation, geometry),
                  camera: interactionCamera,
                  label: '출발',
                  surfaceColor: EasySubwayFanMenuColors.departure,
                  semanticSuffix: '출발 지정됨',
                  clearButtonKey: const Key('networkMapDraftPinClear-origin'),
                  ignorePointers: _gestureActive,
                  onClear: widget.onClearOrigin,
                ),
              if (interactionCamera != null && waypointStation != null)
                _NetworkMapDraftPin(
                  key: const Key('networkMapDraftPin-waypoint'),
                  station: waypointStation,
                  anchorSource: _fanMenuAnchorSource(waypointStation, geometry),
                  camera: interactionCamera,
                  label: '경유',
                  surfaceColor: EasySubwayFanMenuColors.waypoint,
                  semanticSuffix: '경유 지정됨',
                  clearButtonKey: const Key('networkMapDraftPinClear-waypoint'),
                  ignorePointers: _gestureActive,
                  onClear: widget.onClearWaypoint,
                ),
              if (interactionCamera != null && destinationStation != null)
                _NetworkMapDraftPin(
                  key: const Key('networkMapDraftPin-destination'),
                  station: destinationStation,
                  anchorSource: _fanMenuAnchorSource(
                    destinationStation,
                    geometry,
                  ),
                  camera: interactionCamera,
                  label: '도착',
                  surfaceColor: EasySubwayFanMenuColors.arrival,
                  semanticSuffix: '도착 지정됨',
                  clearButtonKey: const Key(
                    'networkMapDraftPinClear-destination',
                  ),
                  ignorePointers: _gestureActive,
                  onClear: widget.onClearDestination,
                ),
              if (interactionCamera != null &&
                  !_gestureActive &&
                  selectedStation != null)
                Builder(
                  builder: (context) {
                    final stationPoint = interactionCamera
                        .sourceToViewportPoint(
                          _fanMenuTailAnchorSource(selectedStation, geometry),
                        );
                    // #2109: 배치 규칙은 fanMenuPlacement 단일 함수가 소유한다
                    // (카메라 최소 패닝 _panCameraToRevealFanMenu와 동일 규칙 소비).
                    final placement = fanMenuPlacement(
                      stationPoint: stationPoint,
                      viewport: Size(
                        constraints.maxWidth,
                        constraints.maxHeight,
                      ),
                      clampPosition: true,
                    );
                    final left = placement.left;
                    final menuWidth = placement.menuWidth;
                    final top = placement.top;
                    final selectedSlots = fanMenuSelectedSlots(
                      stationId: selectedStation.id,
                      originStationId: widget.originStationId,
                      waypointStationId: widget.waypointStationId,
                      destinationStationId: widget.destinationStationId,
                    );
                    return Positioned(
                      key: const Key('networkMapStationSheet'),
                      left: left,
                      top: top,
                      width: menuWidth,
                      child: StationFanMenu(
                        width: menuWidth,
                        selectedSlots: selectedSlots,
                        disabledSlots: fanMenuDisabledSlots(
                          stationId: selectedStation.id,
                          originStationId: widget.originStationId,
                          waypointStationId: widget.waypointStationId,
                          destinationStationId: widget.destinationStationId,
                        ),
                        onAction: (slot) {
                          if (fanMenuShouldClear(slot, selectedSlots)) {
                            // 재탭 → 해당 슬롯 해제.
                            switch (slot) {
                              case RouteDraftSlot.origin:
                                widget.onClearOrigin();
                              case RouteDraftSlot.waypoint:
                                widget.onClearWaypoint();
                              case RouteDraftSlot.destination:
                                widget.onClearDestination();
                            }
                          } else {
                            switch (slot) {
                              case RouteDraftSlot.origin:
                                widget.onSetOrigin(selectedStation);
                              case RouteDraftSlot.waypoint:
                                widget.onSetWaypoint(selectedStation);
                              case RouteDraftSlot.destination:
                                widget.onSetDestination(selectedStation);
                            }
                          }
                          _dismissSelection();
                        },
                        onClose: _dismissSelection,
                      ),
                    );
                  },
                ),
            ],
          );
        },
      ),
    );
  }

  Map<String, List<NetworkMapLine>> _stationLinesByIdCached(
    NetworkMapData data,
  ) {
    final key =
        '${data.selectedRegion}:${identityHashCode(data.stations)}:${data.stations.length}';
    final cached = _stationLinesByIdCache;
    if (_stationLinesByIdCacheKey == key && cached != null) {
      return cached;
    }
    final computed = networkMapStationLinesById(data);
    _stationLinesByIdCacheKey = key;
    _stationLinesByIdCache = computed;
    return computed;
  }

  _MapGeometry _geometryFor(NetworkMapData data) {
    // basemap 오너 라벨 sidecar(로드는 async)를 geometry bounds에 반영한다(#2068).
    // 로드 전엔 null → 라벨 rect 없이 계산되지만, 로드가 끝나면 setState로 rebuild
    // 되며 ownerKey가 바뀌어 캐시가 무효화되고 라벨 extents를 포함해 재계산된다
    // (stale bounds 방지 — sidecar 로드 전/후 캐시 키 구분).
    //
    // data.selectedRegion은 drift_station_repository._storedNetworkMapRegion이
    // 만든 저장형('광주권' 등 접미 포함)이라 kRouteMapBasemapRegionToId의 짧은
    // 키('광주')와 직접 안 맞는다 — _displayRegionName으로 정규화해야 조회가
    // 성공한다(실기기 회귀: 정규화 누락으로 basemapAssetId가 항상 null이 돼
    // 라벨이 bounds에 전혀 반영되지 않았다, #2068).
    final basemapAssetId =
        kRouteMapBasemapRegionToId[_displayRegionName(data.selectedRegion)];
    final ownerEntries = basemapAssetId == null
        ? null
        : _ownerLabelsByRegion?[basemapAssetId];
    final ownerKey = ownerEntries == null
        ? 'none'
        : 'owner:${ownerEntries.length}';
    final cacheKey =
        'generated:${data.selectedRegion}:${identityHashCode(data.stations)}:${data.stations.length}:$ownerKey';
    final cached = _geometryCache;
    if (_geometryCacheKey == cacheKey && cached != null) {
      return cached;
    }
    final ownerLabelSourceRects = ownerEntries == null || ownerEntries.isEmpty
        ? const <Rect>[]
        : networkMapOwnerLabelSourceRects(
            ownerLabels: ownerEntries.values.expand((entries) => entries),
          );
    final geometry = _MapGeometry.fromStations(
      data.stations,
      ownerLabelSourceRects: ownerLabelSourceRects,
    );
    _geometryCacheKey = cacheKey;
    _geometryCache = geometry;
    return geometry;
  }

  /// 이 지역 오너 라벨 sidecar로 산출한 초기 카메라 가독 배율(#2068 트랙 QA
  /// 후속). sidecar 미로드·미매핑이면 null → 초기 카메라는 기존 contain-fit.
  /// build는 팬 프레임마다 호출되므로 [_geometryFor]와 같은 키 규칙으로 캐시해
  /// 라벨 수백~수천 건 중앙값 계산이 매 프레임 반복되지 않게 한다.
  double? _readableInitialMapScaleFor(NetworkMapData data) {
    final basemapAssetId =
        kRouteMapBasemapRegionToId[_displayRegionName(data.selectedRegion)];
    final ownerEntries = basemapAssetId == null
        ? null
        : _ownerLabelsByRegion?[basemapAssetId];
    final cacheKey =
        '${data.selectedRegion}:${identityHashCode(data.stations)}:'
        '${data.stations.length}:'
        '${ownerEntries == null ? 'none' : 'owner:${ownerEntries.length}'}';
    if (_readableInitialMapScaleCacheKey == cacheKey) {
      return _readableInitialMapScaleCache;
    }
    final scale = ownerEntries == null || ownerEntries.isEmpty
        ? null
        : networkMapReadableInitialMapScale(
            ownerLabelsByStationName: ownerEntries,
            stationNames: {for (final station in data.stations) station.nameKo},
          );
    _readableInitialMapScaleCacheKey = cacheKey;
    _readableInitialMapScaleCache = scale;
    return scale;
  }

  void _updateCameraForGesture(ScaleUpdateDetails details) {
    final startCamera = _gestureStartCamera;
    final startFocalPoint = _gestureStartFocalPoint;
    if (startCamera == null || startFocalPoint == null) {
      return;
    }
    final viewportCenter = startCamera.viewportSize.center(Offset.zero);
    final sourceBefore = startCamera.viewportToSourcePoint(startFocalPoint);
    final nextScale = (startCamera.scale * details.scale)
        .clamp(startCamera.minScale, startCamera.maxScale)
        .toDouble();
    final nextCenter =
        sourceBefore - (details.localFocalPoint - viewportCenter) / nextScale;
    _setCamera(
      startCamera
          .copyWith(
            center: nextCenter,
            scale: nextScale,
            revision: startCamera.revision + 1,
          )
          .clamped(viewportMargin: 220),
    );
  }

  void _endScaleGesture() {
    _forceRendererCameraCommit = true;
    if (_pendingCamera == null && _camera != null) {
      _pendingCamera = _camera;
    }
    final pendingCamera = _pendingCamera;
    if (pendingCamera != null) {
      widget.onViewportChanged(pendingCamera.visibleSourceRect);
    }
    _scheduleCameraCommit();
    _gestureStartCamera = null;
    _gestureStartFocalPoint = null;
    if (!_gestureActive) {
      return;
    }
    if (!mounted) {
      _gestureActive = false;
      return;
    }
    setState(() {
      _gestureActive = false;
    });
  }

  void _setCamera(MapCameraState camera) {
    final currentCamera = _pendingCamera ?? _camera;
    final nextCamera = currentCamera == null
        ? camera
        : networkMapCameraWithMonotonicRevision(
            current: currentCamera,
            next: camera,
          );
    if (identical(_pendingCamera, nextCamera) ||
        (_pendingCamera == null && identical(_camera, nextCamera))) {
      return;
    }
    _pendingCamera = nextCamera;
    _scheduleCameraCommit();
  }

  void _scheduleCameraCommit() {
    if (_pendingCamera == null) {
      return;
    }
    if (_cameraFrameCallbackScheduled) {
      return;
    }
    _cameraFrameCallbackScheduled = true;
    SchedulerBinding.instance.scheduleFrameCallback((_) {
      _cameraFrameCallbackScheduled = false;
      final pendingCamera = _pendingCamera;
      final forceRendererCameraCommit = _forceRendererCameraCommit;
      _pendingCamera = null;
      _forceRendererCameraCommit = false;
      if (!mounted || pendingCamera == null) {
        return;
      }
      if (!_routeMapRendererActive) {
        setState(() {
          _camera = pendingCamera;
          _requestedRendererCamera = null;
          _presentedRendererCamera = null;
          _requestedRendererCamerasByRevision.clear();
        });
        return;
      }
      final rendererCamera = _requestedRendererCameraFor(
        pendingCamera,
        forceCommit: forceRendererCameraCommit,
      );
      if (identical(_camera, pendingCamera) &&
          identical(_requestedRendererCamera, rendererCamera)) {
        return;
      }
      setState(() {
        _camera = pendingCamera;
        if (!identical(_requestedRendererCamera, rendererCamera)) {
          _requestedRendererCamerasByRevision[rendererCamera.revision] =
              rendererCamera;
        }
        _requestedRendererCamera = rendererCamera;
      });
    });
  }

  MapCameraState _requestedRendererCameraFor(
    MapCameraState pendingCamera, {
    required bool forceCommit,
  }) {
    final committedCamera = networkMapRendererCommitBasisCamera(
      presentedCamera: _presentedRendererCamera,
      requestedCamera: _requestedRendererCamera,
      visualCamera: pendingCamera,
    );
    final requestedCamera = networkMapOverscannedRendererCamera(pendingCamera);
    final now = DateTime.now();
    final shouldCommit =
        forceCommit ||
        !_gestureActive ||
        committedCamera == null ||
        !networkMapRendererCameraCoversVisual(
          rendererCamera: committedCamera,
          visualCamera: pendingCamera,
        ) ||
        networkMapShouldCommitRendererCamera(
          committed: committedCamera,
          candidate: requestedCamera,
          elapsedSinceLastCommit: _lastRendererCameraRequestAt == null
              ? kNetworkMapRendererCommitInterval
              : now.difference(_lastRendererCameraRequestAt!),
        );
    if (!shouldCommit) {
      final skippedCommitCamera = networkMapRendererCameraForSkippedCommit(
        requestedCamera: _requestedRendererCamera,
        candidateCamera: requestedCamera,
        visualCamera: pendingCamera,
      );
      if (!identical(skippedCommitCamera, _requestedRendererCamera)) {
        _lastRendererCameraRequestAt = now;
      }
      return skippedCommitCamera;
    }
    _lastRendererCameraRequestAt = now;
    return requestedCamera;
  }

  void _openNearestStation(
    Offset viewportPosition,
    Map<String, List<NetworkMapLine>> stationLinesById,
    _MapGeometry geometry,
    MapCameraState camera,
  ) {
    final station = _stationAtViewportPosition(
      viewportPosition,
      geometry,
      camera: camera,
    );
    if (station == null) {
      return;
    }
    _selectStation(station);
  }

  /// 팬 메뉴를 닫는다: 내부 선택과 함께, prop([selectedStationId])으로 열린
  /// 경우 부모 선택 상태도 비우도록 알린다(그렇지 않으면 prop이 다시 띄운다).
  void _clearSelectionAndNotify() {
    _selectedStation = null;
    widget.onSelectionDismissed();
  }

  void _dismissSelection() => setState(_clearSelectionAndNotify);

  void _selectStation(NetworkMapStation station) {
    setState(() => _selectedStation = station);
    // #2200: 캔버스 역 탭은 팬 메뉴와 함께 하단 역 정보 패널도 열도록 부모에
    // 통지한다(부모가 역을 StationSearchResult로 해석해 패널을 연다).
    widget.onStationTapped(station);
    // #2109: 화면 경계에서 팬 메뉴가 잘리면 카메라를 최소 거리만 패닝해 전체
    // 노출한다. 다음 프레임(레이아웃 확정 후) 뷰포트 대비 메뉴 bbox를 계산한다.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _selectedStation?.id != station.id) {
        return;
      }
      _panCameraToRevealFanMenu(station);
    });
  }

  void _panCameraToRevealFanMenu(NetworkMapStation station) {
    final camera = _pendingCamera ?? _camera;
    if (camera == null) {
      return;
    }
    final geometry = _geometryFor(widget.data);
    final stationPoint = camera.sourceToViewportPoint(
      _fanMenuTailAnchorSource(station, geometry),
    );
    const margin = kFanMenuViewportMargin;
    // #2109: 배치 bbox는 build와 동일하게 fanMenuPlacement가 계산한다
    // (규칙 중복 제거 — 한쪽만 바뀌어 패닝 bbox와 렌더 위치가 어긋나는 것 방지).
    // 패닝은 같은 viewport의 클램프 없는 이상적 배치로 최대한 노출을 시도하고,
    // 패닝이 .clamped() 한계로 다 못 드러내는 잔여는 build 경로의 viewport 클램프
    // 폴백이 처리한다.
    final placement = fanMenuPlacement(
      stationPoint: stationPoint,
      viewport: camera.viewportSize,
      clampPosition: false,
    );
    final menuRect = placement.revealBounds;
    final viewport = Offset.zero & camera.viewportSize;
    var dx = 0.0;
    var dy = 0.0;
    if (menuRect.left < viewport.left + margin) {
      dx = (viewport.left + margin) - menuRect.left;
    } else if (menuRect.right > viewport.right - margin) {
      dx = (viewport.right - margin) - menuRect.right;
    }
    if (menuRect.top < viewport.top + margin) {
      dy = (viewport.top + margin) - menuRect.top;
    } else if (menuRect.bottom > viewport.bottom - margin) {
      dy = (viewport.bottom - margin) - menuRect.bottom;
    }
    if (dx == 0 && dy == 0) {
      return;
    }
    // 뷰포트 픽셀 이동 → source 좌표 center 이동(반대 방향).
    final nextCenter = camera.center - Offset(dx, dy) / camera.scale;
    // #2192: v3는 flip을 제거하고 항상 노드 위에 배치하므로, 지도 최상단(경계)
    // 역에서도 꼬리 팁이 노드에 닿은 채 메뉴 전체가 드러나려면 카메라가 source
    // 경계를 메뉴 높이만큼 넘겨 패닝할 수 있어야 한다. clamped 헤드룸을 메뉴
    // 높이+여백으로 열어 상단 여유를 준다(dx·dy는 필요한 방향으로만 이동하므로
    // 다른 역 배치에는 영향 없음). 잔여는 build 경로의 viewport 클램프가 처리한다.
    final headroom = placement.menuHeight + margin;
    _setCamera(
      camera
          .copyWith(center: nextCenter, revision: camera.revision + 1)
          .clamped(viewportMargin: headroom),
    );
  }

  // Native SVG viewport와 Flutter overlay는 source 좌표계를 공유한다.
  Widget _buildStructuredRouteMapCanvas(
    MapCameraState visualCamera,
    Offset sourceOrigin,
  ) {
    final rendererCamera = _requestedRendererCamera ?? visualCamera;
    if (!identical(_presentedRendererCamera, rendererCamera)) {
      _requestedRendererCamerasByRevision[rendererCamera.revision] =
          rendererCamera;
    }
    final displayedRendererCamera = _presentedRendererCamera ?? rendererCamera;
    final transformedVisualCamera = networkMapRendererTransformVisualCamera(
      rendererCamera: displayedRendererCamera,
      visualCamera: visualCamera,
    );
    final attribution = _attributionTextByRegion?[widget.data.selectedRegion];
    _ensureStructuredRouteMap();
    final map = _structuredRouteMapCache!;
    final lineColors = _structuredLineColorsCache!;
    final labelTextByStationId = _structuredLabelTextCache!;
    final lineBadgeLabelByLineId = _structuredLineBadgeLabelCache!;
    return Transform(
      alignment: Alignment.topLeft,
      transform: networkMapRendererFrameTransform(
        rendererCamera: displayedRendererCamera,
        visualCamera: transformedVisualCamera,
      ),
      child: RouteMapBasemapView(
        key: ValueKey(_layoutKey),
        region: _displayRegionName(widget.data.selectedRegion),
        camera: rendererCamera,
        sourceOrigin: sourceOrigin,
        attributionText: attribution,
        onUnavailable: _markRouteMapBasemapUnavailable,
        onFramePresented: _acceptRouteMapFrame,
        overlay: StructuredRouteMapView(
          map: map,
          camera: rendererCamera,
          lineColors: lineColors,
          labelTextByStationId: labelTextByStationId,
          lineBadgeLabelByLineId: lineBadgeLabelByLineId,
          drawLines: false,
          drawStationSymbols: false,
          sourceOrigin: sourceOrigin,
        ),
      ),
    );
  }

  void _acceptRouteMapFrame(int revision) {
    final camera = _requestedRendererCamerasByRevision[revision];
    if (!mounted || camera == null) return;
    setState(() {
      _presentedRendererCamera = camera;
      _requestedRendererCamerasByRevision.removeWhere(
        (candidateRevision, _) => candidateRevision <= revision,
      );
    });
  }

  void _markRouteMapBasemapUnavailable() {
    if (!mounted || _routeMapBasemapFailed) return;
    setState(() => _routeMapBasemapFailed = true);
  }

  void _ensureStructuredRouteMap() {
    final data = widget.data;
    // geometry 캐시와 동일하게 identityHashCode를 포함해, 같은 region·같은 개수라도
    // data 인스턴스가 바뀌면(좌표 수정/노선 교체) 재계산되게 한다(overlay와 정합).
    final key =
        '${data.selectedRegion}:${identityHashCode(data.stations)}:${data.stations.length}:${data.lines.length}';
    if (_structuredCacheKey == key && _structuredRouteMapCache != null) {
      return;
    }
    _structuredCacheKey = key;
    final structured = data.toStructuredRouteMap();
    _structuredRouteMapCache = structured;
    _structuredDesignScaleCache = routeMapDesignSpaceFor(
      structured,
    ).designScale;
    _structuredTransferGroupCache = {
      for (final group in structured.transferGroups) group.stationId: group,
    };
    _structuredLineColorsCache = routeMapLineColors({
      for (final line in data.lines) line.id: line.color,
    });
    _structuredLabelTextCache = {
      for (final station in data.stations)
        station.id: routeMapStationLabel(station.nameKo),
    };
    _structuredLineBadgeLabelCache = {
      for (final line in data.lines) line.id: routeMapLineBadgeLabel(line.name),
    };
  }

  /// 팬 메뉴 꼬리 팁이 닿을 앵커의 source 좌표(#2068 QA). 노드 바닥에서
  /// 노드 높이의 2/3만큼 위, 즉 ([_fanMenuAnchorSource])에서 높이의 1/6만큼
  /// 위로 올라간 지점이다.
  /// build(렌더)와 [_panCameraToRevealFanMenu](카메라)가 같은 앵커를 소비하도록
  /// 단일 헬퍼로 둔다. **팬 메뉴 전용** — 드래프트 핀은 이동 없이
  /// [_fanMenuAnchorSource](정중앙)를 그대로 쓴다.
  Offset _fanMenuTailAnchorSource(
    NetworkMapStation station,
    _MapGeometry geometry,
  ) {
    final center = _fanMenuAnchorSource(station, geometry);
    final group = _structuredTransferGroupCache?[station.id];
    return fanMenuTailAnchorPoint(
      nodeCenter: center,
      nodeHeight: fanMenuAnchorNodeHeight(
        memberPositions: group?.memberPositions ?? const <Offset>[],
        designScale: _structuredDesignScaleCache ?? 1.0,
      ),
    );
  }

  /// 노드 **정중앙**의 source 좌표(#2192). 환승역은 렌더 캡슐의 시각 중심으로,
  /// 일반역은 노드 좌표 그대로 유도한 뒤 [_MapGeometry] 원점을 빼
  /// [MapCameraState.sourceToViewportPoint] 입력 좌표계로 맞춘다.
  /// 드래프트 핀(출발·경유·도착)이 이 좌표를 그대로 앵커로 쓴다. 팬 메뉴는
  /// 여기서 한 번 더 올린 [_fanMenuTailAnchorSource]를 쓴다(#2068 QA).
  Offset _fanMenuAnchorSource(
    NetworkMapStation station,
    _MapGeometry geometry,
  ) {
    _ensureStructuredRouteMap();
    final tapped = Offset(
      station.position.x.toDouble(),
      station.position.y.toDouble(),
    );
    final group = _structuredTransferGroupCache?[station.id];
    final center = group == null
        ? tapped
        : fanMenuTransferAnchor(
            memberPositions: group.memberPositions,
            tappedPosition: tapped,
            designScale: _structuredDesignScaleCache ?? 1.0,
          );
    return Offset(
      center.dx - geometry.origin.dx,
      center.dy - geometry.origin.dy,
    );
  }
}

/// 저장형 권역명('부산권')을 표시형('부산')으로 정규화한다. 규칙의 단일 원본은
/// [routeMapDisplayRegionName]이다 — 사본을 두면 한쪽만 갱신돼 조회가 조용히
/// 어긋난다(#2068).
String _displayRegionName(String region) => routeMapDisplayRegionName(region);

Rect _sourceRectToViewport(Rect sourceRect, MapCameraState camera) {
  final topLeft = camera.sourceToViewportPoint(sourceRect.topLeft);
  final bottomRight = camera.sourceToViewportPoint(sourceRect.bottomRight);
  return Rect.fromLTRB(
    math.min(topLeft.dx, bottomRight.dx),
    math.min(topLeft.dy, bottomRight.dy),
    math.max(topLeft.dx, bottomRight.dx),
    math.max(topLeft.dy, bottomRight.dy),
  );
}

/// 초기 카메라 bounds의 **기준선**(하한 배율)을 만든다. 최종 초기 카메라는
/// [networkMapInitialCameraBounds]가 여기에 가독 배율을 얹어 정한다.
Rect _readableBoundsFor(_MapGeometry geometry, {required int stationCount}) {
  // 소규모 지역은 38% 도심 확대 대신 지역 전체를 기준선으로 둬 과확대를
  // 막는다(#1764 E). 판정은 networkMapUsesWholeRegionInitialView 단일 소스를
  // 쓴다(테스트가 실제 렌더 분기를 가드하도록).
  if (networkMapUsesWholeRegionInitialView(stationCount)) {
    return Rect.fromLTWH(0, 0, geometry.width, geometry.height);
  }
  final width = math.min(
    geometry.width,
    math.max(320.0, geometry.width * 0.38),
  );
  final height = math.min(
    geometry.height,
    math.max(320.0, geometry.height * 0.38),
  );
  final maxLeft = math.max(0.0, geometry.width - width);
  final maxTop = math.max(0.0, geometry.height - height);
  final left = (geometry.focus.dx - width / 2).clamp(0.0, maxLeft).toDouble();
  final top = (geometry.focus.dy - height / 2).clamp(0.0, maxTop).toDouble();
  return Rect.fromLTWH(left, top, width, height);
}

/// [initialBounds]는 이 지역이 실제로 쓰는 초기 카메라 bounds다(#2068 트랙 QA
/// 후속으로 [networkMapInitialCameraBounds]가 확대해 준 값). geometry의 원
/// initialBounds를 쓰면 초기 화면이 확대된 만큼 focus가 오히려 축소돼 #2062
/// ("focus는 초기 화면보다 확대") 불변식이 깨진다 — 두 카메라가 같은 bounds를
/// 공유해야 focus 배율이 항상 동일한 feature policy로 계산된다.
Rect _stationFocusBoundsFor(
  NetworkMapStation station,
  _MapGeometry geometry, {
  required Rect initialBounds,
}) {
  return networkMapStationFocusBounds(
    initialBounds: initialBounds,
    center: Offset(geometry.x(station), geometry.y(station)),
    sourceWidth: geometry.width,
    sourceHeight: geometry.height,
  );
}

class _MapGeometry {
  _MapGeometry({
    required this.origin,
    required this.focus,
    required this.width,
    required this.height,
    Rect? initialBounds,
    this.overlayStyleScale = 1.0,
    _StationSpatialIndex? stationIndex,
  }) : initialBounds = initialBounds ?? Rect.fromLTWH(0, 0, width, height),
       stationIndex = stationIndex ?? _StationSpatialIndex.empty;

  final Offset origin;
  final Offset focus;
  final double width;
  final double height;
  final Rect initialBounds;
  final double overlayStyleScale;
  final _StationSpatialIndex stationIndex;

  factory _MapGeometry.fromStations(
    List<NetworkMapStation> stations, {
    // basemap 오너 라벨(sidecar)의 실제 렌더 extents(source 단위). 오너 라벨은
    // route_map_positions의 합성 label_polygon보다 훨씬 넓게 그려지므로(예: 광주
    // '학동·증심사입구'가 anchor에서 오른쪽으로 수백 source px 확장), 이 rect들을
    // bounds에 union하지 않으면 초기 fit·팬 한계가 라벨을 잘라낸다(#2068 실기기
    // 반려). 미매치/무sidecar 지역은 빈 리스트라 기존 동작(label_polygon) 그대로.
    List<Rect> ownerLabelSourceRects = const [],
  }) {
    var minX = double.infinity;
    var minY = double.infinity;
    var maxX = 0.0;
    var maxY = 0.0;
    final stationXs = <double>[];
    final stationYs = <double>[];
    for (final station in stations) {
      stationXs.add(station.position.x.toDouble());
      stationYs.add(station.position.y.toDouble());
      final point = Rect.fromCircle(
        center: Offset(
          station.position.x.toDouble(),
          station.position.y.toDouble(),
        ),
        radius: 18,
      );
      minX = math.min(minX, point.left);
      minY = math.min(minY, point.top);
      maxX = math.max(maxX, point.right);
      maxY = math.max(maxY, point.bottom);
      for (final pathData in [
        station.position.upPath,
        station.position.downPath,
      ]) {
        if (pathData.isEmpty) {
          continue;
        }
        final bounds = cachedRouteMapPath(pathData, Offset.zero).bounds;
        minX = math.min(minX, bounds.left);
        minY = math.min(minY, bounds.top);
        maxX = math.max(maxX, bounds.right);
        maxY = math.max(maxY, bounds.bottom);
      }
      final labelPolygonBounds = _labelPolygonBoundsFor(station);
      if (labelPolygonBounds != null) {
        minX = math.min(minX, labelPolygonBounds.left);
        minY = math.min(minY, labelPolygonBounds.top);
        maxX = math.max(maxX, labelPolygonBounds.right);
        maxY = math.max(maxY, labelPolygonBounds.bottom);
      }
    }
    for (final rect in ownerLabelSourceRects) {
      minX = math.min(minX, rect.left);
      minY = math.min(minY, rect.top);
      maxX = math.max(maxX, rect.right);
      maxY = math.max(maxY, rect.bottom);
    }
    if (!minX.isFinite || !minY.isFinite) {
      return _MapGeometry(
        origin: Offset.zero,
        focus: Offset(430, 280),
        width: 860,
        height: 560,
      );
    }
    const margin = 54.0;
    final origin = Offset(minX - margin, minY - margin);
    final geometry = _MapGeometry(
      origin: origin,
      focus: Offset(
        _median(stationXs) - origin.dx,
        _median(stationYs) - origin.dy,
      ),
      width: math.max(860, maxX - minX + margin * 2),
      height: math.max(560, maxY - minY + margin * 2),
    );
    final result = _MapGeometry(
      origin: geometry.origin,
      focus: geometry.focus,
      width: geometry.width,
      height: geometry.height,
      initialBounds: _readableBoundsFor(
        geometry,
        stationCount: stations.length,
      ),
    );
    return result.copyWith(
      stationIndex: _StationSpatialIndex.fromStations(stations, result),
    );
  }

  double x(NetworkMapStation station) => station.position.x - origin.dx;

  double y(NetworkMapStation station) => station.position.y - origin.dy;

  _MapGeometry copyWith({_StationSpatialIndex? stationIndex}) {
    return _MapGeometry(
      origin: origin,
      focus: focus,
      width: width,
      height: height,
      initialBounds: initialBounds,
      overlayStyleScale: overlayStyleScale,
      stationIndex: stationIndex ?? this.stationIndex,
    );
  }
}

class _StationSpatialIndex {
  _StationSpatialIndex._({
    required Map<_StationSpatialCell, List<NetworkMapStation>> buckets,
    required Map<String, int> stationOrder,
  }) : _buckets = buckets, // ignore: prefer_initializing_formals
       // ignore: prefer_initializing_formals
       _stationOrder = stationOrder;

  static final empty = _StationSpatialIndex._(
    buckets: const {},
    stationOrder: const {},
  );

  static const _cellSize = 256.0;

  final Map<_StationSpatialCell, List<NetworkMapStation>> _buckets;
  final Map<String, int> _stationOrder;

  factory _StationSpatialIndex.fromStations(
    List<NetworkMapStation> stations,
    _MapGeometry geometry,
  ) {
    final buckets = <_StationSpatialCell, List<NetworkMapStation>>{};
    final stationOrder = <String, int>{};
    for (var index = 0; index < stations.length; index += 1) {
      final station = stations[index];
      final key = _stationGeometryKey(station);
      stationOrder[key] = index;
      final bounds = _stationHitRect(station, geometry);
      for (final cell in _cellsFor(bounds)) {
        buckets.putIfAbsent(cell, () => []).add(station);
      }
    }
    return _StationSpatialIndex._(buckets: buckets, stationOrder: stationOrder);
  }

  List<NetworkMapStation> query(Rect sourceBounds) {
    if (_buckets.isEmpty || sourceBounds.isEmpty) {
      return const [];
    }
    final byKey = <String, NetworkMapStation>{};
    for (final cell in _cellsFor(sourceBounds)) {
      for (final station in _buckets[cell] ?? const <NetworkMapStation>[]) {
        byKey[_stationGeometryKey(station)] = station;
      }
    }
    final result = byKey.values.toList(growable: false);
    result.sort((a, b) {
      final aOrder = _stationOrder[_stationGeometryKey(a)] ?? 0;
      final bOrder = _stationOrder[_stationGeometryKey(b)] ?? 0;
      return aOrder.compareTo(bOrder);
    });
    return result;
  }

  static Iterable<_StationSpatialCell> _cellsFor(Rect bounds) sync* {
    final left = _cellFor(bounds.left);
    final right = _cellFor(bounds.right);
    final top = _cellFor(bounds.top);
    final bottom = _cellFor(bounds.bottom);
    for (var x = left; x <= right; x += 1) {
      for (var y = top; y <= bottom; y += 1) {
        yield _StationSpatialCell(x, y);
      }
    }
  }

  static int _cellFor(double value) => (value / _cellSize).floor();
}

@immutable
class _StationSpatialCell {
  const _StationSpatialCell(this.x, this.y);

  final int x;
  final int y;

  @override
  bool operator ==(Object other) {
    return other is _StationSpatialCell && other.x == x && other.y == y;
  }

  @override
  int get hashCode => Object.hash(x, y);
}

const _maximumStationHitDistance = 24.0;

/// 역 tap hit target 한 변 길이(logical px). 노드 중심에서 사방
/// [_maximumStationHitDistance]까지 tap을 받으므로 hit rect 한 변은 그 2배다.
/// AGENTS.md 큰 터치 영역 hard rule + WCAG 2.5.5(target size 최소 48×48)를
/// 노선도 역 선택에 보장한다 — #1642 접근성 회귀 가드.
@visibleForTesting
const double networkMapStationHitTargetLogicalSize =
    _maximumStationHitDistance * 2;

List<NetworkMapStation> _canonicalStations(
  Iterable<NetworkMapStation> stations,
  _MapGeometry geometry,
) {
  final canonicalStations = <NetworkMapStation>[];
  for (final station in stations) {
    final existingIndex = canonicalStations.indexWhere((existing) {
      return existing.id == station.id &&
          _isOverlappingStationGeometry(existing, station, geometry);
    });
    if (existingIndex == -1) {
      canonicalStations.add(station);
      continue;
    }
    final existing = canonicalStations[existingIndex];
    if (_stationGeometryPriority(station) >
        _stationGeometryPriority(existing)) {
      canonicalStations[existingIndex] = station;
    }
  }
  return canonicalStations;
}

bool _isOverlappingStationGeometry(
  NetworkMapStation a,
  NetworkMapStation b,
  _MapGeometry geometry,
) {
  return _stationHitRect(
    a,
    geometry,
  ).inflate(8).overlaps(_stationHitRect(b, geometry).inflate(8));
}

List<NetworkMapStation> _visibleCanonicalStations({
  required _MapGeometry geometry,
  required MapCameraState camera,
}) {
  final visibleSourceRect = camera.visibleSourceRect.inflate(96 / camera.scale);
  return _canonicalStations(
    geometry.stationIndex.query(visibleSourceRect).where((station) {
      return _stationHitRect(station, geometry).overlaps(visibleSourceRect);
    }),
    geometry,
  );
}

int _stationGeometryPriority(NetworkMapStation station) {
  if (station.position.labelPolygon.isNotEmpty) {
    return 3;
  }
  if (station.position.upPath.isNotEmpty ||
      station.position.downPath.isNotEmpty) {
    return 2;
  }
  return 1;
}

Rect _stationHitRect(
  NetworkMapStation station,
  _MapGeometry geometry, {
  double nodeRadius = 24,
  double labelHeight = 40,
}) {
  final node = Rect.fromCenter(
    center: Offset(geometry.x(station), geometry.y(station)),
    width: nodeRadius * 2,
    height: nodeRadius * 2,
  );
  final labelOffset = _labelOffsetFor(station);
  final labelPolygon = _labelPolygonFor(station, geometry);
  if (labelPolygon != null) {
    return node.expandToInclude(_boundsForPolygon(labelPolygon));
  }
  final labelCenter = Offset(
    geometry.x(station) + labelOffset.dx,
    geometry.y(station) + labelOffset.dy,
  );
  final label = Rect.fromCenter(
    center: labelCenter,
    width: math.max(64, station.nameKo.characters.length * 18 + 32),
    height: labelHeight,
  );
  return node.expandToInclude(label);
}

NetworkMapStation? _stationAtViewportPosition(
  Offset viewportPosition,
  _MapGeometry geometry, {
  required MapCameraState camera,
}) {
  final safeScale = camera.scale > 0 ? camera.scale : 1.0;
  final sourcePosition = camera.viewportToSourcePoint(viewportPosition);
  final sourceQuery = Rect.fromCircle(
    center: sourcePosition,
    radius: _maximumStationHitDistance / safeScale,
  );
  NetworkMapStation? bestStation;
  _StationTapScore? bestScore;
  for (final station in geometry.stationIndex.query(sourceQuery)) {
    final score = _stationTapScore(viewportPosition, station, geometry, camera);
    if (score == null) {
      continue;
    }
    if (bestScore == null || score.compareTo(bestScore) < 0) {
      bestScore = score;
      bestStation = station;
    }
  }
  return bestStation;
}

_StationTapScore? _stationTapScore(
  Offset viewportPosition,
  NetworkMapStation station,
  _MapGeometry geometry,
  MapCameraState camera,
) {
  final safeScale = camera.scale > 0 ? camera.scale : 1.0;
  final nodeCenter = camera.sourceToViewportPoint(
    Offset(geometry.x(station), geometry.y(station)),
  );
  final nodeHitRect = Rect.fromCenter(
    center: nodeCenter,
    // 노출 상수를 단일 소스로 써서, 48dp 접근성 회귀 가드 테스트가 실제 hit
    // rect를 지키게 한다(상수와 rect의 독립 재유도 드리프트 방지).
    width: networkMapStationHitTargetLogicalSize,
    height: networkMapStationHitTargetLogicalSize,
  );
  final containsNode = nodeHitRect.contains(viewportPosition);
  final nodeDistance = (viewportPosition - nodeCenter).distance;
  var bestHitDistance = containsNode ? 0.0 : double.infinity;
  var bestSelectionDistance = containsNode ? nodeDistance : double.infinity;
  var containsShape = containsNode;
  final labelPolygon = _labelPolygonFor(station, geometry);
  if (labelPolygon != null) {
    final viewportPolygon = [
      for (final point in labelPolygon) camera.sourceToViewportPoint(point),
    ];
    final polygonDistance = math.sqrt(
      _distanceSquaredToPolygon(viewportPosition, viewportPolygon),
    );
    bestHitDistance = math.min(bestHitDistance, polygonDistance);
    if (polygonDistance <= _maximumStationHitDistance) {
      bestSelectionDistance = math.min(bestSelectionDistance, polygonDistance);
    }
    containsShape = containsShape || polygonDistance == 0;
  } else {
    final labelRect = _sourceRectToViewport(
      _stationLabelRect(station, geometry, labelHeight: 40 / safeScale),
      camera,
    );
    final labelDistance = _distanceToRect(viewportPosition, labelRect);
    bestHitDistance = math.min(bestHitDistance, labelDistance);
    if (labelDistance <= _maximumStationHitDistance) {
      bestSelectionDistance = math.min(
        bestSelectionDistance,
        (viewportPosition - labelRect.center).distance,
      );
    }
    containsShape = containsShape || labelDistance == 0;
  }
  if (bestHitDistance > _maximumStationHitDistance) {
    return null;
  }
  return _StationTapScore(
    containsNode: containsNode,
    containsShape: containsShape,
    screenDistance: bestSelectionDistance.isFinite
        ? bestSelectionDistance
        : bestHitDistance,
    stableKey: _stationGeometryKey(station),
  );
}

Rect _stationLabelRect(
  NetworkMapStation station,
  _MapGeometry geometry, {
  double labelHeight = 40,
}) {
  final labelOffset = _labelOffsetFor(station);
  final labelCenter = Offset(
    geometry.x(station) + labelOffset.dx,
    geometry.y(station) + labelOffset.dy,
  );
  return Rect.fromCenter(
    center: labelCenter,
    width: math.max(64, station.nameKo.characters.length * 18 + 32),
    height: labelHeight,
  );
}

double _distanceToRect(Offset point, Rect rect) {
  if (rect.contains(point)) {
    return 0;
  }
  final dx = point.dx < rect.left
      ? rect.left - point.dx
      : point.dx > rect.right
      ? point.dx - rect.right
      : 0.0;
  final dy = point.dy < rect.top
      ? rect.top - point.dy
      : point.dy > rect.bottom
      ? point.dy - rect.bottom
      : 0.0;
  return math.sqrt(dx * dx + dy * dy);
}

class _StationTapScore implements Comparable<_StationTapScore> {
  const _StationTapScore({
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
  int compareTo(_StationTapScore other) {
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

String _stationGeometryKey(NetworkMapStation station) {
  return '${station.id}:${station.lineId}';
}

Rect? _labelPolygonBoundsFor(NetworkMapStation station) {
  final polygon = parseRouteMapLabelPolygon(station.position.labelPolygon);
  return polygon == null ? null : _boundsForPolygon(polygon);
}

/// 테스트용: 주어진 역·오너 라벨 rect로 산출한 지도 geometry의 전체 source
/// bounds(팬 한계·초기 fit의 근거). #2068 오너 라벨 extents 포함 회귀 가드.
@visibleForTesting
Rect networkMapGeometrySourceBoundsFor(
  List<NetworkMapStation> stations, {
  List<Rect> ownerLabelSourceRects = const [],
}) {
  final geometry = _MapGeometry.fromStations(
    stations,
    ownerLabelSourceRects: ownerLabelSourceRects,
  );
  return Rect.fromLTWH(
    geometry.origin.dx,
    geometry.origin.dy,
    geometry.width,
    geometry.height,
  );
}

List<Offset>? _labelPolygonFor(
  NetworkMapStation station,
  _MapGeometry geometry,
) {
  final polygon = parseRouteMapLabelPolygon(station.position.labelPolygon);
  if (polygon == null) {
    return null;
  }
  return [
    for (final point in polygon)
      Offset(point.dx - geometry.origin.dx, point.dy - geometry.origin.dy),
  ];
}

Rect _boundsForPolygon(List<Offset> polygon) {
  var minX = double.infinity;
  var minY = double.infinity;
  var maxX = -double.infinity;
  var maxY = -double.infinity;
  for (final point in polygon) {
    minX = math.min(minX, point.dx);
    minY = math.min(minY, point.dy);
    maxX = math.max(maxX, point.dx);
    maxY = math.max(maxY, point.dy);
  }
  return Rect.fromLTRB(minX, minY, maxX, maxY);
}

double _distanceSquaredToPolygon(Offset point, List<Offset> polygon) {
  if (_pointInPolygon(point, polygon)) {
    return 0;
  }
  var best = double.infinity;
  for (var index = 0; index < polygon.length; index += 1) {
    best = math.min(
      best,
      _distanceSquaredToSegment(
        point,
        polygon[index],
        polygon[(index + 1) % polygon.length],
      ),
    );
  }
  return best;
}

bool _pointInPolygon(Offset point, List<Offset> polygon) {
  var inside = false;
  for (
    var index = 0, previous = polygon.length - 1;
    index < polygon.length;
    previous = index, index += 1
  ) {
    final currentPoint = polygon[index];
    final previousPoint = polygon[previous];
    final crossesY =
        (currentPoint.dy > point.dy) != (previousPoint.dy > point.dy);
    if (!crossesY) {
      continue;
    }
    final intersectionX =
        (previousPoint.dx - currentPoint.dx) *
            (point.dy - currentPoint.dy) /
            (previousPoint.dy - currentPoint.dy) +
        currentPoint.dx;
    if (point.dx < intersectionX) {
      inside = !inside;
    }
  }
  return inside;
}

double _distanceSquaredToSegment(Offset point, Offset start, Offset end) {
  final segment = end - start;
  final lengthSquared = segment.distanceSquared;
  if (lengthSquared == 0) {
    return (point - start).distanceSquared;
  }
  final t =
      (((point.dx - start.dx) * segment.dx) +
          ((point.dy - start.dy) * segment.dy)) /
      lengthSquared;
  final clampedT = t.clamp(0.0, 1.0).toDouble();
  final projection = Offset(
    start.dx + segment.dx * clampedT,
    start.dy + segment.dy * clampedT,
  );
  return (point - projection).distanceSquared;
}

double _median(List<double> values) {
  if (values.isEmpty) {
    return 0;
  }
  values.sort();
  return values[values.length ~/ 2];
}

bool _usesOfficialRouteMapSource(NetworkMapStation station) {
  return station.position.sourceId.endsWith('-cyberstation') ||
      station.position.sourceId == 'qa-wikimedia-seoul-svg-coordinate';
}

Offset _labelOffsetFor(NetworkMapStation station) {
  if (_usesOfficialRouteMapSource(station)) {
    return Offset(
      station.position.labelDx.toDouble(),
      station.position.labelDy.toDouble(),
    );
  }
  final pathData = station.position.downPath.isNotEmpty
      ? station.position.downPath
      : station.position.upPath;
  if (pathData.isEmpty) {
    return const Offset(8, 3);
  }
  final bounds = cachedRouteMapPath(pathData, Offset.zero).bounds;
  if (bounds.width > bounds.height * 1.2) {
    return const Offset(0, 12);
  }
  if (bounds.height > bounds.width * 1.2) {
    return const Offset(9, 3);
  }
  return const Offset(8, -8);
}

/// #1948: 상단바 draft 필드의 종류. 출발/도착에 더해 경유(2단계 경유역)를
/// 같은 무채색 채움 필드 리듬으로 표시한다.
enum _RouteDraftFieldKind { origin, waypoint, destination }

/// #1933 요구 2: 출발/도착이 하나라도 차면 상단바 "자체"가 참고 앱 OD 입력
/// 구조(출발/도착 각각을 무채색 채움 필드 2개로 표시)로 변신한다. 아래 별도
/// 카드를 띄우지 않는다 — 그림자/elevation 0, 라운딩은 8 이하, splash 없이
/// 채움 색과 여백만으로 depth를 준다. 무채색 잉크만.
///
/// 검색바와 같은 문법:
/// `[←][출발 필드........]  수도권`  ← 지역은 필드 열 밖(필드 폭 통일)
/// `[+][도착 필드........]`       ← 출발·도착 중 하나만 있을 때 +
/// `+`는 검색을 열지 않고 출발·도착 사이에 빈 경유 칸만 삽입한다.
class _NetworkMapTopBarRouteDraft extends StatelessWidget {
  const _NetworkMapTopBarRouteDraft({
    required this.draft,
    required this.showWaypointRow,
    required this.regionLabel,
    required this.onClearDraft,
    required this.onOpenWaypointSlot,
    required this.onClearOrigin,
    required this.onClearDestination,
    required this.onClearWaypoint,
    required this.onReorderDraft,
    this.onPickOrigin,
    this.onPickDestination,
    this.onPickWaypoint,
    super.key,
  });

  static const _leadingWidth = EasySubwayTouchTarget.general;
  static const _rowGap = 6.0;

  /// 노선홈 지하철역 검색 시각 박스와 동일 높이(#2083).
  static const _fieldMinHeight = easySubwaySearchFieldVisualHeight;

  /// 홈 idle 검색 행과 같은 필드↔구분선 간격.
  /// 검색 행은 고정 높이 [easySubwayTopBarContentHeight] 안에서 필드가
  /// 수직 중앙이라, 패딩 6 + 여유 4 = (60 − 40) / 2 = 10이 된다.
  static const _chromeVerticalInset =
      (easySubwayTopBarContentHeight - _fieldMinHeight) / 2;

  final RouteDraft draft;

  /// 빈 경유 칸 포함, 경유 행을 그릴지.
  final bool showWaypointRow;

  /// 현재 지도 지역 표시명. draft가 있으면 변경 불가(잠김 텍스트만).
  final String regionLabel;
  final VoidCallback onClearDraft;

  /// 왼쪽 +: 빈 경유 칸을 출발·도착 사이에 연다.
  final VoidCallback onOpenWaypointSlot;
  final VoidCallback onClearOrigin;
  final VoidCallback onClearDestination;
  final VoidCallback onClearWaypoint;

  /// #1985: draft 행 드래그 재배열 콜백. (from, to) 슬롯 쌍을 넘긴다.
  final void Function(RouteDraftSlot from, RouteDraftSlot to) onReorderDraft;

  /// G4: 각 칸 탭 → 역 검색 열기(같은 draft로 수렴). null이면 칸을 탭할 수 없다.
  final VoidCallback? onPickOrigin;
  final VoidCallback? onPickDestination;

  /// #1948: 경유 칸 탭 → 역 검색. null이면 칸을 탭할 수 없다.
  final VoidCallback? onPickWaypoint;

  @override
  Widget build(BuildContext context) {
    // #1985: 현재 렌더 중인 행 슬롯 순서. 경유 행이 있으면 출발·경유·도착 3행.
    final visibleSlots = <RouteDraftSlot>[
      RouteDraftSlot.origin,
      if (showWaypointRow) RouteDraftSlot.waypoint,
      RouteDraftSlot.destination,
    ];
    List<RouteDraftSlot> targetsFor(RouteDraftSlot slot) =>
        visibleSlots.where((s) => s != slot).toList();

    // 경유 +: 출발·도착 중 하나만 있고 경유 행이 아직 없을 때.
    final hasOrigin = draft.origin != null;
    final hasDestination = draft.destination != null;
    final canAddWaypoint = !showWaypointRow && (hasOrigin != hasDestination);

    final originField = _NetworkMapRouteDraftField(
      kind: _RouteDraftFieldKind.origin,
      slot: RouteDraftSlot.origin,
      station: draft.origin,
      onClear: onClearOrigin,
      onPick: onPickOrigin,
      reorderTargets: targetsFor(RouteDraftSlot.origin),
      onReorder: onReorderDraft,
    );
    final destinationField = _NetworkMapRouteDraftField(
      kind: _RouteDraftFieldKind.destination,
      slot: RouteDraftSlot.destination,
      station: draft.destination,
      onClear: onClearDestination,
      onPick: onPickDestination,
      reorderTargets: targetsFor(RouteDraftSlot.destination),
      onReorder: onReorderDraft,
    );

    // 필드 열은 모두 같은 Expanded 폭. 지역은 열 밖에 두어 출발 행만 짧아지지 않게 한다.
    final fieldRows = <Widget>[
      _draftChromeRow(
        leading: _draftIconButton(
          key: const Key('networkMapRouteDraftBackButton'),
          tooltip: '경로 입력 지우기',
          icon: Icons.arrow_back,
          onPressed: onClearDraft,
        ),
        field: originField,
      ),
      if (showWaypointRow)
        _draftChromeRow(
          leading: const SizedBox(width: _leadingWidth),
          field: _NetworkMapRouteDraftField(
            kind: _RouteDraftFieldKind.waypoint,
            slot: RouteDraftSlot.waypoint,
            station: draft.waypoint,
            onClear: onClearWaypoint,
            onPick: onPickWaypoint,
            reorderTargets: targetsFor(RouteDraftSlot.waypoint),
            onReorder: onReorderDraft,
            showClearWhenEmpty: true,
          ),
        ),
      _draftChromeRow(
        leading: canAddWaypoint
            ? _draftIconButton(
                key: const Key('networkMapRouteDraftAddWaypoint'),
                tooltip: '경유역 칸 추가',
                icon: Icons.add,
                onPressed: onOpenWaypointSlot,
              )
            : const SizedBox(width: _leadingWidth),
        field: destinationField,
      ),
    ];

    // 노선홈 검색 행과 동일: 상·하 10(필드↔구분선), 필드는 검색 박스 시각 높이.
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        4,
        _chromeVerticalInset,
        8,
        _chromeVerticalInset,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < fieldRows.length; i++) ...[
                  if (i > 0) const SizedBox(height: _rowGap),
                  fieldRows[i],
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: _fieldMinHeight,
            child: Align(
              alignment: Alignment.centerRight,
              child: _draftLockedRegionLabel(regionLabel),
            ),
          ),
        ],
      ),
    );
  }

  /// 검색 모드 ← 와 같은 테두리 없는 아이콘 버튼.
  static Widget _draftIconButton({
    required Key key,
    required String tooltip,
    required IconData icon,
    required VoidCallback? onPressed,
  }) {
    return SizedBox(
      width: _leadingWidth,
      height: _fieldMinHeight,
      child: IconButton(
        key: key,
        tooltip: tooltip,
        onPressed: onPressed,
        style: IconButton.styleFrom(
          minimumSize: const Size.square(EasySubwayTouchTarget.general),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          padding: EdgeInsets.zero,
        ),
        icon: Icon(
          icon,
          size: 26,
          color: EasySubwayAccessibleColors.contentPrimary,
        ),
      ),
    );
  }

  /// 검색바 지역 라벨과 같은 톤의 잠김 표시(▾·탭 없음).
  static Widget _draftLockedRegionLabel(String regionLabel) {
    return Semantics(
      label: '지역: $regionLabel, 변경할 수 없음',
      child: ExcludeSemantics(
        child: ConstrainedBox(
          key: const Key('networkMapRouteDraftRegionLabel'),
          constraints: const BoxConstraints(maxWidth: 88),
          child: Text(
            regionLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: const TextStyle(
              color: EasySubwayAccessibleColors.contentSecondary,
              fontSize: 17,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  static Widget _draftChromeRow({
    required Widget leading,
    required Widget field,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        leading,
        const SizedBox(width: 4),
        Expanded(child: field),
      ],
    );
  }
}

/// 변신한 상단바의 한 줄(출발 또는 도착) — 무채색 채움 필드. 라운딩 8 이하,
/// 그림자/elevation 없음, splash 없음(GestureDetector만 사용). 채워졌을
/// 때만 지우기(✕) 버튼을 보인다.
class _NetworkMapRouteDraftField extends StatelessWidget {
  const _NetworkMapRouteDraftField({
    required this.kind,
    required this.slot,
    required this.station,
    required this.onClear,
    required this.reorderTargets,
    required this.onReorder,
    this.onPick,
    this.showClearWhenEmpty = false,
  });

  final _RouteDraftFieldKind kind;

  /// #1985: 이 행이 대응하는 draft 슬롯. 드래그 재배열의 from/to 계산에 쓴다.
  final RouteDraftSlot slot;
  final RouteDraftStation? station;
  final VoidCallback onClear;

  /// #1985: 이 행에서 옮겨 갈 수 있는 다른 슬롯들(현재 렌더 중인 다른 행들).
  final List<RouteDraftSlot> reorderTargets;

  /// #1985: 드래그·시맨틱 액션이 호출하는 재배열 콜백. (from, to) 슬롯을 넘긴다.
  final void Function(RouteDraftSlot from, RouteDraftSlot to) onReorder;

  /// G4: 이 칸(역명/플레이스홀더 영역)을 탭하면 역 검색을 연다. null이면 탭 불가.
  final VoidCallback? onPick;

  /// 빈 경유 칸처럼 값이 없어도 ✕로 행을 닫을 때 true.
  final bool showClearWhenEmpty;

  /// 칸 왼쪽 고정 역할 라벨('출발역'/'경유역'/'도착역').
  String get _roleLabel => slot.displayLabel;

  /// 값 영역 빈 칸 플레이스홀더.
  String get _valuePlaceholder => '${slot.displayLabel} 입력';

  String get _searchLabel => '${slot.displayLabel} 검색';

  String get _rowKey => switch (kind) {
    _RouteDraftFieldKind.origin => 'networkMapRouteDraftOriginRow',
    _RouteDraftFieldKind.waypoint => 'networkMapRouteDraftWaypointRow',
    _RouteDraftFieldKind.destination => 'networkMapRouteDraftDestinationRow',
  };

  String get _pickKey => switch (kind) {
    _RouteDraftFieldKind.origin => 'networkMapRouteDraftPickOrigin',
    _RouteDraftFieldKind.waypoint => 'networkMapRouteDraftPickWaypoint',
    _RouteDraftFieldKind.destination => 'networkMapRouteDraftPickDestination',
  };

  String get _clearKey => switch (kind) {
    _RouteDraftFieldKind.origin => 'networkMapRouteDraftClearOrigin',
    _RouteDraftFieldKind.waypoint => 'networkMapRouteDraftClearWaypoint',
    _RouteDraftFieldKind.destination => 'networkMapRouteDraftClearDestination',
  };

  @override
  Widget build(BuildContext context) {
    final roleLabel = _roleLabel;
    final filled = station != null;
    final filledStation = station;
    final showLineBadge = filledStation != null && filledStation.hasLine;
    final lineForBadge = showLineBadge
        ? StationSearchLine(
            id: filledStation.lineId,
            name: filledStation.lineName,
            color: filledStation.lineColor,
            stationCode: filledStation.stationCode,
          )
        : null;
    // 값 영역: 비면 '출발역 입력', 채우면 역명(+호선 뱃지).
    final valueText = filled ? filledStation!.displayName : _valuePlaceholder;
    final lineNameLabel =
        showLineBadge && filledStation.lineName.trim().isNotEmpty
        ? filledStation.lineName.trim()
        : null;
    final searchLabel = _searchLabel;
    final filledSemanticsCore = lineNameLabel == null
        ? '$roleLabel $valueText'
        : '$roleLabel $lineNameLabel $valueText';
    final pickSemanticsLabel = filled
        ? '$filledSemanticsCore, $searchLabel'
        : '$roleLabel, $_valuePlaceholder, $searchLabel';

    // 역할 라벨은 시각 전용·고정 폭(출발역 기준)이라 행마다 구분선이 어긋나지 않는다.
    // 색은 길찾기/팬메뉴와 동일(출발 파랑·경유 주황·도착 빨강).
    final roleColor = switch (kind) {
      _RouteDraftFieldKind.origin => EasySubwayFanMenuColors.departure,
      _RouteDraftFieldKind.waypoint => EasySubwayFanMenuColors.waypoint,
      _RouteDraftFieldKind.destination => EasySubwayFanMenuColors.arrival,
    };
    final roleLabelWidget = ExcludeSemantics(
      child: SizedBox(
        width: 72,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            roleLabel,
            maxLines: 1,
            softWrap: false,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: roleColor,
              fontSize: 15,
              fontWeight: FontWeight.w700,
              height: 1.2,
            ),
          ),
        ),
      ),
    );

    final valueRow = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (lineForBadge != null) ...[
          StationLineBadge(line: lineForBadge, size: 26),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: Text(
            valueText,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: filled
                  ? EasySubwayAccessibleColors.text
                  : EasySubwayAccessibleColors.mutedText,
              fontSize: filled ? 17 : 15,
              fontWeight: filled ? FontWeight.w700 : FontWeight.w600,
              height: 1.2,
            ),
          ),
        ),
      ],
    );

    final Widget pickArea = onPick == null
        ? Semantics(
            label: filled ? filledSemanticsCore : _valuePlaceholder,
            child: ExcludeSemantics(
              child: SizedBox(
                height: easySubwaySearchFieldVisualHeight,
                child: Center(child: valueRow),
              ),
            ),
          )
        : Semantics(
            button: true,
            label: pickSemanticsLabel,
            onTap: onPick,
            child: ExcludeSemantics(
              child: GestureDetector(
                key: Key(_pickKey),
                behavior: HitTestBehavior.opaque,
                onTap: onPick,
                child: SizedBox(
                  height: easySubwaySearchFieldVisualHeight,
                  child: Center(child: valueRow),
                ),
              ),
            ),
          );

    // 검색 박스(heroStationSearch*)와 동일 높이·면·외곽선·radius로 UX 톤을 통일한다.
    final rowContainer = Container(
      height: easySubwaySearchFieldVisualHeight,
      decoration: BoxDecoration(
        color: EasySubwayAccessibleColors.searchFieldSurface,
        borderRadius: easySubwaySearchFieldRadius,
        border: Border.all(
          color: easySubwaySearchFieldBorderColor,
          width: easySubwaySearchFieldBorderWidth,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 역할 라벨 구역(왼쪽 고정).
            Align(alignment: Alignment.centerLeft, child: roleLabelWidget),
            // 출발역 | 선택역 사이 경계(외곽선과 동일 톤·굵기).
            Container(
              width: easySubwaySearchFieldBorderWidth,
              color: easySubwaySearchFieldBorderColor,
            ),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 10,
                  right: (filled || showClearWhenEmpty) ? 0 : 10,
                ),
                child: pickArea,
              ),
            ),
            if (filled || showClearWhenEmpty)
              Semantics(
                button: true,
                label: filled ? '$roleLabel 지우기' : '$roleLabel 칸 닫기',
                onTap: onClear,
                child: ExcludeSemantics(
                  child: IconButton(
                    key: Key(_clearKey),
                    onPressed: onClear,
                    style: IconButton.styleFrom(
                      splashFactory: NoSplash.splashFactory,
                      highlightColor: Colors.transparent,
                      backgroundColor: Colors.transparent,
                      elevation: 0,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    icon: Container(
                      width: 22,
                      height: 22,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        color: EasySubwayAccessibleColors.disclosure,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.close,
                        size: 14,
                        color: EasySubwayAccessibleColors.interactionOnPrimary,
                      ),
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 40,
                      minHeight: 40,
                    ),
                    padding: const EdgeInsets.only(right: 4),
                  ),
                ),
              ),
          ],
        ),
      ),
    );

    // #1985: 채워진 행만 드래그로 재배열할 수 있다. 빈 행은 드래그 소스를 두지
    // 않고 이동 대상(DragTarget)으로만 쓴다.
    Widget content = rowContainer;
    if (filled) {
      content = LongPressDraggable<RouteDraftSlot>(
        data: slot,
        maxSimultaneousDrags: 1,
        dragAnchorStrategy: childDragAnchorStrategy,
        // 드래그 피드백: 무채색·radius 8·elevation 0·그림자 없음(#1933 원칙 유지).
        feedback: Material(
          elevation: 0,
          type: MaterialType.transparency,
          child: SizedBox(
            width: 220,
            child: Container(
              height: easySubwaySearchFieldVisualHeight,
              decoration: BoxDecoration(
                color: EasySubwayAccessibleColors.searchFieldSurface,
                borderRadius: easySubwaySearchFieldRadius,
                border: Border.all(
                  color: easySubwaySearchFieldBorderColor,
                  width: easySubwaySearchFieldBorderWidth,
                ),
              ),
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: [
                  Text(
                    roleLabel,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: EasySubwayAccessibleColors.mutedText,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (lineForBadge != null) ...[
                    StationLineBadge(line: lineForBadge, size: 30),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Text(
                      station!.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: EasySubwayAccessibleColors.text,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // 드래그 중 원래 행은 무채색으로 흐리게(노선색/틴트 없음).
        childWhenDragging: Opacity(opacity: 0.4, child: rowContainer),
        child: rowContainer,
      );
      // 커스텀 시맨틱 액션: 각 대상 슬롯으로 '~으로 이동'. child 트리 밖 wrapper라
      // 별도 SemanticsNode로 병합된다.
      content = Semantics(
        container: true,
        customSemanticsActions: <CustomSemanticsAction, VoidCallback>{
          for (final target in reorderTargets)
            CustomSemanticsAction(label: '${target.displayLabel}으로 이동'): () =>
                onReorder(slot, target),
        },
        child: content,
      );
    }

    // 모든 행(빈 행 포함)이 이동 대상이 된다. 행 키는 최상위 DragTarget에 둔다.
    return DragTarget<RouteDraftSlot>(
      key: Key(_rowKey),
      onWillAcceptWithDetails: (details) => details.data != slot,
      onAcceptWithDetails: (details) => onReorder(details.data, slot),
      builder: (context, candidateData, rejectedData) => content,
    );
  }
}

/// #1948: 출발/경유/도착으로 지정된 역 위에 맵 핀을 표시한다.
/// 실루엣 에셋 + 내부 팬 메뉴색 + 외곽선은 상단바 '수도권' 글자색(#606060).
/// 뾰족한 끝은 [anchorSource](일반 노드/환승 캡슐 중심) 정중앙에 둔다.
class _NetworkMapDraftPin extends StatelessWidget {
  const _NetworkMapDraftPin({
    super.key,
    required this.station,
    required this.anchorSource,
    required this.camera,
    required this.label,
    required this.surfaceColor,
    required this.semanticSuffix,
    required this.clearButtonKey,
    required this.onClear,
    this.ignorePointers = false,
  });

  static const _assetPath = 'assets/illustrations/map_draft_pin.png';
  // 에셋은 800², 끝점은 하단 중앙. 표시 크기는 터치·가독 균형.
  static const _pinWidth = 52.0;
  static const _pinHeight = 52.0;
  static const _clearSize = 18.0;

  /// 역할색 외곽 ≈1.5px 고정 두께(양옆 합 3px / 핀 폭).
  static const _edgeStrokePx = 1.5;
  static const _edgeScale = 1 + (2 * _edgeStrokePx) / _pinWidth;

  /// soft drop: y 3 · blur 6 상당(sigma 3).
  static const _shadowOffsetY = 3.0;
  static const _shadowBlurSigma = 3.0;

  /// ✕ soft drop: y 2 · blur 4 상당(sigma 2).
  static const _clearShadowOffsetY = 2.0;
  static const _clearShadowBlurSigma = 2.0;
  static const _labelFontSize = 13.0;
  static const _labelStrokeWidth = 3.0;

  static Color _pinEdgeFor(Color fill) {
    if (fill == EasySubwayFanMenuColors.departure) {
      return EasySubwayFanMenuColors.pinEdgeDeparture;
    }
    if (fill == EasySubwayFanMenuColors.waypoint) {
      return EasySubwayFanMenuColors.pinEdgeWaypoint;
    }
    return EasySubwayFanMenuColors.pinEdgeArrival;
  }

  final NetworkMapStation station;

  /// geometry 원점 보정된 source 좌표. 환승이면 캡슐 중심.
  final Offset anchorSource;
  final MapCameraState camera;
  final String label;
  final Color surfaceColor;
  final String semanticSuffix;
  final Key clearButtonKey;
  final VoidCallback onClear;

  /// 줌/팬 제스처 중 핀치가 핀에 먹히지 않도록 포인터를 통과시킨다.
  final bool ignorePointers;

  @override
  Widget build(BuildContext context) {
    final anchorPoint = camera.sourceToViewportPoint(anchorSource);
    // ✕는 핀 머리 우상단에 붙이므로, 핀 기준으로 여유를 둔다.
    const hitPadLeft = 8.0;
    const hitPadRight = 18.0;
    const hitPadTop = 10.0;
    const hitPadBottom = 0.0;
    const hitWidth = _pinWidth + hitPadLeft + hitPadRight;
    const hitHeight = _pinHeight + hitPadTop + hitPadBottom;
    final viewportWidth = camera.viewportSize.width;
    // 핀 이미지 하단 중앙(뾰족한 끝)이 앵커에 오도록 배치.
    final pinLeft = anchorPoint.dx - _pinWidth / 2;
    final pinTop = anchorPoint.dy - _pinHeight;
    final hitLeft = (pinLeft - hitPadLeft)
        .clamp(4.0, math.max(4.0, viewportWidth - hitWidth - 4))
        .toDouble();
    final hitTop = math.max(4.0, pinTop - hitPadTop);
    final pinOffsetInHit = Offset(pinLeft - hitLeft, pinTop - hitTop);
    // ✕는 카카오처럼 핀 머리 안쪽·약간 위에 붙인다. 터치 타깃은 그 중심 기준 56.
    final clearVisualLeft = pinOffsetInHit.dx + _pinWidth - (_clearSize * 0.92);
    final clearVisualTop = pinOffsetInHit.dy - (_clearSize * 0.42);
    final clearHitLeft =
        clearVisualLeft + _clearSize / 2 - EasySubwayTouchTarget.general / 2;
    final clearHitTop =
        clearVisualTop + _clearSize / 2 - EasySubwayTouchTarget.general / 2;
    final edgeColor = _pinEdgeFor(surfaceColor);
    return Positioned(
      left: hitLeft,
      top: hitTop,
      width: hitWidth,
      height: hitHeight,
      child: IgnorePointer(
        ignoring: ignorePointers,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: pinOffsetInHit.dx,
              top: pinOffsetInHit.dy,
              width: _pinWidth,
              height: _pinHeight,
              child: Semantics(
                container: true,
                label: '${station.displayName}, $semanticSuffix',
                child: ExcludeSemantics(
                  child: Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.center,
                    children: [
                      // soft drop → 역할색 외곽(≈1.5px) → 역할색 면.
                      ImageFiltered(
                        imageFilter: ImageFilter.blur(
                          sigmaX: _shadowBlurSigma,
                          sigmaY: _shadowBlurSigma,
                          tileMode: TileMode.decal,
                        ),
                        child: Transform.translate(
                          offset: const Offset(0, _shadowOffsetY),
                          child: ColorFiltered(
                            colorFilter: const ColorFilter.mode(
                              EasySubwayFanMenuColors.pinShadow,
                              BlendMode.srcIn,
                            ),
                            child: Image.asset(
                              _assetPath,
                              width: _pinWidth,
                              height: _pinHeight,
                              fit: BoxFit.contain,
                              filterQuality: FilterQuality.high,
                            ),
                          ),
                        ),
                      ),
                      Transform.scale(
                        scale: _edgeScale,
                        child: ColorFiltered(
                          colorFilter: ColorFilter.mode(
                            edgeColor,
                            BlendMode.srcIn,
                          ),
                          child: Image.asset(
                            _assetPath,
                            width: _pinWidth,
                            height: _pinHeight,
                            fit: BoxFit.contain,
                            filterQuality: FilterQuality.high,
                          ),
                        ),
                      ),
                      ColorFiltered(
                        colorFilter: ColorFilter.mode(
                          surfaceColor,
                          BlendMode.srcIn,
                        ),
                        child: Image.asset(
                          _assetPath,
                          width: _pinWidth,
                          height: _pinHeight,
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.high,
                        ),
                      ),
                      // 라벨: 흰 글자 + 핀색 외곽선.
                      Align(
                        alignment: const Alignment(0, -0.28),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                Text(
                                  label,
                                  textAlign: TextAlign.center,
                                  maxLines: 1,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: _labelFontSize,
                                    height: 1.0,
                                    foreground: Paint()
                                      ..style = PaintingStyle.stroke
                                      ..strokeWidth = _labelStrokeWidth
                                      ..strokeJoin = StrokeJoin.round
                                      ..color = surfaceColor,
                                  ),
                                ),
                                Text(
                                  label,
                                  textAlign: TextAlign.center,
                                  maxLines: 1,
                                  style: const TextStyle(
                                    color: EasySubwayAccessibleColors
                                        .interactionOnPrimary,
                                    fontWeight: FontWeight.w700,
                                    fontSize: _labelFontSize,
                                    height: 1.0,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              left: clearHitLeft,
              top: clearHitTop,
              width: EasySubwayTouchTarget.general,
              height: EasySubwayTouchTarget.general,
              child: Semantics(
                button: true,
                label: '$label 지우기',
                onTap: onClear,
                child: ExcludeSemantics(
                  child: GestureDetector(
                    key: clearButtonKey,
                    behavior: HitTestBehavior.opaque,
                    onTap: onClear,
                    child: Center(
                      child: SizedBox(
                        width: _clearSize + 4,
                        height: _clearSize + 4,
                        child: Stack(
                          alignment: Alignment.center,
                          clipBehavior: Clip.none,
                          children: [
                            ImageFiltered(
                              imageFilter: ImageFilter.blur(
                                sigmaX: _clearShadowBlurSigma,
                                sigmaY: _clearShadowBlurSigma,
                                tileMode: TileMode.decal,
                              ),
                              child: Transform.translate(
                                offset: const Offset(0, _clearShadowOffsetY),
                                child: Container(
                                  width: _clearSize,
                                  height: _clearSize,
                                  decoration: const BoxDecoration(
                                    color:
                                        EasySubwayFanMenuColors.pinClearShadow,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                            ),
                            Container(
                              width: _clearSize,
                              height: _clearSize,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: EasySubwayFanMenuColors.pinClearBg,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: EasySubwayFanMenuColors.pinClearBorder,
                                  width: 1,
                                ),
                              ),
                              child: const Icon(
                                Icons.close_rounded,
                                size: 11,
                                color: EasySubwayFanMenuColors.pinClearInk,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

RouteDraftStation _routeDraftStationFromMapStation(
  NetworkMapStation station,
  NetworkMapData? data,
) {
  NetworkMapLine? line;
  final lineId = station.lineId.trim();
  if (data != null && lineId.isNotEmpty) {
    for (final candidate in data.lines) {
      if (candidate.id == lineId) {
        line = candidate;
        break;
      }
    }
  }
  return RouteDraftStation(
    id: station.id,
    nameKo: station.nameKo,
    lineId: lineId,
    lineName: line?.name ?? '',
    lineColor: line?.color ?? '',
    stationCode: station.stationCode,
  );
}
