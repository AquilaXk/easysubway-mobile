import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../../accessible_design.dart';
import '../../../design_tokens.dart';
import '../domain/map_camera.dart';
import '../domain/network_map_models.dart';

/// 출발/경유/도착으로 지정된 역 위에 표시하는 route-draft 핀이다.
///
/// 실루엣 에셋 + 내부 팬 메뉴색 + 외곽선은 상단바 '수도권' 글자색(#606060).
/// 뾰족한 끝은 [anchorSource](일반 노드/환승 캡슐 중심) 정중앙에 둔다.
class NetworkMapDraftPin extends StatelessWidget {
  const NetworkMapDraftPin({
    super.key,
    required this.station,
    required this.anchorSource,
    required this.camera,
    required this.label,
    required this.surfaceColor,
    required this.semanticSuffix,
    required this.clearButtonKey,
    required this.onClear,
    this.ignorePointers = false,
  });

  static const _assetPath = 'assets/illustrations/map_draft_pin.png';
  // 에셋은 800², 끝점은 하단 중앙. 표시 크기는 터치·가독 균형.
  static const _pinWidth = 52.0;
  static const _pinHeight = 52.0;
  static const _clearSize = 18.0;

  /// 역할색 외곽 ≈1.5px 고정 두께(양옆 합 3px / 핀 폭).
  static const _edgeStrokePx = 1.5;
  static const _edgeScale = 1 + (2 * _edgeStrokePx) / _pinWidth;

  /// soft drop: y 3 · blur 6 상당(sigma 3).
  static const _shadowOffsetY = 3.0;
  static const _shadowBlurSigma = 3.0;

  /// ✕ soft drop: y 2 · blur 4 상당(sigma 2).
  static const _clearShadowOffsetY = 2.0;
  static const _clearShadowBlurSigma = 2.0;
  static const _labelFontSize = 13.0;
  static const _labelStrokeWidth = 3.0;

  static Color _pinEdgeFor(Color fill) {
    if (fill == EasySubwayFanMenuColors.departure) {
      return EasySubwayFanMenuColors.pinEdgeDeparture;
    }
    if (fill == EasySubwayFanMenuColors.waypoint) {
      return EasySubwayFanMenuColors.pinEdgeWaypoint;
    }
    return EasySubwayFanMenuColors.pinEdgeArrival;
  }

  final NetworkMapStation station;

  /// geometry 원점 보정된 source 좌표. 환승이면 캡슐 중심.
  final Offset anchorSource;
  final MapCameraState camera;
  final String label;
  final Color surfaceColor;
  final String semanticSuffix;
  final Key clearButtonKey;
  final VoidCallback onClear;

  /// 줌/팬 제스처 중 핀치가 핀에 먹히지 않도록 포인터를 통과시킨다.
  final bool ignorePointers;

  @override
  Widget build(BuildContext context) {
    final anchorPoint = camera.sourceToViewportPoint(anchorSource);
    // ✕는 핀 머리 우상단에 붙이므로, 핀 기준으로 여유를 둔다.
    const hitPadLeft = 8.0;
    const hitPadRight = 18.0;
    const hitPadTop = 10.0;
    const hitPadBottom = 0.0;
    const hitWidth = _pinWidth + hitPadLeft + hitPadRight;
    const hitHeight = _pinHeight + hitPadTop + hitPadBottom;
    final viewportWidth = camera.viewportSize.width;
    // 핀 이미지 하단 중앙(뾰족한 끝)이 앵커에 오도록 배치.
    final pinLeft = anchorPoint.dx - _pinWidth / 2;
    final pinTop = anchorPoint.dy - _pinHeight;
    final hitLeft = (pinLeft - hitPadLeft)
        .clamp(4.0, math.max(4.0, viewportWidth - hitWidth - 4))
        .toDouble();
    final hitTop = math.max(4.0, pinTop - hitPadTop);
    final pinOffsetInHit = Offset(pinLeft - hitLeft, pinTop - hitTop);
    // ✕는 카카오처럼 핀 머리 안쪽·약간 위에 붙인다. 터치 타깃은 그 중심 기준 56.
    final clearVisualLeft = pinOffsetInHit.dx + _pinWidth - (_clearSize * 0.92);
    final clearVisualTop = pinOffsetInHit.dy - (_clearSize * 0.42);
    final clearHitLeft =
        clearVisualLeft + _clearSize / 2 - EasySubwayTouchTarget.general / 2;
    final clearHitTop =
        clearVisualTop + _clearSize / 2 - EasySubwayTouchTarget.general / 2;
    final edgeColor = _pinEdgeFor(surfaceColor);
    return Positioned(
      left: hitLeft,
      top: hitTop,
      width: hitWidth,
      height: hitHeight,
      child: IgnorePointer(
        ignoring: ignorePointers,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: pinOffsetInHit.dx,
              top: pinOffsetInHit.dy,
              width: _pinWidth,
              height: _pinHeight,
              child: Semantics(
                container: true,
                label: '${station.displayName}, $semanticSuffix',
                child: ExcludeSemantics(
                  child: Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.center,
                    children: [
                      // soft drop → 역할색 외곽(≈1.5px) → 역할색 면.
                      ImageFiltered(
                        imageFilter: ImageFilter.blur(
                          sigmaX: _shadowBlurSigma,
                          sigmaY: _shadowBlurSigma,
                          tileMode: TileMode.decal,
                        ),
                        child: Transform.translate(
                          offset: const Offset(0, _shadowOffsetY),
                          child: ColorFiltered(
                            colorFilter: const ColorFilter.mode(
                              EasySubwayFanMenuColors.pinShadow,
                              BlendMode.srcIn,
                            ),
                            child: Image.asset(
                              _assetPath,
                              width: _pinWidth,
                              height: _pinHeight,
                              fit: BoxFit.contain,
                              filterQuality: FilterQuality.high,
                            ),
                          ),
                        ),
                      ),
                      Transform.scale(
                        scale: _edgeScale,
                        child: ColorFiltered(
                          colorFilter: ColorFilter.mode(
                            edgeColor,
                            BlendMode.srcIn,
                          ),
                          child: Image.asset(
                            _assetPath,
                            width: _pinWidth,
                            height: _pinHeight,
                            fit: BoxFit.contain,
                            filterQuality: FilterQuality.high,
                          ),
                        ),
                      ),
                      ColorFiltered(
                        colorFilter: ColorFilter.mode(
                          surfaceColor,
                          BlendMode.srcIn,
                        ),
                        child: Image.asset(
                          _assetPath,
                          width: _pinWidth,
                          height: _pinHeight,
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.high,
                        ),
                      ),
                      // 라벨: 흰 글자 + 핀색 외곽선.
                      Align(
                        alignment: const Alignment(0, -0.28),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                Text(
                                  label,
                                  textAlign: TextAlign.center,
                                  maxLines: 1,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: _labelFontSize,
                                    height: 1.0,
                                    foreground: Paint()
                                      ..style = PaintingStyle.stroke
                                      ..strokeWidth = _labelStrokeWidth
                                      ..strokeJoin = StrokeJoin.round
                                      ..color = surfaceColor,
                                  ),
                                ),
                                Text(
                                  label,
                                  textAlign: TextAlign.center,
                                  maxLines: 1,
                                  style: const TextStyle(
                                    color: EasySubwayAccessibleColors
                                        .interactionOnPrimary,
                                    fontWeight: FontWeight.w700,
                                    fontSize: _labelFontSize,
                                    height: 1.0,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              left: clearHitLeft,
              top: clearHitTop,
              width: EasySubwayTouchTarget.general,
              height: EasySubwayTouchTarget.general,
              child: Semantics(
                button: true,
                label: '$label 지우기',
                onTap: onClear,
                child: ExcludeSemantics(
                  child: GestureDetector(
                    key: clearButtonKey,
                    behavior: HitTestBehavior.opaque,
                    onTap: onClear,
                    child: Center(
                      child: SizedBox(
                        width: _clearSize + 4,
                        height: _clearSize + 4,
                        child: Stack(
                          alignment: Alignment.center,
                          clipBehavior: Clip.none,
                          children: [
                            ImageFiltered(
                              imageFilter: ImageFilter.blur(
                                sigmaX: _clearShadowBlurSigma,
                                sigmaY: _clearShadowBlurSigma,
                                tileMode: TileMode.decal,
                              ),
                              child: Transform.translate(
                                offset: const Offset(0, _clearShadowOffsetY),
                                child: Container(
                                  width: _clearSize,
                                  height: _clearSize,
                                  decoration: const BoxDecoration(
                                    color:
                                        EasySubwayFanMenuColors.pinClearShadow,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                            ),
                            Container(
                              width: _clearSize,
                              height: _clearSize,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: EasySubwayFanMenuColors.pinClearBg,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: EasySubwayFanMenuColors.pinClearBorder,
                                  width: 1,
                                ),
                              ),
                              child: const Icon(
                                Icons.close_rounded,
                                size: 11,
                                color: EasySubwayFanMenuColors.pinClearInk,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
