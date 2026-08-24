import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

import { buildImmutableDartSourceGraph } from "./lib/mobile-dart-source-graph.mjs";
import { compareGraphs, forbiddenConcreteEdges, parsePolicy } from "./mobile-cross-feature-boundary-ratchet.mjs";

const policy = parsePolicy(readFileSync("tools/ci/mobile-cross-feature-boundary-policy.json"));

test("cross-feature concrete imports and exports are normalized and compared to the reviewed baseline", () => {
  const baseFiles = { "apps/mobile/lib/features/journey/domain/journey.dart": "final class Journey {}\n", "apps/mobile/lib/features/favorites/domain/favorite.dart": "final class Favorite {}\n" };
  const currentFiles = { ...baseFiles, "apps/mobile/lib/features/favorites/presentation/favorite_screen.dart": "import '../../journey/presentation/journey_screen.dart';\n", "apps/mobile/lib/features/journey/presentation/journey_screen.dart": "final class JourneyScreen {}\n" };
  const result = compareGraphs({ baseFiles, currentFiles, policy });
  assert.equal(result.baseline.length, 0);
  assert.equal(result.newEdges.length, 1);
  assert.deepEqual(result.newEdges[0], { source: "apps/mobile/lib/features/favorites/presentation/favorite_screen.dart", target: "apps/mobile/lib/features/journey/presentation/journey_screen.dart", kind: "IMPORT", uri: "../../journey/presentation/journey_screen.dart", uriKind: "RELATIVE", conditional: false });
});

test("same-feature and other-feature domain imports are not concrete-boundary violations", () => {
  const files = { "apps/mobile/lib/features/journey/domain/journey.dart": "final class Journey {}\n", "apps/mobile/lib/features/journey/presentation/journey_screen.dart": "import '../domain/journey.dart';\n", "apps/mobile/lib/features/favorites/domain/favorite.dart": "import '../../journey/domain/journey.dart';\n" };
  assert.deepEqual(forbiddenConcreteEdges(buildImmutableDartSourceGraph({ files, packageName: "easysubway_mobile" }), policy), []);
});
