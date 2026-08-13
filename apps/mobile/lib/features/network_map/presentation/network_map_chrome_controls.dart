import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;

import '../../../accessible_design.dart';
import '../../../search_field.dart';
import '../../route_draft/domain/route_draft.dart';
import '../domain/network_map_models.dart';
import '../domain/route_map_min_scale.dart';
import 'region_menu.dart';

class NetworkMapTopBar extends StatelessWidget {
  const NetworkMapTopBar({
    required this.regions,
    required this.selectedRegion,
    required this.notificationAction,
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
    required this.lineBadgeBuilder,
    this.onPickOrigin,
    this.onPickDestination,
    this.onPickWaypoint,
    super.key,
  });

  final List<NetworkMapRegion> regions;
  final String selectedRegion;
  final Widget? notificationAction;
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
  final Widget Function(RouteDraftStation station, double size)
  lineBadgeBuilder;
  final VoidCallback? onPickOrigin;
  final VoidCallback? onPickDestination;
  final VoidCallback? onPickWaypoint;

  @override
  Widget build(BuildContext context) {
    return Material(
      key: const Key('networkMapTopBar'),
      color: EasySubwayAccessibleColors.topBarSurface,
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
                  lineBadgeBuilder: lineBadgeBuilder,
                );
              },
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            // 노선도 idle/draft만 mapChrome 드롭. 검색 모드(흰 검색 본문)는
            // 역 검색 화면과 같이 선만 둔다.
            child: searchMode
                ? const EasySubwayHeaderDivider(
                    key: Key('networkMapTopBarDivider'),
                  )
                : const EasySubwayHeaderDivider.mapChrome(
                    key: Key('networkMapTopBarDivider'),
                  ),
          ),
        ],
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
            if (searchMode)
              IconButton(
                key: const Key('networkMapSearchBackButton'),
                tooltip: '뒤로',
                onPressed: onSearchBack,
                style: IconButton.styleFrom(
                  minimumSize: const Size.square(EasySubwayTouchTarget.general),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding: EdgeInsets.zero,
                ),
                icon: const Icon(
                  Icons.arrow_back,
                  size: 26,
                  color: EasySubwayAccessibleColors.contentPrimary,
                ),
              )
            else
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
                  color: EasySubwayAccessibleColors.contentPrimary,
                ),
              ),
            const SizedBox(width: 4),
            Expanded(
              child: searchMode
                  ? EasySubwaySearchField(
                      controller: searchQueryController,
                      focusNode: searchFocusNode,
                      hintText: '역 이름을 입력해 주세요',
                      autofocus: true,
                      onSubmitted: onSearchSubmitted,
                      onClear: onSearchClear,
                    )
                  : NetworkMapSearchEntryButton(onTap: onSearchTap),
            ),
            const SizedBox(width: 8),
            Builder(
              builder: (regionContext) {
                // 검색 행은 draft가 비었을 때만 렌더되지만, 경로 칸이 생기면
                // 지역 변경을 막고 ▾도 숨긴다(표시명만 유지).
                final canChangeRegion = routeDraft().isEmpty;
                return Semantics(
                  key: const Key('mapRegionTabs'),
                  container: true,
                  button: canChangeRegion,
                  label: canChangeRegion
                      ? '지역: $currentRegion, 지역 변경'
                      : '지역: $currentRegion',
                  onTap: canChangeRegion
                      ? () => _showRegionMenu(regionContext, availableRegions)
                      : null,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 148),
                    child: ExcludeSemantics(
                      child: InkWell(
                        key: const Key('networkMapRegionDropdown'),
                        onTap: canChangeRegion
                            ? () => _showRegionMenu(
                                regionContext,
                                availableRegions,
                              )
                            : null,
                        splashFactory: NoSplash.splashFactory,
                        splashColor: Colors.transparent,
                        highlightColor: Colors.transparent,
                        child: SizedBox(
                          height: EasySubwayTouchTarget.general,
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
                                        .contentSecondary,
                                    fontSize: 17,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              if (canChangeRegion) ...[
                                const SizedBox(width: 2),
                                const Icon(
                                  Icons.keyboard_arrow_down,
                                  color: EasySubwayAccessibleColors
                                      .contentSecondary,
                                  size: 22,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
            if (notificationAction != null) ...[
              const SizedBox(width: 8),
              notificationAction!,
            ],
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
    required this.lineBadgeBuilder,
    this.onPickOrigin,
    this.onPickDestination,
    this.onPickWaypoint,
    super.key,
  });

  static const _leadingWidth = EasySubwayTouchTarget.general;
  static const _rowGap = 6.0;
  static const _fieldMinHeight = easySubwaySearchFieldVisualHeight;
  static const _chromeVerticalInset =
      (easySubwayTopBarContentHeight - _fieldMinHeight) / 2;

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
  final Widget Function(RouteDraftStation station, double size)
  lineBadgeBuilder;
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
      lineBadgeBuilder: lineBadgeBuilder,
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
      lineBadgeBuilder: lineBadgeBuilder,
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
            lineBadgeBuilder: lineBadgeBuilder,
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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < fieldRows.length; i++) ...[
                  if (i > 0) const SizedBox(height: _rowGap),
                  fieldRows[i],
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: _fieldMinHeight,
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
      height: _fieldMinHeight,
      child: IconButton(
        key: key,
        tooltip: tooltip,
        onPressed: onPressed,
        style: IconButton.styleFrom(
          minimumSize: const Size.square(EasySubwayTouchTarget.general),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          padding: EdgeInsets.zero,
        ),
        icon: Icon(
          icon,
          size: 26,
          color: EasySubwayAccessibleColors.contentPrimary,
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
              color: EasySubwayAccessibleColors.contentSecondary,
              fontSize: 17,
              fontWeight: FontWeight.w600,
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
    required this.lineBadgeBuilder,
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
  final Widget Function(RouteDraftStation station, double size)
  lineBadgeBuilder;
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

    final roleLabelWidget = ExcludeSemantics(
      child: SizedBox(
        width: 72,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            roleLabel,
            maxLines: 1,
            softWrap: false,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: roleColorForSlot(slot),
              fontSize: 15,
              fontWeight: FontWeight.w700,
              height: 1.2,
            ),
          ),
        ),
      ),
    );

    final valueRow = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (showLineBadge) ...[
          lineBadgeBuilder(filledStation, 26),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: Text(
            valueText,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: filled
                  ? EasySubwayAccessibleColors.text
                  : EasySubwayAccessibleColors.mutedText,
              fontSize: filled ? 17 : 15,
              fontWeight: filled ? FontWeight.w700 : FontWeight.w600,
              height: 1.2,
            ),
          ),
        ),
      ],
    );

    final Widget pickArea = onPick == null
        ? Semantics(
            label: filled ? filledSemanticsCore : _valuePlaceholder,
            child: ExcludeSemantics(
              child: SizedBox(
                height: easySubwaySearchFieldVisualHeight,
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
                  height: easySubwaySearchFieldVisualHeight,
                  child: Center(child: valueRow),
                ),
              ),
            ),
          );

    final rowContainer = Container(
      height: easySubwaySearchFieldVisualHeight,
      decoration: BoxDecoration(
        color: EasySubwayAccessibleColors.searchFieldSurface,
        borderRadius: easySubwaySearchFieldRadius,
        border: Border.all(
          color: easySubwaySearchFieldBorderColor,
          width: easySubwaySearchFieldBorderWidth,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(alignment: Alignment.centerLeft, child: roleLabelWidget),
            Container(
              width: easySubwaySearchFieldBorderWidth,
              color: easySubwaySearchFieldBorderColor,
            ),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 10,
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
                        color: EasySubwayAccessibleColors.interactionOnPrimary,
                      ),
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 40,
                      minHeight: 40,
                    ),
                    padding: const EdgeInsets.only(right: 4),
                  ),
                ),
              ),
          ],
        ),
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
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (showLineBadge) ...[
                    lineBadgeBuilder(filledStation, 30),
                    const SizedBox(width: 8),
                  ],
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
