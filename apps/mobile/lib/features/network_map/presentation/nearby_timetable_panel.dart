import 'dart:async';

import 'package:flutter/material.dart';

import '../../../accessible_design.dart';
import 'nearby_direction_columns.dart';

class NearbyTimetablePanelData {
  const NearbyTimetablePanelData({required this.directions});

  final List<NearbyTimetableDirectionData> directions;
}

class NearbyTimetableDirectionData {
  const NearbyTimetableDirectionData({
    required this.name,
    required this.departures,
  });

  final String name;
  final List<NearbyTimetableDepartureData> departures;
}

class NearbyTimetableDepartureData {
  const NearbyTimetableDepartureData({
    required this.directionName,
    required this.seconds,
    required this.timeLabel,
    required this.semanticLabel,
    required this.isExpress,
    this.destination = '',
    this.isFirstTrain = false,
  });

  final String directionName;
  final int seconds;
  final String timeLabel;
  final String semanticLabel;
  final bool isExpress;
  final String destination;
  final bool isFirstTrain;

  /// 열차 종착역 행선지 라벨 (예: '사당행', '진접행').
  String get destinationLabel {
    final trimmed = destination.trim();
    if (trimmed.isEmpty) {
      return '';
    }
    if (trimmed.contains('순환')) {
      return trimmed;
    }
    return trimmed.endsWith('행') ? trimmed : '$trimmed행';
  }
}

class NearbyTimetablePanel extends StatefulWidget {
  const NearbyTimetablePanel({
    required this.data,
    required this.lineColor,
    required this.leftName,
    required this.rightName,
    required this.expressBadgeBuilder,
    this.now,
    this.enableTicker,
    this.tickerInterval = const Duration(seconds: 5),
    super.key,
  });

  final NearbyTimetablePanelData? data;
  final Color lineColor;
  final String? leftName;
  final String? rightName;
  final Widget Function() expressBadgeBuilder;
  final DateTime? now;
  final bool? enableTicker;
  final Duration tickerInterval;

  @override
  State<NearbyTimetablePanel> createState() => _NearbyTimetablePanelState();
}

class _NearbyTimetablePanelState extends State<NearbyTimetablePanel>
    with WidgetsBindingObserver {
  Timer? _tickerTimer;
  Duration _tickerElapsed = Duration.zero;

  bool get _isTickerEnabled => widget.enableTicker ?? (widget.now == null);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (_isTickerEnabled) {
      _startTicker();
    }
  }

  @override
  void didUpdateWidget(NearbyTimetablePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.now != oldWidget.now) {
      _tickerElapsed = Duration.zero;
    }
    if (_isTickerEnabled && _tickerTimer == null) {
      _startTicker();
    } else if (!_isTickerEnabled && _tickerTimer != null) {
      _stopTicker();
    }
  }

  void _startTicker() {
    _tickerTimer?.cancel();
    _tickerTimer = Timer.periodic(widget.tickerInterval, (_) {
      if (!mounted) {
        _stopTicker();
        return;
      }
      setState(() {
        if (widget.now != null) {
          _tickerElapsed += widget.tickerInterval;
        }
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
      if (_isTickerEnabled) {
        _startTicker();
      }
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
    final baseNow = widget.now;
    if (baseNow != null) {
      return baseNow.add(_tickerElapsed);
    }
    return DateTime.now();
  }

  @override
  Widget build(BuildContext context) {
    // 로컬 조회 중이어도 스피너 대신 인접역 방면·대시 골격을 즉시 그린다(#2453).
    final departures = _nextTimetableDepartures(widget.data, _effectiveNow);
    // 방면별로 그룹핑(실시간과 동일한 열 구성 원칙 적용).
    final dataGroups = <List<_NextTimetableDeparture>>[];
    for (final departure in departures) {
      if (dataGroups.isEmpty ||
          dataGroups.last.first.directionLabel != departure.directionLabel) {
        dataGroups.add([departure]);
      } else {
        dataGroups.last.add(departure);
      }
    }
    final dataTitles = [
      for (final group in dataGroups) group.first.directionLabel,
    ];
    final slots = resolveNearbyColumnSlots(
      dataTitles: dataTitles,
      leftName: widget.leftName,
      rightName: widget.rightName,
    );
    if (slots.isEmpty) {
      return const NearbyDataUnavailable();
    }

    final columns = <NearbyPanelColumn>[];
    final semanticParts = <String>[];
    for (final slot in slots) {
      final dataIndex = slot.dataIndex;
      if (dataIndex == null) {
        // 대시 열 의미는 NearbyPanelColumns 열 단위 Semantics가 담당한다.
        columns.add(NearbyPanelColumn(title: slot.title));
        continue;
      }
      final group = dataGroups[dataIndex];
      final rows = <Widget>[];
      for (var row = 0; row < group.length; row++) {
        if (row > 0) {
          rows.add(const SizedBox(height: 4));
        }
        rows.add(
          _NearbyTimetableDepartureView(
            data: group[row],
            expressBadgeBuilder: widget.expressBadgeBuilder,
            now: _effectiveNow,
          ),
        );
        final departureItem = group[row];
        final departureSemantic = departureItem.isServiceEnded
            ? '${slot.title} 운행 종료'
            : (departureItem.isFirstTrain
                  ? '${departureItem.departure!.directionName} 방면, 첫차 ${departureItem.departure!.timeLabel} 출발'
                  : departureItem.departure!.semanticLabel);
        semanticParts.add(departureSemantic);
      }
      columns.add(NearbyPanelColumn(title: slot.title, rows: rows));
    }

    final hasData = departures.isNotEmpty;
    final columnsView = KeyedSubtree(
      key: hasData ? null : const Key('networkMapNearbyTimetableSkeleton'),
      child: NearbyPanelColumns(columns: columns, lineColor: widget.lineColor),
    );
    // 골격↔데이터 갱신 시 liveRegion 재발화를 피한다.
    // 순수 골격은 열 단위 Semantics, 데이터 혼재 시 부모 라벨에 대시 열도 합친다.
    if (semanticParts.isEmpty) {
      return columnsView;
    }
    final dashLabels = [
      for (final slot in slots)
        if (slot.dataIndex == null)
          slot.title.isEmpty ? '정보 없음' : '${slot.title} 정보 없음',
    ];
    return Semantics(
      excludeSemantics: true,
      label: [...semanticParts, ...dashLabels].join(', '),
      child: columnsView,
    );
  }
}

class _NextTimetableDeparture {
  const _NextTimetableDeparture({
    required this.directionLabel,
    this.departure,
    this.isFirstTrain = false,
    this.isServiceEnded = false,
  });

  final String directionLabel;
  final NearbyTimetableDepartureData? departure;
  final bool isFirstTrain;
  final bool isServiceEnded;
}

List<_NextTimetableDeparture> _nextTimetableDepartures(
  NearbyTimetablePanelData? data,
  DateTime now,
) {
  if (data == null) {
    return const [];
  }
  final currentSeconds =
      now.hour * Duration.secondsPerHour +
      now.minute * Duration.secondsPerMinute +
      now.second;
  final isLateNight = now.hour < 4;
  final lateNightServiceSeconds = Duration.secondsPerDay + currentSeconds;

  final result = <_NextTimetableDeparture>[];
  var visibleDirectionCount = 0;
  for (final direction in data.directions) {
    if (direction.departures.isEmpty) {
      continue;
    }
    final rawDirection = direction.name.trim().isEmpty
        ? direction.departures.first.directionName.trim()
        : direction.name.trim();
    final label = rawDirection.endsWith('방면')
        ? rawDirection
        : '$rawDirection 방면';

    List<_NextTimetableDeparture> departures = [];

    if (isLateNight) {
      // 심야 새벽 시간대 (00:00~03:59):
      // 당일 심야 운행 열차 중 현재 시각 이후 남은 열차 확인
      final remainingLateNight = direction.departures
          .where(
            (candidate) => _isLateNightCandidate(
              candidate.seconds,
              currentSeconds,
              lateNightServiceSeconds,
            ),
          )
          .take(2)
          .toList(growable: false);

      if (remainingLateNight.isNotEmpty) {
        // 심야 열차가 아직 남아있으면 해당 심야 열차만 표시 (첫차와 섞이지 않음)
        departures = [
          for (final dep in remainingLateNight)
            _NextTimetableDeparture(
              directionLabel: label,
              departure: dep,
              isFirstTrain: dep.isFirstTrain,
            ),
        ];
      } else {
        // 당일 심야 운행까지 완전히 종료된 경우:
        // 새벽 4시 전에는 첫차를 띄우지 않고 '운행 종료' 안내
        departures = [
          _NextTimetableDeparture(directionLabel: label, isServiceEnded: true),
        ];
      }
    } else {
      // 주간 및 저녁 시간대 (04:00~23:59):
      final upcoming = direction.departures
          .where((candidate) => candidate.seconds >= currentSeconds)
          .take(2)
          .toList(growable: false);

      if (upcoming.isNotEmpty) {
        final isBeforeFirstTrain =
            now.hour < 6 &&
            upcoming.first == direction.departures.first &&
            (upcoming.first.seconds - currentSeconds >=
                15 * Duration.secondsPerMinute);
        departures = [
          for (var i = 0; i < upcoming.length; i++)
            _NextTimetableDeparture(
              directionLabel: label,
              departure: upcoming[i],
              isFirstTrain:
                  upcoming[i].isFirstTrain || (i == 0 && isBeforeFirstTrain),
            ),
        ];
      } else {
        // 당일 모든 열차 종료 -> 첫차는 새벽 04:00 이후에만 노출하므로 운행 종료 안내
        departures = [
          _NextTimetableDeparture(directionLabel: label, isServiceEnded: true),
        ];
      }
    }

    if (departures.isEmpty) {
      continue;
    }
    result.addAll(departures);
    visibleDirectionCount++;
    if (visibleDirectionCount == 2) {
      break;
    }
  }
  return result;
}

bool _isLateNightCandidate(
  int seconds,
  int currentSeconds,
  int lateNightServiceSeconds,
) {
  if (seconds >= Duration.secondsPerDay) {
    return seconds >= lateNightServiceSeconds;
  }
  // 자정 이후 당일 심야 열차(현재 시각 이후 2시간 이내이거나 04시 이전)
  return seconds >= currentSeconds &&
      (seconds - currentSeconds <= 2 * Duration.secondsPerHour ||
          seconds < 4 * Duration.secondsPerHour);
}

class _NearbyTimetableDepartureView extends StatelessWidget {
  const _NearbyTimetableDepartureView({
    required this.data,
    required this.expressBadgeBuilder,
    required this.now,
  });

  final _NextTimetableDeparture data;
  final Widget Function() expressBadgeBuilder;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    if (data.isServiceEnded) {
      return const SizedBox(
        height: 46,
        child: Center(
          child: Text(
            '운행 종료',
            style: TextStyle(
              color: EasySubwayAccessibleColors.contentSecondary,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    }
    final departure = data.departure!;
    final countdown = _formatDepartureCountdown(departure, now);
    final isImminent = countdown == '곧 도착' || countdown == '진입';
    final isWarning =
        !isImminent &&
        (countdown == '1분 뒤 도착' ||
            countdown == '2분 뒤 도착' ||
            countdown == '3분 뒤 도착' ||
            countdown.startsWith('1분') ||
            countdown.startsWith('2분') ||
            countdown.startsWith('3분'));
    final countdownColor = isImminent
        ? EasySubwayColorPrimitives.statusDanger
        : (isWarning
              ? EasySubwayAccessibleColors.amber
              : EasySubwayAccessibleColors.secondaryText);
    final countdownWeight = (isImminent || isWarning)
        ? FontWeight.w700
        : FontWeight.w600;

    final destinationLabel = departure.destinationLabel;
    final bool hasDestination = destinationLabel.isNotEmpty;
    final bool showFirstTrain = data.isFirstTrain;

    final Widget leadingText;
    if (showFirstTrain) {
      leadingText = Text(
        '첫차 ${departure.timeLabel}',
        style: const TextStyle(
          color: EasySubwayAccessibleColors.contentPrimary,
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
      );
    } else if (hasDestination) {
      leadingText = Text(
        destinationLabel,
        style: const TextStyle(
          color: EasySubwayAccessibleColors.contentPrimary,
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
      );
    } else {
      leadingText = Text(
        departure.timeLabel,
        style: const TextStyle(
          color: EasySubwayAccessibleColors.contentPrimary,
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
      );
    }

    final countdownText = Text(
      countdown,
      style: TextStyle(
        color: countdownColor,
        fontSize: 13,
        fontWeight: countdownWeight,
      ),
    );

    return Wrap(
      spacing: 6,
      runSpacing: 2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        leadingText,
        countdownText,
        if (departure.isExpress) expressBadgeBuilder(),
      ],
    );
  }
}

String _formatDepartureCountdown(
  NearbyTimetableDepartureData departure,
  DateTime now,
) {
  final currentSeconds =
      now.hour * Duration.secondsPerHour +
      now.minute * Duration.secondsPerMinute +
      now.second;
  final isLateNight = now.hour < 4;
  final lateNightServiceSeconds = Duration.secondsPerDay + currentSeconds;

  final int diffSeconds;
  if (isLateNight && departure.seconds >= Duration.secondsPerDay) {
    diffSeconds = departure.seconds - lateNightServiceSeconds;
  } else if (!isLateNight &&
      departure.seconds < currentSeconds &&
      departure.seconds >= Duration.secondsPerDay) {
    diffSeconds = departure.seconds - currentSeconds;
  } else {
    diffSeconds = departure.seconds - currentSeconds;
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
