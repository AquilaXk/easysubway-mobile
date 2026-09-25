import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/widgets.dart';

import '../../../core/database/user/user_database.dart' as user_db;
import '../domain/network_map_models.dart';

const _networkMapViewportKeyPrefix = 'network_map_viewport';
const _networkMapSelectedRegionKey = 'network_map_selected_region';

class DriftNetworkMapViewportRepository
    implements NetworkMapViewportRepository {
  DriftNetworkMapViewportRepository({required this.userDatabase});

  final user_db.UserDatabase userDatabase;
  final Map<String, Rect> _viewportCache = {};
  String? _selectedRegionCache;

  @override
  Future<String?> loadSelectedRegion() async {
    if (_selectedRegionCache != null) {
      return _selectedRegionCache;
    }
    final row = await userDatabase
        .customSelect(
          'SELECT value FROM app_preferences WHERE key = ?',
          variables: [Variable.withString(_networkMapSelectedRegionKey)],
          readsFrom: {userDatabase.appPreferences},
        )
        .getSingleOrNull();
    final region = row?.read<String>('value').trim();
    final result = region == null || region.isEmpty ? null : region;
    _selectedRegionCache = result;
    return result;
  }

  @override
  Future<void> saveSelectedRegion(String region) async {
    final value = region.trim();
    if (value.isEmpty) {
      throw ArgumentError.value(region, 'region', 'must not be empty');
    }
    _selectedRegionCache = value;
    await userDatabase
        .into(userDatabase.appPreferences)
        .insertOnConflictUpdate(
          user_db.AppPreferencesCompanion.insert(
            key: _networkMapSelectedRegionKey,
            value: value,
            updatedAt: DateTime.now().toUtc(),
          ),
        );
  }

  @override
  Future<Rect?> loadViewport(String region) async {
    final key = _storageKey(region);
    if (_viewportCache.containsKey(key)) {
      return _viewportCache[key];
    }
    final row = await userDatabase
        .customSelect(
          'SELECT value FROM app_preferences WHERE key = ?',
          variables: [Variable.withString(key)],
          readsFrom: {userDatabase.appPreferences},
        )
        .getSingleOrNull();
    if (row == null) {
      return null;
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(row.read<String>('value'));
    } on FormatException {
      return null;
    }
    if (decoded is! Map<String, Object?>) {
      return null;
    }
    final left = _doubleFrom(decoded['left']);
    final top = _doubleFrom(decoded['top']);
    final right = _doubleFrom(decoded['right']);
    final bottom = _doubleFrom(decoded['bottom']);
    if (left == null || top == null || right == null || bottom == null) {
      return null;
    }
    if (right <= left || bottom <= top) {
      return null;
    }
    final rect = Rect.fromLTRB(left, top, right, bottom);
    _viewportCache[key] = rect;
    return rect;
  }

  @override
  Future<void> saveViewport({
    required String region,
    required Rect viewport,
  }) async {
    final key = _storageKey(region);
    _viewportCache[key] = viewport;
    final now = DateTime.now().toUtc();
    await userDatabase
        .into(userDatabase.appPreferences)
        .insertOnConflictUpdate(
          user_db.AppPreferencesCompanion.insert(
            key: key,
            value: jsonEncode({
              'left': viewport.left,
              'top': viewport.top,
              'right': viewport.right,
              'bottom': viewport.bottom,
            }),
            updatedAt: now,
          ),
        );
  }

  String _storageKey(String region) => '$_networkMapViewportKeyPrefix:$region';
}

double? _doubleFrom(Object? value) {
  if (value is num) {
    final result = value.toDouble();
    return result.isFinite ? result : null;
  }
  return null;
}
