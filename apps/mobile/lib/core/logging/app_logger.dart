import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';

import '../crashlytics/crash_report_redaction.dart';

/// 앱 공통 로거. release는 콘솔(debugPrint) 원시 오류/스택 노출을 차단하고,
/// 모든 모드에서 토큰·헤더·내부 경로를 마스킹한다.
class AppLogger {
  AppLogger._(this._logger, {required this.isReleaseMode});

  final Logger _logger;
  final bool isReleaseMode;

  static AppLogger instance = AppLogger._(
    _createLogger(isReleaseMode: kReleaseMode),
    isReleaseMode: kReleaseMode,
  );

  @visibleForTesting
  factory AppLogger.forTest({bool isReleaseMode = false, LogOutput? output}) {
    return AppLogger._(
      _createLogger(isReleaseMode: isReleaseMode, output: output),
      isReleaseMode: isReleaseMode,
    );
  }

  static Logger _createLogger({
    required bool isReleaseMode,
    LogOutput? output,
  }) {
    return Logger(
      level: isReleaseMode ? Level.warning : Level.debug,
      printer: PrettyPrinter(
        methodCount: isReleaseMode ? 0 : 2,
        errorMethodCount: isReleaseMode ? 0 : 8,
        lineLength: 100,
        colors: !isReleaseMode,
        printEmojis: false,
        dateTimeFormat: DateTimeFormat.none,
      ),
      output:
          output ?? (isReleaseMode ? _NoopLogOutput() : _DebugPrintOutput()),
    );
  }

  @visibleForTesting
  static void replaceForTest(AppLogger logger) {
    instance = logger;
  }

  @visibleForTesting
  static void reset() {
    instance = AppLogger._(
      _createLogger(isReleaseMode: kReleaseMode),
      isReleaseMode: kReleaseMode,
    );
  }

  void d(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Object? cause,
    StackTrace? causeStackTrace,
  }) {
    if (isReleaseMode) {
      return;
    }
    _logger.d(
      _compose(message, cause: cause, causeStackTrace: causeStackTrace),
      error: _redactError(error),
      stackTrace: _redactStackTrace(stackTrace),
    );
  }

  void i(String message, {Object? error, StackTrace? stackTrace}) {
    if (isReleaseMode) {
      return;
    }
    _logger.i(
      redactSensitiveText(message),
      error: _redactError(error),
      stackTrace: _redactStackTrace(stackTrace),
    );
  }

  void w(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Object? cause,
    StackTrace? causeStackTrace,
  }) {
    if (isReleaseMode) {
      _logger.w(redactSensitiveText(message));
      return;
    }
    _logger.w(
      _compose(message, cause: cause, causeStackTrace: causeStackTrace),
      error: _redactError(error),
      stackTrace: _redactStackTrace(stackTrace),
    );
  }

  void e(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Object? cause,
    StackTrace? causeStackTrace,
  }) {
    if (isReleaseMode) {
      _logger.e(redactSensitiveText(message));
      return;
    }
    _logger.e(
      _compose(message, cause: cause, causeStackTrace: causeStackTrace),
      error: _redactError(error),
      stackTrace: _redactStackTrace(stackTrace),
    );
  }

  String _compose(
    String message, {
    Object? cause,
    StackTrace? causeStackTrace,
  }) {
    final safeMessage = redactSensitiveText(message);
    if (isReleaseMode ||
        !kDebugMode ||
        (cause == null && causeStackTrace == null)) {
      return safeMessage;
    }
    final buffer = StringBuffer(safeMessage);
    if (cause != null) {
      buffer.write(' | cause=${_safeString(cause)}');
    }
    if (causeStackTrace != null) {
      buffer.write(' | causeStack=${_safeString(causeStackTrace)}');
    }
    return buffer.toString();
  }

  Object? _redactError(Object? error) {
    if (error == null) {
      return null;
    }
    return _safeString(error);
  }

  StackTrace? _redactStackTrace(StackTrace? stackTrace) {
    if (stackTrace == null) {
      return null;
    }
    return StackTrace.fromString(_safeString(stackTrace));
  }

  String _safeString(Object value) {
    try {
      return redactSensitiveText(value.toString());
    } catch (_) {
      return '<unprintable>';
    }
  }
}

class _DebugPrintOutput extends LogOutput {
  _DebugPrintOutput();

  @override
  void output(OutputEvent event) {
    for (final line in event.lines) {
      debugPrint(redactSensitiveText(line));
    }
  }
}

class _NoopLogOutput extends LogOutput {
  _NoopLogOutput();

  @override
  void output(OutputEvent event) {}
}

AppLogger get appLog => AppLogger.instance;
