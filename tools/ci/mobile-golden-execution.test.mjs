import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

import {
  verifyGoldenExecution,
  verifyGoldenMutation,
} from "./mobile-golden-execution.mjs";

const TEST_PATH =
  "apps/mobile/test/features/network_map/presentation/station_fan_menu_golden_test.dart";
const PACKAGE_PATH =
  "test/features/network_map/presentation/station_fan_menu_golden_test.dart";
const ASSET_PATH =
  "apps/mobile/test/features/network_map/presentation/goldens/station_fan_menu_default.png";
const repositoryRoot = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  "../..",
);

const inventory = ({ tests = [TEST_PATH], references = 1, findings = [] } = {}) => ({
  schemaVersion: 1,
  artifactKind: "mobile-golden-parity-v1",
  tests,
  references: Array.from({ length: references }, () => ({
    test: TEST_PATH,
    asset: ASSET_PATH,
  })),
  assets: [ASSET_PATH],
  findings,
  outcome: findings.length === 0 ? "PASS" : "FAIL",
});

const environment = (overrides = {}) => ({
  runnerOs: "macOS",
  imageOs: "macos15",
  imageVersion: "20260801.1",
  flutterVersion: "3.44.0",
  headSha: "a".repeat(40),
  ...overrides,
});

function report({
  suites = [PACKAGE_PATH],
  tests = [{ suiteID: 0, skipped: false, result: "success" }],
  doneSuccess = true,
} = {}) {
  const events = [
    { type: "start", time: 0, protocolVersion: "0.1.1", runnerVersion: "3.12.0" },
    { type: "allSuites", time: 1, count: suites.length },
    ...suites.map((suitePath, index) => ({
      type: "suite",
      time: 2,
      suite: { id: index, path: suitePath },
    })),
  ];
  for (const [index, fixture] of tests.entries()) {
    const testID = 100 + index;
    events.push({
      type: "testStart",
      time: 3 + index,
      test: {
        id: testID,
        name: `golden ${index}`,
        suiteID: fixture.suiteID,
        groupIDs: [],
      },
    });
    events.push({
      type: "testDone",
      time: 4 + index,
      testID,
      result: fixture.result,
      hidden: false,
      skipped: fixture.skipped,
    });
  }
  events.push({ type: "done", time: 20, success: doneSuccess });
  return events;
}

test("actual comparison accepts a complete non-skipped golden report", () => {
  const result = verifyGoldenExecution({
    inventory: inventory(),
    events: report(),
    testExitCode: 0,
    environment: environment(),
  });

  assert.equal(result.outcome, "PASS");
  assert.equal(result.executedSuiteCount, 1);
  assert.equal(result.nonSkippedComparisonCount, 1);
  assert.deepEqual(result.executedTests, [TEST_PATH]);
});

test("zero inventory, parity findings, and a missing reporter suite fail closed", () => {
  assert.throws(
    () =>
      verifyGoldenExecution({
        inventory: inventory({ tests: [], references: 0 }),
        events: report(),
        testExitCode: 0,
        environment: environment(),
      }),
    /zero golden tests|zero golden references/i,
  );
  assert.throws(
    () =>
      verifyGoldenExecution({
        inventory: inventory({ findings: [{ code: "ORPHAN", path: ASSET_PATH }] }),
        events: report(),
        testExitCode: 0,
        environment: environment(),
      }),
    /parity/i,
  );
  assert.throws(
    () =>
      verifyGoldenExecution({
        inventory: inventory(),
        events: report({ suites: ["test/other_test.dart"] }),
        testExitCode: 0,
        environment: environment(),
      }),
    /missing golden suite|unexpected suite/i,
  );
});

test("all-skipped and partial-skipped comparisons fail closed", () => {
  assert.throws(
    () =>
      verifyGoldenExecution({
        inventory: inventory(),
        events: report({ tests: [{ suiteID: 0, skipped: true, result: "success" }] }),
        testExitCode: 0,
        environment: environment(),
      }),
    /all skipped/i,
  );
  assert.throws(
    () =>
      verifyGoldenExecution({
        inventory: inventory(),
        events: report({
          tests: [
            { suiteID: 0, skipped: false, result: "success" },
            { suiteID: 0, skipped: true, result: "success" },
          ],
        }),
        testExitCode: 0,
        environment: environment(),
      }),
    /contains a skipped comparison/i,
  );
});

test("runner failure, comparison failure, and incomplete reports cannot pass", () => {
  assert.throws(
    () =>
      verifyGoldenExecution({
        inventory: inventory(),
        events: report(),
        testExitCode: 2,
        environment: environment(),
      }),
    /runner exit/i,
  );
  assert.throws(
    () =>
      verifyGoldenExecution({
        inventory: inventory(),
        events: report({
          tests: [{ suiteID: 0, skipped: false, result: "failure" }],
          doneSuccess: false,
        }),
        testExitCode: 1,
        environment: environment(),
      }),
    /runner exit|failed/i,
  );
  assert.throws(
    () =>
      verifyGoldenExecution({
        inventory: inventory(),
        events: report().slice(0, -1),
        testExitCode: 0,
        environment: environment(),
      }),
    /done|terminal/i,
  );
});

test("mutation probe requires a nonzero mismatch and sanitized PNG evidence", () => {
  const mismatchEvents = report({
    tests: [{ suiteID: 0, skipped: false, result: "failure" }],
    doneSuccess: false,
  });
  const artifacts = [
    "apps/mobile/test/features/network_map/presentation/failures/station_fan_menu_default_isolatedDiff.png",
    "apps/mobile/test/features/network_map/presentation/failures/station_fan_menu_default_testImage.png",
  ];

  const result = verifyGoldenMutation({
    inventory: inventory(),
    events: mismatchEvents,
    testExitCode: 1,
    failureArtifacts: artifacts,
    environment: environment(),
  });
  assert.equal(result.outcome, "EXPECTED_MISMATCH");
  assert.deepEqual(result.failureArtifacts, artifacts);

  assert.throws(
    () =>
      verifyGoldenMutation({
        inventory: inventory(),
        events: report(),
        testExitCode: 0,
        failureArtifacts: artifacts,
        environment: environment(),
      }),
    /mutation.*success|expected.*nonzero/i,
  );
  assert.throws(
    () =>
      verifyGoldenMutation({
        inventory: inventory(),
        events: mismatchEvents,
        testExitCode: 1,
        failureArtifacts: [],
        environment: environment(),
      }),
    /failure PNG/i,
  );
  assert.throws(
    () =>
      verifyGoldenMutation({
        inventory: inventory(),
        events: mismatchEvents,
        testExitCode: 1,
        failureArtifacts: ["/tmp/leak.png"],
        environment: environment(),
      }),
    /artifact path/i,
  );
});

test("environment identity is exact and excludes absolute values", () => {
  assert.throws(
    () =>
      verifyGoldenExecution({
        inventory: inventory(),
        events: report(),
        testExitCode: 0,
        environment: environment({ runnerOs: "Linux" }),
      }),
    /macOS/i,
  );
  assert.throws(
    () =>
      verifyGoldenExecution({
        inventory: inventory(),
        events: report(),
        testExitCode: 0,
        environment: environment({ imageVersion: "/Users/runner/private" }),
      }),
    /environment identity/i,
  );
});

test("workflow pins comparison, mutation, evidence, and no baseline writes", () => {
  const workflow = readFileSync(
    path.join(repositoryRoot, ".github/workflows/mobile-golden.yml"),
    "utf8",
  );

  assert.match(workflow, /name: Mobile Golden CI/u);
  assert.match(workflow, /runs-on: macos-15/u);
  assert.match(workflow, /flutter-version: "3\.44\.0"/u);
  assert.match(workflow, /node-version: "24"/u);
  assert.match(workflow, /mobile-golden-execution\.mjs verify/u);
  assert.match(workflow, /mobile-golden-execution\.mjs verify-mutation/u);
  assert.match(workflow, /EASYSUBWAY_GOLDEN_MUTATION=true/u);
  assert.match(workflow, /--plain-name "\^기본 상태\$"/u);
  assert.match(workflow, /--file-reporter "json:\$mutation_report" \\\n\s+> \/dev\/null 2>&1/u);
  assert.match(
    workflow,
    /actual_report="\$RUNNER_TEMP\/mobile-golden-actual-events\.json"/u,
  );
  assert.match(
    workflow,
    /mutation_report="\$RUNNER_TEMP\/mobile-golden-mutation-events\.json"/u,
  );
  assert.match(
    workflow,
    /flutter_identity="\$RUNNER_TEMP\/mobile-golden-flutter-version\.json"/u,
  );
  assert.equal(workflow.includes("$evidence_root/actual-events.json"), false);
  assert.equal(workflow.includes("$evidence_root/mutation-events.json"), false);
  assert.equal(workflow.includes("$evidence_root/flutter-version.json"), false);
  assert.match(workflow, /actions\/upload-artifact@65462800fd760344b1a7b4382951275a0abb4808/u);
  assert.equal(workflow.includes("--update-goldens"), false);
});
