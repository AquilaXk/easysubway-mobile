import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import test from "node:test";

import { buildImmutableDartSourceGraph } from "./lib/mobile-dart-source-graph.mjs";
import {
  auditCrossFeatureBoundaries,
  compareGraphs,
  forbiddenConcreteEdges,
  parseInventory,
  parsePolicy,
  verifyInventoryBinding,
} from "./mobile-cross-feature-boundary-ratchet.mjs";

const policy = parsePolicy(readFileSync("tools/ci/mobile-cross-feature-boundary-policy.json"));
const reviewedInventoryBytes = readFileSync("tools/ci/mobile-cross-feature-boundary-inventory.json");

function inventoryBytes(overrides = {}) {
  return Buffer.from(`${JSON.stringify({
    schemaVersion: 1,
    artifactKind: "mobile-cross-feature-boundary-inventory-v1",
    repository: "AquilaXk/easysubway-mobile",
    featureRoots: ["favorites", "journey"],
    appCompositionPrefix: "apps/mobile/lib/app/",
    sharedNeutralPrefixes: ["apps/mobile/lib/core/"],
    generatedOwnerPrefix: "apps/mobile/lib/generated/",
    generatedAdapterPaths: ["apps/mobile/lib/features/journey/data/journey_adapter.dart"],
    publicApis: [{
      path: "apps/mobile/lib/features/journey/domain/journey.dart",
      ownerFeature: "journey",
      classification: "PUBLIC_API",
      contractKind: "TYPED_DOMAIN",
      terminalDisposition: "RETAIN_TYPED_CONTRACT",
    }],
    migrationExceptions: [],
    ...overrides,
  })}\n`, "utf8");
}

function policyFor(bytes, overrides = {}) {
  return parsePolicy(Buffer.from(`${JSON.stringify({
    schemaVersion: 2,
    artifactKind: "mobile-cross-feature-boundary-policy-v2",
    repository: "AquilaXk/easysubway-mobile",
    inventoryPath: "tools/ci/mobile-cross-feature-boundary-inventory.json",
    inventorySha256: createHash("sha256").update(bytes).digest("hex"),
    featurePrefix: "apps/mobile/lib/features/",
    forbiddenTargetSegments: ["application", "data", "infrastructure", "presentation"],
    terminalZeroRequired: false,
    ...overrides,
  })}\n`, "utf8"));
}

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

test("current policy is byte-bound to the reviewed repository inventory", () => {
  const reviewedInventory = verifyInventoryBinding(policy, reviewedInventoryBytes);
  assert.equal(reviewedInventory.featureRoots.length, 24);
  assert.equal(reviewedInventory.publicApis.length, 24);
  assert.equal(reviewedInventory.migrationExceptions.length, 1);
});

test("policy is byte-bound to a normalized explicit inventory", () => {
  const bytes = inventoryBytes();
  const boundPolicy = policyFor(bytes);
  assert.equal(verifyInventoryBinding(boundPolicy, bytes).featureRoots.length, 2);
  assert.throws(
    () => verifyInventoryBinding(boundPolicy, Buffer.concat([bytes, Buffer.from(" ")])),
    /inventory SHA-256 mismatch/u,
  );
  assert.throws(
    () => parseInventory(inventoryBytes({ featureRoots: ["journey", "favorites"] })),
    /inventory identity is invalid/u,
  );
});

test("only exact typed public API targets are retained across features", () => {
  const bytes = inventoryBytes();
  const explicitInventory = parseInventory(bytes);
  const explicitPolicy = policyFor(bytes);
  const files = {
    "apps/mobile/lib/features/journey/domain/journey.dart": "final class Journey {}\n",
    "apps/mobile/lib/features/journey/domain/internal.dart": "final class InternalJourney {}\n",
    "apps/mobile/lib/features/favorites/presentation/favorite_screen.dart": "import '../../journey/domain/journey.dart';\n",
  };
  assert.deepEqual(
    auditCrossFeatureBoundaries({ files, policy: explicitPolicy, inventory: explicitInventory }).violations,
    [],
  );
  files["apps/mobile/lib/features/favorites/presentation/favorite_screen.dart"] = "import '../../journey/domain/internal.dart';\n";
  assert.deepEqual(
    auditCrossFeatureBoundaries({ files, policy: explicitPolicy, inventory: explicitInventory }).violations.map((entry) => entry.code),
    ["UNLISTED_CROSS_FEATURE_API"],
  );
});

test("migration exceptions are exact, reviewed and forbidden in terminal-zero mode", () => {
  const exception = {
    source: "apps/mobile/lib/features/favorites/presentation/favorite_screen.dart",
    target: "apps/mobile/lib/features/journey/presentation/journey_screen.dart",
    kind: "IMPORT",
    ownerIssue: 37,
    reason: "typed app-composition handoff pending",
    removalTrigger: "remove when the app-owned destination callback is wired",
  };
  const bytes = inventoryBytes({ migrationExceptions: [exception] });
  const explicitInventory = parseInventory(bytes);
  const explicitPolicy = policyFor(bytes);
  const files = {
    [exception.source]: "import '../../journey/presentation/journey_screen.dart';\n",
    [exception.target]: "final class JourneyScreen {}\n",
  };
  assert.deepEqual(
    auditCrossFeatureBoundaries({ files, policy: explicitPolicy, inventory: explicitInventory }).violations,
    [],
  );
  files[exception.source] += "import '../../journey/application/journey_controller.dart';\n";
  files["apps/mobile/lib/features/journey/application/journey_controller.dart"] = "final class JourneyController {}\n";
  assert.deepEqual(
    auditCrossFeatureBoundaries({ files, policy: explicitPolicy, inventory: explicitInventory }).violations.map((entry) => entry.code),
    ["UNREVIEWED_CONCRETE_EDGE"],
  );
  assert.throws(
    () => auditCrossFeatureBoundaries({ files: {}, policy: policyFor(bytes, { terminalZeroRequired: true }), inventory: explicitInventory }),
    /terminal zero forbids migration exceptions/u,
  );
});

test("a public API cannot re-export its own internal concrete implementation", () => {
  const bytes = inventoryBytes();
  const explicitInventory = parseInventory(bytes);
  const files = {
    "apps/mobile/lib/features/journey/domain/journey.dart": "export '../presentation/journey_screen.dart';\n",
    "apps/mobile/lib/features/journey/presentation/journey_screen.dart": "final class JourneyScreen {}\n",
  };
  assert.deepEqual(
    auditCrossFeatureBoundaries({ files, policy: policyFor(bytes), inventory: explicitInventory }).violations.map((entry) => entry.code),
    ["PUBLIC_API_REEXPORTS_INTERNAL"],
  );
});

test("generated code is reachable only from exact reviewed adapter paths", () => {
  const bytes = inventoryBytes();
  const explicitInventory = parseInventory(bytes);
  const generated = "apps/mobile/lib/generated/journey_v3/client.dart";
  const files = {
    [generated]: "final class GeneratedJourney {}\n",
    "apps/mobile/lib/features/journey/data/journey_adapter.dart": "import '../../../generated/journey_v3/client.dart';\n",
    "apps/mobile/lib/features/journey/presentation/journey_screen.dart": "import '../../../generated/journey_v3/client.dart';\n",
  };
  assert.deepEqual(
    auditCrossFeatureBoundaries({ files, policy: policyFor(bytes), inventory: explicitInventory }).violations.map((entry) => entry.code),
    ["UNREVIEWED_GENERATED_CONSUMER"],
  );
});

test("feature composition cannot move into locator, event bus, static singleton, or ambient registry", () => {
  const bytes = inventoryBytes();
  const explicitInventory = parseInventory(bytes);
  const files = {
    "apps/mobile/lib/features/favorites/presentation/locator.dart":
      "final journey = GetIt.instance.get<JourneyPort>();\n",
    "apps/mobile/lib/features/favorites/presentation/events.dart":
      "final events = EventBus();\n",
    "apps/mobile/lib/features/favorites/presentation/singleton.dart":
      "class WorkflowOwner { static final WorkflowOwner instance = WorkflowOwner(); }\n",
    "apps/mobile/lib/features/favorites/presentation/static_registry.dart":
      "class WorkflowOwner { static final Map<Type, Object> registry = <Type, Object>{}; }\n",
    "apps/mobile/lib/features/favorites/presentation/registry.dart":
      "final Map<Type, Object> registry = <Type, Object>{};\n",
    "apps/mobile/lib/features/favorites/presentation/navigator.dart":
      "final navigatorKey = GlobalKey<NavigatorState>();\n",
    "apps/mobile/lib/features/favorites/presentation/allowed.dart": [
      "// GetIt.instance and EventBus() are documentation only.",
      "const description = 'static final instance = registry';",
      "class Parser { static Parser fromJson(Object? value) => Parser(); }",
    ].join("\n"),
    "apps/mobile/lib/app/composition.dart":
      "final Map<Type, Object> registry = <Type, Object>{};\n",
  };

  assert.deepEqual(
    auditCrossFeatureBoundaries({
      files,
      policy: policyFor(bytes),
      inventory: explicitInventory,
    }).violations.map((entry) => [entry.code, entry.source]),
    [
      ["GLOBAL_EVENT_BUS", "apps/mobile/lib/features/favorites/presentation/events.dart"],
      ["GLOBAL_NAVIGATOR_KEY", "apps/mobile/lib/features/favorites/presentation/navigator.dart"],
      ["GLOBAL_SERVICE_LOCATOR", "apps/mobile/lib/features/favorites/presentation/locator.dart"],
      ["STATIC_REGISTRY", "apps/mobile/lib/features/favorites/presentation/static_registry.dart"],
      ["STATIC_SINGLETON", "apps/mobile/lib/features/favorites/presentation/singleton.dart"],
      ["TOP_LEVEL_REGISTRY", "apps/mobile/lib/features/favorites/presentation/registry.dart"],
    ],
  );
});
