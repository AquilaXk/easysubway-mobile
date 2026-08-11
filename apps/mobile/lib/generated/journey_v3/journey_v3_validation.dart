// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=200
// Generated strict Journey V3 JSON validation helpers.
class JourneyDate {
  final String value;
  const JourneyDate._(this.value);
  factory JourneyDate.parse(Object? value) {
    if (value is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) throw const FormatException('invalid JourneyDate');
    final year = int.parse(value.substring(0, 4));
    final month = int.parse(value.substring(5, 7));
    final day = int.parse(value.substring(8, 10));
    final date = DateTime.utc(year, month, day);
    if (date.year != year || date.month != month || date.day != day) throw const FormatException('invalid JourneyDate');
    return JourneyDate._(value);
  }
  @override
  String toString() => value;
}

abstract final class JourneyV3Validation {
  static void exactKeys(Map<String, Object?> value, Set<String> keys) {
    if (value.length != keys.length || !value.keys.toSet().containsAll(keys)) throw const FormatException('unexpected JSON keys');
  }

  static String string(Object? value, String field) {
    if (value is! String) throw FormatException('$field must be string');
    return value;
  }

  static String nonBlank(Object? value, String field) {
    final text = string(value, field);
    if (text.trim().isEmpty) throw FormatException('$field must be nonblank');
    return text;
  }

  static String matching(Object? value, String field, RegExp pattern) {
    final text = string(value, field);
    if (!pattern.hasMatch(text)) throw FormatException('$field has invalid format');
    return text;
  }

  static String ulid(Object? value, String field) => matching(value, field, RegExp(r'^[0-7][0-9A-HJKMNP-TV-Z]{25}$'));
  static String sha256(Object? value, String field) => matching(value, field, RegExp(r'^[a-f0-9]{64}$'));
  static int integer(Object? value, String field, int minimum, [int? maximum]) {
    if (value is! int || value < minimum || (maximum != null && value > maximum)) throw FormatException('$field outside range');
    return value;
  }

  static bool boolean(Object? value, String field) {
    if (value is! bool) throw FormatException('$field must be bool');
    return value;
  }

  static T enumWire<T>(Object? value, String field, T Function(Object?) parse) {
    try {
      return parse(value);
    } on FormatException {
      throw FormatException('$field has unrecognized wire value');
    }
  }

  static DateTime rfc3339(Object? value, String field) {
    final text = string(value, field);
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$').firstMatch(text);
    if (match == null) throw const FormatException('invalid RFC3339 date-time');
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    final hour = int.parse(match.group(4)!);
    final minute = int.parse(match.group(5)!);
    final second = int.parse(match.group(6)!);
    if (hour > 23 || minute > 59 || second > 59) throw const FormatException('invalid RFC3339 date-time');
    final calendar = DateTime.utc(year, month, day, hour, minute, second);
    if (calendar.year != year || calendar.month != month || calendar.day != day || calendar.hour != hour || calendar.minute != minute || calendar.second != second) {
      throw const FormatException('invalid RFC3339 date-time');
    }
    if (!text.endsWith('Z')) {
      final offset = RegExp(r'([+-])(\d{2}):(\d{2})$').firstMatch(text);
      if (offset == null || int.parse(offset.group(2)!) > 23 || int.parse(offset.group(3)!) > 59) throw const FormatException('invalid RFC3339 offset');
    }
    try {
      return DateTime.parse(text);
    } on FormatException {
      throw const FormatException('invalid RFC3339 date-time');
    }
  }

  static String rfc3339Wire(DateTime value) => value.toUtc().toIso8601String();
  static T? nullable<T>(Map<String, Object?> json, String key, T Function(Object?) parse) {
    if (!json.containsKey(key)) throw FormatException('$key is required');
    final value = json[key];
    return value == null ? null : parse(value);
  }

  static List<T> list<T>(Object? value, String field, T Function(Object?) parse, {int minimum = 0, int? maximum, bool unique = false}) {
    if (value is! List || value.length < minimum || (maximum != null && value.length > maximum)) throw FormatException('$field has invalid cardinality');
    final parsed = value.map(parse).toList(growable: false);
    if (unique && parsed.toSet().length != parsed.length) throw FormatException('$field must be unique');
    return List<T>.unmodifiable(parsed);
  }
}
