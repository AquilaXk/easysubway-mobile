import 'package:flutter/material.dart';

import '../../../accessible_design.dart';
import '../../../design_tokens.dart';
import '../application/station_search_controller.dart';
import '../domain/station_line.dart';
import '../domain/station_models.dart';
import 'station_line_badges.dart';

/// 검색어 일치 구간 하이라이트는 primary interaction 역할색을 쓴다.
const _searchMatchHighlight = EasySubwayAccessibleColors.interactionPrimary;

/// 즐겨찾기 버튼이 없을 때 이름 앞에 두는 여백.
const _rowLeadingGap = 8.0;

/// 즐겨찾기 채움 별빛.
const _favoriteStarFilled = EasySubwayAccessibleColors.interactionPrimary;

typedef StationSearchFavoriteToggle =
    void Function(StationSearchResult result, StationSearchLine? line);

typedef StationSearchResultTap =
    void Function(StationSearchResult result, StationSearchLine? line);

class StationSearchBody extends StatelessWidget {
  const StationSearchBody({
    super.key,
    required this.state,
    required this.onResultTap,
    this.query = '',
    this.favoriteKeys = const <String>{},
    this.onToggleFavorite,
  });

  final StationSearchState state;
  final StationSearchResultTap onResultTap;
  final String query;

  /// [favoriteStationLineKey] 집합.
  final Set<String> favoriteKeys;
  final StationSearchFavoriteToggle? onToggleFavorite;

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
        for (final row in _sortedResultRows(state.results, favoriteKeys))
          _StationSearchResultLineRow(
            key: Key(
              'stationSearchResult-${row.result.id}-${row.line?.id ?? 'none'}',
            ),
            stationName: _stationResultDisplayName(row.result.nameKo),
            query: query,
            line: row.line,
            showFavorite: onToggleFavorite != null,
            isFavorite: isFavoriteStationLine(
              favoriteKeys,
              row.result.id,
              row.line?.id,
            ),
            semanticLabel: row.line == null
                ? '${_stationResultDisplayName(row.result.nameKo)}, 선택'
                : '${_stationResultDisplayName(row.result.nameKo)}, ${row.line!.name}, 선택',
            onTap: () => onResultTap(row.result, row.line),
            onToggleFavorite: onToggleFavorite == null
                ? null
                : () => onToggleFavorite!(row.result, row.line),
            favoriteButtonKey: Key(
              'stationSearchFavorite-${row.result.id}-${row.line?.id ?? 'none'}',
            ),
          ),
      ],
    );
  }
}

class _StationSearchResultRow {
  const _StationSearchResultRow({
    required this.result,
    required this.line,
    required this.originalIndex,
  });

  final StationSearchResult result;
  final StationSearchLine? line;
  final int originalIndex;
}

/// 호선 행으로 펼친 뒤, 즐겨찾기 행을 위로. 그룹 안·비즐겨찾기는 원래 순서를 유지한다.
List<_StationSearchResultRow> _sortedResultRows(
  List<StationSearchResult> results,
  Set<String> favoriteKeys,
) {
  final rows = <_StationSearchResultRow>[];
  var index = 0;
  for (final result in results) {
    final lines = result.lines;
    if (lines.isEmpty) {
      rows.add(
        _StationSearchResultRow(
          result: result,
          line: null,
          originalIndex: index++,
        ),
      );
      continue;
    }
    for (final line in lines) {
      rows.add(
        _StationSearchResultRow(
          result: result,
          line: line,
          originalIndex: index++,
        ),
      );
    }
  }
  if (favoriteKeys.isEmpty || rows.length < 2) {
    return rows;
  }
  rows.sort((a, b) {
    final aFav = isFavoriteStationLine(favoriteKeys, a.result.id, a.line?.id);
    final bFav = isFavoriteStationLine(favoriteKeys, b.result.id, b.line?.id);
    if (aFav != bFav) {
      return aFav ? -1 : 1;
    }
    return a.originalIndex.compareTo(b.originalIndex);
  });
  return rows;
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
                  fontWeight: FontWeight.w600,
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
          fontWeight: FontWeight.w700,
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
    required this.showFavorite,
    required this.isFavorite,
    required this.semanticLabel,
    required this.onTap,
    this.onToggleFavorite,
    this.favoriteButtonKey,
    super.key,
  });

  final String stationName;
  final String query;
  final StationSearchLine? line;
  final bool showFavorite;
  final bool isFavorite;
  final String semanticLabel;
  final VoidCallback onTap;
  final VoidCallback? onToggleFavorite;
  final Key? favoriteButtonKey;

  /// 역·호선과 현재 상태를 담아 같은 역의 다른 호선 행과 구분한다.
  String get _favoriteSemanticLabel {
    final target = line == null ? stationName : '$stationName, ${line!.name}';
    return '$target 즐겨찾기 ${isFavorite ? '해제' : '추가'}';
  }

  @override
  Widget build(BuildContext context) {
    final line = this.line;
    const nameStyle = TextStyle(
      color: EasySubwayAccessibleColors.text,
      fontSize: 17,
      fontWeight: FontWeight.w600,
      height: 1.2,
    );
    const highlightStyle = TextStyle(
      color: _searchMatchHighlight,
      fontSize: 17,
      fontWeight: FontWeight.w700,
      height: 1.2,
    );
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: EasySubwayAccessibleColors.surface,
        border: Border(
          bottom: BorderSide(color: EasySubwayAccessibleColors.line),
        ),
      ),
      // 즐겨찾기 토글은 행 위에 얹은 형제 노드라, 행 노드는 역 선택만 맡고 토글은 따로 읽힌다.
      child: Stack(
        children: [
          Semantics(
            label: semanticLabel,
            button: true,
            onTap: onTap,
            child: ExcludeSemantics(
              child: InkWell(
                onTap: onTap,
                splashColor: Colors.transparent,
                highlightColor: Colors.transparent,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 56),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        SizedBox.square(
                          dimension: showFavorite
                              ? EasySubwayTouchTarget.general
                              : _rowLeadingGap,
                        ),
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
                          StationLineBadge(line: line, size: 32),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (showFavorite)
            Positioned(
              left: 8,
              top: 8,
              child: _FavoriteToggleButton(
                buttonKey: favoriteButtonKey,
                semanticLabel: _favoriteSemanticLabel,
                isFavorite: isFavorite,
                onPressed: onToggleFavorite,
              ),
            ),
        ],
      ),
    );
  }
}

/// 행 탭과 따로 스크린리더가 짚을 수 있는 즐겨찾기 토글. 라벨에 역·호선과 현재 상태를 담는다.
class _FavoriteToggleButton extends StatelessWidget {
  const _FavoriteToggleButton({
    required this.buttonKey,
    required this.semanticLabel,
    required this.isFavorite,
    required this.onPressed,
  });

  final Key? buttonKey;
  final String semanticLabel;
  final bool isFavorite;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      button: true,
      toggled: isFavorite,
      onTap: onPressed,
      excludeSemantics: true,
      child: IconButton(
        key: buttonKey,
        onPressed: onPressed,
        tooltip: isFavorite ? '즐겨찾기 해제' : '즐겨찾기 추가',
        style: IconButton.styleFrom(
          minimumSize: const Size.square(EasySubwayTouchTarget.general),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          padding: EdgeInsets.zero,
        ),
        icon: Icon(
          isFavorite ? Icons.star : Icons.star_border,
          size: 26,
          color: isFavorite
              ? _favoriteStarFilled
              : EasySubwayAccessibleColors.disclosure,
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
