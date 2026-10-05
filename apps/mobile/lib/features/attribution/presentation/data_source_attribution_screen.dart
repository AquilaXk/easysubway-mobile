import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../accessible_design.dart';
import '../../../app/app_components.dart';

class DataSourceAttributionScreen extends StatefulWidget {
  const DataSourceAttributionScreen({
    super.key,
    this.initialManifest,
    this.initialInventory,
  }) : assert(
         (initialManifest == null) == (initialInventory == null),
         'initialManifest and initialInventory must be provided together.',
       );

  final Map<String, Object?>? initialManifest;
  final Map<String, Object?>? initialInventory;

  @override
  State<DataSourceAttributionScreen> createState() =>
      _DataSourceAttributionScreenState();
}

class _DataSourceAttributionScreenState
    extends State<DataSourceAttributionScreen> {
  static const _mapManifestAsset =
      'assets/datapacks/metro_map_pack/manifest.json';
  static const _sourceInventoryAsset = 'assets/datapacks/source-inventory.json';

  late final Future<
    ({Map<String, Object?> manifest, Map<String, Object?> inventory})
  >
  _future = _load();

  Future<({Map<String, Object?> manifest, Map<String, Object?> inventory})>
  _load() async {
    final initialManifest = widget.initialManifest;
    final initialInventory = widget.initialInventory;
    if (initialManifest != null && initialInventory != null) {
      return (manifest: initialManifest, inventory: initialInventory);
    }
    final [manifestText, inventoryText] = await Future.wait([
      rootBundle.loadString(_mapManifestAsset),
      rootBundle.loadString(_sourceInventoryAsset),
    ]);
    return (
      manifest: jsonDecode(manifestText) as Map<String, Object?>,
      inventory: jsonDecode(inventoryText) as Map<String, Object?>,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('dataSourceAttributionScreen'),
      appBar: AppBar(
        title: const Text('데이터 및 지도 출처'),
        flexibleSpace: const Align(
          alignment: Alignment.bottomCenter,
          child: EasySubwayHeaderDivider.mapChrome(),
        ),
      ),
      body: SafeArea(
        child:
            FutureBuilder<
              ({Map<String, Object?> manifest, Map<String, Object?> inventory})
            >(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return ListView(
                    padding: mainPagePadding,
                    children: const [
                      AppCard(
                        child: AppInfoRow(
                          icon: Icons.error_outline,
                          iconColor: EasySubwayAccessibleColors.amber,
                          title: '자료 제공 정보를 불러오지 못했어요',
                          subtitle: '앱을 다시 열고, 계속 보이지 않으면 고객지원에 알려 주세요.',
                        ),
                      ),
                    ],
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final manifest = snapshot.data!.manifest;
                final inventory = snapshot.data!.inventory;
                final maps = (manifest['maps'] as List)
                    .cast<Map<String, Object?>>();
                final sources = (inventory['sources'] as List)
                    .cast<Map<String, Object?>>()
                    .where(isListedDataSource)
                    .toList(growable: false);
                return ListView(
                  padding: mainPagePadding,
                  children: [
                    const AppCard(
                      child: AppInfoRow(
                        icon: Icons.fact_check_outlined,
                        iconColor: EasySubwayAccessibleColors.amber,
                        title: '자료 안내',
                        subtitle: '지도와 길·시설 안내는 공식·공개 자료를 바탕으로 해요.',
                      ),
                    ),
                    const AppSectionTitle(title: '노선도'),
                    for (final map in maps) _AttributionCard.map(map),
                    const AppSectionTitle(title: '길·시설 안내에 쓰는 자료'),
                    for (final source in sources)
                      _AttributionCard.source(source),
                  ],
                );
              },
            ),
      ),
    );
  }
}

/// 사용자 출처 목록에 올리는 자료인지(내부 수집 검사용 자료는 뺀다).
@visibleForTesting
bool isListedDataSource(Map<String, Object?> source) =>
    !source.containsKey('rawSnapshotAdmission') &&
    !_isInternalCanarySource(source);

/// CI canary 원천은 데이터 수집 검사용 내부 원천이라 사용자 출처 목록에 넣지
/// 않는다(#444 리뷰 F1). source-inventory에는 canary를 뜻하는 구조 필드가
/// 없다. requiredForProductionPack·productionUseAllowed·capabilities는 서비스용
/// 원천(빠른하차 등)과 값이 같아 구분하지 못한다. 그래서 안정 식별자인 `id`의
/// 마지막 토큰 `canary`로 판정한다. 표시 이름은 보지 않는다.
bool _isInternalCanarySource(Map<String, Object?> source) {
  final id = source['id'];
  return id is String && id.split('-').last == 'canary';
}

/// 자료 목록의 표시 이름에서 내부 작업용 꼬리표를 떼어 사용자에게 보일 이름으로
/// 만든다(#443). 예: `…대구 1호선 membership admission` → `…대구 1호선`.
@visibleForTesting
String userFacingSourceName(String displayName) => displayName
    .replaceAll(RegExp(r'\s*membership admission$'), '')
    .replaceAll('_route_map_positions', '')
    .replaceAll(RegExp(r'\s*\(KRIC \d+\)'), '')
    .trim();

class _AttributionCard extends StatelessWidget {
  const _AttributionCard._({
    required this.title,
    required this.subtitle,
    required this.rows,
  });

  factory _AttributionCard.map(Map<String, Object?> map) {
    final license = (map['license'] as Map<String, Object?>?) ?? const {};
    return _AttributionCard._(
      title: '${_text(map['name_ko'], '지도')} 노선도',
      subtitle: '쉬운 지하철이 직접 그린 노선도예요.',
      rows: [..._rowIfPresent('기준일', _date(license['date']))],
    );
  }

  factory _AttributionCard.source(Map<String, Object?> source) {
    final license = (source['license'] as Map<String, Object?>?) ?? const {};
    final provider = _text(source['provider'], '');
    final owner = _text(source['owner'], '');
    return _AttributionCard._(
      title: userFacingSourceName(_text(source['displayName'], '자료')),
      subtitle: [
        provider,
        if (owner.isNotEmpty && owner != provider) owner,
      ].where((name) => name.isNotEmpty).join(' / '),
      rows: [
        ..._rowIfPresent('이용 조건', _text(license['name'], '')),
        ..._rowIfPresent('출처 표기', _text(license['attribution'], '')),
        ..._rowIfPresent('자료 받은 날', _date(source['retrievedAt'])),
        ..._rowIfPresent('자료 확인일', _date(source['observedDataUpdatedAt'])),
        ..._rowIfPresent('안내 페이지', _text(license['evidenceUrl'], '')),
      ],
    );
  }

  /// 값이 없는 항목은 "정보 없음" 같은 말을 띄우지 않고 숨긴다.
  static List<(String, String)> _rowIfPresent(String label, String value) =>
      value.isEmpty ? const [] : [(label, value)];

  /// `2026-07-12T00:00:00+00:00` 같은 값을 날짜만 남긴다.
  static String _date(Object? value) {
    final text = _text(value, '');
    final match = RegExp(r'^\d{4}-\d{2}-\d{2}').firstMatch(text);
    return match?.group(0) ?? text;
  }

  final String title;
  final String subtitle;
  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) {
    final semanticLabel = [
      title,
      subtitle,
      for (final row in rows) '${row.$1}: ${row.$2}',
    ].join(', ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Semantics(
        label: semanticLabel,
        child: AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: EasySubwayAccessibleColors.text,
                  fontWeight: FontWeight.w700,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: EasySubwayAccessibleColors.mutedText,
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 10),
              for (final row in rows)
                _AttributionRow(label: row.$1, value: row.$2),
            ],
          ),
        ),
      ),
    );
  }

  static String _text(Object? value, [String fallback = '']) {
    if (value is List) {
      final joined = value
          .whereType<Object>()
          .map((item) => '$item')
          .join(', ');
      return joined.isEmpty ? fallback : joined;
    }
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }
}

class _AttributionRow extends StatelessWidget {
  const _AttributionRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: EasySubwayAccessibleColors.secondaryText,
              fontWeight: FontWeight.w700,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: EasySubwayAccessibleColors.text,
              fontWeight: FontWeight.w700,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}
