import 'package:flutter/material.dart';

import '../application/network_map_nearby_panel_state.dart';

typedef NetworkMapNearbyPanelSuccessContent = ({
  Widget stationBar,
  Widget dataPanel,
});

typedef NetworkMapNearbyPanelSuccessBuilder =
    NetworkMapNearbyPanelSuccessContent Function(BuildContext context);

/// 주변역 패널의 loading/success 전환과 성공 content layout을 소유한다.
///
/// Stations·Realtime concrete widgets는 app composition이 typed record로
/// 제공하고, success 상태에서만 builder를 호출한다.
class NetworkMapNearbyPanelContent extends StatelessWidget {
  const NetworkMapNearbyPanelContent({
    required this.status,
    required this.successBuilder,
    super.key,
  });

  final NetworkMapNearbyPanelStatus status;
  final NetworkMapNearbyPanelSuccessBuilder successBuilder;

  @override
  Widget build(BuildContext context) {
    return switch (status) {
      NetworkMapNearbyPanelStatus.idle ||
      NetworkMapNearbyPanelStatus.loading => const SizedBox(
        height: 132,
        child: Center(child: CircularProgressIndicator()),
      ),
      NetworkMapNearbyPanelStatus.success => _buildSuccess(context),
    };
  }

  Widget _buildSuccess(BuildContext context) {
    final content = successBuilder(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        content.stationBar,
        const SizedBox(height: 17),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
          child: content.dataPanel,
        ),
      ],
    );
  }
}
