import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../accessible_design.dart';
import '../domain/facility_status.dart';
import '../domain/station_models.dart';
import 'station_facility_detail_screen.dart';

class StationFacilityCard extends StatelessWidget {
  const StationFacilityCard({
    required this.facility,
    required this.station,
    required this.onReportTap,
    super.key,
  });

  final StationFacilityInfo facility;
  final StationDetail station;
  final VoidCallback onReportTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final style = _resolveFacilityStyle(facility);
    final isToilet =
        facility.type == 'TOILET' ||
        facility.type == 'ACCESSIBLE_TOILET' ||
        facility.name.contains('화장실');
    final toiletText =
        '${facility.name} ${facility.description} ${facility.floorFrom}'
            .toLowerCase();
    final isInsideGate =
        toiletText.contains('안쪽') ||
        toiletText.contains('내부') ||
        toiletText.contains('운임구역 내') ||
        toiletText.contains('승강장') ||
        toiletText.contains('게이트 안') ||
        toiletText.contains('개찰구 안') ||
        (toiletText.contains(' 안') && !toiletText.contains('안내'));

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: EasySubwayAccessibleColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(
            color: EasySubwayAccessibleColors.line,
            width: 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              container: true,
              label: facility.semanticLabel,
              button: true,
              child: InkWell(
                key: Key('stationFacilityCard-${facility.id}'),
                onTap: () => _openFacilityDetail(context),
                child: ExcludeSemantics(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: style.iconBgColor,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: style.iconBorderColor,
                              width: 1,
                            ),
                          ),
                          child: Center(
                            child: style.svgAsset != null
                                ? SvgPicture.asset(
                                    style.svgAsset!,
                                    width: 24,
                                    height: 24,
                                    colorFilter: ColorFilter.mode(
                                      style.iconColor,
                                      BlendMode.srcIn,
                                    ),
                                  )
                                : style.pngAsset != null
                                ? Image.asset(
                                    style.pngAsset!,
                                    width: 24,
                                    height: 24,
                                    color: style.iconColor,
                                    colorBlendMode: BlendMode.srcIn,
                                  )
                                : Icon(
                                    style.icon,
                                    color: style.iconColor,
                                    size: 24,
                                  ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Text(
                                      facility.displayName,
                                      style: textTheme.titleMedium?.copyWith(
                                        color: EasySubwayAccessibleColors.text,
                                        fontWeight: FontWeight.w700,
                                        height: 1.25,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  const Icon(
                                    Icons.chevron_right,
                                    color: EasySubwayAccessibleColors.mutedText,
                                    size: 20,
                                  ),
                                ],
                              ),
                              if (isToilet) ...[
                                const SizedBox(height: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isInsideGate
                                        ? const Color(0xFFEFF6FF)
                                        : const Color(0xFFF3F4F6),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                      color: isInsideGate
                                          ? const Color(0xFF3B82F6)
                                          : const Color(0xFFD1D5DB),
                                    ),
                                  ),
                                  child: Text(
                                    isInsideGate
                                        ? '개찰구 안쪽 (운임구역 내)'
                                        : '개찰구 바깥쪽 (대합실)',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: isInsideGate
                                          ? const Color(0xFF1D4ED8)
                                          : const Color(0xFF4B5563),
                                    ),
                                  ),
                                ),
                              ],
                              if (facility.needsAttention) ...[
                                const SizedBox(height: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: style.badgeBgColor,
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: style.badgeBorderColor,
                                      width: 1,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      Container(
                                        width: 6,
                                        height: 6,
                                        decoration: BoxDecoration(
                                          color: style.badgeDotColor,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Flexible(
                                        child: Text(
                                          facility.statusTitle,
                                          style: textTheme.bodySmall?.copyWith(
                                            color: style.badgeTextColor,
                                            fontWeight: FontWeight.w700,
                                            height: 1.2,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  const Icon(
                                    Icons.place_outlined,
                                    size: 16,
                                    color: EasySubwayAccessibleColors.mutedText,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      facility.locationLabel,
                                      style: textTheme.bodyMedium?.copyWith(
                                        color: EasySubwayAccessibleColors
                                            .secondaryText,
                                        fontWeight: FontWeight.w500,
                                        height: 1.3,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  const Icon(
                                    Icons.event_available,
                                    size: 15,
                                    color: EasySubwayAccessibleColors.mutedText,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      facility.updatedLabel,
                                      style: textTheme.bodySmall?.copyWith(
                                        color: EasySubwayAccessibleColors
                                            .mutedText,
                                        fontWeight: FontWeight.w500,
                                        height: 1.3,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const Divider(
              height: 1,
              thickness: 1,
              color: EasySubwayAccessibleColors.line,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Semantics(
                    container: true,
                    label: '${facility.displayName} 시설 제보',
                    button: true,
                    onTap: onReportTap,
                    child: ExcludeSemantics(
                      child: TextButton.icon(
                        key: Key('facilityReportButton-${facility.id}'),
                        onPressed: onReportTap,
                        style: TextButton.styleFrom(
                          foregroundColor:
                              EasySubwayAccessibleColors.secondaryText,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          minimumSize: const Size(48, 48),
                        ),
                        icon: const Icon(Icons.report_outlined, size: 18),
                        label: const Text(
                          '시설 제보',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
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

  void _openFacilityDetail(BuildContext context) {
    unawaited(
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => FacilityDetailScreen(
            station: station,
            facility: facility,
            onReportTap: onReportTap,
          ),
        ),
      ),
    );
  }
}

class _FacilityStyle {
  const _FacilityStyle({
    required this.icon,
    required this.iconColor,
    required this.iconBgColor,
    required this.iconBorderColor,
    this.svgAsset,
    this.pngAsset,
    required this.badgeTextColor,
    required this.badgeBgColor,
    required this.badgeBorderColor,
    required this.badgeDotColor,
  });

  final IconData icon;
  final String? svgAsset;
  final String? pngAsset;
  final Color iconColor;
  final Color iconBgColor;
  final Color iconBorderColor;
  final Color badgeTextColor;
  final Color badgeBgColor;
  final Color badgeBorderColor;
  final Color badgeDotColor;
}

IconData _resolveFacilityIcon(String type) {
  return switch (type.trim().toUpperCase()) {
    'ELEVATOR' => Icons.elevator,
    'ESCALATOR' => Icons.escalator,
    'WHEELCHAIR_LIFT' => Icons.accessible_forward,
    'RAMP' => Icons.accessible,
    'ACCESSIBLE_TOILET' || 'TOILET' => Icons.wc_outlined,
    'NURSING_ROOM' => Icons.baby_changing_station,
    'CUSTOMER_CENTER' || 'STATION_OFFICE' => Icons.support_agent,
    'LOST_ITEM' || 'LOST_AND_FOUND' => Icons.find_in_page_outlined,
    'WHEELCHAIR_CHARGER' ||
    'CHARGER' ||
    'CHARGE' => Icons.battery_charging_full,
    _ => Icons.info_outline,
  };
}

String? _resolveFacilitySvg(String type) {
  return switch (type.trim().toUpperCase()) {
    'ELEVATOR' => 'assets/icons/elevator.svg',
    'ESCALATOR' => 'assets/icons/escalator.svg',
    'ACCESSIBLE_TOILET' => 'assets/icons/diabled_toilet.svg',
    'TOILET' => 'assets/icons/toilet.svg',
    'NURSING_ROOM' => 'assets/icons/nursing.svg',
    'LOST_ITEM' || 'LOST_AND_FOUND' => 'assets/icons/lost_item.svg',
    'WHEELCHAIR_CHARGER' || 'CHARGER' || 'CHARGE' => 'assets/icons/charge.svg',
    _ => null,
  };
}

String? _resolveFacilityPng(String type) {
  return switch (type.trim().toUpperCase()) {
    'WHEELCHAIR_LIFT' || 'RAMP' => 'assets/icons/wheelchair.png',
    _ => null,
  };
}

_FacilityStyle _resolveFacilityStyle(StationFacilityInfo facility) {
  final icon = _resolveFacilityIcon(facility.type);
  final svgAsset = _resolveFacilitySvg(facility.type);
  final pngAsset = _resolveFacilityPng(facility.type);

  return switch (facility.statusPresentation.severity) {
    FacilityStatusSeverity.blocked => _FacilityStyle(
      icon: icon,
      svgAsset: svgAsset,
      pngAsset: pngAsset,
      iconColor: EasySubwayAccessibleColors.red,
      iconBgColor: EasySubwayAccessibleColors.surfaceSubtle,
      iconBorderColor: EasySubwayAccessibleColors.line,
      badgeTextColor: EasySubwayAccessibleColors.red,
      badgeBgColor: EasySubwayAccessibleColors.surfaceSubtle,
      badgeBorderColor: EasySubwayAccessibleColors.line,
      badgeDotColor: EasySubwayAccessibleColors.red,
    ),
    FacilityStatusSeverity.caution => _FacilityStyle(
      icon: icon,
      svgAsset: svgAsset,
      pngAsset: pngAsset,
      iconColor: EasySubwayAccessibleColors.amber,
      iconBgColor: EasySubwayAccessibleColors.surfaceSubtle,
      iconBorderColor: EasySubwayAccessibleColors.line,
      badgeTextColor: EasySubwayAccessibleColors.amber,
      badgeBgColor: EasySubwayAccessibleColors.surfaceSubtle,
      badgeBorderColor: EasySubwayAccessibleColors.line,
      badgeDotColor: EasySubwayAccessibleColors.amber,
    ),
    FacilityStatusSeverity.needsInfo => _FacilityStyle(
      icon: icon,
      svgAsset: svgAsset,
      pngAsset: pngAsset,
      iconColor: EasySubwayAccessibleColors.needsInfo,
      iconBgColor: EasySubwayAccessibleColors.surfaceSubtle,
      iconBorderColor: EasySubwayAccessibleColors.line,
      badgeTextColor: EasySubwayAccessibleColors.needsInfo,
      badgeBgColor: EasySubwayAccessibleColors.surfaceSubtle,
      badgeBorderColor: EasySubwayAccessibleColors.line,
      badgeDotColor: EasySubwayAccessibleColors.needsInfo,
    ),
    FacilityStatusSeverity.normal => _FacilityStyle(
      icon: icon,
      svgAsset: svgAsset,
      pngAsset: pngAsset,
      iconColor: EasySubwayAccessibleColors.primary,
      iconBgColor: EasySubwayAccessibleColors.surfaceBrandChrome,
      iconBorderColor: EasySubwayAccessibleColors.line,
      badgeTextColor: EasySubwayAccessibleColors.mint,
      badgeBgColor: EasySubwayAccessibleColors.surfaceSubtle,
      badgeBorderColor: EasySubwayAccessibleColors.line,
      badgeDotColor: EasySubwayAccessibleColors.mint,
    ),
  };
}
