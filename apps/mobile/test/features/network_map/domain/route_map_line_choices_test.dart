import 'package:easysubway_mobile/features/network_map/domain/network_map_models.dart';
import 'package:easysubway_mobile/features/network_map/domain/route_map_line_choices.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

/// 번들 데이터팩 `lines` 표의 수도권 노선 이름과 색. 저장소는 이름 가나다순으로
/// 돌려주므로 그 순서 그대로 둔다.
const _capitalLines = <(String, String, String)>[
  ('seoul-1', '수도권 1호선', '#0052a4'),
  ('seoul-2', '수도권 2호선', '#00a84d'),
  ('seoul-3', '수도권 3호선', '#ef7c1c'),
  ('seoul-4', '수도권 4호선', '#00a5de'),
  ('seoul-5', '수도권 5호선', '#996cac'),
  ('seoul-6', '수도권 6호선', '#cd7c2f'),
  ('seoul-7', '수도권 7호선', '#747f00'),
  ('seoul-8', '수도권 8호선', '#e6186c'),
  ('seoul-9', '수도권 9호선', '#bdb092'),
  ('gtx-a', '수도권 GTX-A', '#9f6181'),
  ('gyeonggang', '수도권 경강', '#003da5'),
  ('gyeongui', '수도권 경의중앙', '#77c4a3'),
  ('gyeongchun', '수도권 경춘', '#0c8e72'),
  ('airport', '수도권 공항', '#0090d2'),
  ('gimpo', '수도권 김포골드라인', '#a17800'),
  ('seohae', '수도권 서해선', '#81a914'),
  ('suin', '수도권 수인분당', '#f5a200'),
  ('sillim', '수도권 신림선', '#0781fa'),
  ('shinbundang', '수도권 신분당', '#d4003b'),
  ('everline', '수도권 에버라인', '#509f22'),
  ('ui-sinseol', '수도권 우이신설', '#b0ce18'),
  ('uijeongbu', '수도권 의정부', '#fda600'),
  ('incheon-1', '인천 1호선', '#7ca8d5'),
  ('incheon-2', '인천 2호선', '#ed8b00'),
];

List<NetworkMapLine> _lines(Iterable<(String, String, String)> rows) => [
  for (final (id, name, color) in rows)
    NetworkMapLine(id: id, name: name, color: color, region: '수도권'),
];

void main() {
  test('수도권 노선을 상용 지하철 서비스 노선 선택 시트 순서와 이름으로 보여 준다', () {
    final choices = routeMapLineChoices(_lines(_capitalLines));

    expect(choices.map((choice) => choice.name), [
      '1호선',
      '2호선',
      '3호선',
      '4호선',
      '5호선',
      '6호선',
      '7호선',
      '8호선',
      '9호선',
      '공항',
      '경의중앙',
      '경춘',
      '수인분당',
      '신분당',
      '경강',
      '서해',
      '인천1',
      '인천2',
      '에버라인',
      '의정부',
      '우이신설',
      '김포골드',
      '신림',
      'GTX-A',
    ]);
  });

  test('번호 노선은 번호, 이름 노선은 첫 글자 하나를 원형 마크에 쓴다', () {
    final marks = {
      for (final choice in routeMapLineChoices(_lines(_capitalLines)))
        choice.name: choice.markLabel,
    };

    expect(marks['1호선'], '1');
    expect(marks['9호선'], '9');
    expect(marks['공항'], '공');
    expect(marks['경의중앙'], '경');
    expect(marks['경강'], '경');
    expect(marks['인천1'], '인');
    expect(marks['우이신설'], '우');
    expect(marks['김포골드'], '김');
    expect(marks['GTX-A'], 'G');
  });

  test('노선색은 데이터팩 색을 그대로 쓴다', () {
    final choices = routeMapLineChoices(_lines(_capitalLines));

    expect(
      choices.firstWhere((choice) => choice.lineId == 'ui-sinseol').color,
      const Color(0xFFB0CE18),
    );
  });

  test('데이터팩에 없는 노선은 만들지 않는다', () {
    final choices = routeMapLineChoices(
      _lines(
        _capitalLines.where(
          (row) => row.$1 == 'seoul-2' || row.$1 == 'ui-sinseol',
        ),
      ),
    );

    expect(choices.map((choice) => choice.lineId), ['seoul-2', 'ui-sinseol']);
  });

  test('순서표에 없는 이름 노선은 번호·순서표 노선 뒤에 데이터팩 순서대로 둔다', () {
    final choices = routeMapLineChoices(
      _lines(const [
        ('busan-donghae', '부산 동해', '#b7a36a'),
        ('busan-1', '부산 1호선', '#f06a00'),
        ('busan-gimhae', '부산 부산김해경전철', '#8652a1'),
        ('busan-2', '부산 2호선', '#81bf48'),
      ]),
    );

    expect(choices.map((choice) => choice.name), ['1호선', '2호선', '동해', '부산김해']);
    expect(choices.map((choice) => choice.markLabel), ['1', '2', '동', '부']);
  });

  test('고른 노선 id가 지금 노선 목록에 없으면 고른 노선이 없다', () {
    final choices = routeMapLineChoices(_lines(_capitalLines));

    expect(routeMapSelectedLineChoice(choices, 'ui-sinseol')?.name, '우이신설');
    expect(routeMapSelectedLineChoice(choices, 'busan-1'), isNull);
    expect(routeMapSelectedLineChoice(choices, null), isNull);
  });
}
