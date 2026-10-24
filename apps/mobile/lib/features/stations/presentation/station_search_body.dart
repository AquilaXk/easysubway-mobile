import 'package:flutter/material.dart';

import '../../../accessible_design.dart';
import '../../../core/ui/line_mark.dart';
import '../../../design_tokens.dart';
import '../application/station_search_controller.dart';
import '../domain/station_line.dart';
import '../domain/station_models.dart';
import 'station_line_badges.dart';

const _searchMatchHighlight = EasySubwayAccessibleColors.searchMatchHighlight;

/// 결과 행 좌우 여백. 역명과 노선 마크가 같은 가장자리 간격을 갖는다.
const _rowHorizontalPadding = 18.0;

/// 결과 행 최소 높이.
const _rowMinHeight = 52.0;

const _stationNameFontSize = 16.0;

typedef StationSearchResultTap =
    void Function(StationSearchResult result, StationSearchLine? line);

class StationSearchBody extends StatelessWidget {
  const StationSearchBody({
    super.key,
    required this.state,
    required this.onResultTap,
    this.query = '',
  });

  final StationSearchState state;
  final StationSearchResultTap onResultTap;
  final String query;

  @override
  Widget build(BuildContext context) {
    return switch (state.status) {
      StationSearchStatus.idle => const SizedBox.shrink(),
      // 재검색 중에도 이전 결과가 있으면 목록을 유지한다(스피너 깜빡임 방지).
      StationSearchStatus.loading when state.results.isNotEmpty =>
        _buildResults(announceCount: false),
      StationSearchStatus.loading => Semantics(
        label: '역 검색 중',
        liveRegion: true,
        child: const Center(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: CircularProgressIndicator(),
          ),
        ),
      ),
      // 노선도 임베드·풀페이지 검색 공통: 최근 검색 빈 상태와 같은 토큰.
      StationSearchStatus.empty => _StationSearchEmptyState(
        message: state.message,
        liveRegion: true,
      ),
      StationSearchStatus.failure => _StationSearchMessage(
        message: state.message,
        liveRegion: true,
      ),
      StationSearchStatus.success => _buildResults(announceCount: true),
    };
  }

  Widget _buildResults({required bool announceCount}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (announceCount)
          Semantics(
            container: true,
            label: '검색 결과 ${state.results.length}개',
            liveRegion: true,
            child: const SizedBox(width: 1, height: 1),
          ),
        if (!announceCount)
          Semantics(
            label: '역 검색 중',
            liveRegion: true,
            child: const SizedBox(width: 1, height: 1),
          ),
        for (final row in _resultRows(state.results))
          _StationSearchResultLineRow(
            key: Key(
              'stationSearchResult-${row.result.id}-${row.line?.id ?? 'none'}',
            ),
            stationName: _stationResultDisplayName(row.result.nameKo),
            query: query,
            line: row.line,
            semanticLabel: row.line == null
                ? '${_stationResultDisplayName(row.result.nameKo)}, 선택'
                : '${_stationResultDisplayName(row.result.nameKo)}, ${row.line!.name}, 선택',
            onTap: () => onResultTap(row.result, row.line),
          ),
      ],
    );
  }
}

class _StationSearchResultRow {
  const _StationSearchResultRow({required this.result, required this.line});

  final StationSearchResult result;
  final StationSearchLine? line;
}

/// 역·호선 쌍마다 한 행으로 펼친다. 호선이 없는 역은 마크 없는 한 행이다.
List<_StationSearchResultRow> _resultRows(List<StationSearchResult> results) {
  return [
    for (final result in results)
      if (result.lines.isEmpty)
        _StationSearchResultRow(result: result, line: null)
      else
        for (final line in result.lines)
          _StationSearchResultRow(result: result, line: line),
  ];
}

class _StationSearchEmptyState extends StatelessWidget {
  const _StationSearchEmptyState({
    required this.message,
    this.liveRegion = false,
  });

  final String message;
  final bool liveRegion;

  // 최근 검색 빈 상태와 동일 토큰(아이콘 56·글자 16·disclosure·정렬 -0.55).
  static const _iconSize = 56.0;
  static const _emptyTone = EasySubwayAccessibleColors.disclosure;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final keyboardOpen = media.viewInsets.bottom > 0;
    final minHeight =
        (media.size.height -
                media.padding.top -
                media.viewInsets.bottom -
                easySubwayTopBarContentHeight -
                48)
            .clamp(220.0, 640.0);

    return Semantics(
      key: const Key('stationSearchEmptyState'),
      container: true,
      liveRegion: liveRegion,
      label: message,
      child: SizedBox(
        width: double.infinity,
        height: minHeight,
        child: Align(
          alignment: Alignment(0, keyboardOpen ? -0.75 : -0.55),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                'assets/illustrations/empty_recent_search_warning.png',
                key: const Key('stationSearchEmptyImage'),
                width: _iconSize,
                height: _iconSize,
                color: _emptyTone,
                colorBlendMode: BlendMode.srcIn,
                excludeFromSemantics: true,
              ),
              const SizedBox(height: EasySubwaySpacing.md),
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: _emptyTone,
                  height: 1.35,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StationSearchMessage extends StatelessWidget {
  const _StationSearchMessage({required this.message, this.liveRegion = false});

  final String message;
  final bool liveRegion;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      liveRegion: liveRegion,
      child: Text(
        message,
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
          color: EasySubwayAccessibleColors.secondaryText,
          height: 1.35,
        ),
      ),
    );
  }
}

class _StationSearchResultLineRow extends StatelessWidget {
  const _StationSearchResultLineRow({
    required this.stationName,
    required this.query,
    required this.line,
    required this.semanticLabel,
    required this.onTap,
    super.key,
  });

  final String stationName;
  final String query;
  final StationSearchLine? line;
  final String semanticLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final line = this.line;
    const nameStyle = TextStyle(
      color: EasySubwayAccessibleColors.text,
      fontSize: _stationNameFontSize,
      fontWeight: EasySubwayFontWeight.regular,
      height: 1.2,
    );
    final highlightStyle = nameStyle.copyWith(color: _searchMatchHighlight);
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: EasySubwayAccessibleColors.surface,
        border: Border(
          bottom: BorderSide(color: EasySubwayAccessibleColors.line),
        ),
      ),
      child: Semantics(
        label: semanticLabel,
        button: true,
        onTap: onTap,
        child: ExcludeSemantics(
          child: InkWell(
            onTap: onTap,
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: _rowMinHeight),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: _rowHorizontalPadding,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          children: _highlightedNameSpans(
                            stationName,
                            query,
                            nameStyle,
                            highlightStyle,
                          ),
                        ),
                      ),
                    ),
                    if (line != null) ...[
                      const SizedBox(width: 12),
                      StationLineBadge(line: line, size: lineMarkDefaultSize),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

List<InlineSpan> _highlightedNameSpans(
  String text,
  String query,
  TextStyle base,
  TextStyle highlight,
) {
  final trimmedQuery = query.trim();
  if (trimmedQuery.isEmpty) {
    return [TextSpan(text: text, style: base)];
  }
  final lowerText = text.toLowerCase();
  final lowerQuery = trimmedQuery.toLowerCase();
  if (lowerQuery.isEmpty) {
    return [TextSpan(text: text, style: base)];
  }
  final spans = <InlineSpan>[];
  var start = 0;
  while (start < text.length) {
    final matchIndex = lowerText.indexOf(lowerQuery, start);
    if (matchIndex < 0) {
      spans.add(TextSpan(text: text.substring(start), style: base));
      break;
    }
    if (matchIndex > start) {
      spans.add(TextSpan(text: text.substring(start, matchIndex), style: base));
    }
    spans.add(
      TextSpan(
        text: text.substring(matchIndex, matchIndex + lowerQuery.length),
        style: highlight,
      ),
    );
    start = matchIndex + lowerQuery.length;
  }
  return spans;
}

String _stationResultDisplayName(String name) {
  final trimmedName = name.trim();
  // 백엔드 역 이름은 접미사 없이 내려올 수 있어 검색 결과 화면에서만 보정한다.
  if (trimmedName.endsWith('역')) {
    return trimmedName;
  }
  return '$trimmedName역';
}
