import 'package:flutter/material.dart';

import '../../../accessible_design.dart';

/// 주변역 패널의 "○○ 방면" 제목 (오너 스펙 2026-07-16, #2200).
///
/// 역명 부분은 선택 노선색, " 방면" 부분은 primary content 역할색으로 스타일만 분리한다. 라벨
/// 문자열(데이터 포맷)은 조작하지 않는다 — "방면"으로 끝나지 않으면 전체를
/// 노선색으로 그린다. 실시간·시간표 열이 공유하는 단일 스타일이다.
///
/// 노선색 이름은 노선마다 굵기가 달라 보이지 않게 모든 노선에 대비용 굵기(700)를 쓴다.
/// 14pt 굵은 글자는 흰 바탕 위 대비 기준이 4.5:1에서 큰 글자 기준 3:1로 내려가
/// 2·5·6·7·8호선과 공항철도(3.13~4.46)를 구한다. 1호선과 신분당선은 굵게 하지 않아도
/// 4.5:1을 넘는다. 3·4·9호선, 경의중앙선, 수인분당선은 굵게 해도 3:1에 못 미치며
/// 이는 별도로 추적하는 기존 문제다.
class NearbyDirectionTitle extends StatelessWidget {
  const NearbyDirectionTitle({
    required this.label,
    required this.lineColor,
    super.key,
  });

  static const _suffix = '방면';
  static const _suffixColor = EasySubwayAccessibleColors.contentPrimary;
  static const _nameWeight = EasySubwayFontWeight.boldForContrast;
  static const _style = TextStyle(
    fontSize: 14,
    fontWeight: EasySubwayFontWeight.emphasis,
    height: 20 / 14,
  );

  final String label;
  final Color lineColor;

  @override
  Widget build(BuildContext context) {
    final spans = <TextSpan>[];
    if (label.endsWith(_suffix)) {
      final head = label.substring(0, label.length - _suffix.length);
      final name = head.trimRight();
      final gap = head.substring(name.length);
      if (name.isNotEmpty) {
        spans.add(
          TextSpan(
            text: name,
            style: TextStyle(color: lineColor, fontWeight: _nameWeight),
          ),
        );
      }
      spans.add(
        TextSpan(
          text: '$gap$_suffix',
          style: const TextStyle(color: _suffixColor),
        ),
      );
    } else {
      spans.add(
        TextSpan(
          text: label,
          style: TextStyle(color: lineColor, fontWeight: _nameWeight),
        ),
      );
    }
    return Text.rich(
      TextSpan(style: _style, children: spans),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
    );
  }
}

/// 실시간 도착 정보 한 행("○○행" + 도착 안내). 오너 스펙(#2200)의 방면 제목
/// 개편에서도 이 행의 위젯·폰트·색·간격은 무변경으로 유지한다(회귀 고정).
class NearbyArrivalRow extends StatelessWidget {
  const NearbyArrivalRow({
    required this.destination,
    required this.eta,
    this.isDestructive,
    super.key,
  });

  final String destination;
  final String eta;
  final bool? isDestructive;

  @override
  Widget build(BuildContext context) {
    final isSoon = isDestructive ?? (eta == '곧 도착');
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        children: [
          if (destination.isNotEmpty)
            Text(
              destination.endsWith('행') ? destination : '$destination행',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: EasySubwayAccessibleColors.contentPrimary,
                fontSize: 13,
                height: 1.3,
                fontWeight: EasySubwayFontWeight.regular,
              ),
            ),
          if (eta.isNotEmpty)
            Text(
              eta,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isSoon
                    ? EasySubwayAccessibleColors.statusDestructive
                    : EasySubwayAccessibleColors.secondaryText,
                fontSize: 12,
                height: 1.3,
                fontWeight: isSoon
                    ? EasySubwayFontWeight.emphasis
                    : EasySubwayFontWeight.regular,
              ),
            ),
        ],
      ),
    );
  }
}
