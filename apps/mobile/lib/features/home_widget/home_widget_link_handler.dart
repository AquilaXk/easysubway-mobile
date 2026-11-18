import 'dart:async';

import 'package:flutter/material.dart';

class HomeWidgetLinkHandler extends StatefulWidget {
  const HomeWidgetLinkHandler({
    required this.clicks,
    required this.navigatorKey,
    required this.stationDetailBuilder,
    required this.child,
    super.key,
  });

  final Stream<Uri?> clicks;
  final GlobalKey<NavigatorState> navigatorKey;
  final Widget Function(String stationId) stationDetailBuilder;
  final Widget child;

  @override
  State<HomeWidgetLinkHandler> createState() => _HomeWidgetLinkHandlerState();
}

class _HomeWidgetLinkHandlerState extends State<HomeWidgetLinkHandler> {
  StreamSubscription<Uri?>? _subscription;

  @override
  void initState() {
    super.initState();
    _subscription = widget.clicks.listen(_open);
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;

  void _open(Uri? uri) {
    final stationId = stationIdFromHomeWidgetUri(uri);
    final navigator = widget.navigatorKey.currentState;
    if (stationId == null || navigator == null) {
      return;
    }
    unawaited(
      navigator.push<void>(
        MaterialPageRoute<void>(
          builder: (_) => widget.stationDetailBuilder(stationId),
        ),
      ),
    );
  }
}

final RegExp _homeWidgetIdentifierPattern = RegExp(r'^[A-Za-z0-9._:-]{1,64}$');

String? stationIdFromHomeWidgetUri(Uri? uri) {
  if (uri == null ||
      uri.scheme != 'easysubway' ||
      uri.host != 'station' ||
      uri.path != '/detail' ||
      uri.userInfo.isNotEmpty ||
      uri.hasPort ||
      uri.hasFragment) {
    return null;
  }
  final query = uri.queryParameters;
  for (final key in query.keys) {
    if (key != 'stationId' && key != 'lineId') {
      return null;
    }
  }
  final stationId = query['stationId']?.trim();
  if (stationId == null || !_homeWidgetIdentifierPattern.hasMatch(stationId)) {
    return null;
  }
  final lineId = query['lineId']?.trim();
  if (lineId != null &&
      lineId.isNotEmpty &&
      !_homeWidgetIdentifierPattern.hasMatch(lineId)) {
    return null;
  }
  return stationId;
}
