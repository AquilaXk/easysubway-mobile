import 'package:flutter/foundation.dart';

import 'domain/route_draft.dart';

abstract interface class RouteDraftPort implements Listenable {
  RouteDraft get draft;

  void clear();

  void setOrigin(RouteDraftStation station);

  void setDestination(RouteDraftStation station);

  void setWaypoint(RouteDraftStation station);
}
