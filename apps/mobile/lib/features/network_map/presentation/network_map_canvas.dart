import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../../accessible_design.dart';
import '../../../design_tokens.dart';
import '../../../mobile_error_reporter.dart';
import '../../route_draft/domain/route_draft.dart';
import '../data/network_map_attribution_cache.dart';
import '../data/network_map_owner_labels_cache.dart';
import '../domain/map_camera.dart';
import '../domain/network_map_models.dart';
import '../domain/network_map_station_selection.dart';
import '../domain/route_map_design_space.dart';
import '../domain/route_map_min_scale.dart';
import '../domain/route_map_owner_labels.dart';
import '../domain/structured_route_map.dart';
import 'network_map_camera_policy.dart';
import 'network_map_draft_pin.dart';
import 'network_map_geometry.dart';
import 'network_map_unavailable_states.dart';
import 'route_map_basemap_view.dart';
import 'route_map_owner_label_bounds.dart';
import 'station_fan_menu.dart';
import 'station_fan_menu_policy.dart';
import 'station_hit_target.dart';
import 'structured_route_map_painter.dart';

class NetworkMapCanvas extends StatefulWidget {
  const NetworkMapCanvas({
    super.key,
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
  State<NetworkMapCanvas> createState() => _NetworkMapCanvasState();
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

class _NetworkMapCanvasState extends State<NetworkMapCanvas>
    with WidgetsBindingObserver {
  String? _layoutKey;
  String? _layoutRegion;
  MapCameraState? _camera;
  MapCameraState? _pendingCamera;
  MapCameraState? _requestedRendererCamera;
  MapCameraState? _presentedRendererCamera;
  final _requestedRendererCamerasByRevision = <int, MapCameraState>{};
  bool _routeMapBasemapFailed = false;
  DateTime? _lastRendererCameraRequestAt;
  bool _cameraFrameCallbackScheduled = false;
  bool _forceRendererCameraCommit = false;
  bool _gestureActive = false;
  (String, bool)? _cameraFocusedStationKey;
  MapCameraState? _gestureStartCamera;
  Offset? _gestureStartFocalPoint;
  String? _geometryCacheKey;
  NetworkMapGeometry? _geometryCache;
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
  void didUpdateWidget(covariant NetworkMapCanvas oldWidget) {
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
          final hitGeometry = NetworkMapStationHitGeometry(geometry: geometry);
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
          if (_routeMapBasemapFailed || widget.data.stations.isEmpty) {
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
                                  hitGeometry,
                                  interactionCamera,
                                );
                              },
                      ),
                    ),
                  ),
                ),
              if (interactionCamera != null && !_gestureActive)
                for (final station in hitGeometry.visibleCanonicalStations(
                  camera: interactionCamera,
                ))
                  Positioned.fromRect(
                    rect: hitGeometry.viewportBoundsFor(
                      station,
                      camera: interactionCamera,
                      nodeRadius: 24 / interactionCamera.scale,
                      labelHeight: 40 / interactionCamera.scale,
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
                NetworkMapDraftPin(
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
                NetworkMapDraftPin(
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
                NetworkMapDraftPin(
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

  NetworkMapGeometry _geometryFor(NetworkMapData data) {
    // basemap 오너 라벨 sidecar(로드는 async)를 geometry bounds에 반영한다(#2068).
    // 로드 전엔 null → 라벨 rect 없이 계산되지만, 로드가 끝나면 setState로 rebuild
    // 되며 ownerKey가 바뀌어 캐시가 무효화되고 라벨 extents를 포함해 재계산된다
    // (stale bounds 방지 — sidecar 로드 전/후 캐시 키 구분).
    //
    // data.selectedRegion은 drift_station_repository._storedNetworkMapRegion이
    // 만든 저장형('광주권' 등 접미 포함)이라 kRouteMapBasemapRegionToId의 짧은
    // 키('광주')와 직접 안 맞는다 — routeMapDisplayRegionName으로 정규화해야 조회가
    // 성공한다(실기기 회귀: 정규화 누락으로 basemapAssetId가 항상 null이 돼
    // 라벨이 bounds에 전혀 반영되지 않았다, #2068).
    final basemapAssetId =
        kRouteMapBasemapRegionToId[routeMapDisplayRegionName(
          data.selectedRegion,
        )];
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
    final geometry = NetworkMapGeometry.fromStations(
      data.stations,
      ownerLabelSourceRects: ownerLabelSourceRects,
      stationSourceBoundsFor:
          NetworkMapStationHitGeometry.sourceBoundsForStation,
      stationKeyFor: NetworkMapStationHitGeometry.stationKeyFor,
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
        kRouteMapBasemapRegionToId[routeMapDisplayRegionName(
          data.selectedRegion,
        )];
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
      _lastRendererCameraRequestAt =
          identical(skippedCommitCamera, _requestedRendererCamera)
          ? _lastRendererCameraRequestAt
          : now;
      return skippedCommitCamera;
    }
    _lastRendererCameraRequestAt = now;
    return requestedCamera;
  }

  void _openNearestStation(
    Offset viewportPosition,
    NetworkMapStationHitGeometry hitGeometry,
    MapCameraState camera,
  ) {
    final station = hitGeometry.stationAtViewportPosition(
      viewportPosition,
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
    final revealOffset = fanMenuRevealOffset(
      menuRect: menuRect,
      viewport: camera.viewportSize,
    );
    if (revealOffset == Offset.zero) {
      return;
    }
    // 뷰포트 픽셀 이동 → source 좌표 center 이동(반대 방향).
    final nextCenter = camera.center - revealOffset / camera.scale;
    // #2192: v3는 flip을 제거하고 항상 노드 위에 배치하므로, 지도 최상단(경계)
    // 역에서도 꼬리 팁이 노드에 닿은 채 메뉴 전체가 드러나려면 카메라가 source
    // 경계를 메뉴 높이만큼 넘겨 패닝할 수 있어야 한다. clamped 헤드룸을 메뉴
    // 높이+여백으로 열어 상단 여유를 준다(reveal offset은 필요한 방향으로만 이동하므로
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
        region: routeMapDisplayRegionName(widget.data.selectedRegion),
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
    NetworkMapGeometry geometry,
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
  /// 일반역은 노드 좌표 그대로 유도한 뒤 [NetworkMapGeometry] 원점을 빼
  /// [MapCameraState.sourceToViewportPoint] 입력 좌표계로 맞춘다.
  /// 드래프트 핀(출발·경유·도착)이 이 좌표를 그대로 앵커로 쓴다. 팬 메뉴는
  /// 여기서 한 번 더 올린 [_fanMenuTailAnchorSource]를 쓴다(#2068 QA).
  Offset _fanMenuAnchorSource(
    NetworkMapStation station,
    NetworkMapGeometry geometry,
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

/// [initialBounds]는 이 지역이 실제로 쓰는 초기 카메라 bounds다(#2068 트랙 QA
/// 후속으로 [networkMapInitialCameraBounds]가 확대해 준 값). geometry의 원
/// initialBounds를 쓰면 초기 화면이 확대된 만큼 focus가 오히려 축소돼 #2062
/// ("focus는 초기 화면보다 확대") 불변식이 깨진다 — 두 카메라가 같은 bounds를
/// 공유해야 focus 배율이 항상 동일한 feature policy로 계산된다.
Rect _stationFocusBoundsFor(
  NetworkMapStation station,
  NetworkMapGeometry geometry, {
  required Rect initialBounds,
}) {
  return networkMapStationFocusBounds(
    initialBounds: initialBounds,
    center: Offset(geometry.x(station), geometry.y(station)),
    sourceWidth: geometry.width,
    sourceHeight: geometry.height,
  );
}
