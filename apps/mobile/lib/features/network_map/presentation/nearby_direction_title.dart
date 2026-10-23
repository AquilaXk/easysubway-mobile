import 'package:flutter/material.dart';

import '../../../accessible_design.dart';

/// 방면 카드 제목("○○ 방면"). 상용 지하철 서비스처럼 노선색이 아닌 검정 강조
/// 글자로 쓴다. 노선색 글자는 3·4·9호선 등에서 흰 바탕 대비가 3:1에 못 미쳤다
/// (에픽 7-48). [showChevron]이면 카드가 그 방면을 여는 버튼이라 꺽쇠를 붙인다.
class NearbyDirectionTitle extends StatelessWidget {
  const NearbyDirectionTitle({
    required this.label,
    this.showChevron = false,
    super.key,
  });

  static const style = TextStyle(
    color: EasySubwayAccessibleColors.contentPrimary,
    fontSize: 16,
    fontWeight: EasySubwayFontWeight.emphasis,
    height: 1.3,
  );

  final String label;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
        ),
        if (showChevron)
          const Icon(
            Icons.chevron_right,
            color: EasySubwayAccessibleColors.contentPrimary,
          ),
      ],
    );
  }
}

/// 실시간 도착 한 줄. 상용 지하철 서비스처럼 행선지는 왼쪽 보조 글자, 남은 시간은
/// 오른쪽 빨강 강조 글자다.
class NearbyArrivalRow extends StatelessWidget {
  const NearbyArrivalRow({
    required this.destination,
    required this.eta,
    super.key,
  });

  static const destinationStyle = TextStyle(
    color: EasySubwayAccessibleColors.contentSecondary,
    fontSize: 15,
    fontWeight: EasySubwayFontWeight.regular,
    height: 1.4,
  );
  static const etaStyle = TextStyle(
    color: EasySubwayAccessibleColors.statusDestructive,
    fontSize: 15,
    fontWeight: EasySubwayFontWeight.emphasis,
    height: 1.4,
  );

  final String destination;
  final String eta;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: NearbyDirectionRowLayout(
        leading: Text(destination, style: destinationStyle),
        trailing: Text(eta, style: etaStyle),
      ),
    );
  }
}

/// 방면 카드 한 줄의 배치. 왼쪽 글자와 오른쪽 남은 시간이 한 줄에 들어가면 양 끝에
/// 두고, 남은 시간이 `[3]번째 전역 (고잔)`처럼 길거나 글자가 커서 넘치면 남은 시간을
/// 다음 줄로 내린다. 글자 중간에서 줄이 끊기지 않게 한다.
class NearbyDirectionRowLayout extends StatelessWidget {
  const NearbyDirectionRowLayout({
    required this.leading,
    required this.trailing,
    super.key,
  });

  final Widget leading;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        children: [leading, trailing],
      ),
    );
  }
}

/// 행선지 대신 들어오는 방향 낱말. 이 낱말은 `행`을 떼지 않는다.
const nearbyDirectionWords = {'상행', '하행'};

/// 방면 카드 행의 행선지. 상용 지하철 서비스처럼 `행` 없이 역 이름만 쓴다(`약수`).
String nearbyDestinationName(String destination) {
  if (nearbyDirectionWords.contains(destination) ||
      !destination.endsWith('행')) {
    return destination;
  }
  return destination.substring(0, destination.length - 1);
}
