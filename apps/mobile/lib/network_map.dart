import 'dart:async';

import 'package:flutter/material.dart';

import 'accessible_design.dart';
import 'ad_slot.dart';
import 'design_tokens.dart';
import 'features/ads/ad_repository.dart';
import 'features/facility_report/domain/facility_report_repository.dart';
import 'features/facility_report/domain/facility_report_target.dart';
import 'features/network_map/application/network_map_nearby_display_cache.dart';
import 'features/network_map/application/network_map_load_result.dart';
import 'features/network_map/application/nearby_panel_request_key.dart';
import 'features/network_map/application/network_map_region_bridge.dart';
import 'features/network_map/application/network_map_nearby_panel_state.dart';
import 'features/network_map/application/network_map_route_draft_station_projection.dart';
import 'features/network_map/data/network_map_owner_labels_cache.dart';
import 'features/network_map/domain/nearby_adjacent_stations.dart';
import 'features/network_map/domain/network_map_edge_topology.dart';
import 'features/network_map/domain/network_map_models.dart';
import 'features/network_map/domain/route_map_min_scale.dart';
import 'features/network_map/domain/route_map_owner_labels.dart';
import 'features/network_map/presentation/nearby_arrival_panel.dart';
import 'features/network_map/presentation/nearby_data_source_toggle.dart';
import 'features/network_map/presentation/nearby_station_line_bar.dart';
import 'features/network_map/presentation/nearby_timetable_panel.dart';
import 'features/network_map/presentation/network_map_chrome_controls.dart';
import 'features/network_map/presentation/network_map_canvas.dart';
import 'features/network_map/presentation/network_map_menu_panel.dart';
import 'features/network_map/presentation/network_map_unavailable_states.dart';
import 'features/realtime/realtime_repository.dart';
import 'features/route_draft/application/route_draft_controller.dart';
import 'features/route_draft/domain/route_draft.dart';
import 'features/stations/presentation/service_pattern_badge.dart';
import 'features/stations/presentation/station_detail_body.dart';
import 'features/stations/presentation/station_detail_screen.dart';
import 'features/stations/presentation/station_line_badges.dart';
import 'internal_route.dart';
import 'mobile_error_reporter.dart';
import 'station_search.dart';

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
  NetworkMapNearbyPanelData<StationSearchResult> _nearbyPanelData =
      const NetworkMapNearbyPanelData<StationSearchResult>.idle();
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
  NetworkMapNearbyRealtimeDisplay<RealtimeSnapshot>? _nearbyRealtimeDisplay;

  /// 성공한 시간표만 stationId+lineId 키로 보관. 실패로 성공 캐시를 지우지 않는다.
  NetworkMapNearbyTimetableDisplay<StationTimetable>? _nearbyTimetableDisplay;
  NetworkMapNearbyPanelDataSource _nearbyDataSource =
      NetworkMapNearbyPanelDataSource.realtime;

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
      _nearbyPanelData = NetworkMapNearbyPanelData.success([station]);
      // 모든 오픈 경로 기본 탭은 시간표. 실시간은 백그라운드 prefetch.
      // keyed display는 지우지 않는다 — 키 불일치면 미표시, 일치하면 즉시 재사용.
      _nearbyDataSource = NetworkMapNearbyPanelDataSource.timetable;
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
              return _buildNetworkMapChrome(
                regions: const [NetworkMapRegion(name: '수도권')],
                selectedRegion: _selectedRegion ?? '수도권',
                adjacentStations: const NearbyAdjacentStations(),
                child: const Center(child: CircularProgressIndicator()),
              );
            }
            if (snapshot.hasError || !snapshot.hasData) {
              return _buildNetworkMapChrome(
                regions: const [NetworkMapRegion(name: '수도권')],
                selectedRegion: _selectedRegion ?? '수도권',
                adjacentStations: const NearbyAdjacentStations(),
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
            return _buildNetworkMapChrome(
              regions: data.regions,
              selectedRegion: data.selectedRegion,
              adjacentStations: _adjacentStationsFor(data),
              // #1933: _setOriginStation은 routeDraftController만 갱신하고 이
              // State에서 setState를 호출하지 않으므로, canvas를 좁게
              // ListenableBuilder로 감싸 draft 변경 시 하위 트리가 다시
              // 계산되게 한다(그래야 슬롯 배정 상태가 즉시 반영됨).
              child: ListenableBuilder(
                listenable: widget.routeDraftController,
                builder: (context, _) {
                  return NetworkMapCanvas(
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
            : const NetworkMapBottomAdBanner(
                // 실광고 미연동: release에서는 placeholder 없이 슬롯이 collapse된다.
                slot: AdBannerSlot(slotKey: Key('networkMapBottomAdBanner')),
              ),
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
      _nearbyPanelData =
          const NetworkMapNearbyPanelData<StationSearchResult>.loading();
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
    _nearbyPanelData =
        const NetworkMapNearbyPanelData<StationSearchResult>.idle();
    _nearbyRealtimeDisplay = null;
    _nearbyDataSource = NetworkMapNearbyPanelDataSource.realtime;
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
          _nearbyRealtimeDisplay = NetworkMapNearbyRealtimeDisplay(
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
        _nearbyDataSource == NetworkMapNearbyPanelDataSource.realtime;
    if (!shouldFallbackToTimetable) {
      return;
    }
    final hasTimetable = _nearbyTimetableDisplayMatchesCurrent();
    setState(() {
      _nearbyDataSource = NetworkMapNearbyPanelDataSource.timetable;
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
        _nearbyTimetableDisplay = NetworkMapNearbyTimetableDisplay(
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
    final next = _nearbyDataSource == NetworkMapNearbyPanelDataSource.realtime
        ? NetworkMapNearbyPanelDataSource.timetable
        : NetworkMapNearbyPanelDataSource.realtime;
    setState(() {
      _nearbyDataSource = next;
    });
    if (next == NetworkMapNearbyPanelDataSource.realtime) {
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
      networkMapRouteDraftStation(station, _latestMapData),
    );
    _dismissNearbyPanelForDraft();
  }

  void _setDestinationStation(NetworkMapStation station) {
    widget.routeDraftController.setDestination(
      networkMapRouteDraftStation(station, _latestMapData),
    );
    _dismissNearbyPanelForDraft();
  }

  void _setWaypointStation(NetworkMapStation station) {
    widget.routeDraftController.setWaypoint(
      networkMapRouteDraftStation(station, _latestMapData),
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

  Widget _buildNetworkMapChrome({
    required List<NetworkMapRegion> regions,
    required String selectedRegion,
    required NearbyAdjacentStations adjacentStations,
    required Widget child,
  }) {
    final searchBody = _buildSearchBody();
    final inSearchMode = _searchMode && searchBody != null;
    return NetworkMapChrome(
      topBar: NetworkMapTopBar(
        regions: regions,
        selectedRegion: selectedRegion,
        notificationAction: widget.notificationAction,
        onMenuTap: _openMapMenu,
        onSearchTap: _enterSearchMode,
        searchMode: inSearchMode,
        onSearchBack: _exitSearchMode,
        searchQueryController: _searchQueryController,
        searchFocusNode: _searchFocusNode,
        onSearchSubmitted: _submitSearch,
        onSearchClear: _searchQueryController.clear,
        onRegionSelected: (region) => _reload(region: region),
        routeDraftListenable: widget.routeDraftController,
        routeDraft: () => widget.routeDraftController.draft,
        isWaypointRowVisible: () =>
            widget.routeDraftController.isWaypointRowVisible,
        onClearDraft: widget.routeDraftController.clear,
        onOpenWaypointSlot: widget.routeDraftController.openWaypointSlot,
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
        roleColorForSlot: (slot) => switch (slot) {
          RouteDraftSlot.origin => EasySubwayFanMenuColors.departure,
          RouteDraftSlot.waypoint => EasySubwayFanMenuColors.waypoint,
          RouteDraftSlot.destination => EasySubwayFanMenuColors.arrival,
        },
        lineBadgeBuilder: (station, size) => StationLineBadge(
          line: StationSearchLine(
            id: station.lineId,
            name: station.lineName,
            color: station.lineColor,
            stationCode: station.stationCode,
          ),
          size: size,
        ),
      ),
      disruptionBanner: widget.disruptionBanner,
      searchMode: inSearchMode,
      searchBody: searchBody,
      nearbyPanelVisible: _nearbyPanelVisible,
      nearbyPanelExpanded: _nearbyPanelExpanded,
      nearbyPanel: _NetworkMapNearbyStationPanel(
        data: _nearbyPanelData,
        expanded: _nearbyPanelExpanded,
        realtime: _nearbyRealtimeForDisplay,
        selectedLineId: _nearbySelectedLineId,
        dataSource: _nearbyDataSource,
        timetable: _nearbyTimetableForDisplay,
        adjacentStations: adjacentStations,
        onClose: _hideNearbyPanel,
        onLineSelected: _selectNearbyLine,
        onDataSourceToggle: _toggleNearbyDataSource,
        onOpenStationDetail: _nearbyStationDetailAction,
        onSelectNeighbor: _selectNearbyNeighborStation,
        stationSearchRepository: widget.stationSearchRepository,
        reportRepository: widget.reportRepository,
        favoriteRepository: widget.favoriteRepository,
        adRepository: widget.adRepository,
        realtimeRepository: widget.realtimeRepository,
        locationProvider: widget.locationProvider,
        facilityReportDraftTargetStore: widget.facilityReportDraftTargetStore,
        internalRouteRepository: widget.internalRouteRepository,
        internalRouteMobilityType: widget.internalRouteMobilityType,
        routeDraftController: widget.routeDraftController,
      ),
      nearbyLookupMessage: _nearbyLookupMessage,
      onCurrentLocationTap: _showNearestStationFanMenu,
      child: child,
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

/// #1915 홈 노선도 in-place 역 검색의 "세션" — 검색 컨트롤러·디바운스·최근
/// 검색어·결과 본문 등 키 입력마다 바뀌는 상태를 이 서브트리로 격리한다.
/// 검색 모드로 진입/이탈하는 모드 플래그만 상위 [_NetworkMapScreenState]에
/// 남고, 타이핑으로 인한 재빌드는 이 세션(검색 필드 지우기 버튼·결과 본문)에
/// 국한된다. 그래야 지도 canvas·chrome 서브트리가 키 입력마다 재빌드되지
/// 않아 입력 지연이 사라진다.
///
/// 상단바의 편집 필드는 [NetworkMapChrome]의 별도 Stack 자식이라 이 세션이
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

  final NetworkMapNearbyPanelData<StationSearchResult> data;
  final bool expanded;
  final RealtimeSnapshot realtime;
  final String? selectedLineId;
  final NetworkMapNearbyPanelDataSource dataSource;
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
                      isRealtime:
                          dataSource ==
                          NetworkMapNearbyPanelDataSource.realtime,
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

  final NetworkMapNearbyPanelData<StationSearchResult> data;
  final RealtimeSnapshot realtime;
  final String? selectedLineId;
  final NetworkMapNearbyPanelDataSource dataSource;
  final StationTimetable? timetable;
  final NearbyAdjacentStations adjacentStations;
  final VoidCallback? onOpenStationDetail;
  final ValueChanged<StationDetailNeighbor>? onSelectNeighbor;

  @override
  Widget build(BuildContext context) {
    return switch (data.status) {
      NetworkMapNearbyPanelStatus.idle ||
      NetworkMapNearbyPanelStatus.loading => const SizedBox(
        height: 132,
        child: Center(child: CircularProgressIndicator()),
      ),
      NetworkMapNearbyPanelStatus.success => _NetworkMapNearbySuccessList(
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
  final NetworkMapNearbyPanelDataSource dataSource;
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
          child: dataSource == NetworkMapNearbyPanelDataSource.realtime
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

/// 저장형 권역명('부산권')을 표시형('부산')으로 정규화한다. 규칙의 단일 원본은
/// [routeMapDisplayRegionName]이다 — 사본을 두면 한쪽만 갱신돼 조회가 조용히
/// 어긋난다(#2068).
String _displayRegionName(String region) => routeMapDisplayRegionName(region);
