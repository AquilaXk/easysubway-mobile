import 'package:flutter/material.dart';

import '../../../accessible_design.dart';
import '../../../search_field.dart';

class NetworkMapBottomAdBanner extends StatelessWidget {
  const NetworkMapBottomAdBanner({required this.slot, super.key});

  final Widget slot;

  @override
  Widget build(BuildContext context) {
    return SafeArea(top: false, child: slot);
  }
}

class NetworkMapLookupToast extends StatelessWidget {
  const NetworkMapLookupToast({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.center,
      child: Material(
        key: const Key('networkMapNearbyLookupMessage'),
        color: const Color(0xE62F3437),
        elevation: 0,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          child: Text(
            message,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: EasySubwayAccessibleColors.interactionOnPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w800,
              height: 1.2,
            ),
          ),
        ),
      ),
    );
  }
}

class NetworkMapCurrentLocationButton extends StatelessWidget {
  const NetworkMapCurrentLocationButton({required this.onTap, super.key});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '현재 위치에서 가장 가까운 역 찾기',
      onTap: onTap,
      child: ExcludeSemantics(
        child: Material(
          key: const Key('nearbyStationButton'),
          color: EasySubwayAccessibleColors.surfaceDefault,
          elevation: 0,
          shape: const CircleBorder(
            side: BorderSide(
              color: EasySubwayAccessibleColors.borderSubtle,
              width: 1,
            ),
          ),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: const SizedBox(
              width: 56,
              height: 56,
              child: Icon(
                Icons.my_location,
                size: 27,
                color: EasySubwayAccessibleColors.contentSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class NetworkMapSearchEntryButton extends StatelessWidget {
  const NetworkMapSearchEntryButton({required this.onTap, super.key});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '지하철역 검색',
      onTap: onTap,
      child: ExcludeSemantics(
        // 입력 필드처럼 보이되 탭 시 어떤 ink 하이라이트/사각형도 뜨지 않게
        // GestureDetector로 처리한다(InkWell의 transparent color로는 상위
        // Material에 사각형이 남을 수 있음). 탭하면 조용히 검색 화면으로 전환. #1933
        child: GestureDetector(
          key: const Key('stationSearchButton'),
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 72;
              return SizedBox(
                height: EasySubwayTouchTarget.general,
                child: Center(
                  child: Container(
                    key: const Key('heroStationSearchButton'),
                    height: easySubwaySearchFieldVisualHeight,
                    decoration: BoxDecoration(
                      color: EasySubwayAccessibleColors.searchFieldSurface,
                      border: Border.all(
                        color: easySubwaySearchFieldBorderColor,
                        width: easySubwaySearchFieldBorderWidth,
                      ),
                      borderRadius: easySubwaySearchFieldRadius,
                    ),
                    padding: EdgeInsets.symmetric(
                      horizontal: compact
                          ? 0
                          : easySubwaySearchFieldHorizontalPadding,
                    ),
                    child: compact
                        ? const SizedBox.shrink()
                        : const Row(
                            children: [
                              Icon(
                                Icons.search,
                                size: easySubwaySearchFieldIconSize,
                                color: EasySubwayAccessibleColors.iconMuted,
                              ),
                              SizedBox(width: easySubwaySearchFieldIconGap),
                              Expanded(
                                child: Text(
                                  '지하철역 검색',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: easySubwaySearchFieldHintStyle,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
