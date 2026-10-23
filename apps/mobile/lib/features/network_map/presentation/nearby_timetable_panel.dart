import 'dart:async';

import 'package:flutter/material.dart';

import 'nearby_direction_columns.dart';
import 'nearby_direction_title.dart';

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
    required this.leftName,
    required this.rightName,
    required this.expressBadgeBuilder,
    this.onOpenDirection,
    this.now,
    this.enableTicker,
    this.tickerInterval = const Duration(seconds: 5),
    super.key,
  });

  /// 시간표를 아직 받지 못했거나 받을 수 없는 방면.
  static const unavailableMessage = ['시간표 정보 없음'];

  /// 그 방면에 남은 출발이 없을 때. 상용 지하철 서비스의 표기를 따른다.
  static const serviceEndedMessage = ['운행종료'];

  final NearbyTimetablePanelData? data;
  final String? leftName;
  final String? rightName;
  final Widget Function() expressBadgeBuilder;
  final ValueChanged<String>? onOpenDirection;
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
      if (!mounted) return;
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
    // 로컬 조회 중이어도 스피너 대신 인접역 방면 카드를 즉시 그린다(#2453).
    final departures = _nextTimetableDepartures(widget.data, _effectiveNow);
    final dataGroups = <List<_NextTimetableDeparture>>[];
    for (final departure in departures) {
      if (dataGroups.isEmpty ||
          dataGroups.last.first.directionLabel != departure.directionLabel) {
        dataGroups.add([departure]);
      } else {
        dataGroups.last.add(departure);
      }
    }
    final slots = resolveNearbyColumnSlots(
      dataTitles: [for (final group in dataGroups) group.first.directionLabel],
      leftName: widget.leftName,
      rightName: widget.rightName,
    );
    if (slots.isEmpty) {
      return const NearbyDataUnavailable(
        lines: NearbyTimetablePanel.unavailableMessage,
      );
    }

    final columns = [
      for (final slot in slots)
        switch (slot.dataIndex) {
          null => NearbyPanelColumn(
            title: slot.title,
            emptyMessage: NearbyTimetablePanel.unavailableMessage,
          ),
          final index => _timetableColumn(slot.title, dataGroups[index]),
        },
    ];
    return KeyedSubtree(
      key: departures.isEmpty
          ? const Key('networkMapNearbyTimetableSkeleton')
          : null,
      child: NearbyPanelColumns(
        columns: columns,
        onOpenDirection: widget.onOpenDirection,
      ),
    );
  }

  NearbyPanelColumn _timetableColumn(
    String title,
    List<_NextTimetableDeparture> group,
  ) {
    if (group.first.isServiceEnded) {
      return NearbyPanelColumn(
        title: title,
        emptyMessage: NearbyTimetablePanel.serviceEndedMessage,
      );
    }
    final now = _effectiveNow;
    return NearbyPanelColumn(
      title: title,
      rows: [
        for (final departure in group)
          _NearbyTimetableDepartureView(
            data: departure,
            expressBadgeBuilder: widget.expressBadgeBuilder,
            now: now,
          ),
      ],
      rowsLabel: [
        for (final item in group)
          item.isFirstTrain
              ? '${item.departure!.directionName} 방면, 첫차 ${item.departure!.timeLabel} 출발'
              : item.departure!.semanticLabel,
      ].join(', '),
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
    final departure = data.departure!;
    final destinationLabel = departure.destinationLabel;
    final leading = data.isFirstTrain
        ? '첫차 ${departure.timeLabel}'
        : (destinationLabel.isNotEmpty
              ? nearbyDestinationName(destinationLabel)
              : departure.timeLabel);
    return NearbyDirectionRowLayout(
      leading: Wrap(
        spacing: 6,
        runSpacing: 2,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(leading, style: NearbyArrivalRow.destinationStyle),
          if (departure.isExpress) expressBadgeBuilder(),
        ],
      ),
      trailing: Text(
        _formatDepartureCountdown(departure, now),
        style: NearbyArrivalRow.etaStyle,
      ),
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
    return '$minutes분';
  }
  final hours = minutes ~/ 60;
  final remMin = minutes % 60;
  return remMin == 0 ? '$hours시간' : '$hours시간 $remMin분';
}
