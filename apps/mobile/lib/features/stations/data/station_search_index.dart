// 역 검색용 정렬 prefix term 인덱스.
// 모든 prefix 조합을 Map으로 펼치지 않고, 정렬된 term 테이블에서
// lower-bound + startsWith 순회로 후보 station id만 모은다.
import 'dart:collection';

enum StationSearchTermKind { korean, english, subname, chosung }

/// 검색 질의 및 정규화 문자열의 64-bit 2-gram Bloom 필터 서명을 계산한다.
///
/// 부분일치(`contains`) 스캔 시 `(target.bloom64 & queryBloom) == queryBloom` 비트
/// 연산으로 불일치 대상을 문자열 비교 전에 O(1)로 즉시 기각한다.
int computeSearchBloom64(String text) {
  if (text.isEmpty) return 0;
  var mask = 0;
  final len = text.length;
  if (len == 1) {
    final c = text.codeUnitAt(0);
    final h1 = (c * 31) & 63;
    final h2 = ((c * 17) ^ (c >> 4)) & 63;
    return (1 << h1) | (1 << h2);
  }
  for (var i = 0; i < len - 1; i++) {
    final c1 = text.codeUnitAt(i);
    final c2 = text.codeUnitAt(i + 1);
    final h1 = ((c1 * 31) ^ c2) & 63;
    final h2 = (((c1 << 5) - c1) ^ (c2 * 17)) & 63;
    mask |= (1 << h1) | (1 << h2);
  }
  return mask;
}

class StationSearchTermEntry implements Comparable<StationSearchTermEntry> {
  const StationSearchTermEntry({
    required this.normalizedKey,
    required this.stationId,
    required this.termKind,
  });

  final String normalizedKey;
  final String stationId;
  final StationSearchTermKind termKind;

  @override
  int compareTo(StationSearchTermEntry other) {
    final byKey = normalizedKey.compareTo(other.normalizedKey);
    if (byKey != 0) {
      return byKey;
    }
    return stationId.compareTo(other.stationId);
  }
}

/// 인덱스 구축에 필요한 최소 station 행.
class StationSearchIndexStationRow {
  const StationSearchIndexStationRow({
    required this.stationId,
    required this.koreanTerms,
    required this.englishTerms,
    required this.subnameTerms,
    required this.chosungTerms,
  });

  final String stationId;
  final List<String> koreanTerms;
  final List<String> englishTerms;
  final List<String> subnameTerms;
  final List<String> chosungTerms;
}

class StationSearchIndex {
  StationSearchIndex._({
    required this.sortedKoreanTerms,
    required this.sortedEnglishTerms,
    required this.sortedSubnameTerms,
    required this.sortedChosungTerms,
  });

  final List<StationSearchTermEntry> sortedKoreanTerms;
  final List<StationSearchTermEntry> sortedEnglishTerms;
  final List<StationSearchTermEntry> sortedSubnameTerms;
  final List<StationSearchTermEntry> sortedChosungTerms;

  factory StationSearchIndex.build(List<StationSearchIndexStationRow> rows) {
    final korean = <StationSearchTermEntry>[];
    final english = <StationSearchTermEntry>[];
    final subname = <StationSearchTermEntry>[];
    final chosung = <StationSearchTermEntry>[];

    for (final row in rows) {
      for (final term in row.koreanTerms) {
        if (term.isEmpty) {
          continue;
        }
        korean.add(
          StationSearchTermEntry(
            normalizedKey: term,
            stationId: row.stationId,
            termKind: StationSearchTermKind.korean,
          ),
        );
      }
      for (final term in row.englishTerms) {
        if (term.isEmpty) {
          continue;
        }
        english.add(
          StationSearchTermEntry(
            normalizedKey: term,
            stationId: row.stationId,
            termKind: StationSearchTermKind.english,
          ),
        );
      }
      for (final term in row.subnameTerms) {
        if (term.isEmpty) {
          continue;
        }
        subname.add(
          StationSearchTermEntry(
            normalizedKey: term,
            stationId: row.stationId,
            termKind: StationSearchTermKind.subname,
          ),
        );
      }
      for (final term in row.chosungTerms) {
        if (term.isEmpty) {
          continue;
        }
        chosung.add(
          StationSearchTermEntry(
            normalizedKey: term,
            stationId: row.stationId,
            termKind: StationSearchTermKind.chosung,
          ),
        );
      }
    }

    korean.sort();
    english.sort();
    subname.sort();
    chosung.sort();

    return StationSearchIndex._(
      sortedKoreanTerms: UnmodifiableListView(korean),
      sortedEnglishTerms: UnmodifiableListView(english),
      sortedSubnameTerms: UnmodifiableListView(subname),
      sortedChosungTerms: UnmodifiableListView(chosung),
    );
  }

  /// [query]로 시작하는 term의 station id를 중복 없이 모은다.
  void collectPrefixMatches(
    List<StationSearchTermEntry> sortedTerms,
    String query,
    Set<String> sink,
  ) {
    if (query.isEmpty || sortedTerms.isEmpty) {
      return;
    }
    final start = _lowerBound(sortedTerms, query);
    if (start >= sortedTerms.length) {
      return;
    }
    for (var i = start; i < sortedTerms.length; i++) {
      final entry = sortedTerms[i];
      if (!entry.normalizedKey.startsWith(query)) {
        break;
      }
      sink.add(entry.stationId);
    }
  }

  void collectChosungPrefixInto(String query, Set<String> sink) {
    collectPrefixMatches(sortedChosungTerms, query, sink);
  }

  void collectNamePrefixInto(String query, Set<String> sink) {
    if (query.isEmpty) {
      return;
    }
    collectPrefixMatches(sortedKoreanTerms, query, sink);
    collectPrefixMatches(sortedEnglishTerms, query, sink);
    collectPrefixMatches(sortedSubnameTerms, query, sink);
  }

  Set<String> lookupPrefix(
    List<StationSearchTermEntry> sortedTerms,
    String query,
  ) {
    if (query.isEmpty || sortedTerms.isEmpty) {
      return const {};
    }
    final ids = <String>{};
    collectPrefixMatches(sortedTerms, query, ids);
    return ids;
  }

  Set<String> lookupChosungPrefix(String query) =>
      lookupPrefix(sortedChosungTerms, query);

  Set<String> lookupNamePrefix(String query) {
    if (query.isEmpty) {
      return const {};
    }
    final ids = <String>{};
    collectNamePrefixInto(query, ids);
    return ids;
  }
}

int _lowerBound(List<StationSearchTermEntry> sorted, String query) {
  var low = 0;
  var high = sorted.length;
  while (low < high) {
    final mid = low + ((high - low) >> 1);
    if (sorted[mid].normalizedKey.compareTo(query) < 0) {
      low = mid + 1;
    } else {
      high = mid;
    }
  }
  return low;
}
