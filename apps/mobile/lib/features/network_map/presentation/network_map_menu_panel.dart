import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../accessible_design.dart';

class NetworkMapMenuPanel extends StatefulWidget {
  const NetworkMapMenuPanel({
    this.onOpenSavedItems,
    this.onOpenTrainSearch,
    this.onOpenServiceNotices,
    this.onOpenSettings,
    this.onOpenStationSearch,
    this.bottomBanner,
    super.key,
  });

  final VoidCallback? onOpenSavedItems;
  final VoidCallback? onOpenTrainSearch;
  final VoidCallback? onOpenServiceNotices;
  final VoidCallback? onOpenSettings;

  /// 상단바 검색으로 일원화되어 메뉴 패널에서는 더 이상 표시되지 않는다.
  final VoidCallback? onOpenStationSearch;

  /// 메인 화면 하단 배너와의 중복 방지로 메뉴 패널에서는 제거되었다.
  final Widget? bottomBanner;

  @override
  State<NetworkMapMenuPanel> createState() => _NetworkMapMenuPanelState();
}

class _NetworkMapMenuPanelState extends State<NetworkMapMenuPanel>
    with SingleTickerProviderStateMixin {
  double _dragOffset = 0.0;
  AnimationController? _settleController;

  @override
  void dispose() {
    _settleController?.dispose();
    super.dispose();
  }

  void _runAction(BuildContext context, VoidCallback action) {
    Navigator.of(context).pop();
    action();
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    final delta = details.primaryDelta ?? 0.0;
    if (delta > 0 || _dragOffset > 0) {
      setState(() {
        _dragOffset = math.max(0.0, _dragOffset + delta);
      });
    }
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0.0;
    if (_dragOffset > 80.0 || velocity > 200.0) {
      Navigator.of(context).pop();
    } else if (_dragOffset > 0) {
      _settleController?.dispose();
      final controller = AnimationController(
        duration: const Duration(milliseconds: 160),
        vsync: this,
      );
      final animation = Tween<double>(begin: _dragOffset, end: 0.0).animate(
        CurvedAnimation(parent: controller, curve: Curves.easeOutCubic),
      );
      animation.addListener(() {
        setState(() {
          _dragOffset = animation.value;
        });
      });
      _settleController = controller;
      unawaited(controller.forward());
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragUpdate: _onHorizontalDragUpdate,
      onHorizontalDragEnd: _onHorizontalDragEnd,
      child: Transform.translate(
        offset: Offset(_dragOffset, 0),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            border: Border(
              left: BorderSide(
                color: EasySubwayAccessibleColors.line,
                width: 1,
              ),
            ),
            boxShadow: [
              BoxShadow(
                color: EasySubwayAccessibleColors.cardShadow,
                blurRadius: 24,
                spreadRadius: 2,
                offset: Offset(-8, 0),
              ),
              BoxShadow(
                color: EasySubwayAccessibleColors.cardShadow,
                blurRadius: 10,
                offset: Offset(-2, 0),
              ),
            ],
          ),
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
                      child: SingleChildScrollView(
                        clipBehavior: Clip.none,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const _NetworkMapMenuHeader(),
                            const EasySubwayHeaderDivider.mapChrome(
                              key: Key('networkMapMenuHeaderDivider'),
                            ),
                            if (widget.onOpenTrainSearch != null)
                              _NetworkMapMenuTile(
                                key: const Key(
                                  'networkMapMenuTrainSearchButton',
                                ),
                                icon: Icons.train_outlined,
                                label: '기차 검색',
                                onTap: () => _runAction(
                                  context,
                                  widget.onOpenTrainSearch!,
                                ),
                              ),
                            if (widget.onOpenSavedItems != null ||
                                widget.onOpenSettings != null) ...[
                              const Divider(
                                height: 1,
                                color: EasySubwayAccessibleColors.line,
                              ),
                              if (widget.onOpenSavedItems != null)
                                _NetworkMapMenuTile(
                                  key: const Key('networkMapMenuSavedButton'),
                                  icon: Icons.star_border_rounded,
                                  label: '즐겨찾기',
                                  onTap: () => _runAction(
                                    context,
                                    widget.onOpenSavedItems!,
                                  ),
                                ),
                              if (widget.onOpenSettings != null)
                                _NetworkMapMenuTile(
                                  key: const Key(
                                    'networkMapMenuSettingsButton',
                                  ),
                                  icon: Icons.settings_outlined,
                                  label: '설정',
                                  onTap: () => _runAction(
                                    context,
                                    widget.onOpenSettings!,
                                  ),
                                ),
                            ],
                            if (widget.onOpenServiceNotices != null) ...[
                              const Divider(
                                height: 1,
                                color: EasySubwayAccessibleColors.line,
                              ),
                              _NetworkMapMenuTile(
                                key: const Key(
                                  'networkMapMenuServiceNoticesButton',
                                ),
                                icon: Icons.campaign_outlined,
                                label: '공지사항',
                                onTap: () => _runAction(
                                  context,
                                  widget.onOpenServiceNotices!,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                  const _NetworkMapMenuFooter(),
                ],
              ),
            ),
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
    return ColoredBox(
      color: EasySubwayAccessibleColors.topBarSurface,
      child: Container(
        key: const Key('networkMapMenuHeader'),
        padding: const EdgeInsets.fromLTRB(16, 16, 14, 16),
        child: Row(
          children: [
            const Image(
              key: Key('networkMapMenuAppIcon'),
              image: ResizeImage(
                AssetImage('assets/branding/app_icon/app_icon.png'),
                width: 88,
                height: 88,
              ),
              width: 44,
              height: 44,
              excludeFromSemantics: true,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Flexible(
                        child: Text(
                          '쉬운 지하철',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: EasySubwayAccessibleColors.listRowText,
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: EasySubwayAccessibleColors.surfaceBrand,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: EasySubwayAccessibleColors.borderSubtle,
                            width: 0.8,
                          ),
                        ),
                        child: const Text(
                          'v4.0.0',
                          style: TextStyle(
                            color: EasySubwayAccessibleColors.contentPrimary,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  const Text(
                    '모두를 위한 쉬운 지하철 길찾기',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: EasySubwayAccessibleColors.mutedText,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
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
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
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

class _NetworkMapMenuFooter extends StatelessWidget {
  const _NetworkMapMenuFooter();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        key: const Key('networkMapMenuFooter'),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Divider(height: 1, color: EasySubwayAccessibleColors.line),
            const SizedBox(height: 14),
            const Row(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 14,
                  color: EasySubwayAccessibleColors.mutedText,
                ),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '쉬운 지하철 v4.0.0',
                    style: TextStyle(
                      color: EasySubwayAccessibleColors.mutedText,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '공공데이터포털 및 서울교통공사 연동 데이터\n오픈소스 라이선스 및 교통약자 이동지원',
              style: TextStyle(
                color: EasySubwayAccessibleColors.mutedText.withValues(
                  alpha: 0.8,
                ),
                fontSize: 11,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
