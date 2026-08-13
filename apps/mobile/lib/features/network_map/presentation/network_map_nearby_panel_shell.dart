import 'package:flutter/material.dart';

/// 주변역 패널의 공용 chrome과 collapsed/expanded layout을 소유한다.
///
/// 역·노선·실시간·상세 구현은 app composition에서 [lineTabs],
/// [dataSourceToggle], [body], [expandedDetail]로 조합한다. 이 shell은 feature
/// layout과 접근성 close action만 유지한다.
class NetworkMapNearbyPanelShell extends StatelessWidget {
  const NetworkMapNearbyPanelShell({
    required this.expanded,
    required this.lineTabs,
    required this.dataSourceToggle,
    required this.onClose,
    required this.body,
    required this.surfaceColor,
    required this.borderColor,
    required this.contentPrimaryColor,
    this.expandedDetail,
    super.key,
  });

  final bool expanded;
  final List<Widget> lineTabs;
  final Widget dataSourceToggle;
  final VoidCallback onClose;
  final Widget body;
  final Color surfaceColor;
  final Color borderColor;
  final Color contentPrimaryColor;
  final Widget? expandedDetail;

  @override
  Widget build(BuildContext context) {
    final detail = expandedDetail;
    final panel = SafeArea(
      top: expanded,
      bottom: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: surfaceColor,
          border: expanded
              ? null
              : Border(
                  top: BorderSide(
                    color: borderColor,
                  ),
                ),
        ),
        child: Column(
          mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
          children: [
            SizedBox(
              height: 52,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const SizedBox(width: 14),
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final lineTab in lineTabs)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 2),
                              child: lineTab,
                            ),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: dataSourceToggle,
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: IconButton(
                      key: const Key('networkMapNearbyPanelCloseButton'),
                      tooltip: '닫기',
                      onPressed: onClose,
                      constraints: const BoxConstraints.tightFor(
                        width: 48,
                        height: 48,
                      ),
                      padding: EdgeInsets.zero,
                      icon: Icon(
                        Icons.close,
                        color: contentPrimaryColor,
                        size: 27,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
              ),
            ),
            Divider(
              height: 1,
              color: borderColor,
            ),
            body,
            if (detail != null) ...[
              Divider(
                height: 1,
                color: borderColor,
              ),
              Expanded(child: detail),
            ],
          ],
        ),
      ),
    );

    return Material(
      key: const Key('networkMapNearbyStationPanel'),
      color: surfaceColor,
      elevation: 0,
      child: expanded
          ? SizedBox.expand(
              key: const Key('networkMapNearbyStationPanelExpanded'),
              child: panel,
            )
          : panel,
    );
  }
}
