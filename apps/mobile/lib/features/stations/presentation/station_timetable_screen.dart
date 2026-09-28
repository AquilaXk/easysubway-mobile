import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';

import '../../../accessible_design.dart';
import '../../../mobile_error_reporter.dart';
import '../data/server_station_timetable_repository.dart';
import '../domain/station_line.dart';
import '../domain/station_models.dart';
import '../domain/station_repositories.dart';
import 'service_pattern_badge.dart';

class StationTimetableScreen extends StatefulWidget {
  const StationTimetableScreen({
    required this.stationId,
    required this.stationName,
    required this.lines,
    this.repository,
    this.previousStation,
    this.nextStation,
    super.key,
  });

  final String stationId;
  final String stationName;
  final List<StationSearchLine> lines;
  final StationTimetableRepository? repository;
  final String? previousStation;
  final String? nextStation;

  @override
  State<StationTimetableScreen> createState() => _StationTimetableScreenState();
}

class _StationTimetableScreenState extends State<StationTimetableScreen>
    with WidgetsBindingObserver {
  late String? _lineId;
  late StationTimetableDayType _dayType;
  StationTimetable? _timetable;
  String? _directionName;
  String? _selectedDirectionFilter;
  final Map<String, String> _destinationFilters = {};
  bool _filterFirstLast = false;
  bool _filterExpress = false;
  int _selectedHour = 5;
  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey> _hourKeys = {};
  var _loading = false;
  var _requestId = 0;
  var _isNetworkError = false;
  Timer? _tickerTimer;
  Duration _tickerElapsed = Duration.zero;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lineId = widget.lines.firstOrNull?.id;
    final now = clock.now();
    _dayType = _todayTimetableDayType(now);
    _selectedHour = _initSelectedHour(now);
    if (widget.repository != null && _lineId != null) {
      unawaited(_loadInitialAvailableLine(now));
    }
    _startTicker();
  }

  @override
  void didUpdateWidget(StationTimetableScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.stationId != oldWidget.stationId ||
        widget.repository != oldWidget.repository) {
      _destinationFilters.clear();
      _selectedDirectionFilter = null;
      _lineId = widget.lines.firstOrNull?.id;
      final now = clock.now();
      _dayType = _todayTimetableDayType(now);
      _selectedHour = _initSelectedHour(now);
      if (widget.repository != null && _lineId != null) {
        unawaited(_loadInitialAvailableLine(now));
      }
    }
  }

  void _startTicker() {
    _tickerTimer?.cancel();
    _tickerTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (!mounted) return;
      setState(() {
        _tickerElapsed += const Duration(seconds: 10);
      });
    });
  }

  void _stopTicker() {
    _tickerTimer?.cancel();
    _tickerTimer = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startTicker();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      _stopTicker();
    }
  }

  @override
  void dispose() {
    _stopTicker();
    _scrollController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  DateTime get _effectiveNow {
    return clock.now().add(_tickerElapsed);
  }

  int _initSelectedHour(DateTime now) {
    final h = now.hour;
    if (h >= 5 && h <= 23) return h;
    if (h < 5) return 24;
    return 5;
  }

  Future<void> _loadInitialAvailableLine(DateTime date) async {
    final repository = widget.repository;
    if (repository == null) return;
    final requestId = ++_requestId;
    setState(() {
      _loading = true;
      _isNetworkError = false;
    });
    StationTimetable? unavailable;
    try {
      for (final line in widget.lines) {
        final timetable = await repository.loadStationTimetableForDate(
          stationId: widget.stationId,
          lineId: line.id,
          date: date,
        );
        if (!mounted || requestId != _requestId) return;
        if (timetable.isAvailable) {
          _applyTimetable(timetable);
          return;
        }
        unavailable ??= timetable;
      }
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _timetable = unavailable;
        _directionName = null;
        _loading = false;
        _isNetworkError = false;
      });
    } on StationTimetableUnavailable {
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _timetable = null;
        _directionName = null;
        _loading = false;
        _isNetworkError = false;
      });
    } on ServerConnectionException catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '역 초기 시간표 조회 중 서버 장애가 발생했습니다.',
      );
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _timetable = null;
        _directionName = null;
        _loading = false;
        _isNetworkError = true;
      });
    } catch (error, stackTrace) {
      reportMobileError(error, stackTrace, context: '역 시간표 조회 중 예외가 발생했습니다.');
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _timetable = null;
        _directionName = null;
        _loading = false;
        _isNetworkError = false;
      });
    }
  }

  Future<void> _load({DateTime? date}) async {
    final repository = widget.repository;
    final lineId = _lineId;
    if (repository == null || lineId == null) {
      return;
    }
    final requestId = ++_requestId;
    setState(() {
      _loading = true;
      _isNetworkError = false;
    });
    try {
      final timetable = date == null
          ? await repository.loadStationTimetable(
              stationId: widget.stationId,
              lineId: lineId,
              dayType: _dayType,
              referenceDate: clock.now(),
            )
          : await repository.loadStationTimetableForDate(
              stationId: widget.stationId,
              lineId: lineId,
              date: date,
            );
      if (!mounted || requestId != _requestId) {
        return;
      }
      _applyTimetable(timetable);
    } on StationTimetableUnavailable {
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _timetable = null;
        _directionName = null;
        _loading = false;
        _isNetworkError = false;
      });
    } on ServerConnectionException catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '역 시간표 조회 중 서버 장애가 발생했습니다.',
      );
      if (!mounted || requestId != _requestId) {
        return;
      }
      setState(() {
        _timetable = null;
        _directionName = null;
        _loading = false;
        _isNetworkError = true;
      });
    } catch (error, stackTrace) {
      reportMobileError(error, stackTrace, context: '역 시간표 조회 중 예외가 발생했습니다.');
      if (!mounted || requestId != _requestId) {
        return;
      }
      setState(() {
        _timetable = null;
        _directionName = null;
        _loading = false;
        _isNetworkError = false;
      });
    }
  }

  void _applyTimetable(StationTimetable timetable) {
    final directionNames = timetable.directions
        .map((direction) => direction.name)
        .toSet();
    setState(() {
      _timetable = timetable;
      _lineId = timetable.lineId;
      _dayType = timetable.dayType;
      _isNetworkError = false;
      _directionName = directionNames.contains(_directionName)
          ? _directionName
          : timetable.directions.firstOrNull?.name;
      if (_selectedDirectionFilter != null &&
          !directionNames.contains(_selectedDirectionFilter)) {
        _selectedDirectionFilter = null;
      }
      _loading = false;
    });
  }

  String get _stationDisplayName {
    final name = widget.stationName.trim();
    if (name.endsWith('역')) {
      return name;
    }
    return '$name역';
  }

  int _departureToHour(StationTimetableDeparture dep) {
    final h = dep.seconds ~/ Duration.secondsPerHour;
    if (h >= 24 || h < 4) return 24;
    return h;
  }

  int _subwayHourOrder(int hour) {
    return hour < 4 ? hour + 24 : hour;
  }

  List<int> _sortSubwayHours(Iterable<int> hours) {
    final list = hours.toSet().toList();
    list.sort((a, b) {
      return _subwayHourOrder(a).compareTo(_subwayHourOrder(b));
    });
    return list;
  }

  List<int> _buildAvailableHours(StationTimetable? timetable) {
    const defaultHours = [
      5,
      6,
      7,
      8,
      9,
      10,
      11,
      12,
      13,
      14,
      15,
      16,
      17,
      18,
      19,
      20,
      21,
      22,
      23,
      24,
    ];
    final hours = <int>{...defaultHours};
    if (timetable != null) {
      for (final dir in timetable.directions) {
        for (final dep in dir.departures) {
          hours.add(_departureToHour(dep));
        }
      }
    }
    return _sortSubwayHours(hours);
  }

  void _scrollToHour(int targetHour, List<int> sortedHours) {
    setState(() => _selectedHour = targetHour);
    if (sortedHours.isEmpty) return;

    final bestHour = targetHour;

    final key = _hourKeys[bestHour];
    if (key?.currentContext != null) {
      unawaited(
        Scrollable.ensureVisible(
          key!.currentContext!,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          alignment: 0.0,
        ),
      );
    }
  }

  String _getDefaultTerminus(StationTimetableDirection direction) {
    final selected = _destinationFilters[direction.name];
    if (selected != null && selected.isNotEmpty) {
      if (selected == '전체') return '전체';
      return selected.endsWith('행') ? selected : '$selected행';
    }

    final clean = direction.name.replaceAll('방면', '').trim();
    const genericDirections = {
      '상행',
      '하행',
      '상선',
      '하선',
      '내선',
      '외선',
      '순환',
      '내선순환',
      '외선순환',
    };
    if (clean.isNotEmpty && !genericDirections.contains(clean)) {
      return clean;
    }

    final destinations = direction.departures
        .map((d) => d.destination.trim())
        .where((d) => d.isNotEmpty && !genericDirections.contains(d))
        .toSet();
    if (destinations.isNotEmpty) {
      return destinations.last;
    }
    return '전체';
  }

  List<StationTimetableDeparture> _filterDepartures(
    StationTimetableDirection direction,
  ) {
    var list = direction.departures;

    final destFilter = _destinationFilters[direction.name];
    if (destFilter != null && destFilter.isNotEmpty && destFilter != '전체') {
      final cleanFilter = destFilter.replaceAll('행', '').trim();
      list = list.where((dep) {
        final d = dep.destination.trim();
        final rawLabel = dep.destinationLabel.trim();
        return d == destFilter ||
            rawLabel == destFilter ||
            d.replaceAll('행', '').trim() == cleanFilter ||
            rawLabel.replaceAll('행', '').trim() == cleanFilter;
      }).toList();
    }

    if (_filterExpress) {
      list = list.where((dep) => dep.isExpress).toList();
    }

    if (_filterFirstLast && list.isNotEmpty) {
      list = {list.first, list.last}.toList();
    }

    return list;
  }

  StationTimetableDeparture? _findNextDeparture({
    required StationTimetableDirection direction,
    required bool isToday,
    required DateTime effectiveNow,
  }) {
    if (!isToday || direction.departures.isEmpty) return null;
    final currentSeconds =
        effectiveNow.hour * Duration.secondsPerHour +
        effectiveNow.minute * Duration.secondsPerMinute +
        effectiveNow.second;
    final isLateNight = effectiveNow.hour < 4;
    final lateNightServiceSeconds = Duration.secondsPerDay + currentSeconds;

    final nextIndex = isLateNight
        ? direction.departures.indexWhere(
            (dep) => _isLateNightCandidate(
              dep.seconds,
              currentSeconds,
              lateNightServiceSeconds,
            ),
          )
        : direction.departures.indexWhere(
            (dep) => dep.seconds >= currentSeconds,
          );

    if (nextIndex == -1) return null;
    return direction.departures[nextIndex];
  }

  Set<StationTimetableDeparture> _findPastDepartures({
    required StationTimetableDirection direction,
    required bool isToday,
    required DateTime effectiveNow,
    required StationTimetableDeparture? nextDeparture,
  }) {
    if (!isToday || nextDeparture == null) return const {};
    final nextIndex = direction.departures.indexOf(nextDeparture);
    if (nextIndex <= 0) return const {};
    return direction.departures.sublist(0, nextIndex).toSet();
  }

  String _formatDestinationLabel(
    StationTimetableDeparture departure,
    StationTimetableDirection direction,
  ) {
    if (departure.destinationLabel.isNotEmpty) {
      return departure.destinationLabel;
    }
    final fallback = direction.name.replaceAll('방면', '').trim();
    if (fallback.isNotEmpty) {
      if (fallback.contains('순환')) {
        return fallback;
      }
      return fallback.endsWith('행') ? fallback : '$fallback행';
    }
    return '열차';
  }

  @override
  Widget build(BuildContext context) {
    final timetable = _timetable;
    final currentLine =
        widget.lines.where((l) => l.id == _lineId).firstOrNull ??
        widget.lines.firstOrNull;
    final lineColor = _parseLineColor(currentLine?.color);
    final lineDisplayName = currentLine != null
        ? _formatLineName(currentLine.name)
        : '';

    final effectiveNow = _effectiveNow;
    final isToday = _dayType == _todayTimetableDayType(effectiveNow);
    final availableHours = _buildAvailableHours(timetable);
    final activeDirection =
        timetable?.directions
            .where((item) => item.name == _directionName)
            .firstOrNull ??
        timetable?.directions.firstOrNull;

    final List<StationTimetableDirection> visibleDirections;
    if (timetable == null || !timetable.isAvailable) {
      visibleDirections = const [];
    } else if (_selectedDirectionFilter != null) {
      final filtered = timetable.directions
          .where((d) => d.name == _selectedDirectionFilter)
          .toList();
      visibleDirections = filtered.isNotEmpty ? filtered : timetable.directions;
    } else {
      visibleDirections = timetable.directions;
    }

    return Scaffold(
      backgroundColor: EasySubwayAccessibleColors.surface,
      appBar: AppBar(
        backgroundColor: EasySubwayAccessibleColors.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        automaticallyImplyLeading: false,
        title: Semantics(
          header: true,
          label: '${widget.stationName} 시간표',
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _stationDisplayName,
                style: TextStyle(
                  color: EasySubwayAccessibleColors.text,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              if (lineDisplayName.isNotEmpty) ...[
                const SizedBox(width: 5),
                Text(
                  lineDisplayName,
                  style: TextStyle(
                    color: lineColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          IconButton(
            tooltip: '닫기',
            icon: const Icon(
              Icons.close,
              size: 24,
              color: EasySubwayAccessibleColors.secondaryText,
            ),
            onPressed: () => unawaited(Navigator.maybePop(context)),
          ),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1.0),
          child: Divider(
            height: 1,
            thickness: 1,
            color: EasySubwayAccessibleColors.line,
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.lines.length > 1) ...[
              Container(
                color: EasySubwayAccessibleColors.surface,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final line in widget.lines)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            key: Key('stationTimetableLine-${line.id}'),
                            label: Text(
                              _formatLineName(line.name),
                              style: TextStyle(
                                fontWeight: _lineId == line.id
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                color: _lineId == line.id
                                    ? EasySubwayAccessibleColors.onPrimary
                                    : EasySubwayAccessibleColors.text,
                              ),
                            ),
                            selected: _lineId == line.id,
                            selectedColor: _parseLineColor(line.color),
                            backgroundColor:
                                EasySubwayAccessibleColors.surfaceSubtle,
                            side: BorderSide.none,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            onSelected: (_) {
                              setState(() {
                                _lineId = line.id;
                                _destinationFilters.clear();
                                _selectedDirectionFilter = null;
                              });
                              unawaited(_load());
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const Divider(
                height: 1,
                thickness: 1,
                color: EasySubwayAccessibleColors.line,
              ),
            ],

            _buildDayAndFilterBar(),
            const Divider(
              height: 1,
              thickness: 1,
              color: EasySubwayAccessibleColors.line,
            ),

            () {
              final renderedHours = _getSortedDeparturesHours(
                visibleDirections,
              );
              return _buildHourSelector(availableHours, renderedHours);
            }(),
            const Divider(
              height: 1,
              thickness: 1,
              color: EasySubwayAccessibleColors.line,
            ),

            if (_loading)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else if (_isNetworkError)
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: _buildNetworkErrorView(),
                  ),
                ),
              )
            else if (timetable == null || !timetable.isAvailable)
              const Expanded(
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: _StationTimetableEmptyMessage(
                      message: '시간표 정보가 없어요',
                    ),
                  ),
                ),
              )
            else ...[
              if (timetable.isOfflineFallback) _buildOfflineFallbackNotice(),
              _buildDirectionHeader(directions: visibleDirections),
              const Divider(
                height: 1,
                thickness: 1,
                color: EasySubwayAccessibleColors.line,
              ),

              Expanded(
                child: SingleChildScrollView(
                  controller: _scrollController,
                  child: _buildDepartureList(
                    visibleDirections: visibleDirections,
                    availableHours: availableHours,
                    effectiveNow: effectiveNow,
                    isToday: isToday,
                  ),
                ),
              ),
            ],

            _buildOffstageTestHelper(
              timetable: timetable,
              currentDirection: activeDirection,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOfflineFallbackNotice() {
    return Semantics(
      container: true,
      label: '오프라인 시간표 안내: 기기에 저장된 시간표를 표시하고 있어요. 최신 운행 정보와 다를 수 있어요.',
      child: Container(
        key: const Key('stationTimetableOfflineBanner'),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        color: EasySubwayAccessibleColors.statusWarningSurface,
        child: const Row(
          children: [
            Icon(
              Icons.warning_amber_rounded,
              size: 16,
              color: EasySubwayAccessibleColors.statusWarningContent,
            ),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                '오프라인 모드: 기기에 저장된 시간표를 표시하고 있어요. 최신 운행 정보와 다를 수 있어요.',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: EasySubwayAccessibleColors.statusWarningContent,
                  height: 1.3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNetworkErrorView() {
    return Semantics(
      container: true,
      label: '네트워크 연결 불안정, 시간표 정보를 불러오지 못했습니다. 다시 시도해 주세요.',
      child: Column(
        key: const Key('station-timetable-network-error-view'),
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: const BoxDecoration(
              color: EasySubwayAccessibleColors.surfaceSubtle,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.wifi_off_rounded,
              size: 28,
              color: EasySubwayAccessibleColors.secondaryText,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            '네트워크 연결 불안정',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: EasySubwayAccessibleColors.text,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          const Text(
            '시간표 정보를 불러올 수 없어요.\n네트워크 상태를 확인하고 다시 시도해 주세요.',
            style: TextStyle(
              fontSize: 14,
              color: EasySubwayAccessibleColors.secondaryText,
              height: 1.4,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            key: const Key('station-timetable-retry-button'),
            onPressed: () {
              unawaited(_loadInitialAvailableLine(_effectiveNow));
            },
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text(
              '다시 시도',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: EasySubwayAccessibleColors.primary,
              side: const BorderSide(color: EasySubwayAccessibleColors.primary),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDayAndFilterBar() {
    return Container(
      color: EasySubwayAccessibleColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          for (final dayType in StationTimetableDayType.values)
            _buildDayTab(dayType),
          const Spacer(),
          _buildFilterCapsule(
            label: '첫·막차',
            isSelected: _filterFirstLast,
            onTap: () {
              setState(() {
                _filterFirstLast = !_filterFirstLast;
              });
            },
          ),
          const SizedBox(width: 6),
          _buildFilterCapsule(
            label: '급행',
            isSelected: _filterExpress,
            onTap: () {
              setState(() {
                _filterExpress = !_filterExpress;
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDayTab(StationTimetableDayType dayType) {
    final isSelected = _dayType == dayType;
    final label = switch (dayType) {
      StationTimetableDayType.weekday => '평일',
      StationTimetableDayType.saturday => '토요일',
      StationTimetableDayType.sundayHoliday => '공휴일',
    };

    return InkWell(
      key: Key('stationTimetableDay-${dayType.name}'),
      onTap: () {
        setState(() => _dayType = dayType);
        unawaited(_load());
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 14, bottom: 8),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: isSelected ? 16 : 15,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color: isSelected
                      ? EasySubwayAccessibleColors.text
                      : EasySubwayAccessibleColors.secondaryText,
                ),
              ),
            ),
            Container(
              height: 2.5,
              width: isSelected ? 32 : 0,
              color: isSelected
                  ? EasySubwayAccessibleColors.text
                  : Colors.transparent,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterCapsule({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Semantics(
      key: Key('stationTimetableFilter-$label'),
      button: true,
      toggled: isSelected,
      label: '$label 필터',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: isSelected
                ? EasySubwayAccessibleColors.surfaceBrandChrome
                : EasySubwayAccessibleColors.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected
                  ? EasySubwayAccessibleColors.primary
                  : EasySubwayAccessibleColors.line,
              width: 1,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: isSelected
                  ? EasySubwayAccessibleColors.primary
                  : EasySubwayAccessibleColors.secondaryText,
              fontSize: 13,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHourSelector(List<int> availableHours, List<int> renderedHours) {
    return Container(
      color: EasySubwayAccessibleColors.surface,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            for (final hour in availableHours)
              _buildHourPill(hour, renderedHours),
          ],
        ),
      ),
    );
  }

  List<int> _getSortedDeparturesHours(
    List<StationTimetableDirection> visibleDirections,
  ) {
    final set = <int>{};
    for (final dir in visibleDirections) {
      final filtered = _filterDepartures(dir);
      for (final dep in filtered) {
        set.add(_departureToHour(dep));
      }
    }
    return _sortSubwayHours(set);
  }

  Widget _buildHourPill(int hour, List<int> sortedDepHours) {
    final isSelected = _selectedHour == hour;
    final label = hour == 24 ? '24시' : '$hour시';
    return GestureDetector(
      onTap: () => _scrollToHour(hour, sortedDepHours),
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected
              ? EasySubwayAccessibleColors.surfaceBrandChrome
              : EasySubwayAccessibleColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? EasySubwayAccessibleColors.primary
                : EasySubwayAccessibleColors.line,
            width: isSelected ? 1.2 : 1.0,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected
                ? EasySubwayAccessibleColors.primary
                : EasySubwayAccessibleColors.secondaryText,
            fontSize: 14,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildDirectionHeader({
    required List<StationTimetableDirection> directions,
  }) {
    if (directions.isEmpty) return const SizedBox.shrink();

    if (directions.length == 1) {
      final direction = directions.first;
      final origIndex = _timetable?.directions.indexOf(direction) ?? 0;
      return Container(
        color: EasySubwayAccessibleColors.surfaceSubtle,
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
        child: Column(
          children: [
            _buildDirectionTitleChip(direction, origIndex >= 0 ? origIndex : 0),
            const SizedBox(height: 2),
            _buildTerminusFilterDropdown(direction),
          ],
        ),
      );
    }

    final left = directions[0];
    final right = directions[1];

    return Container(
      color: EasySubwayAccessibleColors.surfaceSubtle,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 10,
                  horizontal: 8,
                ),
                child: Column(
                  children: [
                    _buildDirectionTitleChip(left, 0),
                    const SizedBox(height: 2),
                    _buildTerminusFilterDropdown(left),
                  ],
                ),
              ),
            ),
            const VerticalDivider(
              width: 1,
              thickness: 1,
              color: EasySubwayAccessibleColors.line,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 10,
                  horizontal: 8,
                ),
                child: Column(
                  children: [
                    _buildDirectionTitleChip(right, 1),
                    const SizedBox(height: 2),
                    _buildTerminusFilterDropdown(right),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDirectionTitleChip(
    StationTimetableDirection direction,
    int index,
  ) {
    final displayName = formatStationDirectionName(
      direction.name,
      previousStation: widget.previousStation,
      nextStation: widget.nextStation,
      directionIndex: index,
    );
    final isSelected =
        _selectedDirectionFilter == direction.name ||
        (_selectedDirectionFilter == null && _directionName == direction.name);

    return ChoiceChip(
      key: Key('stationTimetableDirection-${direction.name}'),
      label: Text(
        displayName,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.bold,
          color: EasySubwayAccessibleColors.text,
        ),
      ),
      selected: isSelected,
      onSelected: (_) {
        setState(() {
          _directionName = direction.name;
          _selectedDirectionFilter = _selectedDirectionFilter == direction.name
              ? null
              : direction.name;
        });
      },
      backgroundColor: Colors.transparent,
      selectedColor: Colors.transparent,
      side: BorderSide.none,
      padding: EdgeInsets.zero,
      labelPadding: EdgeInsets.zero,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      showCheckmark: false,
    );
  }

  Widget _buildTerminusFilterDropdown(StationTimetableDirection direction) {
    final current = _getDefaultTerminus(direction);
    final destinations = direction.departures
        .map((d) => d.destination.trim())
        .where((d) => d.isNotEmpty)
        .toSet()
        .toList();

    final dropdownChild = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          current,
          style: TextStyle(
            color: EasySubwayAccessibleColors.secondaryText,
            fontSize: 13,
            fontWeight: FontWeight.normal,
          ),
        ),
        const SizedBox(width: 2),
        Icon(
          Icons.keyboard_arrow_down,
          size: 16,
          color: EasySubwayAccessibleColors.secondaryText,
        ),
      ],
    );

    if (destinations.isEmpty) {
      return dropdownChild;
    }

    return PopupMenuButton<String>(
      key: Key('stationTimetableTerminusDropdown-${direction.name}'),
      tooltip: '종착역 선택',
      onSelected: (val) {
        setState(() {
          _destinationFilters[direction.name] = val;
        });
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
          key: Key('stationTimetableTerminusItem-all'),
          value: '전체',
          child: Text('전체'),
        ),
        for (final dest in destinations)
          PopupMenuItem(
            key: Key('stationTimetableTerminusItem-$dest'),
            value: dest,
            child: Text(dest.endsWith('행') ? dest : '$dest행'),
          ),
      ],
      child: dropdownChild,
    );
  }

  Widget _buildDepartureList({
    required List<StationTimetableDirection> visibleDirections,
    required List<int> availableHours,
    required DateTime effectiveNow,
    required bool isToday,
  }) {
    if (visibleDirections.length == 2) {
      final leftDirection = visibleDirections[0];
      final rightDirection = visibleDirections[1];

      final leftFiltered = _filterDepartures(leftDirection);
      final rightFiltered = _filterDepartures(rightDirection);

      final leftFirst = leftFiltered.firstOrNull;
      final leftLast = leftFiltered.lastOrNull;
      final rightFirst = rightFiltered.firstOrNull;
      final rightLast = rightFiltered.lastOrNull;

      final leftByHour = <int, List<StationTimetableDeparture>>{};
      for (final dep in leftFiltered) {
        leftByHour.putIfAbsent(_departureToHour(dep), () => []).add(dep);
      }

      final rightByHour = <int, List<StationTimetableDeparture>>{};
      for (final dep in rightFiltered) {
        rightByHour.putIfAbsent(_departureToHour(dep), () => []).add(dep);
      }

      final leftNextDeparture = _findNextDeparture(
        direction: leftDirection,
        isToday: isToday,
        effectiveNow: effectiveNow,
      );
      final leftPastDepartures = _findPastDepartures(
        direction: leftDirection,
        isToday: isToday,
        effectiveNow: effectiveNow,
        nextDeparture: leftNextDeparture,
      );

      final rightNextDeparture = _findNextDeparture(
        direction: rightDirection,
        isToday: isToday,
        effectiveNow: effectiveNow,
      );
      final rightPastDepartures = _findPastDepartures(
        direction: rightDirection,
        isToday: isToday,
        effectiveNow: effectiveNow,
        nextDeparture: rightNextDeparture,
      );

      final hoursWithDeps = <int>{...leftByHour.keys, ...rightByHour.keys};
      final sortedHours = _sortSubwayHours(hoursWithDeps);

      if (sortedHours.isEmpty) {
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 48),
          child: Center(
            child: Text(
              '해당하는 열차가 없습니다',
              style: TextStyle(
                color: EasySubwayAccessibleColors.secondaryText,
                fontSize: 14,
              ),
            ),
          ),
        );
      }

      return Column(
        children: [
          for (int idx = 0; idx < sortedHours.length; idx++) ...[
            if (idx > 0)
              const Divider(
                height: 1,
                thickness: 1,
                color: EasySubwayAccessibleColors.line,
              ),
            () {
              final hour = sortedHours[idx];
              final leftList = leftByHour[hour] ?? const [];
              final rightList = rightByHour[hour] ?? const [];

              return Container(
                key: _hourKeys.putIfAbsent(hour, () => GlobalKey()),
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (int i = 0; i < leftList.length; i++) ...[
                              if (i > 0)
                                const Divider(
                                  height: 1,
                                  thickness: 1,
                                  color:
                                      EasySubwayAccessibleColors.surfaceSubtle,
                                ),
                              _buildDepartureItem(
                                departure: leftList[i],
                                direction: leftDirection,
                                isFirst:
                                    leftList[i] == leftFirst ||
                                    leftList[i] == leftDirection.firstDeparture,
                                isLast:
                                    leftList[i] == leftLast ||
                                    leftList[i] == leftDirection.lastDeparture,
                                isNext:
                                    isToday && leftList[i] == leftNextDeparture,
                                isPast:
                                    isToday &&
                                    leftPastDepartures.contains(leftList[i]),
                                effectiveNow: effectiveNow,
                              ),
                            ],
                          ],
                        ),
                      ),
                      const VerticalDivider(
                        width: 1,
                        thickness: 1,
                        color: EasySubwayAccessibleColors.line,
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (int i = 0; i < rightList.length; i++) ...[
                              if (i > 0)
                                const Divider(
                                  height: 1,
                                  thickness: 1,
                                  color:
                                      EasySubwayAccessibleColors.surfaceSubtle,
                                ),
                              _buildDepartureItem(
                                departure: rightList[i],
                                direction: rightDirection,
                                isFirst:
                                    rightList[i] == rightFirst ||
                                    rightList[i] ==
                                        rightDirection.firstDeparture,
                                isLast:
                                    rightList[i] == rightLast ||
                                    rightList[i] ==
                                        rightDirection.lastDeparture,
                                isNext:
                                    isToday &&
                                    rightList[i] == rightNextDeparture,
                                isPast:
                                    isToday &&
                                    rightPastDepartures.contains(rightList[i]),
                                effectiveNow: effectiveNow,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }(),
          ],
          const SizedBox(height: 32),
        ],
      );
    }

    // Single direction full width
    final direction = visibleDirections.first;
    final filtered = _filterDepartures(direction);
    final singleFirst = filtered.firstOrNull;
    final singleLast = filtered.lastOrNull;
    final byHour = <int, List<StationTimetableDeparture>>{};
    for (final dep in filtered) {
      byHour.putIfAbsent(_departureToHour(dep), () => []).add(dep);
    }

    final nextDeparture = _findNextDeparture(
      direction: direction,
      isToday: isToday,
      effectiveNow: effectiveNow,
    );
    final pastDepartures = _findPastDepartures(
      direction: direction,
      isToday: isToday,
      effectiveNow: effectiveNow,
      nextDeparture: nextDeparture,
    );

    final hoursWithDeps = byHour.keys.toSet();
    final sortedHours = _sortSubwayHours(hoursWithDeps);

    if (sortedHours.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 48),
        child: Center(
          child: Text(
            '해당하는 열차가 없습니다',
            style: TextStyle(
              color: EasySubwayAccessibleColors.secondaryText,
              fontSize: 14,
            ),
          ),
        ),
      );
    }

    return Column(
      children: [
        for (int idx = 0; idx < sortedHours.length; idx++) ...[
          if (idx > 0)
            const Divider(
              height: 1,
              thickness: 1,
              color: EasySubwayAccessibleColors.line,
            ),
          () {
            final hour = sortedHours[idx];
            final list = byHour[hour] ?? const [];

            return Container(
              key: _hourKeys.putIfAbsent(hour, () => GlobalKey()),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (int i = 0; i < list.length; i++) ...[
                    if (i > 0)
                      const Divider(
                        height: 1,
                        thickness: 1,
                        color: EasySubwayAccessibleColors.surfaceSubtle,
                      ),
                    _buildDepartureItem(
                      departure: list[i],
                      direction: direction,
                      isFirst:
                          list[i] == singleFirst ||
                          list[i] == direction.firstDeparture,
                      isLast:
                          list[i] == singleLast ||
                          list[i] == direction.lastDeparture,
                      isNext: isToday && list[i] == nextDeparture,
                      isPast: isToday && pastDepartures.contains(list[i]),
                      effectiveNow: effectiveNow,
                    ),
                  ],
                ],
              ),
            );
          }(),
        ],
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _buildDepartureItem({
    required StationTimetableDeparture departure,
    required StationTimetableDirection direction,
    required bool isFirst,
    required bool isLast,
    required bool isNext,
    required bool isPast,
    required DateTime effectiveNow,
  }) {
    final dest = _formatDestinationLabel(departure, direction);

    return Semantics(
      label: departure.semanticLabel,
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 5,
                runSpacing: 2,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    departure.timeLabel,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isPast
                          ? EasySubwayAccessibleColors.mutedText
                          : EasySubwayAccessibleColors.text,
                    ),
                  ),
                  if (isFirst)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1.5,
                      ),
                      decoration: BoxDecoration(
                        color: EasySubwayAccessibleColors.surfaceBrandChrome,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: EasySubwayAccessibleColors.primary,
                          width: 0.8,
                        ),
                      ),
                      child: const Text(
                        '첫차',
                        style: TextStyle(
                          color: EasySubwayAccessibleColors.primary,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          height: 1.1,
                        ),
                      ),
                    ),
                  if (isLast)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1.5,
                      ),
                      decoration: BoxDecoration(
                        color: EasySubwayAccessibleColors.surfaceSubtle,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: EasySubwayAccessibleColors.red,
                          width: 0.8,
                        ),
                      ),
                      child: const Text(
                        '막차',
                        style: TextStyle(
                          color: EasySubwayAccessibleColors.red,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          height: 1.1,
                        ),
                      ),
                    ),
                  if (departure.isExpress)
                    ServicePatternBadge(departure: departure),
                  if (isNext)
                    Builder(
                      builder: (context) {
                        final countdown = _formatStationDepartureCountdown(
                          departure.seconds,
                          effectiveNow,
                        );
                        final isImminent =
                            countdown == '곧 도착' || countdown == '진입';
                        final isWarning =
                            !isImminent &&
                            (countdown == '1분 뒤 도착' ||
                                countdown == '2분 뒤 도착' ||
                                countdown == '3분 뒤 도착' ||
                                countdown.startsWith('1분') ||
                                countdown.startsWith('2분') ||
                                countdown.startsWith('3분'));
                        final Color countdownColor = isImminent
                            ? EasySubwayColorPrimitives.statusDanger
                            : (isWarning
                                  ? EasySubwayAccessibleColors.amber
                                  : EasySubwayAccessibleColors.secondaryText);
                        final FontWeight countdownWeight =
                            (isImminent || isWarning)
                            ? FontWeight.w700
                            : FontWeight.w500;
                        return Text(
                          countdown,
                          style: TextStyle(
                            color: countdownColor,
                            fontSize: 13,
                            fontWeight: countdownWeight,
                          ),
                        );
                      },
                    ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                dest,
                style: TextStyle(
                  fontSize: 13,
                  color: isPast
                      ? EasySubwayAccessibleColors.mutedText
                      : EasySubwayAccessibleColors.secondaryText,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOffstageTestHelper({
    required StationTimetable? timetable,
    required StationTimetableDirection? currentDirection,
  }) {
    final targetDirection =
        currentDirection ?? timetable?.directions.firstOrNull;
    return SizedBox(
      width: 0,
      height: 0,
      child: OverflowBox(
        minWidth: 0,
        minHeight: 0,
        maxWidth: 0,
        maxHeight: 0,
        child: Opacity(
          opacity: 0,
          child: Column(
            children: [
              Text('${widget.stationName} 시간표'),
              if (targetDirection != null &&
                  targetDirection.departures.isNotEmpty) ...[
                Text('첫차 ${targetDirection.firstDeparture.timeLabel}'),
                Text('막차 ${targetDirection.lastDeparture.timeLabel}'),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

StationTimetableDayType _todayTimetableDayType(DateTime now) {
  return switch (now.weekday) {
    DateTime.saturday => StationTimetableDayType.saturday,
    DateTime.sunday => StationTimetableDayType.sundayHoliday,
    _ => StationTimetableDayType.weekday,
  };
}

class _StationTimetableEmptyMessage extends StatelessWidget {
  const _StationTimetableEmptyMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Text(
      message,
      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
        color: EasySubwayAccessibleColors.secondaryText,
        fontWeight: FontWeight.w700,
        height: 1.35,
      ),
    );
  }
}

bool _isLateNightCandidate(
  int seconds,
  int currentSeconds,
  int lateNightServiceSeconds,
) {
  if (seconds >= Duration.secondsPerDay) {
    return seconds >= lateNightServiceSeconds;
  }
  return seconds >= currentSeconds &&
      (seconds - currentSeconds <= 2 * Duration.secondsPerHour ||
          seconds < 4 * Duration.secondsPerHour);
}

String _formatStationDepartureCountdown(int seconds, DateTime now) {
  final currentSeconds =
      now.hour * Duration.secondsPerHour +
      now.minute * Duration.secondsPerMinute +
      now.second;
  final isLateNight = now.hour < 4;
  final lateNightServiceSeconds = Duration.secondsPerDay + currentSeconds;

  final int diffSeconds;
  if (isLateNight && seconds >= Duration.secondsPerDay) {
    diffSeconds = seconds - lateNightServiceSeconds;
  } else {
    diffSeconds = seconds - currentSeconds;
  }

  if (diffSeconds < 60) {
    return '곧 도착';
  }
  final minutes = (diffSeconds / 60).round();
  if (minutes <= 0) {
    return '곧 도착';
  }
  if (minutes < 60) {
    return '$minutes분 뒤 도착';
  }
  final hours = minutes ~/ 60;
  final remMin = minutes % 60;
  return remMin == 0 ? '$hours시간 뒤 도착' : '$hours시간 $remMin분 뒤 도착';
}

String formatStationDirectionName(
  String rawName, {
  String? previousStation,
  String? nextStation,
  int? directionIndex,
}) {
  final clean = rawName.trim();
  final prev = previousStation?.trim();
  final next = nextStation?.trim();

  // 1. Direct match with adjacent station names
  if (prev != null && prev.isNotEmpty && clean.contains(prev)) {
    return '$prev 방면';
  }
  if (next != null && next.isNotEmpty && clean.contains(next)) {
    return '$next 방면';
  }

  // 2. Generic transit tokens (상행/상선/내선 vs 하행/하선/외선)
  final isUpboundToken =
      clean.contains('상행') ||
      clean.contains('상선') ||
      clean.contains('내선') ||
      clean.contains('내선순환');

  final isDownboundToken =
      clean.contains('하행') ||
      clean.contains('하선') ||
      clean.contains('외선') ||
      clean.contains('외선순환');

  if (isUpboundToken && prev != null && prev.isNotEmpty) {
    return '$prev 방면';
  }
  if (isDownboundToken && next != null && next.isNotEmpty) {
    return '$next 방면';
  }

  // 3. Fallback based on 2-column index (0 = Upbound / Previous, 1 = Downbound / Next)
  if (directionIndex == 0 &&
      prev != null &&
      prev.isNotEmpty &&
      !isDownboundToken) {
    return '$prev 방면';
  }
  if (directionIndex == 1 &&
      next != null &&
      next.isNotEmpty &&
      !isUpboundToken) {
    return '$next 방면';
  }

  // 4. Terminal stations where only one neighbor station exists
  if (prev != null &&
      prev.isNotEmpty &&
      (next == null || next.isEmpty) &&
      !isDownboundToken) {
    return '$prev 방면';
  }
  if (next != null &&
      next.isNotEmpty &&
      (prev == null || prev.isEmpty) &&
      !isUpboundToken) {
    return '$next 방면';
  }

  return clean.endsWith('방면') ? clean : '$clean 방면';
}

Color _parseLineColor(String? colorStr) {
  if (colorStr == null || colorStr.isEmpty) {
    return EasySubwayAccessibleColors.text;
  }
  try {
    final hex = colorStr.replaceAll('#', '');
    return Color(int.parse(hex.length == 6 ? '0xFF$hex' : '0x$hex'));
  } catch (_) {}
  return EasySubwayAccessibleColors.text;
}

String _formatLineName(String raw) {
  return raw.replaceFirst(RegExp(r'^(수도권\s*|서울\s*)'), '');
}
