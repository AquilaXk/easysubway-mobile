import 'package:easysubway_mobile/accessible_design.dart';
import 'package:easysubway_mobile/features/network_map/presentation/nearby_station_line_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

const _line2Green = Color(0xFF00A84D);

Widget _bar({
  required String leftName,
  required String rightName,
  String stationName = '금남로4가',
  double width = 412,
  double textScale = 1,
}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(
        size: Size(width, 800),
        textScaler: TextScaler.linear(textScale),
      ),
      child: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            child: NearbyStationLineBar(
              leftName: leftName,
              rightName: rightName,
              stationName: stationName,
              badgeText: '1',
              lineColor: _line2Green,
              onLeftNameTap: () {},
              onRightNameTap: () {},
            ),
          ),
        ),
      ),
    ),
  );
}

RenderParagraph _paragraph(WidgetTester tester, String text) =>
    tester.renderObject<RenderParagraph>(find.text(text));

double _renderedFontSize(WidgetTester tester, String text) {
  final paragraph = _paragraph(tester, text);
  return paragraph.textScaler.scale(paragraph.text.style!.fontSize!);
}

void main() {
  testWidgets('긴 이웃역 이름도 14pt 대비용 굵기로 그린다', (tester) async {
    await tester.pumpWidget(
      _bar(leftName: '동대문역사문화공원', rightName: '국제금융센터·부산은행'),
    );

    for (final name in ['동대문역사문화공원', '국제금융센터·부산은행']) {
      final style = tester.widget<Text>(find.text(name)).style!;
      expect(style.fontSize, 14);
      expect(style.fontWeight, EasySubwayFontWeight.boldForContrast);
      expect(style.color, EasySubwayAccessibleColors.interactionOnPrimary);
    }
  });

  testWidgets('글자 1.5배에서 넘치는 이름은 14pt까지 줄여 끝까지 보인다', (tester) async {
    await tester.pumpWidget(
      _bar(
        leftName: '주안국가산단',
        rightName: '시민공원',
        stationName: '주안',
        textScale: 1.5,
      ),
    );

    for (final name in ['주안국가산단', '시민공원']) {
      expect(_paragraph(tester, name).didExceedMaxLines, isFalse);
      expect(_renderedFontSize(tester, name), greaterThanOrEqualTo(14));
    }
  });

  testWidgets('자리가 넉넉하면 글자 배율을 그대로 따른다', (tester) async {
    await tester.pumpWidget(
      _bar(leftName: '시청', rightName: '을지로', textScale: 1.5),
    );

    expect(_renderedFontSize(tester, '시청'), 21);
  });

  testWidgets('글자 2.0배에서도 넘치지 않는다', (tester) async {
    await tester.pumpWidget(
      _bar(
        leftName: '동대문역사문화공원',
        rightName: '국제금융센터·부산은행',
        width: 320,
        textScale: 2,
      ),
    );

    expect(tester.takeException(), isNull);
    expect(_renderedFontSize(tester, '동대문역사문화공원'), greaterThanOrEqualTo(14));
  });
}
