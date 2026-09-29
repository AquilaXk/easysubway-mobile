import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../accessible_design.dart';

/// 노선도·역 검색 상단바가 공유하는 지역 메뉴 항목.
class EasySubwayRegionMenuItem {
  const EasySubwayRegionMenuItem({required this.id, required this.label});

  /// 원본 지역 키(예: `부산권`, `수도권`).
  final String id;

  /// UI 표시명(예: `부산`, `수도권`).
  final String label;
}

/// 패널이 화면 오른쪽·아래 가장자리와 띄우는 최소 여백.
const _regionMenuScreenEdgeMargin = 16.0;

/// 트리거 버튼 바로 아래·화면 좌측 벽에 밀착하여 콤팩트한 지역 드롭다운 메뉴를 연다.
Future<void> showEasySubwayRegionMenu({
  required BuildContext triggerContext,
  required List<EasySubwayRegionMenuItem> regions,
  required String selectedRegion,
  required ValueChanged<String> onRegionSelected,
}) async {
  final available = regions.isEmpty
      ? const [
          EasySubwayRegionMenuItem(id: '수도권', label: '수도권'),
          EasySubwayRegionMenuItem(id: '부산', label: '부산'),
          EasySubwayRegionMenuItem(id: '대구', label: '대구'),
          EasySubwayRegionMenuItem(id: '광주', label: '광주'),
          EasySubwayRegionMenuItem(id: '대전', label: '대전'),
        ]
      : regions;

  final RenderBox? triggerBox = triggerContext.findRenderObject() as RenderBox?;
  final RenderBox? overlayBox =
      Overlay.of(triggerContext).context.findRenderObject() as RenderBox?;
  if (triggerBox == null || overlayBox == null) {
    return;
  }
  final bottomLeft = triggerBox.localToGlobal(
    triggerBox.size.bottomLeft(Offset.zero),
    ancestor: overlayBox,
  );

  await showGeneralDialog<void>(
    context: triggerContext,
    barrierDismissible: true,
    barrierLabel: '지역 메뉴 닫기',
    barrierColor: const Color(0x99000000),
    pageBuilder: (context, animation, secondaryAnimation) {
      // #404: 큰 글자에서 행이 자라도 패널은 트리거 아래 남은 화면 높이(하단
      // 시스템 영역과 여백 16 제외)를 넘지 않고, 넘치는 행은 패널 안에서 스크롤한다.
      final maxPanelHeight =
          MediaQuery.sizeOf(context).height -
          bottomLeft.dy -
          MediaQuery.paddingOf(context).bottom -
          _regionMenuScreenEdgeMargin;
      return Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).pop(),
              child: const SizedBox.expand(),
            ),
          ),
          Positioned(
            top: bottomLeft.dy,
            left: 0,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxPanelHeight),
              child: EasySubwayRegionMenuPanel(
                availableRegions: available,
                selectedRegion: selectedRegion,
                onRegionSelected: onRegionSelected,
              ),
            ),
          ),
        ],
      );
    },
  );
}

class EasySubwayRegionMenuPanel extends StatelessWidget {
  const EasySubwayRegionMenuPanel({
    required this.availableRegions,
    required this.selectedRegion,
    required this.onRegionSelected,
    super.key,
  });

  final List<EasySubwayRegionMenuItem> availableRegions;
  final String selectedRegion;
  final ValueChanged<String> onRegionSelected;

  bool _isSelected(EasySubwayRegionMenuItem region) {
    return region.id == selectedRegion || region.label == selectedRegion;
  }

  @override
  Widget build(BuildContext context) {
    // #404: 패널 폭은 가장 긴 권역 행(권역명 한 줄 + 체크 아이콘 + 좌우 패딩)의
    // 실제 폭에 맞춰 기본 124에서 자란다. 좌측 벽에 붙은 패널이 화면 밖으로
    // 나가지 않도록 화면 폭 - 16이 상한이고, 창이 좁아 상한이 124보다 작으면
    // 상한이 우선한다.
    const basePanelWidth = 124.0;
    final maxPanelWidth =
        MediaQuery.sizeOf(context).width - _regionMenuScreenEdgeMargin;
    final tiles = <Widget>[];
    for (final region in availableRegions) {
      final isSelected = _isSelected(region);

      tiles.add(
        Material(
          color: Colors.transparent,
          elevation: 0,
          child: InkWell(
            key: ValueKey('networkMapRegionMenuRow_${region.id}'),
            borderRadius: const BorderRadius.only(
              topRight: Radius.circular(6),
              bottomRight: Radius.circular(6),
            ),
            onTap: () {
              unawaited(HapticFeedback.lightImpact());
              Navigator.of(context).pop();
              onRegionSelected(region.id);
            },
            // #404: 고정 높이는 큰 글자에서 줄바꿈된 권역명을 잘랐다. 최소 터치
            // 타깃만 보장하고 내용에 맞춰 자란다. 텍스트 목록 행이지만 승인된 기본
            // 레이아웃(행 48)을 지키려고 EasySubwayTouchTarget.general(56) 대신
            // Material 최소 상호작용 크기(48)를 쓴다. 상하 8 패딩은 기본 배율의
            // 글자 줄(32 이하)에서 행 높이를 정확히 48로 유지한다.
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: kMinInteractiveDimension,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        region.label,
                        style: TextStyle(
                          color: isSelected
                              ? EasySubwayAccessibleColors.interactionPrimary
                              : EasySubwayAccessibleColors.listRowText,
                          fontSize: 16,
                          fontWeight: isSelected
                              ? FontWeight.w700
                              : FontWeight.w600,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ),
                    if (isSelected)
                      const Icon(
                        Icons.check_rounded,
                        key: Key('regionSelectedCheckmark'),
                        color: EasySubwayAccessibleColors.interactionPrimary,
                        size: 20,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Material(
      color: EasySubwayAccessibleColors.surfaceDefault,
      elevation: 0,
      shape: const RoundedRectangleBorder(
        side: BorderSide(
          color: EasySubwayAccessibleColors.borderSubtle,
          width: 1,
        ),
        borderRadius: BorderRadius.only(
          topLeft: Radius.zero,
          bottomLeft: Radius.zero,
          topRight: Radius.circular(8),
          bottomRight: Radius.circular(8),
        ),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: math.min(basePanelWidth, maxPanelWidth),
          maxWidth: maxPanelWidth,
        ),
        child: IntrinsicWidth(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: tiles,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
