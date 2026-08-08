#!/usr/bin/env node

import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import {
  mkdirSync,
  readFileSync,
  writeFileSync,
} from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";

const REQUIRED_CLASS = "REQUIRED_HOST_TEST";
const ALLOWED_CLASSIFICATIONS = new Set([
  REQUIRED_CLASS,
  "GOLDEN_OWNED_BY_MOBILE_23",
  "NATIVE_INTEGRATION_OWNED_BY_MOBILE_72",
  "EXPLICIT_PLATFORM_SPECIFIC",
  "TEMPORARILY_SKIPPED_WITH_OWNER",
  "OBSOLETE_DELETE",
  "GENERATED_OR_NON_TEST",
]);
const ALLOWED_TEST_RESULTS = new Set(["success", "failure", "error"]);
const ALLOWED_REPORT_EVENT_TYPES = new Set([
  "start",
  "allSuites",
  "suite",
  "group",
  "testStart",
  "testDone",
  "print",
  "error",
  "done",
]);

function codepointCompare(a, b) {
  return a < b ? -1 : a > b ? 1 : 0;
}

function canonicalize(value) {
  if (Array.isArray(value)) {
    return value.map(canonicalize);
  }
  if (value && typeof value === "object") {
    return Object.fromEntries(
      Object.keys(value)
        .sort(codepointCompare)
        .map((key) => [key, canonicalize(value[key])]),
    );
  }
  return value;
}

function digest(value) {
  return createHash("sha256")
    .update(JSON.stringify(canonicalize(value)))
    .digest("hex");
}

function fail(message) {
  throw new Error(`mobile-host-test-parity: ${message}`);
}

function normalizeTrackedPath(value, label = "path") {
  if (typeof value !== "string" || value.length === 0) {
    fail(`invalid ${label}: expected a non-empty string`);
  }
  if (/[\u0000-\u001f\u007f]/u.test(value)) {
    fail(`invalid ${label}: control characters are forbidden`);
  }
  const normalized = value.replaceAll("\\", "/");
  if (normalized.startsWith("/") || /^[A-Za-z]:\//u.test(normalized)) {
    fail(`invalid ${label}: absolute paths are forbidden (${value})`);
  }
  const segments = normalized.split("/");
  if (segments.some((segment) => segment === "" || segment === "." || segment === "..")) {
    fail(`invalid ${label}: traversal or empty segments are forbidden (${value})`);
  }
  return segments.join("/");
}

function requireNonBlankString(value, label) {
  if (typeof value !== "string" || value.trim().length === 0) {
    fail(`missing ${label}`);
  }
  return value;
}

function requirePositiveInteger(value, label) {
  if (!Number.isInteger(value) || value <= 0) {
    fail(`${label} must be a positive integer`);
  }
  return value;
}

function validatePolicy(policy) {
  if (!policy || typeof policy !== "object" || Array.isArray(policy)) {
    fail("invalid policy object");
  }
  if (policy.schemaVersion !== 1) {
    fail(`unsupported policy schemaVersion: ${policy.schemaVersion}`);
  }
  if (typeof policy.trackedTestSuffix !== "string" || !policy.trackedTestSuffix.endsWith(".dart")) {
    fail("invalid trackedTestSuffix");
  }
  if (!Array.isArray(policy.roots) || policy.roots.length === 0) {
    fail("policy roots must be a non-empty array");
  }
  if (!Array.isArray(policy.overrides)) {
    fail("policy overrides must be an array");
  }
  if (!Array.isArray(policy.deletionDispositions)) {
    fail("policy deletionDispositions must be an array");
  }

  const rootPaths = new Set();
  const roots = policy.roots.map((entry, index) => {
    if (!entry || typeof entry !== "object" || Array.isArray(entry)) {
      fail(`invalid root entry at index ${index}`);
    }
    const rootPath = normalizeTrackedPath(entry.path, `root[${index}].path`);
    if (rootPaths.has(rootPath)) {
      fail(`duplicate root path: ${rootPath}`);
    }
    rootPaths.add(rootPath);
    if (!ALLOWED_CLASSIFICATIONS.has(entry.classification)) {
      fail(`unknown root classification: ${entry.classification}`);
    }
    requireNonBlankString(entry.owner, `owner for root: ${rootPath}`);
    return { ...entry, path: rootPath };
  });

  for (let i = 0; i < roots.length; i += 1) {
    for (let j = i + 1; j < roots.length; j += 1) {
      const a = `${roots[i].path}/`;
      const b = `${roots[j].path}/`;
      if (a.startsWith(b) || b.startsWith(a)) {
        fail(`overlapping policy roots are forbidden: ${roots[i].path}, ${roots[j].path}`);
      }
    }
  }

  const overridePaths = new Set();
  const overrides = policy.overrides.map((entry, index) => {
    if (!entry || typeof entry !== "object" || Array.isArray(entry)) {
      fail(`invalid override entry at index ${index}`);
    }
    const overridePath = normalizeTrackedPath(entry.path, `override[${index}].path`);
    if (overridePaths.has(overridePath)) {
      fail(`duplicate override path: ${overridePath}`);
    }
    overridePaths.add(overridePath);
    if (!ALLOWED_CLASSIFICATIONS.has(entry.classification)) {
      fail(`unknown override classification: ${entry.classification}`);
    }
    for (const field of ["owner", "reason", "reviewTrigger"]) {
      requireNonBlankString(entry[field], `${field} for override: ${overridePath}`);
    }
    const matchingRoots = roots.filter(
      (root) => overridePath === root.path || overridePath.startsWith(`${root.path}/`),
    );
    if (matchingRoots.length !== 1) {
      fail(`override must belong to exactly one approved root: ${overridePath}`);
    }
    return { ...entry, path: overridePath };
  });

  const deletionPaths = new Set();
  const deletionDispositions = policy.deletionDispositions.map((entry, index) => {
    if (!entry || typeof entry !== "object" || Array.isArray(entry)) {
      fail(`invalid deletion disposition at index ${index}`);
    }
    const deletionPath = normalizeTrackedPath(
      entry.path,
      `deletionDispositions[${index}].path`,
    );
    if (deletionPaths.has(deletionPath)) {
      fail(`duplicate deletion disposition path: ${deletionPath}`);
    }
    deletionPaths.add(deletionPath);
    if (entry.classification !== "OBSOLETE_DELETE") {
      fail(`deleted test disposition must use OBSOLETE_DELETE: ${deletionPath}`);
    }
    for (const field of ["owner", "reason", "reviewTrigger"]) {
      requireNonBlankString(entry[field], `${field} for deletion disposition: ${deletionPath}`);
    }
    const matchingRoots = roots.filter(
      (root) => deletionPath.startsWith(`${root.path}/`),
    );
    if (matchingRoots.length !== 1) {
      fail(`deletion disposition must belong to one approved root: ${deletionPath}`);
    }
    return { ...entry, path: deletionPath };
  });

  return {
    schemaVersion: policy.schemaVersion,
    trackedTestSuffix: policy.trackedTestSuffix,
    roots: roots.sort((a, b) => codepointCompare(a.path, b.path)),
    overrides: overrides.sort((a, b) => codepointCompare(a.path, b.path)),
    deletionDispositions: deletionDispositions.sort((a, b) =>
      codepointCompare(a.path, b.path),
    ),
  };
}

function packagePathFor(repositoryPath) {
  const prefix = "apps/mobile/";
  if (!repositoryPath.startsWith(prefix)) {
    fail(`tracked test has no Flutter package path: ${repositoryPath}`);
  }
  return repositoryPath.slice(prefix.length);
}

function validateChangeIdentity(changeIdentity) {
  if (changeIdentity === null || changeIdentity === undefined) {
    return null;
  }
  if (!changeIdentity || typeof changeIdentity !== "object" || Array.isArray(changeIdentity)) {
    fail("invalid change identity");
  }
  for (const field of ["base", "head"]) {
    if (typeof changeIdentity[field] !== "string" || !/^[0-9a-f]{40}$/u.test(changeIdentity[field])) {
      fail(`change identity ${field} must be a full lowercase SHA`);
    }
  }
  if (changeIdentity.base === changeIdentity.head && changeIdentity.event !== "workflow_dispatch") {
    fail("change identity base and head must differ");
  }
  if (typeof changeIdentity.event !== "string" || changeIdentity.event.length === 0) {
    fail("change identity event is required");
  }
  return {
    base: changeIdentity.base,
    head: changeIdentity.head,
    event: changeIdentity.event,
  };
}

function normalizeChangedEntries(changedEntries, policy) {
  if (!Array.isArray(changedEntries)) {
    fail("changedEntries must be an array");
  }
  const normalized = [];
  const validStatuses = new Set([
    "ADDED",
    "MODIFIED",
    "DELETED",
    "RENAMED",
    "COPIED",
    "TYPE_CHANGED",
    "UNMERGED_OR_UNKNOWN",
  ]);
  for (const entry of changedEntries) {
    if (!entry || typeof entry !== "object" || !validStatuses.has(entry.status)) {
      fail(`invalid changed entry status: ${entry?.status}`);
    }
    if (entry.status === "RENAMED" || entry.status === "COPIED") {
      const oldPath = normalizeTrackedPath(entry.oldPath, "changed oldPath");
      const newPath = normalizeTrackedPath(entry.newPath, "changed newPath");
      if (oldPath.endsWith(policy.trackedTestSuffix) || newPath.endsWith(policy.trackedTestSuffix)) {
        normalized.push({ status: entry.status, oldPath, newPath });
      }
      continue;
    }
    const changedPath = normalizeTrackedPath(entry.path, "changed path");
    if (changedPath.endsWith(policy.trackedTestSuffix)) {
      normalized.push({ status: entry.status, path: changedPath });
    }
  }
  normalized.sort((a, b) =>
    codepointCompare(
      `${a.status}:${a.path ?? a.oldPath}:${a.newPath ?? ""}`,
      `${b.status}:${b.path ?? b.oldPath}:${b.newPath ?? ""}`,
    ),
  );
  return normalized;
}

export function buildInventory({
  trackedPaths,
  symlinkPaths = [],
  changedEntries = [],
  changeIdentity = null,
  policy,
}) {
  if (!Array.isArray(trackedPaths) || !Array.isArray(symlinkPaths)) {
    fail("trackedPaths and symlinkPaths must be arrays");
  }
  const validatedPolicy = validatePolicy(policy);
  const validatedChangeIdentity = validateChangeIdentity(changeIdentity);
  const testChanges = normalizeChangedEntries(changedEntries, validatedPolicy);
  if (testChanges.length > 0 && !validatedChangeIdentity) {
    fail("test changes require an exact change identity");
  }
  const normalizedSymlinks = new Set(
    symlinkPaths.map((entry) => normalizeTrackedPath(entry, "symlink path")),
  );
  const seen = new Set();
  const discovered = [];

  for (const rawPath of trackedPaths) {
    const normalizedPath = normalizeTrackedPath(rawPath, "tracked path");
    if (!normalizedPath.endsWith(validatedPolicy.trackedTestSuffix)) {
      continue;
    }
    if (seen.has(normalizedPath)) {
      fail(`duplicate canonical tracked test path: ${normalizedPath}`);
    }
    seen.add(normalizedPath);
    if (normalizedSymlinks.has(normalizedPath)) {
      fail(`tracked Dart test cannot be a symlink: ${normalizedPath}`);
    }

    const matchingRoots = validatedPolicy.roots.filter(
      (root) => normalizedPath.startsWith(`${root.path}/`),
    );
    if (matchingRoots.length !== 1) {
      fail(`tracked Dart test is outside approved roots: ${normalizedPath}`);
    }
    const root = matchingRoots[0];
    const override = validatedPolicy.overrides.find(
      (entry) => entry.path === normalizedPath,
    );
    const classification = override?.classification ?? root.classification;
    const owner = override?.owner ?? root.owner;
    discovered.push({
      path: normalizedPath,
      packagePath: packagePathFor(normalizedPath),
      classification,
      owner,
      ...(override
        ? { reason: override.reason, reviewTrigger: override.reviewTrigger }
        : {}),
    });
  }

  if (discovered.length === 0) {
    fail("zero tracked Dart tests discovered");
  }
  for (const override of validatedPolicy.overrides) {
    if (!seen.has(override.path)) {
      fail(`stale override references a missing tracked test: ${override.path}`);
    }
  }
  for (const change of testChanges) {
    if (change.status !== "DELETED") {
      continue;
    }
    const disposition = validatedPolicy.deletionDispositions.find(
      (entry) => entry.path === change.path,
    );
    if (!disposition) {
      fail(`deleted test has no exact disposition: ${change.path}`);
    }
  }

  discovered.sort((a, b) => codepointCompare(a.path, b.path));
  const requiredHostCount = discovered.filter(
    (entry) => entry.classification === REQUIRED_CLASS,
  ).length;
  if (requiredHostCount === 0) {
    fail("zero required host tests discovered");
  }

  const unsignedInventory = {
    schemaVersion: 1,
    policyDigest: digest(validatedPolicy),
    changeIdentity: validatedChangeIdentity,
    requiredHostCount,
    testChanges,
    tests: discovered,
  };
  return {
    ...unsignedInventory,
    inventoryDigest: digest(unsignedInventory),
  };
}

function validateInventory(inventory) {
  if (!inventory || typeof inventory !== "object" || Array.isArray(inventory)) {
    fail("invalid inventory object");
  }
  const { inventoryDigest, ...unsignedInventory } = inventory;
  if (inventory.schemaVersion !== 1) {
    fail(`unsupported inventory schemaVersion: ${inventory.schemaVersion}`);
  }
  if (typeof inventory.policyDigest !== "string" || !/^[0-9a-f]{64}$/u.test(inventory.policyDigest)) {
    fail("inventory policyDigest must be a lowercase SHA-256");
  }
  if (typeof inventoryDigest !== "string" || inventoryDigest !== digest(unsignedInventory)) {
    fail("inventory digest mismatch");
  }
  if (!Array.isArray(inventory.tests) || inventory.tests.length === 0) {
    fail("inventory contains zero tests");
  }
  if (!Array.isArray(inventory.testChanges)) {
    fail("inventory testChanges must be an array");
  }
  const changeIdentity = validateChangeIdentity(inventory.changeIdentity);
  if (inventory.testChanges.length > 0 && !changeIdentity) {
    fail("inventory testChanges require an exact change identity");
  }
  const paths = new Set();
  for (const entry of inventory.tests) {
    const repositoryPath = normalizeTrackedPath(entry.path, "inventory test path");
    const packagePath = normalizeTrackedPath(entry.packagePath, "inventory package path");
    if (paths.has(repositoryPath)) {
      fail(`duplicate inventory test path: ${repositoryPath}`);
    }
    paths.add(repositoryPath);
    if (packagePathFor(repositoryPath) !== packagePath) {
      fail(`inventory package path mismatch: ${repositoryPath}`);
    }
    if (!ALLOWED_CLASSIFICATIONS.has(entry.classification)) {
      fail(`unknown inventory classification: ${entry.classification}`);
    }
    requireNonBlankString(entry.owner, `inventory owner for ${repositoryPath}`);
  }
  const requiredHostCount = inventory.tests.filter(
    (entry) => entry.classification === REQUIRED_CLASS,
  ).length;
  if (requiredHostCount === 0 || requiredHostCount !== inventory.requiredHostCount) {
    fail("inventory requiredHostCount mismatch");
  }
  return inventory;
}

export function parseJsonReport(content) {
  if (typeof content !== "string") {
    fail("report content must be a string");
  }
  const events = [];
  for (const [index, rawLine] of content.split(/\r?\n/u).entries()) {
    const line = rawLine.trim();
    if (line.length === 0) {
      continue;
    }
    let event;
    try {
      event = JSON.parse(line);
    } catch (error) {
      fail(`invalid JSON reporter line ${index + 1}: ${error.message}`);
    }
    if (!event || typeof event !== "object" || Array.isArray(event) || typeof event.type !== "string") {
      fail(`invalid JSON reporter event at line ${index + 1}`);
    }
    events.push(event);
  }
  if (events.length === 0) {
    fail("zero reporter events");
  }
  return events;
}

function normalizeReportedSuitePath(value) {
  if (typeof value !== "string" || value.length === 0) {
    fail("suite path must be a non-empty string");
  }
  let normalized = value;
  if (normalized.startsWith("file:")) {
    try {
      normalized = new URL(normalized).pathname;
    } catch (error) {
      fail(`invalid suite file URL: ${error.message}`);
    }
  }
  normalized = decodeURIComponent(normalized).replaceAll("\\", "/");
  const packageMarker = "/apps/mobile/";
  const markerIndex = normalized.lastIndexOf(packageMarker);
  if (markerIndex !== -1) {
    normalized = normalized.slice(markerIndex + packageMarker.length);
  } else if (normalized.startsWith("apps/mobile/")) {
    normalized = normalized.slice("apps/mobile/".length);
  } else {
    normalized = normalized.replace(/^\.\//u, "");
    if (normalized.startsWith("/") || /^[A-Za-z]:\//u.test(normalized)) {
      fail(`absolute suite path is outside apps/mobile: ${value}`);
    }
  }
  return normalizeTrackedPath(normalized, "suite path");
}

function requireSingleEvent(events, type) {
  const matches = events.filter((event) => event.type === type);
  if (matches.length !== 1) {
    fail(`expected exactly one ${type} event, found ${matches.length}`);
  }
  return matches[0];
}

export function verifyExecutionParity({ inventory, events }) {
  validateInventory(inventory);
  if (!Array.isArray(events) || events.length === 0) {
    fail("zero reporter events");
  }
  let previousTime = -1;
  let sawAllSuites = false;
  for (const [index, event] of events.entries()) {
    if (!event || typeof event !== "object" || Array.isArray(event)) {
      fail(`invalid reporter event at index ${index}`);
    }
    if (!ALLOWED_REPORT_EVENT_TYPES.has(event.type)) {
      fail(`unknown reporter event type: ${event.type}`);
    }
    if (!Number.isFinite(event.time) || event.time < 0 || event.time < previousTime) {
      fail(`reporter event time is invalid or out of order at index ${index}`);
    }
    previousTime = event.time;
    if (index === 0 && event.type !== "start") {
      fail("start event must be first");
    }
    if (event.type === "allSuites") {
      if (index === 0 || sawAllSuites) {
        fail("allSuites event must occur exactly once after start");
      }
      sawAllSuites = true;
    } else if ((event.type === "suite" || event.type === "testStart") && !sawAllSuites) {
      fail(`${event.type} event occurred before allSuites`);
    }
  }
  const start = requireSingleEvent(events, "start");
  if (events[0] !== start || typeof start.protocolVersion !== "string") {
    fail("start event must be first and include protocolVersion");
  }
  const allSuites = requireSingleEvent(events, "allSuites");
  if (!Number.isInteger(allSuites.count) || allSuites.count <= 0) {
    fail("allSuites count must be a positive integer");
  }
  const doneEvents = events.filter((event) => event.type === "done");
  if (doneEvents.length !== 1) {
    fail(`expected exactly one final done event, found ${doneEvents.length}`);
  }
  const [done] = doneEvents;
  if (events.at(-1) !== done) {
    fail("final done event is missing or not terminal");
  }

  const inventoryByPackagePath = new Map(
    inventory.tests.map((entry) => [entry.packagePath, entry]),
  );
  const suitesById = new Map();
  const suitesByPath = new Map();
  for (const event of events.filter((entry) => entry.type === "suite")) {
    if (!event.suite) {
      fail("suite event has an invalid suite ID");
    }
    requirePositiveInteger(event.suite.id, "suite event ID");
    if (suitesById.has(event.suite.id)) {
      fail(`duplicate suite ID: ${event.suite.id}`);
    }
    const packagePath = normalizeReportedSuitePath(event.suite.path);
    if (suitesByPath.has(packagePath)) {
      fail(`duplicate suite path: ${packagePath}`);
    }
    const classified = inventoryByPackagePath.get(packagePath);
    if (!classified) {
      fail(`unexpected suite outside effective inventory: ${packagePath}`);
    }
    if (classified.classification === "NATIVE_INTEGRATION_OWNED_BY_MOBILE_72") {
      fail(`native integration suite cannot appear in host parity report: ${packagePath}`);
    }
    const suite = { id: event.suite.id, packagePath, classified };
    suitesById.set(suite.id, suite);
    suitesByPath.set(packagePath, suite);
  }
  if (suitesById.size !== allSuites.count) {
    fail(
      `allSuites count mismatch: declared=${allSuites.count} emitted=${suitesById.size}`,
    );
  }

  const testsById = new Map();
  for (const event of events.filter((entry) => entry.type === "testStart")) {
    if (!event.test) {
      fail("testStart event has invalid IDs");
    }
    requirePositiveInteger(event.test.id, "testStart test ID");
    requirePositiveInteger(event.test.suiteID, "testStart suite ID");
    if (testsById.has(event.test.id)) {
      fail(`duplicate test ID: ${event.test.id}`);
    }
    const suite = suitesById.get(event.test.suiteID);
    if (!suite) {
      fail(`testStart references unknown suite ID: ${event.test.suiteID}`);
    }
    testsById.set(event.test.id, { suite, done: null });
  }

  for (const event of events.filter((entry) => entry.type === "testDone")) {
    requirePositiveInteger(event.testID, "testDone test ID");
    const testState = testsById.get(event.testID);
    if (!testState) {
      fail(`testDone references unknown test ID: ${event.testID}`);
    }
    if (testState.done) {
      fail(`duplicate testDone for test ID: ${event.testID}`);
    }
    if (!ALLOWED_TEST_RESULTS.has(event.result)) {
      fail(`unknown test result: ${event.result}`);
    }
    if (typeof event.hidden !== "boolean" || typeof event.skipped !== "boolean") {
      fail(`testDone is missing hidden/skipped booleans for test ID: ${event.testID}`);
    }
    testState.done = event;
  }

  const errors = events.filter((entry) => entry.type === "error");
  if (errors.length > 0) {
    fail(`report contains ${errors.length} error event(s)`);
  }
  for (const [testID, state] of testsById) {
    if (!state.done) {
      fail(`test ID ${testID} has no terminal testDone event`);
    }
    if (state.done.result !== "success") {
      fail(`test ID ${testID} failed with result=${state.done.result}`);
    }
  }
  if (done.success !== true) {
    fail(`test runner did not succeed: done.success=${done.success}`);
  }

  const requiredFiles = inventory.tests
    .filter((entry) => entry.classification === REQUIRED_CLASS)
    .map((entry) => entry.path)
    .sort(codepointCompare);
  let nonSkippedTerminalTestCount = 0;
  for (const entry of inventory.tests.filter(
    (candidate) => candidate.classification === REQUIRED_CLASS,
  )) {
    const suite = suitesByPath.get(entry.packagePath);
    if (!suite) {
      fail(`missing required suite: ${entry.path}`);
    }
    const terminal = [...testsById.values()]
      .filter((state) => state.suite.id === suite.id)
      .map((state) => state.done);
    const visible = terminal.filter((event) => !event.hidden);
    const skipped = visible.filter((event) => event.skipped);
    const executed = visible.filter((event) => !event.skipped);
    if (visible.length === 0) {
      fail(`required suite has only hidden terminal events: ${entry.path}`);
    }
    if (executed.length === 0) {
      fail(`required suite has all skipped tests and no non-skipped terminal event: ${entry.path}`);
    }
    if (skipped.length > 0) {
      fail(`required suite contains a skipped test without an explicit disposition: ${entry.path}`);
    }
    nonSkippedTerminalTestCount += executed.length;
  }
  if (nonSkippedTerminalTestCount === 0) {
    fail("all required host tests were skipped");
  }

  return {
    schemaVersion: 1,
    inventoryDigest: inventory.inventoryDigest,
    policyDigest: inventory.policyDigest,
    protocolVersion: start.protocolVersion,
    runnerVersion: start.runnerVersion ?? null,
    requiredHostCount: requiredFiles.length,
    executedRequiredHostCount: requiredFiles.length,
    nonSkippedTerminalTestCount,
    reportedSuiteCount: suitesById.size,
    requiredFiles,
  };
}

function parseArgs(argv) {
  const [command, ...tokens] = argv;
  const args = { command };
  for (let index = 0; index < tokens.length; index += 1) {
    const token = tokens[index];
    if (!token.startsWith("--")) {
      fail(`unexpected positional argument: ${token}`);
    }
    const key = token.slice(2);
    const value = tokens[++index];
    if (value === undefined || value.startsWith("--")) {
      fail(`missing value for --${key}`);
    }
    args[key] = value;
  }
  return args;
}

function readJsonFile(filePath, label) {
  try {
    return JSON.parse(readFileSync(filePath, "utf8"));
  } catch (error) {
    fail(`cannot read ${label} ${filePath}: ${error.message}`);
  }
}

function writeJsonFile(filePath, value) {
  const resolved = path.resolve(filePath);
  mkdirSync(path.dirname(resolved), { recursive: true });
  writeFileSync(resolved, `${JSON.stringify(canonicalize(value), null, 2)}\n`, "utf8");
}

function readTrackedIndex(repository) {
  let raw;
  try {
    raw = execFileSync(
      "git",
      ["-C", repository, "ls-files", "--stage", "-z"],
      { encoding: "utf8", maxBuffer: 32 * 1024 * 1024 },
    );
  } catch (error) {
    fail(`git tracked-file discovery failed: ${error.message}`);
  }
  const trackedPaths = [];
  const symlinkPaths = [];
  for (const record of raw.split("\0")) {
    if (record.length === 0) {
      continue;
    }
    const match = /^(\d{6}) [0-9a-f]+ \d+\t([\s\S]+)$/u.exec(record);
    if (!match) {
      fail("cannot parse git ls-files --stage output");
    }
    const [, mode, trackedPath] = match;
    trackedPaths.push(trackedPath);
    if (mode === "120000") {
      symlinkPaths.push(trackedPath);
    }
  }
  return { trackedPaths, symlinkPaths };
}

function readGitChanges(repository, base, head) {
  let raw;
  try {
    raw = execFileSync(
      "git",
      ["-C", repository, "diff", "--name-status", "-z", "--find-renames", "--no-ext-diff", base, head],
      { encoding: "utf8", maxBuffer: 32 * 1024 * 1024 },
    );
  } catch (error) {
    fail(`git changed-file discovery failed: ${error.message}`);
  }
  const fields = raw.split("\0");
  if (fields.at(-1) === "") {
    fields.pop();
  }
  const statusNames = {
    A: "ADDED",
    M: "MODIFIED",
    D: "DELETED",
    R: "RENAMED",
    C: "COPIED",
    T: "TYPE_CHANGED",
    U: "UNMERGED_OR_UNKNOWN",
  };
  const changedEntries = [];
  for (let index = 0; index < fields.length;) {
    const statusToken = fields[index++];
    const status = statusNames[statusToken[0]];
    if (!status) {
      fail(`unsupported git change status: ${statusToken}`);
    }
    if (status === "RENAMED" || status === "COPIED") {
      if (index + 1 >= fields.length) {
        fail(`truncated git ${status} record`);
      }
      changedEntries.push({
        status,
        oldPath: fields[index++],
        newPath: fields[index++],
      });
    } else {
      if (index >= fields.length) {
        fail(`truncated git ${status} record`);
      }
      changedEntries.push({ status, path: fields[index++] });
    }
  }
  return changedEntries;
}

function usage() {
  return [
    "usage:",
    "  node tools/ci/mobile-host-test-parity.mjs discover --repository <repo> --policy <policy.json> --output <inventory.json> [--base <sha> --head <sha> --event <name>]",
    "  node tools/ci/mobile-host-test-parity.mjs verify --inventory <inventory.json> --report <events.jsonl> --summary <summary.json>",
    "",
  ].join("\n");
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  if (args.command === "discover") {
    for (const key of ["repository", "policy", "output"]) {
      if (!args[key]) {
        fail(`discover requires --${key}`);
      }
    }
    const policy = readJsonFile(path.resolve(args.policy), "policy");
    const repository = path.resolve(args.repository);
    const tracked = readTrackedIndex(repository);
    const identityArgs = [args.base, args.head, args.event].filter(Boolean);
    if (identityArgs.length !== 0 && identityArgs.length !== 3) {
      fail("discover requires --base, --head, and --event together");
    }
    const changeIdentity =
      identityArgs.length === 3
        ? { base: args.base, head: args.head, event: args.event }
        : null;
    const changedEntries = changeIdentity
      ? readGitChanges(repository, changeIdentity.base, changeIdentity.head)
      : [];
    const inventory = buildInventory({
      ...tracked,
      changedEntries,
      changeIdentity,
      policy,
    });
    writeJsonFile(args.output, inventory);
    process.stdout.write(
      `mobile-host-test-parity: discovered=${inventory.tests.length} required=${inventory.requiredHostCount} inventory=${inventory.inventoryDigest}\n`,
    );
    return;
  }
  if (args.command === "verify") {
    for (const key of ["inventory", "report", "summary"]) {
      if (!args[key]) {
        fail(`verify requires --${key}`);
      }
    }
    const inventory = readJsonFile(path.resolve(args.inventory), "inventory");
    const events = parseJsonReport(readFileSync(path.resolve(args.report), "utf8"));
    const summary = verifyExecutionParity({ inventory, events });
    writeJsonFile(args.summary, summary);
    process.stdout.write(
      `mobile-host-test-parity: required=${summary.requiredHostCount} executed=${summary.executedRequiredHostCount} terminal=${summary.nonSkippedTerminalTestCount} inventory=${summary.inventoryDigest}\n`,
    );
    return;
  }
  process.stderr.write(usage());
  process.exitCode = 1;
}

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  try {
    main();
  } catch (error) {
    process.stderr.write(`${error.message}\n`);
    process.exitCode = 1;
  }
}
