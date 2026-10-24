import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter/services.dart';

import '../../../accessible_design.dart';
import '../../../search_field.dart';
import '../../route_draft/domain/route_draft.dart';
import '../domain/network_map_models.dart';
import '../domain/route_map_min_scale.dart';
import '../../../core/ui/route_role_dot.dart';
import '../../../core/ui/region_menu.dart';
import 'network_map_overlay_inset.dart';

/// 테스트 전용: [NetworkMapChrome]가 build될 때마다 증가한다. 검색 중 키
/// 입력이 지도 chrome 전체를 재빌드하지 않는지 검증할 때만 읽는다.
@visibleForTesting
int debugNetworkMapChromeBuildCount = 0;

/// 경로 입력 칸 한 줄의 높이. 시각 박스(40dp)는 이 줄 안에서 가운데에 그려지고,
/// 버튼·입력 영역은 줄 높이만큼 눌려 최소 터치 영역(48dp)을 채운다.
const _draftRowHeight = EasySubwayTouchTarget.iconOnly;

/// 역할 점 좌우 여백.
const _roleDotInset = 12.0;

class NetworkMapChrome extends StatefulWidget {
  const NetworkMapChrome({
    required this.topBar,
    required this.disruptionBanner,
    required this.searchMode,
    required this.searchBody,
    required this.nearbyPanelVisible,
    required this.nearbyPanelExpanded,
    required this.nearbyPanel,
    required this.nearbyLookupMessage,
    required this.onCurrentLocationTap,
    required this.child,
    super.key,
  });

  final Widget topBar;
  final Widget? disruptionBanner;
  final bool searchMode;
  final Widget? searchBody;
  final bool nearbyPanelVisible;
  final bool nearbyPanelExpanded;
  final Widget nearbyPanel;
  final String? nearbyLookupMessage;
  final VoidCallback onCurrentLocationTap;
  final Widget child;

  @override
  State<NetworkMapChrome> createState() => _NetworkMapChromeState();
}

class _NetworkMapChromeState extends State<NetworkMapChrome> {
  /// 지도 위를 덮는 상단바 + 알림 바 묶음의 측정 높이. 측정 전에는 null이다.
  ///
  /// 측정값은 레이아웃이 끝난 뒤 setState로 반영되므로 지도는 한 프레임 늦게 알게
  /// 된다. 같은 프레임에 반영하려면 지도 build가 레이아웃 결과에 의존해야 해서
  /// 지도 전체를 레이아웃 단계로 옮겨야 한다. 핀이 가려지는 프레임은 사용자가 핀을
  /// 지정한 직후(또는 오버레이가 커진 직후)의 한두 프레임뿐이라 이 지연은 받아들인다.
  /// 첫 측정 전에는 지도가 초기 카메라를 정하지 않고 기다린다(측정 전 상태를 그대로 전달).
  double? _overlayHeight;

  void _onOverlayHeight(double height) {
    if (mounted && height != _overlayHeight) {
      setState(() => _overlayHeight = height);
    }
  }

  // design_tokens의 간격(lg 16, sm 8)과 같은 값. 이 파일은 경로 역할색을 품은
  // design_tokens를 직접 가져오지 않는다(network_map_chrome_controls_test).
  static const _floatingControlGap = 16.0;
  static const _toastGap = 8.0;

  /// 접힌 시트 위에 쌓는 안내 토스트와 현재 위치 버튼.
  List<Widget> _floatingControls() {
    final message = widget.nearbyLookupMessage;
    return [
      if (message != null) ...[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: NetworkMapLookupToast(message: message),
        ),
        const SizedBox(height: _toastGap),
      ],
      Align(
        alignment: Alignment.centerRight,
        child: Padding(
          padding: const EdgeInsets.only(right: 20),
          child: NetworkMapCurrentLocationButton(
            onTap: widget.onCurrentLocationTap,
          ),
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    debugNetworkMapChromeBuildCount++;
    final topPadding = MediaQuery.paddingOf(context).top;
    final inSearchMode = widget.searchMode && widget.searchBody != null;
    // 지도를 상단바 아래로 약간 겹쳐 그리면, 구분선·짧은 드롭이 흰 배경이 아니라
    // 노선 색 위에 앉아 카카오처럼 닿는 부위가 하얗게 끊기지 않는다.
    const mapUnderTopBarPx = 10.0;
    // 검색 모드는 흰 상단바와 옅은 띠 바로 아래에서 결과 목록이 시작한다.
    final mapTop = inSearchMode
        ? topPadding +
              easySubwayTopBarContentHeight +
              easySubwaySearchBarSeparatorHeight
        : topPadding + easySubwayTopBarContentHeight - mapUnderTopBarPx;
    // 지도는 mapTop에서 시작하지만 오버레이는 측정 높이만큼 그 위를 덮는다. 그 차이가
    // 지도 본문에서 가려지는 높이다.
    final overlayHeight = _overlayHeight;
    final mapInset = overlayHeight == null
        ? const NetworkMapTopInsetUnmeasured()
        : NetworkMapTopInsetMeasured(math.max(0.0, overlayHeight - mapTop));
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          top: mapTop,
          // ClipRect를 쓰면 가장자리 draft 핀의 soft drop·✕가 잘린다.
          child: inSearchMode
              ? widget.searchBody!
              : NetworkMapObscuredTop(inset: mapInset, child: widget.child),
        ),
        // 상단바는 경로 입력 칸 수에 따라 1~3줄로 높이가 달라진다. 알림 바는 고정
        // 오프셋 대신 같은 열에서 상단바 실제 높이 바로 아래에 놓아 입력 칸을 가리지 않는다.
        Positioned(
          left: 0,
          top: 0,
          right: 0,
          child: NetworkMapMeasuredHeight(
            onHeight: _onOverlayHeight,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                widget.topBar,
                if (widget.disruptionBanner != null && !inSearchMode)
                  widget.disruptionBanner!,
              ],
            ),
          ),
        ),
        if (widget.nearbyPanelVisible && !inSearchMode)
          Positioned(
            // 확장 시 상단 검색바까지 덮어 반쯤 열린 슬롭 시트를 막는다.
            left: 0,
            right: 0,
            top: widget.nearbyPanelExpanded ? 0 : null,
            bottom: 0,
            // 접힌 시트는 높이가 방면 카드·글자 배율에 따라 달라, 현재 위치 버튼과
            // 안내 토스트를 고정 오프셋 대신 같은 열에서 시트 바로 위에 쌓는다.
            child: widget.nearbyPanelExpanded
                ? widget.nearbyPanel
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ..._floatingControls(),
                      const SizedBox(height: _floatingControlGap),
                      widget.nearbyPanel,
                    ],
                  ),
          ),
        if (!widget.nearbyPanelVisible &&
            widget.nearbyLookupMessage != null &&
            !inSearchMode)
          Positioned(
            left: 24,
            right: 24,
            bottom: 132,
            child: NetworkMapLookupToast(message: widget.nearbyLookupMessage!),
          ),
        if (!widget.nearbyPanelVisible && !inSearchMode)
          Positioned(
            right: 20,
            bottom: 32,
            child: NetworkMapCurrentLocationButton(
              onTap: widget.onCurrentLocationTap,
            ),
          ),
      ],
    );
  }
}

class NetworkMapTopBar extends StatelessWidget {
  const NetworkMapTopBar({
    required this.regions,
    required this.selectedRegion,
    required this.onMenuTap,
    required this.onSearchTap,
    this.searchMode = false,
    this.onSearchBack,
    this.searchQueryController,
    this.searchFocusNode,
    this.onSearchSubmitted,
    this.onSearchClear,
    required this.onRegionSelected,
    required this.routeDraftListenable,
    required this.routeDraft,
    required this.isWaypointRowVisible,
    required this.onClearDraft,
    required this.onOpenWaypointSlot,
    required this.onClearOrigin,
    required this.onClearDestination,
    required this.onClearWaypoint,
    required this.onReorderDraft,
    required this.roleColorForSlot,
    this.onPickOrigin,
    this.onPickDestination,
    this.onPickWaypoint,
    super.key,
  });

  final List<NetworkMapRegion> regions;
  final String selectedRegion;
  final VoidCallback onMenuTap;
  final VoidCallback onSearchTap;
  final bool searchMode;
  final VoidCallback? onSearchBack;
  final TextEditingController? searchQueryController;
  final FocusNode? searchFocusNode;
  final ValueChanged<String>? onSearchSubmitted;
  final VoidCallback? onSearchClear;
  final ValueChanged<String> onRegionSelected;
  final Listenable routeDraftListenable;
  final RouteDraft Function() routeDraft;
  final bool Function() isWaypointRowVisible;
  final VoidCallback onClearDraft;
  final VoidCallback onOpenWaypointSlot;
  final VoidCallback onClearOrigin;
  final VoidCallback onClearDestination;
  final VoidCallback onClearWaypoint;
  final void Function(RouteDraftSlot from, RouteDraftSlot to) onReorderDraft;
  final Color Function(RouteDraftSlot slot) roleColorForSlot;
  final VoidCallback? onPickOrigin;
  final VoidCallback? onPickDestination;
  final VoidCallback? onPickWaypoint;

  @override
  Widget build(BuildContext context) {
    if (searchMode) {
      return AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.dark,
        child: Material(
          key: const Key('networkMapTopBar'),
          color: EasySubwayAccessibleColors.surface,
          elevation: 0,
          child: EasySubwaySearchBar(
            field: EasySubwaySearchField(
              controller: searchQueryController,
              focusNode: searchFocusNode,
              hintText: '역 이름을 입력해 주세요',
              autofocus: true,
              onSubmitted: onSearchSubmitted,
              onClear: onSearchClear,
              onBack: onSearchBack,
              backButtonKey: const Key('networkMapSearchBackButton'),
            ),
            contentHeight: easySubwayTopBarContentHeight,
            separatorKey: const Key('networkMapTopBarDivider'),
          ),
        ),
      );
    }
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Material(
        key: const Key('networkMapTopBar'),
        color: EasySubwayAccessibleColors.primary,
        elevation: 0,
        // mapChrome 짧은 드롭이 지도 위로 그려지도록 클립하지 않는다.
        clipBehavior: Clip.none,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            SafeArea(
              bottom: false,
              // #1933 요구 2: draft가 비면 검색바, 하나라도 차면 출발/도착 2줄 입력으로
              // 상단바 자체가 변신한다. 별도 카드를 아래에 띄우지 않는다.
              child: ListenableBuilder(
                listenable: routeDraftListenable,
                builder: (context, _) {
                  final draft = routeDraft();
                  if (draft.isEmpty) {
                    return _buildSearchRow(context);
                  }
                  return NetworkMapTopBarRouteDraft(
                    key: const Key('networkMapRouteDraftOverlay'),
                    draft: draft,
                    showWaypointRow: isWaypointRowVisible(),
                    regionLabel: routeMapDisplayRegionName(selectedRegion),
                    onClearDraft: onClearDraft,
                    onOpenWaypointSlot: onOpenWaypointSlot,
                    onClearOrigin: onClearOrigin,
                    onClearDestination: onClearDestination,
                    onClearWaypoint: onClearWaypoint,
                    onReorderDraft: onReorderDraft,
                    onPickOrigin: onPickOrigin,
                    onPickDestination: onPickDestination,
                    onPickWaypoint: onPickWaypoint,
                    roleColorForSlot: roleColorForSlot,
                  );
                },
              ),
            ),
            const Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: EasySubwayHeaderDivider.mapChrome(
                key: Key('networkMapTopBarDivider'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchRow(BuildContext context) {
    final currentRegion = routeMapDisplayRegionName(selectedRegion);
    final availableRegions = regions.isEmpty
        ? const [NetworkMapRegion(name: '수도권')]
        : regions;
    return SizedBox(
      height: easySubwayTopBarContentHeight,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
        child: Row(
          children: [
            Builder(
              builder: (regionContext) {
                // 검색 행은 draft가 비었을 때만 렌더되지만, 경로 칸이 생기면
                // 지역 변경을 막고 ▾도 숨긴다(표시명만 유지).
                final canChangeRegion = routeDraft().isEmpty;
                final onRegionTap = canChangeRegion
                    ? () => _showRegionMenu(regionContext, availableRegions)
                    : null;
                return Semantics(
                  key: const Key('mapRegionTabs'),
                  container: true,
                  button: canChangeRegion,
                  label: canChangeRegion
                      ? '지역: $currentRegion, 지역 변경'
                      : '지역: $currentRegion',
                  onTap: onRegionTap,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      minWidth: 48,
                      minHeight: 48,
                      maxWidth: 148,
                    ),
                    child: ExcludeSemantics(
                      child: InkWell(
                        key: const Key('networkMapRegionDropdown'),
                        onTap: onRegionTap,
                        borderRadius: BorderRadius.circular(8),
                        child: Center(
                          widthFactor: 1.0,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 8,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: Text(
                                    currentRegion,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: EasySubwayAccessibleColors
                                          .interactionOnPrimary,
                                      fontSize: 16,
                                      fontWeight: EasySubwayFontWeight.emphasis,
                                      letterSpacing: -0.2,
                                    ),
                                  ),
                                ),
                                if (canChangeRegion) ...[
                                  const SizedBox(width: 2),
                                  const Icon(
                                    Icons.keyboard_arrow_down_rounded,
                                    color: EasySubwayAccessibleColors
                                        .interactionOnPrimary,
                                    size: 20,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(width: 8),
            Expanded(child: NetworkMapSearchEntryButton(onTap: onSearchTap)),
            const SizedBox(width: 4),
            IconButton(
              key: const Key('networkMapMenuButton'),
              tooltip: '메뉴',
              onPressed: onMenuTap,
              style: IconButton.styleFrom(
                minimumSize: const Size.square(EasySubwayTouchTarget.general),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                padding: EdgeInsets.zero,
              ),
              icon: const Icon(
                Icons.menu,
                size: 26,
                color: EasySubwayAccessibleColors.interactionOnPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showRegionMenu(
    BuildContext triggerContext,
    List<NetworkMapRegion> availableRegions,
  ) {
    return showEasySubwayRegionMenu(
      triggerContext: triggerContext,
      regions: [
        for (final region in availableRegions)
          EasySubwayRegionMenuItem(id: region.name, label: region.displayName),
      ],
      selectedRegion: selectedRegion,
      onRegionSelected: onRegionSelected,
    );
  }
}

enum _RouteDraftFieldKind { origin, waypoint, destination }

class NetworkMapTopBarRouteDraft extends StatelessWidget {
  const NetworkMapTopBarRouteDraft({
    required this.draft,
    required this.showWaypointRow,
    required this.regionLabel,
    required this.onClearDraft,
    required this.onOpenWaypointSlot,
    required this.onClearOrigin,
    required this.onClearDestination,
    required this.onClearWaypoint,
    required this.onReorderDraft,
    required this.roleColorForSlot,
    this.onPickOrigin,
    this.onPickDestination,
    this.onPickWaypoint,
    super.key,
  });

  static const _leadingWidth = EasySubwayTouchTarget.general;

  static const _chromeVerticalInset =
      (easySubwayTopBarContentHeight - _draftRowHeight) / 2;

  final RouteDraft draft;
  final bool showWaypointRow;
  final String regionLabel;
  final VoidCallback onClearDraft;
  final VoidCallback onOpenWaypointSlot;
  final VoidCallback onClearOrigin;
  final VoidCallback onClearDestination;
  final VoidCallback onClearWaypoint;
  final void Function(RouteDraftSlot from, RouteDraftSlot to) onReorderDraft;
  final Color Function(RouteDraftSlot slot) roleColorForSlot;
  final VoidCallback? onPickOrigin;
  final VoidCallback? onPickDestination;
  final VoidCallback? onPickWaypoint;

  @override
  Widget build(BuildContext context) {
    final visibleSlots = <RouteDraftSlot>[
      RouteDraftSlot.origin,
      if (showWaypointRow) RouteDraftSlot.waypoint,
      RouteDraftSlot.destination,
    ];
    List<RouteDraftSlot> targetsFor(RouteDraftSlot slot) =>
        visibleSlots.where((candidate) => candidate != slot).toList();

    final hasOrigin = draft.origin != null;
    final hasDestination = draft.destination != null;
    final canAddWaypoint = !showWaypointRow && (hasOrigin != hasDestination);

    final originField = _NetworkMapRouteDraftField(
      kind: _RouteDraftFieldKind.origin,
      slot: RouteDraftSlot.origin,
      station: draft.origin,
      onClear: onClearOrigin,
      onPick: onPickOrigin,
      reorderTargets: targetsFor(RouteDraftSlot.origin),
      onReorder: onReorderDraft,
      roleColorForSlot: roleColorForSlot,
    );
    final destinationField = _NetworkMapRouteDraftField(
      kind: _RouteDraftFieldKind.destination,
      slot: RouteDraftSlot.destination,
      station: draft.destination,
      onClear: onClearDestination,
      onPick: onPickDestination,
      reorderTargets: targetsFor(RouteDraftSlot.destination),
      onReorder: onReorderDraft,
      roleColorForSlot: roleColorForSlot,
    );

    final fieldRows = <Widget>[
      _draftChromeRow(
        leading: _draftIconButton(
          key: const Key('networkMapRouteDraftBackButton'),
          tooltip: '경로 입력 지우기',
          icon: Icons.arrow_back,
          onPressed: onClearDraft,
        ),
        field: originField,
      ),
      if (showWaypointRow)
        _draftChromeRow(
          leading: const SizedBox(width: _leadingWidth),
          field: _NetworkMapRouteDraftField(
            kind: _RouteDraftFieldKind.waypoint,
            slot: RouteDraftSlot.waypoint,
            station: draft.waypoint,
            onClear: onClearWaypoint,
            onPick: onPickWaypoint,
            reorderTargets: targetsFor(RouteDraftSlot.waypoint),
            onReorder: onReorderDraft,
            roleColorForSlot: roleColorForSlot,
            showClearWhenEmpty: true,
          ),
        ),
      _draftChromeRow(
        leading: canAddWaypoint
            ? _draftIconButton(
                key: const Key('networkMapRouteDraftAddWaypoint'),
                tooltip: '경유역 칸 추가',
                icon: Icons.add,
                onPressed: onOpenWaypointSlot,
              )
            : const SizedBox(width: _leadingWidth),
        field: destinationField,
      ),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        4,
        _chromeVerticalInset,
        8,
        _chromeVerticalInset,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(mainAxisSize: MainAxisSize.min, children: fieldRows),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: _draftRowHeight,
            child: Align(
              alignment: Alignment.centerRight,
              child: _draftLockedRegionLabel(regionLabel),
            ),
          ),
        ],
      ),
    );
  }

  static Widget _draftIconButton({
    required Key key,
    required String tooltip,
    required IconData icon,
    required VoidCallback? onPressed,
  }) {
    return SizedBox(
      width: _leadingWidth,
      height: _draftRowHeight,
      child: IconButton(
        key: key,
        tooltip: tooltip,
        onPressed: onPressed,
        style: IconButton.styleFrom(
          minimumSize: const Size(_leadingWidth, _draftRowHeight),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          padding: EdgeInsets.zero,
        ),
        icon: Icon(
          icon,
          size: 26,
          color: EasySubwayAccessibleColors.interactionOnPrimary,
        ),
      ),
    );
  }

  static Widget _draftLockedRegionLabel(String regionLabel) {
    return Semantics(
      label: '지역: $regionLabel, 변경할 수 없음',
      child: ExcludeSemantics(
        child: ConstrainedBox(
          key: const Key('networkMapRouteDraftRegionLabel'),
          constraints: const BoxConstraints(maxWidth: 88),
          child: Text(
            regionLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: const TextStyle(
              color: EasySubwayAccessibleColors.interactionOnPrimary,
              fontSize: 17,
              fontWeight: EasySubwayFontWeight.regular,
            ),
          ),
        ),
      ),
    );
  }

  static Widget _draftChromeRow({
    required Widget leading,
    required Widget field,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        leading,
        const SizedBox(width: 4),
        Expanded(child: field),
      ],
    );
  }
}

class _NetworkMapRouteDraftField extends StatelessWidget {
  const _NetworkMapRouteDraftField({
    required this.kind,
    required this.slot,
    required this.station,
    required this.onClear,
    required this.reorderTargets,
    required this.onReorder,
    required this.roleColorForSlot,
    this.onPick,
    this.showClearWhenEmpty = false,
  });

  final _RouteDraftFieldKind kind;
  final RouteDraftSlot slot;
  final RouteDraftStation? station;
  final VoidCallback onClear;
  final List<RouteDraftSlot> reorderTargets;
  final void Function(RouteDraftSlot from, RouteDraftSlot to) onReorder;
  final Color Function(RouteDraftSlot slot) roleColorForSlot;
  final VoidCallback? onPick;
  final bool showClearWhenEmpty;

  String get _roleLabel => slot.displayLabel;
  String get _valuePlaceholder => '${slot.displayLabel} 입력';
  String get _searchLabel => '${slot.displayLabel} 검색';

  String get _rowKey => switch (kind) {
    _RouteDraftFieldKind.origin => 'networkMapRouteDraftOriginRow',
    _RouteDraftFieldKind.waypoint => 'networkMapRouteDraftWaypointRow',
    _RouteDraftFieldKind.destination => 'networkMapRouteDraftDestinationRow',
  };

  String get _pickKey => switch (kind) {
    _RouteDraftFieldKind.origin => 'networkMapRouteDraftPickOrigin',
    _RouteDraftFieldKind.waypoint => 'networkMapRouteDraftPickWaypoint',
    _RouteDraftFieldKind.destination => 'networkMapRouteDraftPickDestination',
  };

  String get _clearKey => switch (kind) {
    _RouteDraftFieldKind.origin => 'networkMapRouteDraftClearOrigin',
    _RouteDraftFieldKind.waypoint => 'networkMapRouteDraftClearWaypoint',
    _RouteDraftFieldKind.destination => 'networkMapRouteDraftClearDestination',
  };

  @override
  Widget build(BuildContext context) {
    final roleLabel = _roleLabel;
    final filled = station != null;
    final filledStation = station;
    final showLineBadge = filledStation != null && filledStation.hasLine;
    final valueText = filled ? filledStation!.displayName : _valuePlaceholder;
    final lineNameLabel =
        showLineBadge && filledStation.lineName.trim().isNotEmpty
        ? filledStation.lineName.trim()
        : null;
    final searchLabel = _searchLabel;
    final filledSemanticsCore = lineNameLabel == null
        ? '$roleLabel $valueText'
        : '$roleLabel $lineNameLabel $valueText';
    final pickSemanticsLabel = filled
        ? '$filledSemanticsCore, $searchLabel'
        : '$roleLabel, $_valuePlaceholder, $searchLabel';

    // 상용 지하철 서비스의 입력 칸처럼 역할 글자와 노선 마크 없이 역할 점과 역
    // 이름만 둔다(#509). 역할과 노선은 칸의 Semantics 라벨이 읽는다.
    final roleDot = Padding(
      padding: const EdgeInsets.symmetric(horizontal: _roleDotInset),
      child: RouteRoleDot(color: roleColorForSlot(slot)),
    );

    final valueName = Text(
      valueText,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: filled
            ? EasySubwayAccessibleColors.text
            : EasySubwayAccessibleColors.mutedText,
        fontSize: filled ? 17 : 15,
        fontWeight: filled
            ? EasySubwayFontWeight.emphasis
            : EasySubwayFontWeight.regular,
        height: 1.2,
      ),
    );
    final valueRow = Row(children: [Expanded(child: valueName)]);

    final Widget pickArea = onPick == null
        ? Semantics(
            label: filled ? filledSemanticsCore : _valuePlaceholder,
            child: ExcludeSemantics(
              child: SizedBox(
                height: _draftRowHeight,
                child: Center(child: valueRow),
              ),
            ),
          )
        : Semantics(
            button: true,
            label: pickSemanticsLabel,
            onTap: onPick,
            child: ExcludeSemantics(
              child: GestureDetector(
                key: Key(_pickKey),
                behavior: HitTestBehavior.opaque,
                onTap: onPick,
                child: SizedBox(
                  height: _draftRowHeight,
                  child: Center(child: valueRow),
                ),
              ),
            ),
          );

    // 시각 박스(40dp)는 배경만 그리고, 그 위 행의 입력·지우기 영역이 줄 높이
    // (48dp)만큼 눌려 최소 터치 영역을 채운다.
    final rowContainer = SizedBox(
      height: _draftRowHeight,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            height: easySubwaySearchFieldVisualHeight,
            decoration: BoxDecoration(
              color: EasySubwayAccessibleColors.searchFieldSurface,
              borderRadius: easySubwaySearchFieldRadius,
              border: Border.all(
                color: easySubwaySearchFieldBorderColor,
                width: easySubwaySearchFieldBorderWidth,
              ),
            ),
          ),
          Row(
            children: [
              roleDot,
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    left: 0,
                    right: (filled || showClearWhenEmpty) ? 0 : 10,
                  ),
                  child: pickArea,
                ),
              ),
              if (filled || showClearWhenEmpty)
                Semantics(
                  button: true,
                  label: filled ? '$roleLabel 지우기' : '$roleLabel 칸 닫기',
                  onTap: onClear,
                  child: ExcludeSemantics(
                    child: IconButton(
                      key: Key(_clearKey),
                      onPressed: onClear,
                      style: IconButton.styleFrom(
                        splashFactory: NoSplash.splashFactory,
                        highlightColor: Colors.transparent,
                        backgroundColor: Colors.transparent,
                        elevation: 0,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      icon: Container(
                        width: 22,
                        height: 22,
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(
                          color: EasySubwayAccessibleColors.disclosure,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.close,
                          size: 14,
                          color:
                              EasySubwayAccessibleColors.interactionOnPrimary,
                        ),
                      ),
                      constraints: const BoxConstraints(
                        minWidth: _draftRowHeight,
                        minHeight: _draftRowHeight,
                      ),
                      padding: const EdgeInsets.only(right: 4),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );

    Widget content = rowContainer;
    if (filled) {
      content = LongPressDraggable<RouteDraftSlot>(
        data: slot,
        maxSimultaneousDrags: 1,
        dragAnchorStrategy: childDragAnchorStrategy,
        feedback: Material(
          elevation: 0,
          type: MaterialType.transparency,
          child: SizedBox(
            width: 220,
            child: Container(
              height: easySubwaySearchFieldVisualHeight,
              decoration: BoxDecoration(
                color: EasySubwayAccessibleColors.searchFieldSurface,
                borderRadius: easySubwaySearchFieldRadius,
                border: Border.all(
                  color: easySubwaySearchFieldBorderColor,
                  width: easySubwaySearchFieldBorderWidth,
                ),
              ),
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: [
                  Text(
                    roleLabel,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: EasySubwayAccessibleColors.mutedText,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      filledStation!.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: EasySubwayAccessibleColors.text,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        childWhenDragging: Opacity(opacity: 0.4, child: rowContainer),
        child: rowContainer,
      );
      content = Semantics(
        container: true,
        customSemanticsActions: <CustomSemanticsAction, VoidCallback>{
          for (final target in reorderTargets)
            CustomSemanticsAction(label: '${target.displayLabel}으로 이동'): () =>
                onReorder(slot, target),
        },
        child: content,
      );
    }

    return DragTarget<RouteDraftSlot>(
      key: Key(_rowKey),
      onWillAcceptWithDetails: (details) => details.data != slot,
      onAcceptWithDetails: (details) => onReorder(details.data, slot),
      builder: (context, candidateData, rejectedData) => content,
    );
  }
}

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
              fontWeight: EasySubwayFontWeight.regular,
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
