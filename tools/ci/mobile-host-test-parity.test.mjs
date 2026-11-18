import assert from "node:assert/strict";
import test from "node:test";

import {
  buildInventory,
  parseJsonReport,
  verifyExecutionParity,
} from "./mobile-host-test-parity.mjs";

const POLICY = {
  schemaVersion: 1,
  trackedTestSuffix: "_test.dart",
  roots: [
    {
      path: "apps/mobile/test",
      classification: "REQUIRED_HOST_TEST",
      owner: "https://github.com/AquilaXk/easysubway-mobile/issues/35",
    },
    {
      path: "apps/mobile/integration_test",
      classification: "NATIVE_INTEGRATION_OWNED_BY_MOBILE_72",
      owner: "https://github.com/AquilaXk/easysubway-mobile/issues/72",
    },
    {
      path: "apps/mobile/test_driver",
      classification: "NATIVE_INTEGRATION_OWNED_BY_MOBILE_72",
      owner: "https://github.com/AquilaXk/easysubway-mobile/issues/72",
    },
  ],
  overrides: [
    {
      path: "apps/mobile/test/features/network_map/presentation/station_fan_menu_golden_test.dart",
      classification: "GOLDEN_OWNED_BY_MOBILE_23",
      owner: "https://github.com/AquilaXk/easysubway-mobile/issues/23",
      reason: "macOS rasterizer golden suite",
      reviewTrigger: "Mobile #23 terminal golden lane",
    },
  ],
  deletionDispositions: [],
};

const GOLDEN_PATH =
  "apps/mobile/test/features/network_map/presentation/station_fan_menu_golden_test.dart";

function trackedFixture(...paths) {
  return [GOLDEN_PATH, ...paths];
}

function jsonLines(events) {
  return `${events.map((event) => JSON.stringify(event)).join("\n")}\n`;
}

function completeReport({
  suitePath = "test/unit/example_test.dart",
  skipped = false,
  hidden = false,
  result = "success",
  extraEvents = [],
  doneSuccess = true,
} = {}) {
  return [
    { type: "start", time: 0, protocolVersion: "0.1.1", runnerVersion: "1.0.0", pid: 1 },
    { type: "allSuites", time: 1, count: 1 },
    { type: "suite", time: 2, suite: { id: 0, platform: "vm", path: suitePath } },
    {
      type: "testStart",
      time: 3,
      test: { id: 10, name: "example", suiteID: 0, groupIDs: [] },
    },
    { type: "testDone", time: 4, testID: 10, result, hidden, skipped },
    ...extraEvents,
    { type: "done", time: 5, success: doneSuccess },
  ];
}

test("tracked Dart tests are deterministically classified without a fixed count", () => {
  const inventory = buildInventory({
    trackedPaths: trackedFixture(
      "apps/mobile/test/zeta_test.dart",
      "apps/mobile/integration_test/native_test.dart",
      "apps/mobile/test/alpha_test.dart",
      "apps/mobile/lib/not_a_test_helper.dart",
    ),
    policy: POLICY,
  });

  assert.deepEqual(
    inventory.tests.map(({ path, classification }) => [path, classification]),
    [
      ["apps/mobile/integration_test/native_test.dart", "NATIVE_INTEGRATION_OWNED_BY_MOBILE_72"],
      ["apps/mobile/test/alpha_test.dart", "REQUIRED_HOST_TEST"],
      [
        "apps/mobile/test/features/network_map/presentation/station_fan_menu_golden_test.dart",
        "GOLDEN_OWNED_BY_MOBILE_23",
      ],
      ["apps/mobile/test/zeta_test.dart", "REQUIRED_HOST_TEST"],
    ],
  );
  assert.equal(inventory.requiredHostCount, 2);
  assert.equal(inventory.inventoryDigest.length, 64);
});

test("zero discovery and unclassified out-of-root Dart tests fail closed", () => {
  assert.throws(
    () => buildInventory({ trackedPaths: [], policy: POLICY }),
    /zero tracked Dart tests/i,
  );
  assert.throws(
    () =>
      buildInventory({
        trackedPaths: trackedFixture("unexpected/hidden_test.dart"),
        policy: POLICY,
      }),
    /outside approved roots/i,
  );
});

test("traversal, absolute, duplicate, and symlink test paths fail closed", () => {
  for (const trackedPaths of [
    trackedFixture("../apps/mobile/test/escape_test.dart"),
    trackedFixture("/apps/mobile/test/absolute_test.dart"),
    trackedFixture("apps/mobile/test/dup_test.dart", "apps/mobile/test/dup_test.dart"),
  ]) {
    assert.throws(
      () => buildInventory({ trackedPaths, policy: POLICY }),
      /invalid|duplicate/i,
    );
  }
  assert.throws(
    () =>
      buildInventory({
        trackedPaths: trackedFixture("apps/mobile/test/link_test.dart"),
        symlinkPaths: ["apps/mobile/test/link_test.dart"],
        policy: POLICY,
      }),
    /symlink/i,
  );
});

test("deleted tests require an exact owner disposition while renames remain explicit", () => {
  assert.throws(
    () =>
      buildInventory({
        trackedPaths: trackedFixture("apps/mobile/test/new_test.dart"),
        changedEntries: [
          { status: "DELETED", path: "apps/mobile/test/removed_test.dart" },
        ],
        changeIdentity: {
          base: "a".repeat(40),
          head: "b".repeat(40),
          event: "pull_request",
        },
        policy: POLICY,
      }),
    /deleted test has no exact disposition/i,
  );

  const deletionPolicy = structuredClone(POLICY);
  deletionPolicy.deletionDispositions.push({
    path: "apps/mobile/test/removed_test.dart",
    classification: "OBSOLETE_DELETE",
    owner: "https://github.com/AquilaXk/easysubway-mobile/issues/18",
    reason: "The direct test owner was removed with its consumer-zero production declaration.",
    reviewTrigger: "Mobile #18 terminal deletion",
  });
  const deleted = buildInventory({
    trackedPaths: trackedFixture("apps/mobile/test/new_test.dart"),
    changedEntries: [
      { status: "DELETED", path: "apps/mobile/test/removed_test.dart" },
    ],
    changeIdentity: {
      base: "a".repeat(40),
      head: "b".repeat(40),
      event: "pull_request",
    },
    policy: deletionPolicy,
  });
  assert.deepEqual(deleted.testChanges, [
    { status: "DELETED", path: "apps/mobile/test/removed_test.dart" },
  ]);

  const renamed = buildInventory({
    trackedPaths: trackedFixture("apps/mobile/test/new_test.dart"),
    changedEntries: [
      {
        status: "RENAMED",
        oldPath: "apps/mobile/test/old_test.dart",
        newPath: "apps/mobile/test/new_test.dart",
      },
    ],
    changeIdentity: {
      base: "a".repeat(40),
      head: "b".repeat(40),
      event: "pull_request",
    },
    policy: POLICY,
  });
  assert.deepEqual(renamed.testChanges, [
    {
      status: "RENAMED",
      oldPath: "apps/mobile/test/old_test.dart",
      newPath: "apps/mobile/test/new_test.dart",
    },
  ]);
});

test("blank policy ownership and conflicting change identity fail closed", () => {
  const blankOwnerPolicy = structuredClone(POLICY);
  blankOwnerPolicy.roots[0].owner = "  ";
  assert.throws(
    () => buildInventory({ trackedPaths: trackedFixture("apps/mobile/test/unit/example_test.dart"), policy: blankOwnerPolicy }),
    /missing owner/i,
  );
  assert.throws(
    () => buildInventory({
      trackedPaths: trackedFixture("apps/mobile/test/unit/example_test.dart"),
      changedEntries: [{ status: "MODIFIED", path: "apps/mobile/test/unit/example_test.dart" }],
      changeIdentity: { base: "a".repeat(40), head: "a".repeat(40), event: "pull_request" },
      policy: POLICY,
    }),
    /base and head must differ/i,
  );
  assert.doesNotThrow(() => buildInventory({
    trackedPaths: trackedFixture("apps/mobile/test/unit/example_test.dart"),
    changedEntries: [{ status: "MODIFIED", path: "apps/mobile/test/unit/example_test.dart" }],
    changeIdentity: {
      base: "a".repeat(40),
      head: "a".repeat(40),
      event: "workflow_dispatch",
    },
    policy: POLICY,
  }));
});

test("valid JSON reporter events prove one required suite and terminal execution", () => {
  const inventory = buildInventory({
    trackedPaths: trackedFixture("apps/mobile/test/unit/example_test.dart"),
    policy: POLICY,
  });
  const events = parseJsonReport(jsonLines(completeReport()));
  const result = verifyExecutionParity({ inventory, events });

  assert.equal(result.requiredHostCount, 1);
  assert.equal(result.executedRequiredHostCount, 1);
  assert.equal(result.nonSkippedTerminalTestCount, 1);
  assert.deepEqual(result.requiredFiles, ["apps/mobile/test/unit/example_test.dart"]);
  assert.doesNotMatch(JSON.stringify(result), /\/Users\//);
});

test("inventory mutation after discovery is rejected by its digest", () => {
  const inventory = buildInventory({
    trackedPaths: trackedFixture("apps/mobile/test/unit/example_test.dart"),
    policy: POLICY,
  });
  inventory.tests[0].owner = "mutated";
  assert.throws(
    () => verifyExecutionParity({ inventory, events: completeReport() }),
    /inventory digest mismatch/i,
  );
});

test("missing required suite and unexpected unclassified suite fail closed", () => {
  const inventory = buildInventory({
    trackedPaths: trackedFixture("apps/mobile/test/unit/example_test.dart"),
    policy: POLICY,
  });
  assert.throws(
    () =>
      verifyExecutionParity({
        inventory,
        events: completeReport({ suitePath: "test/other_test.dart" }),
      }),
    /missing required suite|unexpected suite/i,
  );
});

test("all-skipped and hidden-only required suites fail closed", () => {
  const inventory = buildInventory({
    trackedPaths: trackedFixture("apps/mobile/test/unit/example_test.dart"),
    policy: POLICY,
  });
  assert.throws(
    () => verifyExecutionParity({ inventory, events: completeReport({ skipped: true }) }),
    /all skipped|non-skipped terminal/i,
  );
  assert.throws(
    () => verifyExecutionParity({ inventory, events: completeReport({ hidden: true }) }),
    /hidden|terminal/i,
  );
});

test("a partially skipped required suite fails without an explicit file disposition", () => {
  const inventory = buildInventory({
    trackedPaths: trackedFixture("apps/mobile/test/unit/example_test.dart"),
    policy: POLICY,
  });
  const events = completeReport();
  events.splice(-1, 0,
    {
      type: "testStart",
      time: 4,
      test: { id: 11, name: "temporarily skipped", suiteID: 0, groupIDs: [] },
    },
    { type: "testDone", time: 4, testID: 11, result: "success", hidden: false, skipped: true },
  );
  assert.throws(
    () => verifyExecutionParity({ inventory, events }),
    /skipped test without an explicit disposition/i,
  );
});

test("duplicate suites and unknown terminal results fail closed", () => {
  const inventory = buildInventory({
    trackedPaths: trackedFixture("apps/mobile/test/unit/example_test.dart"),
    policy: POLICY,
  });
  const duplicate = completeReport();
  duplicate.splice(3, 0, {
    type: "suite",
    time: 2,
    suite: { id: 2, platform: "vm", path: "test/unit/example_test.dart" },
  });
  assert.throws(
    () => verifyExecutionParity({ inventory, events: duplicate }),
    /duplicate suite/i,
  );
  assert.throws(
    () =>
      verifyExecutionParity({
        inventory,
        events: completeReport({ result: "new-state" }),
      }),
    /unknown test result/i,
  );
});

test("test failure, runner failure, and late error cannot be current success", () => {
  const inventory = buildInventory({
    trackedPaths: trackedFixture("apps/mobile/test/unit/example_test.dart"),
    policy: POLICY,
  });
  assert.throws(
    () =>
      verifyExecutionParity({
        inventory,
        events: completeReport({ result: "failure", doneSuccess: false }),
      }),
    /failed|runner did not succeed/i,
  );
  assert.throws(
    () =>
      verifyExecutionParity({
        inventory,
        events: completeReport({ doneSuccess: false }),
      }),
    /runner did not succeed/i,
  );
  assert.throws(
    () =>
      verifyExecutionParity({
        inventory,
        events: completeReport({
          extraEvents: [
            {
              type: "error",
              time: 5,
              testID: 10,
              error: "late",
              stackTrace: "stack",
              isFailure: false,
            },
          ],
        }),
      }),
    /error event/i,
  );
});

test("malformed, incomplete, and non-terminal JSON reports fail closed", () => {
  assert.throws(() => parseJsonReport("{not-json}\n"), /invalid JSON/i);
  assert.throws(() => parseJsonReport("\n"), /zero reporter events/i);

  const inventory = buildInventory({
    trackedPaths: trackedFixture("apps/mobile/test/unit/example_test.dart"),
    policy: POLICY,
  });
  assert.throws(
    () =>
      verifyExecutionParity({
        inventory,
        events: completeReport().filter((event) => event.type !== "done"),
      }),
    /final done/i,
  );
});

test("golden and native suites do not satisfy required-host parity", () => {
  const inventory = buildInventory({
    trackedPaths: [
      "apps/mobile/test/unit/example_test.dart",
      "apps/mobile/test/features/network_map/presentation/station_fan_menu_golden_test.dart",
      "apps/mobile/integration_test/native_test.dart",
    ],
    policy: POLICY,
  });
  const events = completeReport({
    suitePath: "test/features/network_map/presentation/station_fan_menu_golden_test.dart",
    skipped: true,
  });
  assert.throws(
    () => verifyExecutionParity({ inventory, events }),
    /missing required suite/i,
  );
});

test("new reporter event types do not substitute or break required public events", () => {
  const inventory = buildInventory({
    trackedPaths: trackedFixture("apps/mobile/test/unit/example_test.dart"),
    policy: POLICY,
  });
  const events = completeReport();
  events.splice(-1, 0, { type: "futureReporterEvent", time: 4 });

  const result = verifyExecutionParity({ inventory, events });
  assert.equal(result.executedRequiredHostCount, 1);
});

test("reporter IDs and invalid timestamps fail closed without assuming async adjacency", () => {
  const inventory = buildInventory({
    trackedPaths: trackedFixture("apps/mobile/test/unit/example_test.dart"),
    policy: POLICY,
  });
  const beforeAllSuites = completeReport();
  [beforeAllSuites[1], beforeAllSuites[2]] = [beforeAllSuites[2], beforeAllSuites[1]];
  assert.equal(
    verifyExecutionParity({ inventory, events: beforeAllSuites }).executedRequiredHostCount,
    1,
  );

  const negativeTestId = completeReport();
  negativeTestId[3].test.id = -1;
  negativeTestId[4].testID = -1;
  assert.throws(
    () => verifyExecutionParity({ inventory, events: negativeTestId }),
    /non-negative integer/i,
  );

  const backwardTime = completeReport();
  backwardTime[3].time = -1;
  assert.throws(
    () => verifyExecutionParity({ inventory, events: backwardTime }),
    /time is invalid/i,
  );
});
