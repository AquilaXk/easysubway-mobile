import 'dart:async';

import 'package:flutter/material.dart';

import '../accessible_design.dart';
import '../features/route_draft/application/route_draft_controller.dart';
import '../features/route_draft/domain/route_draft.dart';
import '../features/stations/application/station_search_controller.dart';
import '../features/stations/domain/station_line.dart';
import '../features/stations/domain/station_models.dart';
import '../features/stations/domain/station_repositories.dart';
import '../features/stations/presentation/station_recent_search_section.dart';
import '../features/stations/presentation/station_search_body.dart';
import '../mobile_error_reporter.dart';

/// 홈 노선도 in-place 역 검색의 app-composition 세션이다.
///
/// 검색 컨트롤러·디바운스·최근 검색어·결과 본문 등 키 입력마다 바뀌는 상태를
/// 이 서브트리로 격리한다. 상위 Network Map screen에는 검색 모드 플래그와
/// top-bar 편집 controller/focus만 남는다.
class NetworkMapSearchSession extends StatefulWidget {
  const NetworkMapSearchSession({
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
  State<NetworkMapSearchSession> createState() =>
      NetworkMapSearchSessionState();
}

class NetworkMapSearchSessionState extends State<NetworkMapSearchSession> {
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
  void didUpdateWidget(covariant NetworkMapSearchSession oldWidget) {
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
