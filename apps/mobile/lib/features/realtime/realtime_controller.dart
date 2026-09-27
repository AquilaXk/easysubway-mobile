import 'dart:async';

import 'package:flutter/foundation.dart';

import 'realtime_repository.dart';

class RealtimeStationController extends ChangeNotifier {
  RealtimeStationController({
    required this.repository,
    this.defaultPollingInterval = const Duration(seconds: 15),
  });

  final RealtimeRepository repository;
  final Duration defaultPollingInterval;

  RealtimeSnapshot _state = const RealtimeSnapshot.loading();
  bool _isDisposed = false;
  Timer? _pollingTimer;
  RealtimeStationQuery? _currentPollingQuery;
  bool _isPollingFetchInFlight = false;

  RealtimeSnapshot get state => _state;
  bool get isPolling => _pollingTimer != null && _pollingTimer!.isActive;

  Future<void> load(RealtimeStationQuery query) async {
    _emit(const RealtimeSnapshot.loading());
    await _fetchAndEmit(query);
  }

  /// 10~15초 주기로 실시간 도착 정보를 백그라운드 자동 갱신한다.
  void startPolling(
    RealtimeStationQuery query, {
    Duration? interval,
    bool loadImmediately = true,
  }) {
    stopPolling();
    _currentPollingQuery = query;
    if (loadImmediately) {
      unawaited(load(query));
    }
    _pollingTimer = Timer.periodic(interval ?? defaultPollingInterval, (_) {
      if (_isDisposed || _currentPollingQuery == null) {
        stopPolling();
        return;
      }
      unawaited(_pollTick(_currentPollingQuery!));
    });
  }

  /// 폴링 타이머를 즉시 해제한다.
  void stopPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
    _currentPollingQuery = null;
    _isPollingFetchInFlight = false;
  }

  Future<void> _pollTick(RealtimeStationQuery query) async {
    if (_isDisposed || _isPollingFetchInFlight) {
      return;
    }
    _isPollingFetchInFlight = true;
    try {
      final snapshot = await repository.arrivals(query);
      if (!_isDisposed && _currentPollingQuery == query) {
        _emit(snapshot);
      }
    } catch (_) {
      // 백그라운드 주기 폴링 실패 시 기존 유효 상태를 강제로 날리지 않고 유지한다.
    } finally {
      _isPollingFetchInFlight = false;
    }
  }

  Future<void> _fetchAndEmit(RealtimeStationQuery query) async {
    try {
      _emit(await repository.arrivals(query));
    } on RealtimeException {
      _emit(const RealtimeSnapshot.unavailable());
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'easysubway realtime',
          context: ErrorDescription('실시간 열차 조회 중 예외가 발생했습니다.'),
        ),
      );
      _emit(const RealtimeSnapshot.unavailable());
    }
  }

  void _emit(RealtimeSnapshot nextState) {
    if (_isDisposed) {
      return;
    }
    _state = nextState;
    notifyListeners();
  }

  @override
  void dispose() {
    stopPolling();
    _isDisposed = true;
    super.dispose();
  }
}

