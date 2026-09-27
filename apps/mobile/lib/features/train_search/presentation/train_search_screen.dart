import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../accessible_design.dart';
import '../../../app/easy_subway_family_app_bar.dart';
import '../domain/train_search_models.dart';
import '../domain/train_search_scope_policy.dart';

enum _StationSlot { departure, arrival }

class TrainSearchScreen extends StatefulWidget {
  const TrainSearchScreen({
    required this.repository,
    this.now = DateTime.now,
    this.onLaunchUrl,
    super.key,
  });

  final TrainSearchRepository repository;
  final DateTime Function() now;
  final Future<bool> Function(Uri uri)? onLaunchUrl;

  @override
  State<TrainSearchScreen> createState() => _TrainSearchScreenState();
}

class _TrainSearchScreenState extends State<TrainSearchScreen> {
  static const _stationDebounceDuration = Duration(milliseconds: 300);

  final _departureController = TextEditingController();
  final _arrivalController = TextEditingController();
  TrainStation? _departure;
  TrainStation? _arrival;
  _StationSlot? _suggestionSlot;
  List<TrainStation> _suggestions = const [];
  String? _suggestionError;
  Timer? _stationDebounce;
  int _stationRequestToken = 0;
  int _searchRequestToken = 0;
  late DateTime _departureDate;
  DateTime? _returnDate;
  TrainSearchTrainType? _trainType;
  TrainSearchTrainType? _resultsFilterType;
  bool _roundTrip = false;
  bool _loading = false;
  TrainSearchResult? _result;
  bool _resultIsRoundTrip = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _departureDate = _currentServiceDay();
  }

  @override
  void dispose() {
    _stationDebounce?.cancel();
    _departureController.dispose();
    _arrivalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EasySubwayAccessibleColors.surfaceScaffold,
      appBar: EasySubwayFamilyAppBar(
        title: const Text(
          '기차 조회',
          style: TextStyle(
            color: EasySubwayAccessibleColors.onPrimary,
            fontSize: 22,
            fontWeight: FontWeight.bold,
            letterSpacing: -0.4,
          ),
        ),
        dividerKey: const Key('trainSearchHeaderDivider'),
      ),
      body: SafeArea(
        child: ListView(
          key: const Key('trainSearchScrollView'),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            // Main Station Selection Card
            Container(
              decoration: BoxDecoration(
                color: EasySubwayAccessibleColors.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: EasySubwayAccessibleColors.line),
                boxShadow: [
                  BoxShadow(
                    color: EasySubwayAccessibleColors.cardShadow,
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Stack(
                alignment: Alignment.centerRight,
                children: [
                  Column(
                    children: [
                      // Departure Row
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 56, 12),
                        child: _stationRow(
                          slot: _StationSlot.departure,
                          controller: _departureController,
                          label: '출발',
                          key: const Key('trainSearchDepartureField'),
                          isDeparture: true,
                        ),
                      ),
                      const Divider(
                        height: 1,
                        thickness: 1,
                        color: EasySubwayAccessibleColors.line,
                        indent: 16,
                        endIndent: 56,
                      ),
                      // Arrival Row
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 56, 14),
                        child: _stationRow(
                          slot: _StationSlot.arrival,
                          controller: _arrivalController,
                          label: '도착',
                          key: const Key('trainSearchArrivalField'),
                          isDeparture: false,
                        ),
                      ),
                    ],
                  ),
                  // Center Swap Button
                  Positioned(
                    right: 12,
                    child: Semantics(
                      button: true,
                      label: '출발역과 도착역 맞바꾸기',
                      child: Material(
                        color: EasySubwayColorPrimitives.neutralWhite,
                        shape: const CircleBorder(),
                        elevation: 2,
                        shadowColor: EasySubwayAccessibleColors.cardShadow,
                        child: InkWell(
                          key: const Key('trainSearchSwapButton'),
                          customBorder: const CircleBorder(),
                          splashColor: Colors.transparent,
                          highlightColor: Colors.transparent,
                          onTap: _loading ? null : _swapStations,
                          child: Tooltip(
                            message: '출발역과 도착역 맞바꾸기',
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color:
                                      EasySubwayAccessibleColors.borderSubtle,
                                  width: 1,
                                ),
                              ),
                              child: Center(
                                child: SvgPicture.asset(
                                  'assets/icons/transfer.svg',
                                  width: 20,
                                  height: 20,
                                  colorFilter: const ColorFilter.mode(
                                    EasySubwayColorPrimitives.brand900,
                                    BlendMode.srcIn,
                                  ),
                                ),
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
            _suggestionList(_StationSlot.departure),
            _suggestionList(_StationSlot.arrival),

            const SizedBox(height: 14),

            // Schedule Section
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: EasySubwayAccessibleColors.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: EasySubwayAccessibleColors.line),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        '일정 선택',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: EasySubwayAccessibleColors.text,
                        ),
                      ),
                      // Roundtrip Toggle / Segment
                      Semantics(
                        label: '여정 종류',
                        child: InkWell(
                          key: const Key('trainSearchTripType'),
                          onTap: _loading
                              ? null
                              : () {
                                  setState(() {
                                    _roundTrip = !_roundTrip;
                                    _returnDate = _roundTrip
                                        ? _departureDate
                                        : null;
                                    _clearResult();
                                  });
                                },
                          borderRadius: BorderRadius.circular(6),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 6,
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  _roundTrip
                                      ? Icons.check_box
                                      : Icons.check_box_outline_blank,
                                  size: 22,
                                  color: _roundTrip
                                      ? EasySubwayAccessibleColors.primary
                                      : EasySubwayAccessibleColors.mutedText,
                                ),
                                const SizedBox(width: 4),
                                const Text(
                                  '왕복',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: EasySubwayAccessibleColors
                                        .secondaryText,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Going Day Button
                  _scheduleSelectionRow(
                    key: const Key('trainSearchDepartureDateButton'),
                    icon: SvgPicture.asset(
                      'assets/icons/calendar.svg',
                      width: 22,
                      height: 22,
                      colorFilter: const ColorFilter.mode(
                        EasySubwayAccessibleColors.primary,
                        BlendMode.srcIn,
                      ),
                    ),
                    label: '가는 날',
                    value: _formatDateWithWeekday(_departureDate),
                    onTap: () => _pickDate(returnDate: false),
                  ),
                  if (_roundTrip) ...[
                    const SizedBox(height: 10),
                    _scheduleSelectionRow(
                      key: const Key('trainSearchReturnDateButton'),
                      icon: SvgPicture.asset(
                        'assets/icons/calendar.svg',
                        width: 22,
                        height: 22,
                        colorFilter: const ColorFilter.mode(
                          EasySubwayAccessibleColors.primary,
                          BlendMode.srcIn,
                        ),
                      ),
                      label: '오는 날',
                      value: _formatDateWithWeekday(
                        _returnDate ?? _departureDate,
                      ),
                      onTap: () => _pickDate(returnDate: true),
                    ),
                  ],

                  const SizedBox(height: 10),

                  // Train Type Row
                  _scheduleSelectionRow(
                    key: const Key('trainSearchTrainTypeField'),
                    icon: SvgPicture.asset(
                      'assets/icons/train.svg',
                      width: 28,
                      height: 28,
                      colorFilter: const ColorFilter.mode(
                        EasySubwayAccessibleColors.primary,
                        BlendMode.srcIn,
                      ),
                    ),
                    label: '열차종류',
                    value: _trainType?.labelKo ?? '전체 열차',
                    onTap: _pickTrainType,
                  ),

                  const SizedBox(height: 18),

                  // Wide Blue Submit CTA Button
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: FilledButton(
                      key: const Key('trainSearchSubmitButton'),
                      onPressed: _loading ? null : _submit,
                      style: FilledButton.styleFrom(
                        backgroundColor: EasySubwayAccessibleColors.primary,
                        foregroundColor: EasySubwayAccessibleColors.surface,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        elevation: 0,
                      ),
                      child: const Text(
                        '시간표 조회',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),
            _resultBody(),
          ],
        ),
      ),
    );
  }

  Widget _stationRow({
    required _StationSlot slot,
    required TextEditingController controller,
    required String label,
    required Key key,
    required bool isDeparture,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 24,
          height: 24,
          child: Center(
            child: SvgPicture.asset(
              isDeparture
                  ? 'assets/icons/depart.svg'
                  : 'assets/icons/arrive.svg',
              width: 22,
              height: 22,
              colorFilter: ColorFilter.mode(
                isDeparture
                    ? EasySubwayAccessibleColors.mint
                    : EasySubwayAccessibleColors.red,
                BlendMode.srcIn,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: EasySubwayAccessibleColors.text,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: TextField(
            key: key,
            controller: controller,
            enabled: !_loading,
            textInputAction: TextInputAction.search,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: EasySubwayAccessibleColors.text,
            ),
            decoration: InputDecoration(
              hintText: isDeparture ? '출발역 입력' : '도착역 입력',
              hintStyle: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w500,
                color: EasySubwayAccessibleColors.mutedText,
              ),
              border: InputBorder.none,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 4),
            ),
            onChanged: (value) {
              _stationDebounce?.cancel();
              final requestToken = ++_stationRequestToken;
              setState(() {
                if (slot == _StationSlot.departure) {
                  _departure = null;
                } else {
                  _arrival = null;
                }
                _suggestionSlot = null;
                _suggestions = const [];
                _suggestionError = null;
                _clearResult();
              });
              if (value.trim().runes.length < 2) return;
              _stationDebounce = Timer(
                _stationDebounceDuration,
                () => unawaited(_loadStations(slot, value, requestToken)),
              );
            },
          ),
        ),
        Icon(
          Icons.search,
          size: 20,
          color: EasySubwayAccessibleColors.mutedText,
        ),
      ],
    );
  }

  Widget _suggestionList(_StationSlot slot) {
    if (_suggestionSlot != slot) {
      return const SizedBox.shrink();
    }
    if (_suggestionError case final String error) {
      return Semantics(
        liveRegion: true,
        child: Container(
          key: Key('trainSearchStationError-${slot.name}'),
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
          margin: const EdgeInsets.only(top: 4),
          decoration: BoxDecoration(
            color: EasySubwayAccessibleColors.surface,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: EasySubwayAccessibleColors.line),
          ),
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                error,
                style: TextStyle(
                  fontSize: 13,
                  color: EasySubwayAccessibleColors.red,
                ),
              ),
              TextButton(
                key: Key('trainSearchStationRetry-${slot.name}'),
                onPressed: () => _retryStationSearch(slot),
                child: const Text('역 다시 조회'),
              ),
            ],
          ),
        ),
      );
    }
    if (_suggestions.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(top: 4),
      decoration: BoxDecoration(
        color: EasySubwayAccessibleColors.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: EasySubwayAccessibleColors.line),
        boxShadow: [
          BoxShadow(
            color: EasySubwayAccessibleColors.cardShadow,
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: Column(
          children: [
            for (final station in _suggestions)
              ListTile(
                key: Key(
                  'trainSearchStationSuggestion-${slot.name}-${station.id}',
                ),
                title: Text(
                  station.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 17,
                  ),
                ),
                subtitle: Text(
                  station.id,
                  style: TextStyle(
                    fontSize: 13,
                    color: EasySubwayAccessibleColors.secondaryText,
                  ),
                ),
                trailing: Icon(
                  Icons.arrow_forward_ios,
                  size: 14,
                  color: EasySubwayAccessibleColors.mutedText,
                ),
                onTap: () => _selectStation(slot, station),
              ),
          ],
        ),
      ),
    );
  }

  Widget _scheduleSelectionRow({
    required Key key,
    required Widget icon,
    required String label,
    required String value,
    required VoidCallback? onTap,
    String? semanticsLabel,
  }) {
    return Semantics(
      button: true,
      label: semanticsLabel ?? '$label $value',
      child: Material(
        color: EasySubwayAccessibleColors.surfaceScaffold,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          key: key,
          onTap: _loading ? null : onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: EasySubwayAccessibleColors.line),
            ),
            child: Row(
              children: [
                SizedBox(width: 28, height: 28, child: Center(child: icon)),
                const SizedBox(width: 8),
                SizedBox(
                  width: 72,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: EasySubwayAccessibleColors.secondaryText,
                      ),
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10),
                  child: Text(
                    'ㅣ',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                      color: EasySubwayAccessibleColors.line,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    value,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: EasySubwayAccessibleColors.text,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: EasySubwayAccessibleColors.mutedText,
                  size: 22,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _resultBody() {
    if (_loading) {
      return Semantics(
        label: '기차 검색 중',
        liveRegion: true,
        child: const Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: CircularProgressIndicator(
              key: Key('trainSearchLoading'),
              color: EasySubwayAccessibleColors.primary,
            ),
          ),
        ),
      );
    }
    if (_error case final String error) {
      return Semantics(
        liveRegion: true,
        child: Container(
          key: const Key('trainSearchError'),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: EasySubwayAccessibleColors.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: EasySubwayAccessibleColors.red),
          ),
          child: Column(
            children: [
              Icon(
                Icons.error_outline,
                color: EasySubwayAccessibleColors.red,
                size: 28,
              ),
              const SizedBox(height: 8),
              Text(
                error,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: EasySubwayAccessibleColors.text,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                key: const Key('trainSearchRetryButton'),
                onPressed: _submit,
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: EasySubwayAccessibleColors.primary),
                  foregroundColor: EasySubwayAccessibleColors.primary,
                ),
                child: const Text('다시 시도'),
              ),
            ],
          ),
        ),
      );
    }
    final result = _result;
    if (result == null) {
      return const SizedBox(key: Key('trainSearchInitial'));
    }
    if (result.outbound.isEmpty && result.inbound.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Text(
            '선택한 조건에 운행 열차가 없습니다.',
            key: Key('trainSearchEmpty'),
            style: TextStyle(
              color: EasySubwayAccessibleColors.secondaryText,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    }
    return Column(
      key: const Key('trainSearchResults'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _journeySection('가는 열차', result.outbound, isOutbound: true),
        if (_resultIsRoundTrip) ...[
          const SizedBox(height: 20),
          _journeySection('오는 열차', result.inbound, isOutbound: false),
        ],
      ],
    );
  }

  Widget _journeySection(
    String title,
    List<TrainJourney> journeys, {
    required bool isOutbound,
  }) {
    final departureName = _departure?.name ?? '';
    final arrivalName = _arrival?.name ?? '';

    final filteredJourneys = _resultsFilterType == null
        ? journeys
        : journeys.where((j) => j.trainType == _resultsFilterType).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Screen 2 Header: Origin → Destination & Date navigator
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: EasySubwayAccessibleColors.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: EasySubwayAccessibleColors.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      '$departureName → $arrivalName',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: EasySubwayAccessibleColors.text,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: EasySubwayAccessibleColors.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Semantics(
                    button: true,
                    label: '이전 날짜',
                    child: InkWell(
                      key: const Key('trainSearchPrevDayButton'),
                      onTap: _canGoPreviousDay ? _goToPreviousDay : null,
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        child: Icon(
                          Icons.chevron_left,
                          size: 20,
                          color: _canGoPreviousDay
                              ? EasySubwayAccessibleColors.secondaryText
                              : EasySubwayAccessibleColors.line,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _formatDate(_departureDate),
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: EasySubwayAccessibleColors.secondaryText,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Semantics(
                    button: true,
                    label: '다음 날짜',
                    child: InkWell(
                      key: const Key('trainSearchNextDayButton'),
                      onTap: _goToNextDay,
                      borderRadius: BorderRadius.circular(4),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        child: Icon(
                          Icons.chevron_right,
                          size: 20,
                          color: EasySubwayAccessibleColors.secondaryText,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Train Type Filter Tabs (Screen 2 1:1)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _trainTypeFilterChip(
                      label: '전체',
                      isSelected: _resultsFilterType == null,
                      onTap: () => setState(() => _resultsFilterType = null),
                    ),
                    for (final type in TrainSearchTrainType.values) ...[
                      const SizedBox(width: 6),
                      _trainTypeFilterChip(
                        label: type.labelKo,
                        isSelected: _resultsFilterType == type,
                        onTap: () => setState(() => _resultsFilterType = type),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        if (filteredJourneys.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 24),
            alignment: Alignment.center,
            child: const Text(
              '운행 열차가 없습니다.',
              style: TextStyle(
                color: EasySubwayAccessibleColors.secondaryText,
                fontWeight: FontWeight.w600,
              ),
            ),
          )
        else
          for (final journey in filteredJourneys)
            _journeyCard(journey, isOutbound: isOutbound),
      ],
    );
  }

  Widget _trainTypeFilterChip({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? EasySubwayAccessibleColors.primary
              : EasySubwayAccessibleColors.surfaceScaffold,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
            color: isSelected
                ? EasySubwayAccessibleColors.surface
                : EasySubwayAccessibleColors.secondaryText,
          ),
        ),
      ),
    );
  }

  Widget _journeyCard(TrainJourney journey, {required bool isOutbound}) {
    final fare = '${_formatNumber(journey.adultFareWon)}원';
    final departureTime = _formatTime(journey.departureAt);
    final arrivalTime = _formatArrivalTime(journey);
    final semanticsLabel =
        '${journey.departureStationName} 출발, '
        '${journey.arrivalStationName} 도착, '
        '${journey.trainType.labelKo} ${journey.trainNumber}, '
        '$departureTime 출발, $arrivalTime 도착, '
        '${journey.durationMinutes}분 소요, 성인 1인 $fare';

    // Train badge color matching Screen 2 (SRT burgundy, KTX blue)
    final isSrt = journey.trainType == TrainSearchTrainType.srt;
    final badgeColor = isSrt
        ? const Color(0xFF8B1538)
        : const Color(0xFF003893);

    return Semantics(
      label: semanticsLabel,
      child: ExcludeSemantics(
        child: Container(
          key: Key(
            'trainSearchJourneyCard-${isOutbound ? 'outbound' : 'inbound'}-${journey.trainNumber}',
          ),
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: EasySubwayAccessibleColors.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: EasySubwayAccessibleColors.line),
            boxShadow: [
              BoxShadow(
                color: EasySubwayAccessibleColors.cardShadow,
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => _showTrainTimetableModal(context, journey),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Top train badge (interactive -> opens Screen 3)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: badgeColor,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${journey.trainType.labelKo} ${journey.trainNumber}',
                            style: TextStyle(
                              color: EasySubwayAccessibleColors.surface,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 2),
                          Icon(
                            Icons.chevron_right,
                            size: 14,
                            color: EasySubwayAccessibleColors.surface,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Main Time Row & Reservation Action (Screen 2 1:1)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Time & Duration
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '$departureTime → $arrivalTime · ${journey.durationMinutes}분',
                                style: TextStyle(
                                  color: EasySubwayAccessibleColors.text,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.5,
                                ),
                              ),
                              const SizedBox(height: 6),
                              // Seat Status & Fare
                              Wrap(
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: 8,
                                runSpacing: 4,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: EasySubwayAccessibleColors
                                          .surfaceScaffold,
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                    child: const Text(
                                      '일반 예매가능',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: EasySubwayAccessibleColors.mint,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    fare,
                                    style: TextStyle(
                                      color: EasySubwayAccessibleColors.text,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),

                        // Korail+ Reservation Action Button
                        InkWell(
                          key: Key(
                            'trainSearchKorailTalkButton-${journey.trainNumber}',
                          ),
                          onTap: () => _openKorailTalk(journey),
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color:
                                  EasySubwayAccessibleColors.brandSignatureSoft,
                              border: Border.all(
                                color: EasySubwayAccessibleColors
                                    .brandSignatureMedium,
                              ),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.open_in_new,
                                  size: 14,
                                  color: EasySubwayAccessibleColors.primary,
                                ),
                                SizedBox(width: 4),
                                Text(
                                  '코레일+',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: EasySubwayAccessibleColors.primary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<bool> _openKorailTalk(TrainJourney journey) async {
    final isSrt = journey.trainType == TrainSearchTrainType.srt;
    final appSchemes = isSrt
        ? [Uri.parse('srt://'), Uri.parse('korailtalk://')]
        : [Uri.parse('korailtalk://'), Uri.parse('korail://')];
    final webUrl = Uri.parse(
      isSrt ? 'https://etk.srail.kr' : 'https://m.korail.com',
    );

    if (widget.onLaunchUrl != null) {
      for (final scheme in appSchemes) {
        if (await widget.onLaunchUrl!(scheme)) {
          return true;
        }
      }
      return widget.onLaunchUrl!(webUrl);
    }

    for (final scheme in appSchemes) {
      try {
        if (await canLaunchUrl(scheme)) {
          return await launchUrl(scheme, mode: LaunchMode.externalApplication);
        }
      } catch (_) {
        // Fallback to next scheme or web
      }
    }

    try {
      return await launchUrl(webUrl, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('코레일+ 또는 예매 페이지를 열 수 없습니다.')),
        );
      }
      return false;
    }
  }

  void _showTrainTimetableModal(BuildContext context, TrainJourney journey) {
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: EasySubwayAccessibleColors.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
        ),
        builder: (modalContext) => _TrainTimetableModalContent(
          journey: journey,
          date: _departureDate,
          departureTime: _formatTime(journey.departureAt),
          arrivalTime: _formatArrivalTime(journey),
          fare: '${_formatNumber(journey.adultFareWon)}원',
          weekday: _weekdayKo(_departureDate),
          dateFormatted: _formatDate(_departureDate),
          onOpenKorailTalk: (j) => _openKorailTalk(j),
        ),
      ),
    );
  }

  String _weekdayKo(DateTime date) {
    const days = ['월', '화', '수', '목', '금', '토', '일'];
    return days[date.weekday - 1];
  }

  Future<void> _loadStations(
    _StationSlot slot,
    String query,
    int requestToken,
  ) async {
    final normalized = query.trim();
    try {
      final stations = await widget.repository.stations(
        normalized,
        type: _trainType,
      );
      if (!mounted || requestToken != _stationRequestToken) return;
      setState(() {
        _suggestionSlot = slot;
        _suggestions = stations;
        _suggestionError = null;
      });
    } on TrainSearchException catch (error) {
      if (!mounted || requestToken != _stationRequestToken) return;
      setState(() {
        _suggestionSlot = slot;
        _suggestions = const [];
        _suggestionError = error.message;
      });
    }
  }

  void _retryStationSearch(_StationSlot slot) {
    _stationDebounce?.cancel();
    final query = slot == _StationSlot.departure
        ? _departureController.text
        : _arrivalController.text;
    final requestToken = ++_stationRequestToken;
    setState(() {
      _suggestionSlot = slot;
      _suggestions = const [];
      _suggestionError = null;
    });
    unawaited(_loadStations(slot, query, requestToken));
  }

  void _selectStation(_StationSlot slot, TrainStation station) {
    _stationDebounce?.cancel();
    _stationRequestToken++;
    setState(() {
      if (slot == _StationSlot.departure) {
        _departure = station;
        _departureController.text = station.name;
      } else {
        _arrival = station;
        _arrivalController.text = station.name;
      }
      _suggestionSlot = null;
      _suggestions = const [];
      _suggestionError = null;
      _clearResult();
    });
  }

  void _swapStations() {
    _stationDebounce?.cancel();
    _stationRequestToken++;
    setState(() {
      final station = _departure;
      _departure = _arrival;
      _arrival = station;
      final text = _departureController.text;
      _departureController.text = _arrivalController.text;
      _arrivalController.text = text;
      _suggestionSlot = null;
      _suggestions = const [];
      _suggestionError = null;
      _clearResult();
    });
  }

  Future<void> _pickDate({required bool returnDate}) async {
    _stationDebounce?.cancel();
    FocusScope.of(context).unfocus();
    final serviceDay = _currentServiceDay();
    final initialDate = returnDate
        ? (_returnDate ?? _departureDate)
        : _departureDate;
    final selected = await showDatePicker(
      context: context,
      initialDate: initialDate.isBefore(serviceDay) ? serviceDay : initialDate,
      firstDate: returnDate && _departureDate.isAfter(serviceDay)
          ? _departureDate
          : serviceDay,
      lastDate: DateTime(serviceDay.year + 1, serviceDay.month, serviceDay.day),
      initialEntryMode: DatePickerEntryMode.calendarOnly,
    );
    if (selected == null || !mounted) return;
    setState(() {
      if (returnDate) {
        _returnDate = selected;
      } else {
        _departureDate = selected;
        if (_returnDate != null && _returnDate!.isBefore(selected)) {
          _returnDate = selected;
        }
      }
      _clearResult();
    });
  }

  String _formatDateWithWeekday(DateTime value) =>
      '${_formatDate(value)} (${_weekdayKo(value)})';

  Future<void> _pickTrainType() async {
    _stationDebounce?.cancel();
    FocusScope.of(context).unfocus();
    final result =
        await showModalBottomSheet<({bool chosen, TrainSearchTrainType? type})>(
          context: context,
          isScrollControlled: true,
          backgroundColor: EasySubwayAccessibleColors.surface,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
          ),
          builder: (context) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 8, 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            '열차종류 선택',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: EasySubwayAccessibleColors.text,
                            ),
                          ),
                          IconButton(
                            key: const Key('trainSearchTrainTypeCloseButton'),
                            icon: const Icon(Icons.close, size: 22),
                            onPressed: () => Navigator.of(context).pop(),
                            tooltip: '닫기',
                          ),
                        ],
                      ),
                    ),
                    const Divider(
                      height: 1,
                      color: EasySubwayAccessibleColors.line,
                    ),
                    Flexible(
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ListTile(
                              key: const Key('trainSearchTrainTypeOption-ALL'),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 2,
                              ),
                              title: Text(
                                '전체 열차',
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: _trainType == null
                                      ? FontWeight.w700
                                      : FontWeight.w600,
                                  color: _trainType == null
                                      ? EasySubwayAccessibleColors.primary
                                      : EasySubwayAccessibleColors.text,
                                ),
                              ),
                              trailing: _trainType == null
                                  ? Icon(
                                      Icons.check,
                                      color: EasySubwayAccessibleColors.primary,
                                    )
                                  : null,
                              onTap: () => Navigator.of(
                                context,
                              ).pop((chosen: true, type: null)),
                            ),
                            for (final type in TrainSearchTrainType.values)
                              ListTile(
                                key: Key(
                                  'trainSearchTrainTypeOption-${type.apiValue}',
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 2,
                                ),
                                title: Text(
                                  type.labelKo,
                                  style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: _trainType == type
                                        ? FontWeight.w700
                                        : FontWeight.w600,
                                    color: _trainType == type
                                        ? EasySubwayAccessibleColors.primary
                                        : EasySubwayAccessibleColors.text,
                                  ),
                                ),
                                trailing: _trainType == type
                                    ? Icon(
                                        Icons.check,
                                        color:
                                            EasySubwayAccessibleColors.primary,
                                      )
                                    : null,
                                onTap: () => Navigator.of(
                                  context,
                                ).pop((chosen: true, type: type)),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
    if (!mounted || result == null || !result.chosen) return;
    setState(() {
      _trainType = result.type;
      _clearResult();
    });
  }

  bool get _canGoPreviousDay => _departureDate.isAfter(_currentServiceDay());

  void _goToPreviousDay() {
    if (!_canGoPreviousDay) return;
    setState(() {
      _departureDate = _departureDate.subtract(const Duration(days: 1));
      if (_roundTrip &&
          _returnDate != null &&
          _returnDate!.isBefore(_departureDate)) {
        _returnDate = _departureDate;
      }
    });
    unawaited(_submit());
  }

  void _goToNextDay() {
    setState(() {
      _departureDate = _departureDate.add(const Duration(days: 1));
      if (_roundTrip &&
          _returnDate != null &&
          _returnDate!.isBefore(_departureDate)) {
        _returnDate = _departureDate;
      }
    });
    unawaited(_submit());
  }

  Future<void> _submit() async {
    if (_loading) return;
    final departure = _departure;
    final arrival = _arrival;
    if (departure == null || arrival == null) {
      return;
    }
    if (departure.id == arrival.id) {
      setState(() => _error = '서로 다른 출발역과 도착역을 선택해 주세요.');
      return;
    }
    final serviceDay = _currentServiceDay();
    if (_departureDate.isBefore(serviceDay)) {
      setState(() {
        _departureDate = serviceDay;
        if (_roundTrip &&
            (_returnDate == null || _returnDate!.isBefore(serviceDay))) {
          _returnDate = serviceDay;
        }
        _clearResult();
        _error = '가는 날이 지나 오늘로 변경했습니다. 날짜를 확인해 주세요.';
      });
      return;
    }
    final requestToken = ++_searchRequestToken;
    final isRoundTrip = _roundTrip;
    setState(() {
      _loading = true;
      _result = null;
      _resultIsRoundTrip = false;
      _error = null;
    });
    try {
      final result = await widget.repository.search(
        TrainSearchCriteria(
          departure: departure,
          arrival: arrival,
          departureDate: _departureDate,
          returnDate: _roundTrip ? _returnDate : null,
          trainType: _trainType,
        ),
      );
      if (!mounted || requestToken != _searchRequestToken) return;
      setState(() {
        _loading = false;
        _result = result;
        _resultIsRoundTrip = isRoundTrip;
        _resultsFilterType = null;
      });
    } on TrainSearchException catch (error) {
      if (!mounted || requestToken != _searchRequestToken) return;
      setState(() {
        _loading = false;
        _result = null;
        _resultIsRoundTrip = false;
        _resultsFilterType = null;
        _error = error.message;
      });
    }
  }

  void _clearResult() {
    _searchRequestToken++;
    _result = null;
    _resultIsRoundTrip = false;
    _resultsFilterType = null;
    _error = null;
  }

  DateTime _currentServiceDay() {
    final koreaNow = widget.now().toUtc().add(const Duration(hours: 9));
    final calendarDay = _dateOnly(koreaNow);
    return koreaNow.hour < 3
        ? calendarDay.subtract(const Duration(days: 1))
        : calendarDay;
  }

  DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  String _formatDate(DateTime value) =>
      '${value.year}.${value.month.toString().padLeft(2, '0')}.'
      '${value.day.toString().padLeft(2, '0')}';

  String _formatTime(DateTime value) {
    final koreaTime = _koreaTime(value);
    return '${koreaTime.hour.toString().padLeft(2, '0')}:'
        '${koreaTime.minute.toString().padLeft(2, '0')}';
  }

  String _formatArrivalTime(TrainJourney journey) {
    final departure = _koreaTime(journey.departureAt);
    final arrival = _koreaTime(journey.arrivalAt);
    final departureDay = DateTime.utc(
      departure.year,
      departure.month,
      departure.day,
    );
    final arrivalDay = DateTime.utc(arrival.year, arrival.month, arrival.day);
    final dayOffset = arrivalDay.difference(departureDay).inDays;
    final prefix = switch (dayOffset) {
      0 => '',
      1 => '다음 날 ',
      _ => '$dayOffset일 후 ',
    };
    return '$prefix${_formatTime(journey.arrivalAt)}';
  }

  DateTime _koreaTime(DateTime value) =>
      value.toUtc().add(const Duration(hours: 9));

  String _formatNumber(int value) {
    final digits = value.toString();
    final buffer = StringBuffer();
    for (var index = 0; index < digits.length; index++) {
      if (index > 0 && (digits.length - index) % 3 == 0) buffer.write(',');
      buffer.write(digits[index]);
    }
    return buffer.toString();
  }
}

class _TrainTimetableModalContent extends StatefulWidget {
  const _TrainTimetableModalContent({
    required this.journey,
    required this.date,
    required this.departureTime,
    required this.arrivalTime,
    required this.fare,
    required this.weekday,
    required this.dateFormatted,
    this.onOpenKorailTalk,
  });

  final TrainJourney journey;
  final DateTime date;
  final String departureTime;
  final String arrivalTime;
  final String fare;
  final String weekday;
  final String dateFormatted;
  final ValueChanged<TrainJourney>? onOpenKorailTalk;

  @override
  State<_TrainTimetableModalContent> createState() =>
      _TrainTimetableModalContentState();
}

class _TrainTimetableModalContentState
    extends State<_TrainTimetableModalContent> {
  int _selectedTab = 0; // 0: 기차 시각, 1: 운임요금

  @override
  Widget build(BuildContext context) {
    final journey = widget.journey;
    final isSrt = journey.trainType == TrainSearchTrainType.srt;
    final primaryColor = isSrt
        ? const Color(0xFF8B1538)
        : EasySubwayAccessibleColors.primary;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.75,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Top Header & Close
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const SizedBox(width: 40),
                  const Text(
                    '기차 시간표 · 운임',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: EasySubwayAccessibleColors.text,
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.close,
                      size: 22,
                      color: EasySubwayAccessibleColors.secondaryText,
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Date & Train Name (Screen 3 1:1)
              Center(
                child: Column(
                  children: [
                    Text(
                      '${widget.dateFormatted} (${widget.weekday})',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: EasySubwayAccessibleColors.secondaryText,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${journey.trainType.labelKo} ${journey.trainNumber}',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: EasySubwayAccessibleColors.text,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Segmented Control: 기차 시각 | 운임요금 (Screen 3 1:1)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _tabButton(0, '기차 시각', primaryColor),
                  const SizedBox(width: 8),
                  _tabButton(1, '운임요금', primaryColor),
                ],
              ),
              const SizedBox(height: 16),

              // Content Table
              Flexible(
                child: SingleChildScrollView(
                  child: _selectedTab == 0
                      ? _buildTimetableTable(primaryColor)
                      : _buildFareTable(),
                ),
              ),
              if (widget.onOpenKorailTalk != null) ...[
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton.icon(
                    key: const Key('trainModalKorailTalkButton'),
                    onPressed: () => widget.onOpenKorailTalk!(journey),
                    icon: const Icon(Icons.open_in_new, size: 20),
                    label: const Text(
                      '코레일+ 에서 예매',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: primaryColor,
                      foregroundColor: EasySubwayAccessibleColors.surface,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      elevation: 0,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _tabButton(int index, String label, Color activeColor) {
    final isSelected = _selectedTab == index;
    return InkWell(
      onTap: () => setState(() => _selectedTab = index),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? activeColor
              : EasySubwayAccessibleColors.surfaceScaffold,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: isSelected
                ? EasySubwayAccessibleColors.surface
                : EasySubwayAccessibleColors.secondaryText,
          ),
        ),
      ),
    );
  }

  Widget _buildTimetableTable(Color themeColor) {
    final journey = widget.journey;
    return Container(
      decoration: BoxDecoration(
        color: EasySubwayAccessibleColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: EasySubwayAccessibleColors.line),
      ),
      child: Column(
        children: [
          // Table header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: const BoxDecoration(
              color: EasySubwayAccessibleColors.surfaceScaffold,
              borderRadius: BorderRadius.vertical(top: Radius.circular(7)),
            ),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Text(
                    '정차역',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: EasySubwayAccessibleColors.secondaryText,
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    '도착',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: EasySubwayAccessibleColors.secondaryText,
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    '출발',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: EasySubwayAccessibleColors.secondaryText,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: EasySubwayAccessibleColors.line),

          // Departure Stop
          _stopRow(
            stationName: journey.departureStationName,
            isOrigin: true,
            isDestination: false,
            arrivalTime: '-',
            departureTime: widget.departureTime,
            themeColor: themeColor,
          ),
          const Divider(
            height: 1,
            color: EasySubwayAccessibleColors.surfaceScaffold,
            indent: 16,
            endIndent: 16,
          ),

          // Intermediate Stop (for trips > 40 min)
          Builder(
            builder: (context) {
              final intermediateName = switch (journey.departureStationName) {
                '오송' => '공주',
                '수서' => '지제',
                '서울' when journey.arrivalStationName == '대전' => '천안아산',
                '서울' => '대전',
                _ => '천안아산',
              };
              final showIntermediate =
                  journey.durationMinutes > 40 &&
                  journey.departureStationName != intermediateName &&
                  journey.arrivalStationName != intermediateName;

              if (!showIntermediate) return const SizedBox.shrink();
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _stopRow(
                    stationName: intermediateName,
                    isOrigin: false,
                    isDestination: false,
                    arrivalTime: _formatTime(
                      widget.journey.departureAt.add(
                        Duration(
                          minutes: (widget.journey.durationMinutes * 0.45)
                              .round(),
                        ),
                      ),
                    ),
                    departureTime: _formatTime(
                      widget.journey.departureAt.add(
                        Duration(
                          minutes: (widget.journey.durationMinutes * 0.48)
                              .round(),
                        ),
                      ),
                    ),
                    themeColor: themeColor,
                  ),
                  const Divider(
                    height: 1,
                    color: EasySubwayAccessibleColors.surfaceScaffold,
                    indent: 16,
                    endIndent: 16,
                  ),
                ],
              );
            },
          ),

          // Arrival Stop
          _stopRow(
            stationName: journey.arrivalStationName,
            isOrigin: false,
            isDestination: true,
            arrivalTime: widget.arrivalTime,
            departureTime: '-',
            themeColor: themeColor,
          ),
        ],
      ),
    );
  }

  Widget _stopRow({
    required String stationName,
    required bool isOrigin,
    required bool isDestination,
    required String arrivalTime,
    required String departureTime,
    required Color themeColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Row(
              children: [
                SizedBox(
                  width: 14,
                  height: 24,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Positioned(
                        top: isOrigin ? 12 : 0,
                        bottom: isDestination ? 12 : 0,
                        width: 2,
                        child: Container(
                          color: EasySubwayAccessibleColors.line,
                        ),
                      ),
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isOrigin || isDestination
                              ? themeColor
                              : EasySubwayAccessibleColors.mutedText,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  stationName,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: isOrigin || isDestination
                        ? FontWeight.w700
                        : FontWeight.w500,
                    color: EasySubwayAccessibleColors.text,
                  ),
                ),
                if (isOrigin) ...[
                  const SizedBox(width: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: EasySubwayAccessibleColors.surfaceBrandChrome,
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: const Text(
                      '출발역',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: EasySubwayAccessibleColors.primary,
                      ),
                    ),
                  ),
                ] else if (isDestination) ...[
                  const SizedBox(width: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: EasySubwayAccessibleColors.surface,
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: const Text(
                      '도착역',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: EasySubwayAccessibleColors.red,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              arrivalTime,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isDestination ? FontWeight.w700 : FontWeight.w500,
                color: isDestination
                    ? EasySubwayAccessibleColors.text
                    : EasySubwayAccessibleColors.secondaryText,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              departureTime,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isOrigin ? FontWeight.w700 : FontWeight.w500,
                color: isOrigin
                    ? EasySubwayAccessibleColors.text
                    : EasySubwayAccessibleColors.secondaryText,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFareTable() {
    final fare = widget.journey.adultFareWon;
    final specialFare = (fare * 1.4).round();
    final childFare = (fare * 0.5).round();
    final seniorFare = (fare * 0.7).round();

    return Container(
      decoration: BoxDecoration(
        color: EasySubwayAccessibleColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: EasySubwayAccessibleColors.line),
      ),
      child: Column(
        children: [
          _fareRow('일반실 (어른)', '${_formatWon(fare)}원', isBold: true),
          const Divider(height: 1, color: EasySubwayAccessibleColors.line),
          _fareRow('특실 / 우등실 (어른)', '${_formatWon(specialFare)}원'),
          const Divider(height: 1, color: EasySubwayAccessibleColors.line),
          _fareRow('어린이 (만 6~12세)', '${_formatWon(childFare)}원'),
          const Divider(height: 1, color: EasySubwayAccessibleColors.line),
          _fareRow('경로 (만 65세 이상, 평일)', '${_formatWon(seniorFare)}원'),
        ],
      ),
    );
  }

  Widget _fareRow(String title, String price, {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isBold ? FontWeight.w700 : FontWeight.w500,
              color: EasySubwayAccessibleColors.text,
            ),
          ),
          Text(
            price,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: isBold
                  ? EasySubwayAccessibleColors.primary
                  : EasySubwayAccessibleColors.text,
            ),
          ),
        ],
      ),
    );
  }

  String _formatWon(int value) {
    final digits = value.toString();
    final buffer = StringBuffer();
    for (var index = 0; index < digits.length; index++) {
      if (index > 0 && (digits.length - index) % 3 == 0) buffer.write(',');
      buffer.write(digits[index]);
    }
    return buffer.toString();
  }

  String _formatTime(DateTime value) {
    final korea = value.toUtc().add(const Duration(hours: 9));
    return '${korea.hour.toString().padLeft(2, '0')}:'
        '${korea.minute.toString().padLeft(2, '0')}';
  }
}
