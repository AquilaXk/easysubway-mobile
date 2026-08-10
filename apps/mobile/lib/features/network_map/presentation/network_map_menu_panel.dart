import 'package:flutter/material.dart';

import '../../../accessible_design.dart';

class NetworkMapMenuPanel extends StatelessWidget {
  const NetworkMapMenuPanel({
    required this.bottomBanner,
    required this.onOpenStationSearch,
    required this.onOpenSavedItems,
    required this.onOpenTrainSearch,
    required this.onOpenServiceNotices,
    required this.onOpenSettings,
    super.key,
  });

  final Widget bottomBanner;
  final VoidCallback onOpenStationSearch;
  final VoidCallback? onOpenSavedItems;
  final VoidCallback? onOpenTrainSearch;
  final VoidCallback? onOpenServiceNotices;
  final VoidCallback? onOpenSettings;

  void _runAction(BuildContext context, VoidCallback action) {
    Navigator.of(context).pop();
    action();
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Material(
        key: const Key('networkMapMenuPanel'),
        elevation: 0,
        color: EasySubwayAccessibleColors.surfaceDefault,
        child: SizedBox(
          width: 256,
          height: double.infinity,
          child: Column(
            children: [
              Expanded(
                child: SafeArea(
                  bottom: false,
                  child: ListView(
                    padding: EdgeInsets.zero,
                    // 메뉴 헤더 mapChrome 짧은 드롭이 아래 타일 위로 보이게.
                    clipBehavior: Clip.none,
                    children: [
                      const _NetworkMapMenuHeader(),
                      const EasySubwayHeaderDivider.mapChrome(
                        key: Key('networkMapMenuHeaderDivider'),
                      ),
                      _NetworkMapMenuTile(
                        key: const Key('networkMapMenuStationSearchButton'),
                        icon: Icons.search,
                        label: '역 검색',
                        onTap: () => _runAction(context, onOpenStationSearch),
                      ),
                      // #1933 요구 3: 별도 길찾기 폼 페이지를 없앴다. 길찾기 진입은
                      // 노선도 역 탭(팝오버 출발/도착)·상단바 변신으로만 하므로,
                      // 폼으로 보내던 좌측 메뉴 "길찾기" 항목을 제거한다.
                      if (onOpenTrainSearch != null)
                        _NetworkMapMenuTile(
                          key: const Key('networkMapMenuTrainSearchButton'),
                          icon: Icons.train_outlined,
                          label: '기차 검색',
                          onTap: () => _runAction(context, onOpenTrainSearch!),
                        ),
                      if (onOpenSavedItems != null ||
                          onOpenSettings != null) ...[
                        const Divider(
                          height: 1,
                          color: EasySubwayAccessibleColors.line,
                        ),
                        if (onOpenSavedItems != null)
                          _NetworkMapMenuTile(
                            key: const Key('networkMapMenuSavedButton'),
                            icon: Icons.star_border_rounded,
                            label: '즐겨찾기',
                            onTap: () => _runAction(context, onOpenSavedItems!),
                          ),
                        if (onOpenSettings != null)
                          _NetworkMapMenuTile(
                            key: const Key('networkMapMenuSettingsButton'),
                            icon: Icons.settings_outlined,
                            label: '설정',
                            onTap: () => _runAction(context, onOpenSettings!),
                          ),
                      ],
                      if (onOpenServiceNotices != null) ...[
                        const Divider(
                          height: 1,
                          color: EasySubwayAccessibleColors.line,
                        ),
                        _NetworkMapMenuTile(
                          key: const Key('networkMapMenuServiceNoticesButton'),
                          icon: Icons.campaign_outlined,
                          label: '공지사항',
                          onTap: () =>
                              _runAction(context, onOpenServiceNotices!),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              // 패널 최하단 고정 광고 슬롯(항목 스크롤과 분리, release는 collapse).
              SafeArea(top: false, child: bottomBanner),
            ],
          ),
        ),
      ),
    );
  }
}

class _NetworkMapMenuHeader extends StatelessWidget {
  const _NetworkMapMenuHeader();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: EasySubwayAccessibleColors.topBarSurface,
      child: SizedBox(
        key: Key('networkMapMenuHeader'),
        height: easySubwayTopBarContentHeight,
        child: Padding(
          padding: EdgeInsets.only(left: 24, right: 20),
          child: Row(
            children: [
              Image(
                key: Key('networkMapMenuAppIcon'),
                image: AssetImage('assets/branding/app_icon/app_icon.png'),
                width: 44,
                height: 44,
                excludeFromSemantics: true,
              ),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  '쉬운 지하철',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: EasySubwayAccessibleColors.listRowText,
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NetworkMapMenuTile extends StatelessWidget {
  const _NetworkMapMenuTile({
    required this.icon,
    required this.label,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      onTap: onTap,
      child: ExcludeSemantics(
        child: InkWell(
          onTap: onTap,
          splashFactory: NoSplash.splashFactory,
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          child: SizedBox(
            height: 52,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  Icon(
                    icon,
                    size: 22,
                    color: EasySubwayAccessibleColors.mutedText,
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: EasySubwayAccessibleColors.listRowText,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right,
                    size: 20,
                    color: EasySubwayAccessibleColors.disclosure,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
