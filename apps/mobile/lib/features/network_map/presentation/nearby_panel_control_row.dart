import 'package:flutter/material.dart';

import '../../../accessible_design.dart';
import '../../../design_tokens.dart';

/// 노선 바 아래 줄. 상용 지하철 서비스처럼 왼쪽에 실시간·시간표 토글, 오른쪽에
/// 실시간을 받은 시각과 새로고침을 둔다. 시각([receivedAtLabel])과
/// 새로고침([onRefresh])은 실시간일 때만 넘어온다.
class NearbyPanelControlRow extends StatelessWidget {
  const NearbyPanelControlRow({
    required this.toggle,
    this.receivedAtLabel,
    this.onRefresh,
    super.key,
  });

  final Widget toggle;
  final ({String visible, String spoken})? receivedAtLabel;
  final VoidCallback? onRefresh;

  static const _timeStyle = TextStyle(
    color: EasySubwayAccessibleColors.contentSecondary,
    fontSize: 15,
    fontWeight: EasySubwayFontWeight.regular,
  );

  @override
  Widget build(BuildContext context) {
    final time = receivedAtLabel;
    final refresh = onRefresh;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: EasySubwaySpacing.xl),
      child: Row(
        children: [
          toggle,
          const Spacer(),
          if (time != null)
            Flexible(
              child: Semantics(
                label: '${time.spoken} 기준',
                excludeSemantics: true,
                child: Text(
                  time.visible,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _timeStyle,
                ),
              ),
            ),
          if (refresh != null)
            IconButton.outlined(
              tooltip: '새로고침',
              onPressed: refresh,
              icon: const Icon(
                Icons.refresh,
                color: EasySubwayAccessibleColors.contentSecondary,
              ),
            ),
        ],
      ),
    );
  }
}
