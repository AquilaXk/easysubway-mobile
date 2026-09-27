import 'dart:async';

import 'package:flutter/material.dart';

import '../../../accessible_design.dart';
import '../../../mobile_error_reporter.dart';
import '../data/server_station_timetable_repository.dart';
import '../domain/station_line.dart';
import '../domain/station_models.dart';
import '../domain/station_repositories.dart';
import 'service_pattern_badge.dart';

const _stationTimetablePagePadding = EdgeInsets.fromLTRB(20, 20, 20, 32);

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
  var _loading = false;
  var _requestId = 0;
  Timer? _tickerTimer;
  Duration _tickerElapsed = Duration.zero;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lineId = widget.lines.firstOrNull?.id;
    final now = debugStationVerifiedClock();
    _dayType = _todayTimetableDayType(now);
    if (widget.repository != null && _lineId != null) {
      unawaited(_loadInitialAvailableLine(now));
    }
    _startTicker();
  }

  void _startTicker() {
    _tickerTimer?.cancel();
    _tickerTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (!mounted) {
        _stopTicker();
        return;
      }
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
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  DateTime get _effectiveNow {
    return debugStationVerifiedClock().add(_tickerElapsed);
  }

  Future<void> _loadInitialAvailableLine(DateTime date) async {
    final repository = widget.repository;
    if (repository == null) return;
    final requestId = ++_requestId;
    setState(() => _loading = true);
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
      });
    } on StationTimetableUnavailable {
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _timetable = null;
        _directionName = null;
        _loading = false;
      });
    } catch (error, stackTrace) {
      reportMobileError(error, stackTrace, context: '역 시간표 조회 중 예외가 발생했습니다.');
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _timetable = null;
        _directionName = null;
        _loading = false;
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
    setState(() => _loading = true);
    try {
      final timetable = date == null
          ? await repository.loadStationTimetable(
              stationId: widget.stationId,
              lineId: lineId,
              dayType: _dayType,
              referenceDate: debugStationVerifiedClock(),
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
      _directionName = directionNames.contains(_directionName)
          ? _directionName
          : timetable.directions.firstOrNull?.name;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final timetable = _timetable;
    final direction = timetable?.directions
        .where((item) => item.name == _directionName)
        .firstOrNull;
    final effectiveNow = _effectiveNow;
    final isToday = _dayType == _todayTimetableDayType(effectiveNow);
    final currentSeconds = isToday
        ? effectiveNow.hour * Duration.secondsPerHour +
              effectiveNow.minute * Duration.secondsPerMinute +
              effectiveNow.second
        : -1;
    final isLateNight = effectiveNow.hour < 4;
    final lateNightServiceSeconds = Duration.secondsPerDay + currentSeconds;
    final nextTrainIndex = isToday && direction != null
        ? (isLateNight
              ? direction.departures.indexWhere(
                  (dep) => _isLateNightCandidate(
                    dep.seconds,
                    currentSeconds,
                    lateNightServiceSeconds,
                  ),
                )
              : direction.departures.indexWhere(
                  (dep) => dep.seconds >= currentSeconds,
                ))
        : -1;

    return Scaffold(
      appBar: AppBar(title: Text('${widget.stationName} 시간표')),
      body: SafeArea(
        child: ListView(
          padding: _stationTimetablePagePadding,
          children: [
            if (widget.lines.length > 1) ...[
              const _StationTimetableSectionTitle(title: '노선'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final line in widget.lines)
                    ChoiceChip(
                      key: Key('stationTimetableLine-${line.id}'),
                      label: Text(line.name),
                      selected: _lineId == line.id,
                      onSelected: (_) {
                        setState(() => _lineId = line.id);
                        unawaited(_load());
                      },
                    ),
                ],
              ),
              const SizedBox(height: 20),
            ],
            const _StationTimetableSectionTitle(title: '운행일'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final dayType in StationTimetableDayType.values)
                  ChoiceChip(
                    key: Key('stationTimetableDay-${dayType.name}'),
                    label: Text(dayType.label),
                    selected: _dayType == dayType,
                    onSelected: (_) {
                      setState(() => _dayType = dayType);
                      unawaited(_load());
                    },
                  ),
              ],
            ),
            const SizedBox(height: 20),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (timetable == null || !timetable.isAvailable)
              const _StationTimetableEmptyMessage(message: '시간표 정보가 없어요')
            else ...[
              const _StationTimetableSectionTitle(title: '방향'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final item in timetable.directions)
                    ChoiceChip(
                      key: Key('stationTimetableDirection-${item.name}'),
                      label: Text(
                        formatStationDirectionName(
                          item.name,
                          previousStation: widget.previousStation,
                          nextStation: widget.nextStation,
                        ),
                      ),
                      selected: _directionName == item.name,
                      onSelected: (_) =>
                          setState(() => _directionName = item.name),
                    ),
                ],
              ),
              if (direction != null) ...[
                const SizedBox(height: 20),
                Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  children: [
                    Text(
                      '첫차 ${direction.firstDeparture.timeLabel}',
                      style: const TextStyle(
                        color: EasySubwayAccessibleColors.text,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      '막차 ${direction.lastDeparture.timeLabel}',
                      style: const TextStyle(
                        color: EasySubwayAccessibleColors.text,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                for (
                  var index = 0;
                  index < direction.departures.length;
                  index++
                ) ...[
                  if (index > 0) const Divider(height: 1),
                  Semantics(
                    label: direction.departures[index].semanticLabel,
                    child: ExcludeSemantics(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        child: () {
                          final departure = direction.departures[index];
                          final fallback = direction.name
                              .replaceAll('방면', '')
                              .trim();
                          final dest = departure.destinationLabel.isNotEmpty
                              ? departure.destinationLabel
                              : (fallback.isNotEmpty
                                    ? (fallback.contains('순환')
                                          ? fallback
                                          : (fallback.endsWith('행')
                                                ? fallback
                                                : '$fallback행'))
                                    : '열차');
                          final isPast =
                              isToday &&
                              nextTrainIndex != -1 &&
                              index < nextTrainIndex;
                          final isNext = isToday && index == nextTrainIndex;

                          return Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                dest,
                                style: TextStyle(
                                  color: isPast
                                      ? EasySubwayAccessibleColors.mutedText
                                      : EasySubwayAccessibleColors.text,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                departure.timeLabel,
                                style: TextStyle(
                                  color: isPast
                                      ? EasySubwayAccessibleColors.mutedText
                                      : EasySubwayAccessibleColors.text,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              if (isNext)
                                Builder(
                                  builder: (context) {
                                    final countdown =
                                        _formatStationDepartureCountdown(
                                          departure.seconds,
                                          effectiveNow,
                                        );
                                    final isImminent =
                                        countdown == '곧 도착' ||
                                        countdown == '진입';
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
                                              : EasySubwayAccessibleColors
                                                    .secondaryText);
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
                              ServicePatternBadge(departure: departure),
                            ],
                          );
                        }(),
                      ),
                    ),
                  ),
                ],
              ],
            ],
          ],
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

class _StationTimetableSectionTitle extends StatelessWidget {
  const _StationTimetableSectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleLarge?.copyWith(
          color: EasySubwayAccessibleColors.text,
          fontWeight: FontWeight.w700,
          height: 1.25,
        ),
      ),
    );
  }
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
  } else if (!isLateNight &&
      seconds < currentSeconds &&
      seconds >= Duration.secondsPerDay) {
    diffSeconds = seconds - currentSeconds;
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
}) {
  final clean = rawName.trim();
  final prev = previousStation?.trim();
  final next = nextStation?.trim();
  if (prev != null &&
      prev.isNotEmpty &&
      (clean.contains(prev) ||
          clean.contains('상행') ||
          clean.contains('진접') ||
          clean.contains('당고개') ||
          clean.contains('사당'))) {
    return '$prev 방면';
  }
  if (next != null &&
      next.isNotEmpty &&
      (clean.contains(next) ||
          clean.contains('하행') ||
          clean.contains('오이도') ||
          clean.contains('안산'))) {
    return '$next 방면';
  }
  return clean.endsWith('방면') ? clean : '$clean 방면';
}
