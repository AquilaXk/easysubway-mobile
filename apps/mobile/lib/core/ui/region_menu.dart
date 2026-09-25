import 'dart:async';

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
            child: EasySubwayRegionMenuPanel(
              availableRegions: available,
              selectedRegion: selectedRegion,
              onRegionSelected: onRegionSelected,
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
    if (region.id == selectedRegion || region.label == selectedRegion) {
      return true;
    }
    final cleanSelected = selectedRegion.endsWith('권')
        ? selectedRegion.substring(0, selectedRegion.length - 1)
        : selectedRegion;
    final cleanLabel = region.label.endsWith('권')
        ? region.label.substring(0, region.label.length - 1)
        : region.label;
    final cleanId = region.id.endsWith('권')
        ? region.id.substring(0, region.id.length - 1)
        : region.id;
    return cleanSelected == cleanLabel || cleanSelected == cleanId;
  }

  @override
  Widget build(BuildContext context) {
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
            child: SizedBox(
              height: 48,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
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
      child: SizedBox(
        width: 124,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: tiles,
          ),
        ),
      ),
    );
  }
}
