import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../accessible_design.dart';
import '../../../app/accessibility_theme.dart';
import '../../../design_tokens.dart';
import '../../../mobile_error_reporter.dart';
import '../../notifications/notification_settings.dart';
import '../../onboarding/onboarding_preferences.dart';
import '../../mobility_profile/mobility_preset_labels.dart';
import '../../mobility_profile/mobility_profile_policy.dart';

const _settingsPagePadding = EdgeInsets.only(bottom: 24);

class AppSettingsScreen extends StatefulWidget {
  const AppSettingsScreen({
    required this.currentPreset,
    this.initialWalkingPace,
    required this.viewPreferences,
    required this.notificationRepository,
    required this.notificationPermissionProvider,
    required this.onViewPreferencesChanged,
    required this.onOpenMobilityProfile,
    this.onPresetChanged,
    this.onWalkingPaceChanged,
    required this.onOpenSupportAccess,
    required this.onOpenInquiry,
    required this.onOpenServiceInfo,
    required this.onOpenMyReports,
    this.onShellBack,
    this.bottomNavigationBar,
    super.key,
  });

  final MobilityPreset currentPreset;
  final WalkingPace? initialWalkingPace;
  final OnboardingViewPreferences viewPreferences;
  final NotificationSettingsRepository? notificationRepository;
  final NotificationPermissionProvider? notificationPermissionProvider;
  final Future<void> Function(OnboardingViewPreferences preferences)
  onViewPreferencesChanged;
  final Future<MobilityPreset?> Function() onOpenMobilityProfile;
  final Future<bool> Function(MobilityPreset preset)? onPresetChanged;
  final ValueChanged<WalkingPace>? onWalkingPaceChanged;
  final VoidCallback onOpenSupportAccess;
  final VoidCallback onOpenInquiry;
  final VoidCallback onOpenServiceInfo;
  final VoidCallback onOpenMyReports;

  /// 루트 탭으로 열린 설정에서 Navigator.pop이 안 될 때 이전 탭(없으면 홈)으로 돌아간다.
  final VoidCallback? onShellBack;
  final Widget? bottomNavigationBar;

  @override
  State<AppSettingsScreen> createState() => _AppSettingsScreenState();
}

class _AppSettingsScreenState extends State<AppSettingsScreen> {
  late MobilityPreset _preset;
  late OnboardingViewPreferences _viewPreferences;
  late WalkingPace _walkingPace;
  late FacilityConstraint _facilityConstraint;

  @override
  void initState() {
    super.initState();
    _preset = widget.currentPreset;
    _viewPreferences = widget.viewPreferences;
    _walkingPace = widget.initialWalkingPace ??
        walkingPaceFromPreset(widget.currentPreset);
    _facilityConstraint = facilityConstraintFromPreset(widget.currentPreset);
  }

  @override
  void didUpdateWidget(AppSettingsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentPreset != widget.currentPreset) {
      _preset = widget.currentPreset;
      _syncDimensionsFromPreset(widget.currentPreset);
    }
    if (oldWidget.initialWalkingPace != widget.initialWalkingPace &&
        widget.initialWalkingPace != null) {
      _walkingPace = widget.initialWalkingPace!;
    }
    if (oldWidget.viewPreferences != widget.viewPreferences) {
      _viewPreferences = widget.viewPreferences;
    }
  }

  void _syncDimensionsFromPreset(MobilityPreset preset) {
    _facilityConstraint = facilityConstraintFromPreset(preset);
    if (preset == MobilityPreset.slow) {
      _walkingPace = WalkingPace.slow;
    } else if (preset == MobilityPreset.standard &&
        _walkingPace == WalkingPace.slow) {
      _walkingPace = WalkingPace.standard;
    }
  }

  Future<void> _handleOpenMobilityProfile() async {
    final selected = await widget.onOpenMobilityProfile();
    if (!mounted || selected == null) {
      return;
    }
    setState(() {
      _preset = selected;
      if (selected == MobilityPreset.slow) {
        _walkingPace = WalkingPace.slow;
      } else if (selected == MobilityPreset.standard &&
          _walkingPace == WalkingPace.slow) {
        _walkingPace = WalkingPace.standard;
      }
      _facilityConstraint = facilityConstraintFromPreset(selected);
    });
  }

  Future<void> _handleWalkingPaceSelected(WalkingPace pace) async {
    if (_walkingPace == pace) {
      return;
    }
    final previousPace = _walkingPace;
    setState(() {
      _walkingPace = pace;
    });
    widget.onWalkingPaceChanged?.call(pace);
    final nextPreset = presetFromDimensions(pace, _facilityConstraint);
    await _applyPresetChange(nextPreset, rollbackPace: previousPace);
  }

  Future<void> _handleFacilityConstraintSelected(
    FacilityConstraint constraint,
  ) async {
    if (_facilityConstraint == constraint) {
      return;
    }
    final previousConstraint = _facilityConstraint;
    setState(() {
      _facilityConstraint = constraint;
    });
    final nextPreset = presetFromDimensions(_walkingPace, constraint);
    await _applyPresetChange(
      nextPreset,
      rollbackConstraint: previousConstraint,
    );
  }

  Future<void> _applyPresetChange(
    MobilityPreset nextPreset, {
    WalkingPace? rollbackPace,
    FacilityConstraint? rollbackConstraint,
  }) async {
    final previousPreset = _preset;
    setState(() {
      _preset = nextPreset;
    });
    if (widget.onPresetChanged != null) {
      final success = await widget.onPresetChanged!(nextPreset);
      if (!success && mounted) {
        setState(() {
          _preset = previousPreset;
          if (rollbackPace != null) {
            _walkingPace = rollbackPace;
          }
          if (rollbackConstraint != null) {
            _facilityConstraint = rollbackConstraint;
          }
          if (rollbackPace == null && rollbackConstraint == null) {
            _syncDimensionsFromPreset(previousPreset);
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return OnboardingPreferenceScope(
      preferences: _viewPreferences,
      child: Scaffold(
        key: const Key('settingsScreen'),
        backgroundColor: EasySubwayAccessibleColors.scaffoldSurface,
        appBar: AppBar(
          key: const Key('settingsAppBar'),
          title: const Text('설정'),
          toolbarHeight: 60,
          backgroundColor: EasySubwayAccessibleColors.topBarSurface,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          automaticallyImplyLeading: false,
          leading: IconButton(
            key: const Key('settingsBackButton'),
            tooltip: '뒤로',
            onPressed: () {
              final navigator = Navigator.of(context);
              if (navigator.canPop()) {
                navigator.pop();
                return;
              }
              widget.onShellBack?.call();
            },
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
          ),
          flexibleSpace: const Align(
            alignment: Alignment.bottomCenter,
            child: EasySubwayHeaderDivider(key: Key('settingsHeaderDivider')),
          ),
        ),
        body: SafeArea(
          child: ListView(
            padding: _settingsPagePadding,
            children: [
              const _AppSettingsSectionHeader(
                key: Key('settingsSectionHeader-이동 조건'),
                title: '이동 조건',
              ),
              _MobilityHeroBlock(
                preset: _preset,
                walkingPace: _walkingPace,
                facilityConstraint: _facilityConstraint,
                onWalkingPaceSelected: (pace) {
                  unawaited(_handleWalkingPaceSelected(pace));
                },
                onFacilityConstraintSelected: (constraint) {
                  unawaited(_handleFacilityConstraintSelected(constraint));
                },
                onOpenMobilityProfile: () {
                  unawaited(_handleOpenMobilityProfile());
                },
              ),
              _AppSettingsSection(
                key: const Key('settingsSection-reading'),
                title: '화면 및 접근성',
                children: [
                  _AppSettingsPreferenceTile(
                    key: const Key('simpleViewSettingsButton'),
                    title: '간편 보기',
                    enabled: _viewPreferences.simpleViewEnabled,
                    onChanged: (value) {
                      unawaited(
                        _updateViewPreferences(
                          _viewPreferences.copyWith(simpleViewEnabled: value),
                        ),
                      );
                    },
                  ),
                  _AppSettingsPreferenceTile(
                    key: const Key('highContrastSettingsButton'),
                    title: '고대비',
                    enabled: _viewPreferences.highContrastEnabled,
                    onChanged: (value) {
                      unawaited(
                        _updateViewPreferences(
                          _viewPreferences.copyWith(highContrastEnabled: value),
                        ),
                      );
                    },
                  ),
                ],
              ),
              // 오프라인 안내 섹션·화면은 완전히 제거됐다(#1570): 오프라인 동작은
              // 설명 없이 그냥 되는 것이고, 데이터·지도 출처는 도움말·서비스 정보에 있다.
              if (widget.notificationRepository != null)
                _AppSettingsSection(
                  key: const Key('settingsSection-notification'),
                  title: '알림',
                  children: [
                    _AppSettingsActionTile(
                      key: const Key('notificationSettingsButton'),
                      title: '알림 설정',
                      onTap: () {
                        unawaited(
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => NotificationSettingsScreen(
                                repository: widget.notificationRepository!,
                                notificationPermissionProvider:
                                    widget.notificationPermissionProvider,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              _AppSettingsSection(
                key: const Key('settingsSection-activity'),
                title: '내 활동',
                children: [
                  _AppSettingsActionTile(
                    key: const Key('myReportsSettingsButton'),
                    title: '내 제보',
                    onTap: widget.onOpenMyReports,
                  ),
                ],
              ),
              _AppSettingsSection(
                key: const Key('settingsSection-help-privacy'),
                title: '서비스 정보 및 도움말',
                children: [
                  _AppSettingsActionTile(
                    key: const Key('settingsServiceInfoButton'),
                    title: '서비스 정보',
                    onTap: widget.onOpenServiceInfo,
                  ),
                  _AppSettingsActionTile(
                    key: const Key('settingsSupportPrivacyButton'),
                    title: '도움말',
                    onTap: widget.onOpenSupportAccess,
                  ),
                  _AppSettingsActionTile(
                    key: const Key('settingsInquiryButton'),
                    title: '문의하기',
                    onTap: widget.onOpenInquiry,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _updateViewPreferences(
    OnboardingViewPreferences preferences,
  ) async {
    final previous = _viewPreferences;
    setState(() {
      _viewPreferences = preferences;
    });
    try {
      await widget.onViewPreferencesChanged(preferences);
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '설정 화면 보기 옵션 저장 중 예외가 발생했습니다.',
      );
      if (!mounted) {
        return;
      }
      if (_isSameViewPreferences(_viewPreferences, preferences)) {
        setState(() {
          _viewPreferences = previous;
        });
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('설정을 저장하지 못했어요. 이전 값으로 되돌렸어요.')),
      );
    }
  }
}

class _AppSettingsSectionHeader extends StatelessWidget {
  const _AppSettingsSectionHeader({
    required this.title,
    super.key,
  });

  final String title;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return ColoredBox(
      key: Key('settingsSectionHeader-$title'),
      color: EasySubwayAccessibleColors.scaffoldSurface,
      child: SizedBox(
        width: double.infinity,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 2),
          child: Semantics(
            header: true,
            child: Text(
              title,
              style: textTheme.bodyMedium?.copyWith(
                color: EasySubwayAccessibleColors.secondaryText,
                fontWeight: FontWeight.w700,
                height: 1.25,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MobilityHeroBlock extends StatelessWidget {
  const _MobilityHeroBlock({
    required this.preset,
    required this.walkingPace,
    required this.facilityConstraint,
    required this.onWalkingPaceSelected,
    required this.onFacilityConstraintSelected,
    required this.onOpenMobilityProfile,
  });

  final MobilityPreset preset;
  final WalkingPace walkingPace;
  final FacilityConstraint facilityConstraint;
  final ValueChanged<WalkingPace> onWalkingPaceSelected;
  final ValueChanged<FacilityConstraint> onFacilityConstraintSelected;
  final VoidCallback onOpenMobilityProfile;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final summaryName =
        _summaryTitle(preset, walkingPace, facilityConstraint);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        key: const Key('settingsHeroBlock-mobility'),
        decoration: BoxDecoration(
          color: EasySubwayAccessibleColors.surface,
          borderRadius: BorderRadius.circular(EasySubwayRadius.card),
          border: Border.all(color: EasySubwayAccessibleColors.line),
        ),
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              button: true,
              label: summaryName,
              onTap: onOpenMobilityProfile,
              child: ExcludeSemantics(
                child: Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    key: const Key('mobilityProfileButton'),
                    onTap: onOpenMobilityProfile,
                    borderRadius: BorderRadius.circular(
                      EasySubwayRadius.control,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 0),
                      child: Row(
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color:
                                  EasySubwayAccessibleColors.surfaceBrandChrome,
                              borderRadius: BorderRadius.circular(
                                EasySubwayRadius.control,
                              ),
                            ),
                            alignment: Alignment.center,
                            child: Icon(
                              _heroIcon(preset, walkingPace, facilityConstraint),
                              size: 18,
                              color: EasySubwayAccessibleColors.primary,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  summaryName,
                                  style: textTheme.titleMedium?.copyWith(
                                    color: EasySubwayAccessibleColors.text,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15,
                                    height: 1.2,
                                  ),
                                ),
                                const SizedBox(height: 1),
                                Text(
                                  _summarySubtitle(
                                    walkingPace,
                                    facilityConstraint,
                                  ),
                                  style: textTheme.bodySmall?.copyWith(
                                    color: EasySubwayAccessibleColors.mutedText,
                                    fontWeight: FontWeight.w500,
                                    fontSize: 11,
                                    height: 1.15,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: EasySubwayAccessibleColors.surfaceSubtle,
                              borderRadius: BorderRadius.circular(
                                EasySubwayRadius.control,
                              ),
                            ),
                            alignment: Alignment.center,
                            child: const Icon(
                              Icons.tune_rounded,
                              size: 16,
                              color: EasySubwayAccessibleColors.secondaryText,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const Divider(
              height: 10,
              thickness: 1,
              color: EasySubwayAccessibleColors.line,
            ),
            Text(
              '보행 속도',
              style: textTheme.labelLarge?.copyWith(
                color: EasySubwayAccessibleColors.secondaryText,
                fontWeight: FontWeight.w700,
                fontSize: 11.5,
              ),
            ),
            const SizedBox(height: 3),
            Row(
              children: [
                Expanded(
                  child: _SegmentButton(
                    buttonKey: const Key('walkingSpeedSegment-slow'),
                    icon: Icons.nordic_walking_rounded,
                    title: '느린 걸음',
                    subtitle: '3.5km/h',
                    selected: walkingPace == WalkingPace.slow,
                    onTap: () => onWalkingPaceSelected(WalkingPace.slow),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _SegmentButton(
                    buttonKey: const Key('walkingSpeedSegment-standard'),
                    icon: Icons.directions_walk_rounded,
                    title: '보통 걸음',
                    subtitle: '4.5km/h',
                    selected: walkingPace == WalkingPace.standard,
                    onTap: () => onWalkingPaceSelected(WalkingPace.standard),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _SegmentButton(
                    buttonKey: const Key('walkingSpeedSegment-fast'),
                    icon: Icons.directions_run_rounded,
                    title: '빠른 걸음',
                    subtitle: '6.0km/h',
                    selected: walkingPace == WalkingPace.fast,
                    onTap: () => onWalkingPaceSelected(WalkingPace.fast),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            const Divider(
              height: 10,
              thickness: 1,
              color: EasySubwayAccessibleColors.line,
            ),
            const SizedBox(height: 2),
            Text(
              '이동 편의 (시설 제약)',
              style: textTheme.labelLarge?.copyWith(
                color: EasySubwayAccessibleColors.secondaryText,
                fontWeight: FontWeight.w700,
                fontSize: 11.5,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: _SegmentButton(
                    buttonKey: const Key('facilitySegment-standard'),
                    icon: Icons.directions_walk_rounded,
                    title: '일반',
                    subtitle: '계단 포함',
                    selected: facilityConstraint == FacilityConstraint.none,
                    onTap: () =>
                        onFacilityConstraintSelected(FacilityConstraint.none),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _SegmentButton(
                    buttonKey: const Key('facilitySegment-noStairs'),
                    icon: Icons.elevator_rounded,
                    title: '계단 없이',
                    subtitle: '에스컬레이터·승강기',
                    selected: facilityConstraint == FacilityConstraint.noStairs,
                    onTap: () =>
                        onFacilityConstraintSelected(FacilityConstraint.noStairs),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _SegmentButton(
                    buttonKey: const Key('facilitySegment-stepFree'),
                    icon: Icons.accessible_forward_rounded,
                    title: '휠체어·유모차',
                    subtitle: '승강기 전용',
                    selected:
                        facilityConstraint == FacilityConstraint.elevatorOnly,
                    onTap: () => onFacilityConstraintSelected(
                      FacilityConstraint.elevatorOnly,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _summaryTitle(
    MobilityPreset preset,
    WalkingPace pace,
    FacilityConstraint constraint,
  ) {
    if (constraint == FacilityConstraint.none) {
      return switch (pace) {
        WalkingPace.slow => '천천히',
        WalkingPace.standard => '보통 걸음',
        WalkingPace.fast => '빠른 걸음',
      };
    }
    return mobilityPresetDisplayName(preset);
  }

  static IconData _heroIcon(
    MobilityPreset preset,
    WalkingPace pace,
    FacilityConstraint constraint,
  ) {
    if (constraint == FacilityConstraint.none) {
      return walkingPaceIcon(pace);
    }
    return facilityConstraintIcon(constraint);
  }

  static String _summarySubtitle(
    WalkingPace pace,
    FacilityConstraint constraint,
  ) {
    final paceText =
        '${walkingPaceDisplayName(pace)} (${walkingPaceSpeedLabel(pace)})';
    final facilityText =
        '${facilityConstraintDisplayName(constraint)} (${facilityConstraintDescription(constraint)})';
    return '$paceText · $facilityText';
  }
}

class _SegmentButton extends StatelessWidget {
  const _SegmentButton({
    required this.buttonKey,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final Key buttonKey;
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final primaryColor = EasySubwayAccessibleColors.primary;
    final borderColor =
        selected ? primaryColor : EasySubwayAccessibleColors.line;
    final backgroundColor = selected
        ? EasySubwayAccessibleColors.surfaceBrandChrome
        : EasySubwayAccessibleColors.surface;

    final semanticLabel = '$title, $subtitle';
    return Semantics(
      button: true,
      selected: selected,
      label: semanticLabel,
      onTap: onTap,
      child: ExcludeSemantics(
        child: Material(
          key: buttonKey,
          color: backgroundColor,
          borderRadius: BorderRadius.circular(EasySubwayRadius.control),
          child: InkWell(
            onTap: () {
              unawaited(HapticFeedback.selectionClick());
              onTap();
            },
            borderRadius: BorderRadius.circular(EasySubwayRadius.control),
            child: Container(
              constraints: const BoxConstraints(minHeight: 48),
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 3),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(EasySubwayRadius.control),
                border: Border.all(
                  color: borderColor,
                  width: selected ? 1.5 : 1.0,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    icon,
                    size: 18,
                    color: selected
                        ? primaryColor
                        : EasySubwayAccessibleColors.contentSecondary,
                  ),
                  const SizedBox(height: 2),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      title,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodyMedium?.copyWith(
                        color: selected
                            ? primaryColor
                            : EasySubwayAccessibleColors.text,
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w600,
                        fontSize: 12,
                        height: 1.15,
                      ),
                    ),
                  ),
                  const SizedBox(height: 1),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      subtitle,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.labelSmall?.copyWith(
                        color: selected
                            ? primaryColor
                            : EasySubwayAccessibleColors.mutedText,
                        fontSize: 9.5,
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w500,
                        height: 1.1,
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

class _AppSettingsSection extends StatelessWidget {
  const _AppSettingsSection({
    required this.title,
    required this.children,
    super.key,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _AppSettingsSectionHeader(title: title),
        for (var index = 0; index < children.length; index++) ...[
          children[index],
          if (index < children.length - 1)
            const Divider(
              height: 1,
              thickness: 1,
              indent: 20,
              endIndent: 20,
              color: EasySubwayAccessibleColors.line,
            ),
        ],
      ],
    );
  }
}

class _AppSettingsActionTile extends StatelessWidget {
  const _AppSettingsActionTile({
    required this.title,
    required this.onTap,
    super.key,
  });

  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: title,
      onTap: onTap,
      child: ExcludeSemantics(
        child: Material(
          type: MaterialType.transparency,
          child: ListTile(
            onTap: onTap,
            minVerticalPadding: 12,
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            tileColor: Colors.transparent,
            title: Text(
              title,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: EasySubwayAccessibleColors.text,
                fontWeight: FontWeight.w700,
                height: 1.25,
              ),
            ),
            trailing: const Icon(
              Icons.chevron_right,
              color: EasySubwayAccessibleColors.disclosure,
            ),
          ),
        ),
      ),
    );
  }
}

class _AppSettingsPreferenceTile extends StatelessWidget {
  const _AppSettingsPreferenceTile({
    required this.title,
    required this.enabled,
    required this.onChanged,
    super.key,
  });

  final String title;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final value = enabled ? '켜짐' : '꺼짐';
    final action = enabled ? '끄기' : '켜기';
    final semanticLabel = '$title, $value, 두 번 탭해 $action';
    return Semantics(
      label: semanticLabel,
      toggled: enabled,
      onTap: () => onChanged(!enabled),
      child: ExcludeSemantics(
        child: Material(
          type: MaterialType.transparency,
          child: ListTile(
            onTap: () => onChanged(!enabled),
            minVerticalPadding: 14,
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            tileColor: Colors.transparent,
            title: Text(
              title,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: EasySubwayAccessibleColors.text,
                fontWeight: FontWeight.w700,
                height: 1.25,
              ),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: EasySubwayAccessibleColors.text,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 8),
                Switch(
                  value: enabled,
                  onChanged: onChanged,
                  activeThumbColor:
                      EasySubwayAccessibleColors.interactionOnPrimary,
                  activeTrackColor: EasySubwayAccessibleColors.switchActiveTrack,
                  inactiveThumbColor:
                      EasySubwayAccessibleColors.interactionOnPrimary,
                  inactiveTrackColor:
                      EasySubwayAccessibleColors.switchInactiveTrack,
                  materialTapTargetSize: MaterialTapTargetSize.padded,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

bool _isSameViewPreferences(
  OnboardingViewPreferences left,
  OnboardingViewPreferences right,
) {
  return left.highContrastEnabled == right.highContrastEnabled &&
      left.simpleViewEnabled == right.simpleViewEnabled;
}
