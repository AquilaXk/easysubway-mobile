import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../accessible_design.dart';

/// 표준 광고 배너 슬롯 높이(dp).
///
/// AdMob 앵커 배너(320x50) 또는 카카오 AdFit(320x50/320x100)의 표준 컨테이너
/// 규격에 맞춰 상하 패딩을 포함한 60dp를 기본값으로 둔다.
const double kAdBannerSlotStandardHeight = 60.0;

/// 앱 공용 하단 광고 배너 슬롯.
///
/// 오너 계약(#1933 요구 5):
/// - 노선도 메인 화면 하단: 고정 배치(바텀 시트·패널 뒤로 밀리지 않음).
/// - 좌측 메뉴 서랍(Drawer) 하단: 메뉴 스크롤과 무관하게 하단 고정.
/// - release 빌드: 실광고 SDK가 아직 연결되지 않았으면([child] == null)
///   슬롯을 완전히 숨겨(collapse) 여백이 낭비되지 않게 한다.
/// - debug/internal 빌드: 실광고 미연동 시 실무적인 서비스 안내 하우스 배너를
///   제공하여 화면 균형과 레이아웃 점유를 유지한다.
class AdBannerSlot extends StatelessWidget {
  const AdBannerSlot({
    required this.slotKey,
    this.height = kAdBannerSlotStandardHeight,
    this.showTopDivider = true,
    this.child,
    super.key,
  });

  final Key slotKey;
  final double height;
  final bool showTopDivider;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final ad = child;
    // 실광고가 없는 상태에서 release면 슬롯 자체를 숨긴다(collapse).
    if (ad == null && kReleaseMode) {
      return const SizedBox.shrink();
    }
    return Semantics(
      label: '안내 배너',
      child: Container(
        key: slotKey,
        height: height,
        decoration: BoxDecoration(
          color: EasySubwayAccessibleColors.surface,
          border: showTopDivider
              ? const Border(
                  top: BorderSide(color: EasySubwayAccessibleColors.line),
                )
              : null,
        ),
        child:
            ad ?? const ExcludeSemantics(child: _AdBannerSlotDefaultBanner()),
      ),
    );
  }
}

/// 실광고 미연동 시 노출되는 실무적 기본 안내 배너.
class _AdBannerSlotDefaultBanner extends StatelessWidget {
  const _AdBannerSlotDefaultBanner();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: EasySubwayAccessibleColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.subway,
              color: EasySubwayAccessibleColors.primary,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '쉬운 지하철과 함께하는 편안한 이동',
                    style: TextStyle(
                      color: EasySubwayAccessibleColors.contentPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: 2),
                  Text(
                    '엘리베이터 및 실시간 도착 정보를 확인하세요',
                    style: TextStyle(
                      color: EasySubwayAccessibleColors.contentMuted,
                      fontSize: 11,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
