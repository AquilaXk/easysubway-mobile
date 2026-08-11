import 'package:flutter/material.dart';

import '../../../accessible_design.dart';

class NetworkMapLoadFailure extends StatelessWidget {
  const NetworkMapLoadFailure({required this.onRetry, super.key});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: AccessibleStateCard(
          icon: Icons.map_outlined,
          title: '노선도를 불러오지 못했어요',
          subtitle: '네트워크 상태를 확인한 뒤 다시 시도하거나 역명으로 검색해 주세요.',
          actions: [
            FilledButton.icon(
              key: const Key('networkMapRetryButton'),
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('다시 시도'),
            ),
          ],
        ),
      ),
    );
  }
}

class OriginalRouteMapUnavailable extends StatelessWidget {
  const OriginalRouteMapUnavailable({super.key});

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: EasySubwayAccessibleColors.surfaceDefault,
      child: Center(
        child: Text(
          '노선도를 불러오지 못했어요',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
