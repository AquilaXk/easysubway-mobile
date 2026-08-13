import assert from "node:assert/strict";
import { execFileSync, spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { EventEmitter } from "node:events";
import { mkdirSync, mkdtempSync, readFileSync, readdirSync, realpathSync, renameSync, rmSync, writeFileSync } from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { analyze, changedExecutableLines, commitArtifactPair, derivePhase2Decision, flutterVersionFromMachine, inheritPureRenameDisposition, parseBaselineBytes, parseNameStatusZ, parseNumstatZ, parsePolicyBytes, requestOwnerIssue, runCli, serializeBaseline, strictExternalJson, treeSources, validateDiffTuples, validateEventIdentity, validateOwnerIssueResponse, verifyArtifactDirectory } from "./mobile-coverage-ratchet.mjs";
import { normalizeLcov } from "./filter-mobile-lcov.mjs";

const policyFile = new URL("./mobile-coverage-policy.json", import.meta.url);
const baselineFile = new URL("./mobile-coverage-baseline.json", import.meta.url);
const repositoryRoot = path.resolve(".");
const temporaryRoot = realpathSync(os.tmpdir());

test("Phase 2 canonical policy와 reviewed line-oriented baseline을 닫힌 계약으로 허용한다", () => {
  const policy = parsePolicyBytes(readFileSync(policyFile));
  const baseline = parseBaselineBytes(readFileSync(baselineFile));
  assert.deepEqual(policy.transition, { phase: "REVIEWED_BASELINE_ENFORCED", baselineReviewed: true });
  assert.deepEqual(baseline.reviewState, { phase: "REVIEWED", reviewed: true });
  assert.deepEqual(policy.thresholds, {
    repositoryLineBasisPoints: 8712,
    changedLineBasisPoints: 10000,
    criticalBoundaryLineBasisPoints: {
      JOURNEY_ROUTE_INGRESS: 9328,
      JOURNEY_REPOSITORY_DI_STATE_IDENTITY: 9260,
      DATAPACK_CATALOG_LIFECYCLE: 8005,
      ACCESSIBILITY_ERROR_TRUTHFULNESS: 8904,
      ALARM_WIDGET_REPORT_IO: 8161,
      CRASHLYTICS_PRIVACY: 8596,
      CONTRACT_ARTIFACT_IDENTITY: 7119,
    },
  });
  assert.equal(baseline.paths.length, 187);
  assert.deepEqual(baseline.criticalBoundaries.map(({ id }) => id), Object.keys(policy.thresholds.criticalBoundaryLineBasisPoints));
  assert.deepEqual(baseline.paths.reduce((summary, source) => ({
    sources: summary.sources + 1,
    included: summary.included + Number(!source.path.endsWith(".g.dart")),
    excluded: summary.excluded + Number(source.path.endsWith(".g.dart")),
    lcovPresent: summary.lcovPresent + Number(source.lcovPresent),
  }), { sources: 0, included: 0, excluded: 0, lcovPresent: 0 }), { sources: 187, included: 185, excluded: 2, lcovPresent: 183 });
  const ordinaryMissing = baseline.paths.filter((source) => source.absenceDisposition?.kind === "EXISTING_UNINSTRUMENTED_BASELINE");
  assert.deepEqual(ordinaryMissing.map(({ path: sourcePath }) => sourcePath), [
    "apps/mobile/lib/features/network_map/domain/route_map_major_stations.dart",
    "apps/mobile/lib/features/stations/presentation/station_detail_header.dart",
  ]);
  assert.equal(baseline.paths.filter((source) => !source.lcovPresent && source.absenceDisposition === null).length, 2);
  assert.deepEqual(policy.exclusions.map(({ id, availability }) => [id, availability]), [
    ["DRIFT_CATALOG_DATABASE_GENERATED", "TRACKED_GENERATED_REQUIRED"],
    ["DRIFT_USER_DATABASE_GENERATED", "TRACKED_GENERATED_REQUIRED"],
    ["JOURNEY_V3_CONTRACT_GENERATED", "RESERVED_ABSENT_OR_TRACKED_GENERATED"],
    ["JOURNEY_V3_ENUMS_GENERATED", "RESERVED_ABSENT_OR_TRACKED_GENERATED"],
    ["JOURNEY_V3_ERROR_GENERATED", "RESERVED_ABSENT_OR_TRACKED_GENERATED"],
    ["JOURNEY_V3_MODELS_GENERATED", "RESERVED_ABSENT_OR_TRACKED_GENERATED"],
    ["JOURNEY_V3_VALIDATION_GENERATED", "RESERVED_ABSENT_OR_TRACKED_GENERATED"],
  ]);
});

test("Facility Report root 삭제는 critical boundaries를 feature owner에 보존한다", () => {
  const policy = parsePolicyBytes(readFileSync(policyFile));
  for (const boundary of [
    "ACCESSIBILITY_ERROR_TRUTHFULNESS",
    "ALARM_WIDGET_REPORT_IO",
    "CRASHLYTICS_PRIVACY",
  ]) {
    assert.ok(
      policy.criticalBoundaryRules[boundary].includes(
        "features/facility_report/",
      ),
      `${boundary} must retain the Facility Report feature owner`,
    );
    assert.ok(
      !policy.criticalBoundaryRules[boundary].includes("facility_report.dart"),
      `${boundary} must not retain the deleted root path`,
    );
  }
});

test("Network Map root 삭제는 accessibility critical boundary를 app owner에 보존한다", () => {
  const policy = parsePolicyBytes(readFileSync(policyFile));
  const boundary = policy.criticalBoundaryRules.ACCESSIBILITY_ERROR_TRUTHFULNESS;

  assert.ok(boundary.includes("app/network_map_screen.dart"));
  assert.ok(!boundary.includes("network_map.dart"));
});

test("비정규 policy/baseline과 mixed Phase 2 transition·floor drift를 거부한다", () => {
  const policy = JSON.parse(readFileSync(policyFile, "utf8"));
  assert.throws(() => parsePolicyBytes(Buffer.from(JSON.stringify(policy))));
  const baseline = JSON.parse(readFileSync(baselineFile, "utf8"));
  baseline.reviewState = { phase: "UNREVIEWED_DISCOVERY", reviewed: false };
  assert.throws(() => parseBaselineBytes(Buffer.from(`${JSON.stringify(baseline, null, 2)}\n`)));
  policy.thresholds.changedLineBasisPoints = null;
  assert.throws(() => parsePolicyBytes(Buffer.from(`${JSON.stringify(policy, null, 2)}\n`)));
});

test("Phase 2 baseline serializer, owner API, Flutter producer는 closed contract를 강제한다", () => {
  const owner = { statusCode: 200, redirected: false, body: Buffer.from('{"number":102,"html_url":"https://github.com/AquilaXk/easysubway-mobile/issues/102","state":"open"}') };
  const baselineBytes = readFileSync(baselineFile);
  const baseline = parseBaselineBytes(baselineBytes);
  assert.equal(serializeBaseline(baseline), baselineBytes.toString("utf8"));
  assert.throws(() => parseBaselineBytes(Buffer.from(baselineBytes.toString("utf8").replace('    {"path"', '     {"path"'))), /reviewed Phase 2 pin/i);
  assert.equal(validateOwnerIssueResponse(owner).number, 102);
  for (const response of [{ ...owner, statusCode: 404 }, { ...owner, redirected: true }, { ...owner, body: Buffer.from('{"number":102,"html_url":"https://github.com/AquilaXk/easysubway-mobile/issues/102","state":"closed"}') }, { ...owner, body: Buffer.from('{"number":102,"html_url":"https://github.com/AquilaXk/easysubway-mobile/issues/102","state":"open","pull_request":{}}') }]) assert.throws(() => validateOwnerIssueResponse(response));
  assert.equal(flutterVersionFromMachine(Buffer.from('{"frameworkVersion":"3.44.0"}')), "3.44.0");
  for (const output of [Buffer.from("not json"), Buffer.from('{"frameworkVersion":"3.45.0"}'), Buffer.from('{"other":"3.44.0"}')]) assert.throws(() => flutterVersionFromMachine(output));
});

test("F1/F3/F5 Phase 2 decision, external JSON, pure rename inheritance를 fail-closed로 닫는다", () => {
  const floorBoundaries = [
    { id: "JOURNEY_ROUTE_INGRESS", lineBasisPoints: 9327 },
    { id: "JOURNEY_REPOSITORY_DI_STATE_IDENTITY", lineBasisPoints: 9260 },
    { id: "DATAPACK_CATALOG_LIFECYCLE", lineBasisPoints: 8005 },
    { id: "ACCESSIBILITY_ERROR_TRUTHFULNESS", lineBasisPoints: 8904 },
    { id: "ALARM_WIDGET_REPORT_IO", lineBasisPoints: 8161 },
    { id: "CRASHLYTICS_PRIVACY", lineBasisPoints: 8596 },
    { id: "CONTRACT_ARTIFACT_IDENTITY", lineBasisPoints: 7119 },
  ];
  assert.deepEqual(derivePhase2Decision({ coverage: { lineBasisPoints: 8711 }, changedLines: { entries: [{ hits: 0 }], lineBasisPoints: 9999 }, criticalBoundaries: floorBoundaries }), { reasons: ["UNCOVERED_CHANGED_EXECUTABLE_LINE", "REPOSITORY_LINE_FLOOR_NOT_MET", "CHANGED_LINE_FLOOR_NOT_MET", "CRITICAL_BOUNDARY_LINE_FLOOR_NOT_MET"], outcome: "FAIL" });
  assert.deepEqual(derivePhase2Decision({ coverage: { lineBasisPoints: 8712 }, changedLines: { entries: [], lineBasisPoints: null }, criticalBoundaries: floorBoundaries.map((entry) => ({ ...entry, lineBasisPoints: { JOURNEY_ROUTE_INGRESS: 9328, JOURNEY_REPOSITORY_DI_STATE_IDENTITY: 9260, DATAPACK_CATALOG_LIFECYCLE: 8005, ACCESSIBILITY_ERROR_TRUTHFULNESS: 8904, ALARM_WIDGET_REPORT_IO: 8161, CRASHLYTICS_PRIVACY: 8596, CONTRACT_ARTIFACT_IDENTITY: 7119 }[entry.id] })) }), { reasons: [], outcome: "PASS" });
  for (const text of ['{"frameworkVersion":"3.44.0","frameworkVersion":"3.44.0"}', '{"outer":{"x":1,"x":2}}', '\ufeff{"frameworkVersion":"3.44.0"}', '{"frameworkVersion":"3.44.0"}\0', '{"frameworkVersion":"3.44.0"} trailing']) assert.throws(() => strictExternalJson(Buffer.from(text), "external"));
  const receipt = "apps/mobile/lib/generated/journey_v3/journey_v3_generation_receipt.json";
  assert.throws(() => parseNameStatusZ(Buffer.from(`M\0${receipt}\0`)), /ambiguous/i);
  assert.throws(() => parseNumstatZ(Buffer.from(`1\t0\t${receipt}\0`)), /ambiguous/i);
  const disposition = { kind: "EXISTING_UNINSTRUMENTED_BASELINE" };
  const pureRename = { status: "RENAMED", oldPath: "apps/mobile/lib/old.dart", newPath: "apps/mobile/lib/new.dart", added: 0 };
  const reviewedMissing = { sourceSha256: "a".repeat(64), absenceDisposition: disposition };
  assert.equal(inheritPureRenameDisposition(pureRename, reviewedMissing, "a".repeat(64), "a".repeat(64)), disposition);
  for (const [change, baselineSha, oldSha, newSha] of [
    [{ ...pureRename, added: 1 }, "a".repeat(64), "a".repeat(64), "a".repeat(64)],
    [{ ...pureRename, oldPath: "apps/mobile/lib/alias.dart", newPath: "apps/mobile/lib/alias.dart" }, "a".repeat(64), "a".repeat(64), "a".repeat(64)],
    [{ ...pureRename, status: "COPIED" }, "a".repeat(64), "a".repeat(64), "a".repeat(64)],
    [pureRename, "b".repeat(64), "a".repeat(64), "a".repeat(64)],
    [pureRename, "a".repeat(64), "b".repeat(64), "a".repeat(64)],
  ]) assert.throws(() => inheritPureRenameDisposition(change, { ...reviewedMissing, sourceSha256: baselineSha }, oldSha, newSha), /exact pure rename/i);
  const renamed = validateDiffTuples(
    parseNameStatusZ(Buffer.from("R100\0apps/mobile/lib/old.dart\0apps/mobile/lib/new.dart\0")),
    parseNumstatZ(Buffer.from("0\t0\t\0apps/mobile/lib/old.dart\0apps/mobile/lib/new.dart\0")),
  );
  assert.deepEqual(renamed, [{ ...pureRename, deleted: 0 }]);
  assert.throws(() => validateDiffTuples(
    parseNameStatusZ(Buffer.from("R100\0apps/mobile/lib/old.dart\0apps/mobile/lib/new.dart\0")),
    parseNumstatZ(Buffer.from("0\t0\t\0apps/mobile/lib/old.dart\0apps/mobile/lib/other.dart\0")),
  ), /tuple path mismatch/i);
  assert.throws(() => validateDiffTuples(
    parseNameStatusZ(Buffer.from("R100\0apps/mobile/lib/alias.dart\0apps/mobile/lib/alias.dart\0")),
    parseNumstatZ(Buffer.from("0\t0\t\0apps/mobile/lib/alias.dart\0apps/mobile/lib/alias.dart\0")),
  ), /aliases one path/i);
});

test("F4 CLI는 invalid argument/outcome 전에 owner request를 만들지 않고 bounded injected request를 닫는다", async () => {
  let requests = 0;
  const owner = async () => { requests += 1; return { statusCode: 200, redirected: false, body: Buffer.from('{"number":102,"html_url":"https://github.com/AquilaXk/easysubway-mobile/issues/102","state":"open"}') }; };
  await assert.rejects(runCli(["analyze", "--event", "workflow_dispatch"], { requestOwnerIssueFn: owner }));
  await assert.rejects(runCli(["verdict", "--analysis-outcome", "failure", "--upload-outcome", "success"], { requestOwnerIssueFn: owner }));
  assert.equal(requests, 0);
  for (const response of ["error", "slow", "oversize", "stream-error"]) await assert.rejects(requestOwnerIssue({ token: "test", requestImpl: () => { throw new Error(response); }, timeoutMs: 1, maxBytes: 1 }));
});

test("F1 verdict는 Phase 2 FAIL artifact의 coordinated PASS/reasons/summary rewrite를 거부한다", () => {
  const dir = mkdtempSync(path.join(temporaryRoot, "mobile-ratchet-"));
  const owner = { statusCode: 200, redirected: false, body: Buffer.from('{"number":102,"html_url":"https://github.com/AquilaXk/easysubway-mobile/issues/102","state":"open"}') };
  try {
    const artifact = path.join(dir, "artifact"); analyze(discoveryInput(dir), { repositoryRoot, reportDirectory: artifact });
    const inventoryFile = path.join(artifact, "mobile-coverage-source-inventory.json"); const resultFile = path.join(artifact, "mobile-coverage-result.json");
    const inventory = JSON.parse(readFileSync(inventoryFile, "utf8")); const result = JSON.parse(readFileSync(resultFile, "utf8"));
    inventory.producer.flutterVersion = "3.44.0"; result.phase = "REVIEWED_BASELINE_ENFORCED"; result.producer.flutterVersion = "3.44.0"; result.reasons = []; result.outcome = "PASS"; result.producer.sourceInventorySha256 = sha(Buffer.from(`${JSON.stringify(inventory, null, 2)}\n`));
    writeFileSync(inventoryFile, `${JSON.stringify(inventory, null, 2)}\n`); writeFileSync(resultFile, `${JSON.stringify(result, null, 2)}\n`); writeFileSync(path.join(artifact, "mobile-coverage-summary.md"), `# Mobile coverage ratchet\n\nEvent: ${result.identity.event}\nBase SHA: ${result.identity.baseSha}\nHead SHA: ${result.identity.headSha}\nMerge base SHA: ${result.identity.mergeBaseSha}\nTested merge SHA: ${result.identity.testedMergeSha}\nOutcome: PASS\n`);
    assert.throws(() => verifyArtifactDirectory(artifact, { repositoryRoot, phase2: true, ownerIssue: owner, flutterRunner: () => Buffer.from('{"frameworkVersion":"3.44.0"}') }), /cross-schema/i);
  } finally { rmSync(dir, { recursive: true, force: true }); }
});

test("F4 injected EventEmitter request는 total deadline, oversize와 stream error를 각각 reject한다", async () => {
  const fakeRequest = (schedule) => (_options, onResponse) => { const call = new EventEmitter(); call.end = () => schedule(onResponse, call); call.destroy = () => {}; return call; };
  await assert.rejects(requestOwnerIssue({ token: "test", requestImpl: fakeRequest(() => {}), timeoutMs: 5 }));
  await assert.rejects(requestOwnerIssue({ token: "test", requestImpl: fakeRequest((onResponse) => { const response = new EventEmitter(); response.statusCode = 200; onResponse(response); response.emit("data", Buffer.alloc(2)); }), maxBytes: 1 }));
  await assert.rejects(requestOwnerIssue({ token: "test", requestImpl: fakeRequest((onResponse) => { const response = new EventEmitter(); response.statusCode = 200; onResponse(response); response.emit("error", new Error("stream failure")); }) }));
});

test("provider diagnostic은 non-200의 숫자 allowlist header만 보존하고 body를 누출하지 않는다", async () => {
  const fakeResponse = (statusCode, headers, body = "secret-token=never-log") => (_options, onResponse) => { const call = new EventEmitter(); call.end = () => { const response = new EventEmitter(); response.statusCode = statusCode; response.headers = headers; onResponse(response); response.emit("data", Buffer.from(body)); response.emit("end"); }; call.destroy = () => {}; return call; };
  await assert.rejects(requestOwnerIssue({ token: "test", requestImpl: fakeResponse(403, { "x-ratelimit-remaining": "0", "x-ratelimit-reset": "12345", authorization: "Bearer secret" }) }), /statusCode=403 x-ratelimit-remaining=0 x-ratelimit-reset=12345/);
  await assert.rejects(requestOwnerIssue({ token: "test", requestImpl: fakeResponse(404, {}) }), /statusCode=404/);
  for (const headers of [{ "x-ratelimit-remaining": ["0"], "x-ratelimit-reset": "12345" }, { "x-ratelimit-remaining": "NaN", "x-ratelimit-reset": "12345" }, { "x-ratelimit-remaining": "0", "x-ratelimit-reset": "999999999999999999999" }]) await assert.rejects(requestOwnerIssue({ token: "test", requestImpl: fakeResponse(403, headers) }), /statusCode=403(?!.*secret-token|.*authorization)/);
});

test("owner issue retry는 최대 두 번과 제한된 provider backoff만 허용한다", async () => {
  const calls = [];
  const delays = [];
  const requestSequence = (responses) => (options, onResponse) => {
    calls.push(options);
    const call = new EventEmitter();
    call.destroy = () => {};
    call.end = () => {
      const next = responses.shift();
      const response = new EventEmitter();
      response.statusCode = next.statusCode;
      response.headers = next.headers ?? {};
      onResponse(response);
      response.emit("data", Buffer.from(next.body ?? "secret-token=never-log"));
      response.emit("end");
    };
    return call;
  };
  const owner = JSON.stringify({ number: 102, html_url: "https://github.com/AquilaXk/easysubway-mobile/issues/102", state: "open" });
  const success = { statusCode: 200, body: owner };
  const invoke = async (responses, { clock = () => 1000 } = {}) => requestOwnerIssue({ token: "test-token", requestImpl: requestSequence(responses), sleeper: async (delay) => delays.push(delay), clock });

  await invoke([{ statusCode: 503 }, success]);
  assert.equal(calls.length, 2);
  assert.deepEqual(delays, [1000]);
  assert.equal(calls[0].headers.Authorization, "Bearer test-token");
  delays.length = 0; calls.length = 0;

  await assert.rejects(invoke([{ statusCode: 503 }, { statusCode: 503 }]), /statusCode=503/);
  assert.equal(calls.length, 2);
  assert.deepEqual(delays, [1000]);
  delays.length = 0; calls.length = 0;

  await invoke([{ statusCode: 429, headers: { "retry-after": "12" } }, success]);
  assert.deepEqual(delays, [12000]);
  delays.length = 0; calls.length = 0;
  await invoke([{ statusCode: 403, headers: { "x-ratelimit-remaining": "0", "x-ratelimit-reset": "1030" } }, success]);
  assert.deepEqual(delays, [30000]);
  delays.length = 0; calls.length = 0;
  await invoke([{ statusCode: 403 }, success]);
  assert.deepEqual(delays, [60000]);
  delays.length = 0; calls.length = 0;

  for (const response of [
    { statusCode: 429, headers: { "retry-after": "61" } },
    { statusCode: 403, headers: { "retry-after": "bad" } },
    { statusCode: 429, headers: { "x-ratelimit-remaining": "0", "x-ratelimit-reset": "1061" } },
    { statusCode: 403, headers: { "x-ratelimit-remaining": "0", "x-ratelimit-reset": "bad" } },
    { statusCode: 404 },
  ]) {
    await assert.rejects(invoke([response, success]), /statusCode=/);
    assert.deepEqual(delays, []);
    assert.equal(calls.length, 1);
    delays.length = 0; calls.length = 0;
  }
  await assert.rejects(requestOwnerIssue({ requestImpl: () => { throw new Error("must not request"); } }), /OWNER_ISSUE_TOKEN is required/);
  assert.equal(calls.length, 0);
  await assert.rejects(invoke([{ statusCode: 404, body: "test-token secret-token=never-log" }]), (error) => !error.message.includes("test-token") && !error.message.includes("secret-token"));
});

const sha = (value) => createHash("sha256").update(value).digest("hex");
const head = execFileSync("git", ["rev-parse", "HEAD"], { encoding: "utf8" }).trim();
function discoveryInput(dir, event = "workflow_dispatch") {
  const raw = Buffer.from("SF:lib/accessible_design.dart\nDA:1,0\nLF:1\nLH:0\nend_of_record\nSF:lib/core/database/catalog/catalog_database.g.dart\nDA:1,0\nLF:1\nLH:0\nend_of_record\nSF:lib/core/database/user/user_database.g.dart\nDA:1,0\nLF:1\nLH:0\nend_of_record\n");
  const policyBytes = readFileSync(policyFile); const policy = parsePolicyBytes(policyBytes); const filtered = normalizeLcov(raw.toString("utf8"), { policy, repositoryRoot, policySha256: sha(policyBytes) }); const normalized = Buffer.from(filtered.content);
  const rawFile = path.join(dir, "raw.lcov"); const normalizedFile = path.join(dir, "normalized.lcov"); const filterFile = path.join(dir, "filter.json"); const eventFile = path.join(dir, "event.json");
  writeFileSync(rawFile, raw); writeFileSync(normalizedFile, normalized);
  writeFileSync(eventFile, JSON.stringify(event === "pull_request" ? { pull_request: { base: { sha: head }, head: { sha: head } } } : { ref: "refs/heads/main", after: head }));
  writeFileSync(filterFile, `${JSON.stringify(filtered.result)}\n`);
  return { event, eventPath: eventFile, baseSha: head, headSha: head, testedMergeSha: head, eventRef: event === "pull_request" ? "refs/pull/48/merge" : "refs/heads/main", pullRequestNumber: event === "pull_request" ? "48" : "none", rawLcov: rawFile, normalizedLcov: normalizedFile, filterResult: filterFile, policy: "tools/ci/mobile-coverage-policy.json", baseline: "tools/ci/mobile-coverage-baseline.json" };
}

test("Phase 1 analyzer는 manual artifact를 exact DISCOVERY_REMOTE_RED로 결속한다", () => {
  const dir = mkdtempSync(path.join(temporaryRoot, "mobile-ratchet-"));
  try {
    const manual = analyze(discoveryInput(dir), { repositoryRoot, reportDirectory: path.join(dir, "manual") });
    assert.equal(manual.outcome, "DISCOVERY_REMOTE_RED");
    assert.deepEqual(manual.reasons, ["BASELINE_UNREVIEWED"]);
    assert.equal(manual.changedLines.state, "NOT_APPLICABLE_MANUAL_FULL");
    assert.deepEqual(Object.keys(manual), ["schemaVersion", "artifactKind", "repository", "phase", "identity", "producer", "coverage", "changedLines", "criticalBoundaries", "exclusions", "artifacts", "reasons", "outcome"]);
    assert.deepEqual(Object.keys(manual.producer), ["policySha256", "baselineSha256", "filterSha256", "ratchetSha256", "rawLcovSha256", "normalizedLcovSha256", "sourceInventorySha256", "lcovTagSubset"]);
    assert.equal(readFileSync(path.join(dir, "manual", "mobile-coverage-result.json"), "utf8"), `${JSON.stringify(manual, null, 2)}\n`);
    assert.equal(verifyArtifactDirectory(path.join(dir, "manual")).outcome, "DISCOVERY_REMOTE_RED");
    assert.deepEqual(manual.exclusions.map(({ id }) => id), ["DRIFT_CATALOG_DATABASE_GENERATED", "DRIFT_USER_DATABASE_GENERATED", "JOURNEY_V3_CONTRACT_GENERATED", "JOURNEY_V3_ENUMS_GENERATED", "JOURNEY_V3_ERROR_GENERATED", "JOURNEY_V3_MODELS_GENERATED", "JOURNEY_V3_VALIDATION_GENERATED"]);
    assert.deepEqual(manual.criticalBoundaries.map(({ id }) => id), ["JOURNEY_ROUTE_INGRESS", "JOURNEY_REPOSITORY_DI_STATE_IDENTITY", "DATAPACK_CATALOG_LIFECYCLE", "ACCESSIBILITY_ERROR_TRUTHFULNESS", "ALARM_WIDGET_REPORT_IO", "CRASHLYTICS_PRIVACY", "CONTRACT_ARTIFACT_IDENTITY"]);
    assert.equal(manual.exclusions.length, 7);
    assert.equal(manual.coverage.lcovMissingSources.includes("apps/mobile/lib/core/database/catalog/catalog_database.g.dart"), true);
    assert.equal(manual.coverage.lcovMissingSources.includes("apps/mobile/lib/core/database/user/user_database.g.dart"), true);
    const inventory = JSON.parse(readFileSync(path.join(dir, "manual", "mobile-coverage-source-inventory.json"), "utf8"));
    assert.equal(inventory.sources.some((source) => source.path === "apps/mobile/lib/accessible_design.dart"), true);
    assert.equal(inventory.sources.every((source) => source.owners.length >= 1 && source.owners.length <= 4 && !source.owners.includes("UNKNOWN")), true);
  } finally { rmSync(dir, { recursive: true, force: true }); }
});

test("accepted CRLF raw LCOV는 분석과 artifact 재검증에서 canonical LF와 동등하다", () => {
  const dir = mkdtempSync(path.join(temporaryRoot, "mobile-ratchet-crlf-"));
  try {
    const options = discoveryInput(dir); const raw = readFileSync(options.rawLcov); writeFileSync(options.rawLcov, raw.toString("utf8").replaceAll("\n", "\r\n"));
    const filter = JSON.parse(readFileSync(options.filterResult, "utf8")); filter.inputSha256 = sha(readFileSync(options.rawLcov)); writeFileSync(options.filterResult, `${JSON.stringify(filter)}\n`);
    const artifact = path.join(dir, "artifact"); assert.equal(analyze(options, { repositoryRoot, reportDirectory: artifact }).outcome, "DISCOVERY_REMOTE_RED"); assert.equal(verifyArtifactDirectory(artifact, { repositoryRoot }).outcome, "DISCOVERY_REMOTE_RED");
    const invalidDirectory = path.join(dir, "invalid"); mkdirSync(invalidDirectory); const invalid = discoveryInput(invalidDirectory); const normalized = readFileSync(invalid.normalizedLcov, "utf8").replaceAll("\n", "\r\n"); writeFileSync(invalid.normalizedLcov, normalized); const invalidFilter = JSON.parse(readFileSync(invalid.filterResult, "utf8")); invalidFilter.outputSha256 = sha(normalized); writeFileSync(invalid.filterResult, `${JSON.stringify(invalidFilter)}\n`); assert.throws(() => analyze(invalid, { repositoryRoot, reportDirectory: path.join(dir, "invalid-artifact") }), /normalized LCOV/i);
  } finally { rmSync(dir, { recursive: true, force: true }); }
});

test("PR #140 상태의 tracked Journey 생성 5개와 LCOV 부재를 artifact 재계산까지 보존한다", () => {
  const dir = mkdtempSync(path.join(temporaryRoot, "journey-ratchet-"));
  const owner = { statusCode: 200, redirected: false, body: Buffer.from('{"number":102,"html_url":"https://github.com/AquilaXk/easysubway-mobile/issues/102","state":"open"}') };
  const paths = ["journey_v3_contract.dart", "journey_v3_enums.dart", "journey_v3_error.dart", "journey_v3_models.dart", "journey_v3_validation.dart"].map((name) => `apps/mobile/lib/generated/journey_v3/${name}`);
  const baseGit = { text: (args) => execFileSync("git", ["-C", repositoryRoot, ...args], { encoding: "utf8" }).trim(), bytes: (args) => execFileSync("git", ["-C", repositoryRoot, ...args]) };
  const baseTree = treeSources(head, baseGit); const missingPaths = paths.filter((file) => !baseTree.has(file)); const blobs = new Map(missingPaths.map((file, index) => [file, String(index + 1).repeat(40)]));
  const gitApi = { text: baseGit.text, bytes(args) { if (args[0] === "ls-tree") return Buffer.concat([baseGit.bytes(args), Buffer.from([...blobs].map(([file, blob]) => `100644 blob ${blob}\t${file}\0`).join(""))]); if (args[0] === "cat-file" && [...blobs.values()].includes(args[2])) return Buffer.from("// GENERATED CODE - DO NOT MODIFY BY HAND\n"); return baseGit.bytes(args); } };
  try {
    const options = discoveryInput(dir); const filter = JSON.parse(readFileSync(options.filterResult, "utf8"));
    for (const evidence of filter.exclusions.filter((entry) => paths.includes(entry.path))) Object.assign(evidence, { presence: "TRACKED_GENERATED", lcovRecordPresent: false, executableLines: 0, coveredLines: 0 });
    writeFileSync(options.filterResult, `${JSON.stringify(filter)}\n`);
    const artifact = path.join(dir, "artifact"); const result = analyze(options, { repositoryRoot, reportDirectory: artifact, gitApi });
    const inventory = JSON.parse(readFileSync(path.join(artifact, "mobile-coverage-source-inventory.json"), "utf8"));
    assert.equal(inventory.summary.sources, new Set([...baseTree.keys(), ...paths]).size); assert.equal(inventory.summary.excluded, 7);
    assert.equal(paths.every((file) => inventory.sources.filter((source) => source.path === file).length === 1), true);
    assert.deepEqual(result.exclusions.filter((entry) => paths.includes(entry.path)).map(({ presence, lcovRecordPresent, executableLines, coveredLines }) => [presence, lcovRecordPresent, executableLines, coveredLines]), Array(5).fill(["TRACKED_GENERATED", false, 0, 0]));
    assert.equal(verifyArtifactDirectory(artifact, { repositoryRoot, gitApi }).phase, "DISCOVERY_REMOTE_RED");
    const resultFile = path.join(artifact, "mobile-coverage-result.json"); const canonical = readFileSync(resultFile, "utf8");
    for (const [key, value] of [["presence", "RESERVED_ABSENT"], ["lcovRecordPresent", true]]) { const tampered = JSON.parse(canonical); tampered.exclusions[2][key] = value; writeFileSync(resultFile, `${JSON.stringify(tampered, null, 2)}\n`); assert.throws(() => verifyArtifactDirectory(artifact, { repositoryRoot, gitApi })); writeFileSync(resultFile, canonical); }
  } finally { rmSync(dir, { recursive: true, force: true }); }
});

test("analyzer는 digest mismatch와 event identity mismatch를 fail-closed로 거부한다", () => {
  const dir = mkdtempSync(path.join(temporaryRoot, "mobile-ratchet-"));
  try {
    const options = discoveryInput(dir); const filter = JSON.parse(readFileSync(options.filterResult, "utf8")); filter.inputSha256 = "0".repeat(64); writeFileSync(options.filterResult, JSON.stringify(filter));
    assert.throws(() => analyze(options, { repositoryRoot, reportDirectory: path.join(dir, "out") }), /filter identity/i);
    const mismatch = discoveryInput(dir, "pull_request"); mismatch.pullRequestNumber = "none";
    assert.throws(() => analyze(mismatch, { repositoryRoot, reportDirectory: path.join(dir, "out") }), /pull request/i);
  } finally { rmSync(dir, { recursive: true, force: true }); }
});

test("CLI는 malformed/missing/duplicate argument와 intentional discovery verdict를 거부한다", () => {
  assert.equal(spawnSync("node", ["tools/ci/mobile-coverage-ratchet.mjs", "analyze", "--event", "workflow_dispatch"]).status, 2);
  assert.equal(spawnSync("node", ["tools/ci/mobile-coverage-ratchet.mjs", "verdict", "--analysis-outcome", "success", "--analysis-outcome", "success", "--upload-outcome", "success"]).status, 2);
  assert.equal(spawnSync("node", ["tools/ci/mobile-coverage-ratchet.mjs", "verdict", "--analysis-outcome", "success", "--upload-outcome", "success"]).status, 1);
});

test("Phase 2 enforced workflow는 ratchet 분석·artifact·verdict를 고정 배선한다", () => {
  const workflow = readFileSync(path.join(repositoryRoot, ".github/workflows/ci.yml"), "utf8");
  const analyze = [
    "      - name: Analyze mobile coverage ratchet",
    "        id: coverage_ratchet_analyze",
    "        env:",
    "          OWNER_ISSUE_TOKEN: ${{ secrets.GITHUB_TOKEN }}",
    "          RATCHET_EVENT: ${{ github.event_name }}",
    "          RATCHET_EVENT_PATH: ${{ github.event_path }}",
    "          RATCHET_BASE_SHA: ${{ github.event.pull_request.base.sha || github.event.before || github.sha }}",
    "          RATCHET_HEAD_SHA: ${{ github.event.pull_request.head.sha || github.sha }}",
    "          RATCHET_TESTED_MERGE_SHA: ${{ github.sha }}",
    "          RATCHET_EVENT_REF: ${{ github.ref }}",
    "          RATCHET_PR_NUMBER: ${{ github.event.pull_request.number || 'none' }}",
    "        run: |",
    "          node tools/ci/mobile-coverage-ratchet.mjs analyze \\",
    "            --event \"${RATCHET_EVENT}\" \\",
    "            --event-path \"${RATCHET_EVENT_PATH}\" \\",
    "            --base-sha \"${RATCHET_BASE_SHA}\" \\",
    "            --head-sha \"${RATCHET_HEAD_SHA}\" \\",
    "            --tested-merge-sha \"${RATCHET_TESTED_MERGE_SHA}\" \\",
    "            --event-ref \"${RATCHET_EVENT_REF}\" \\",
    "            --pull-request-number \"${RATCHET_PR_NUMBER}\" \\",
    "            --raw-lcov apps/mobile/coverage/lcov.info \\",
    "            --normalized-lcov \"${RUNNER_TEMP}/mobile-coverage-normalized.lcov\" \\",
    "            --filter-result \"${RUNNER_TEMP}/mobile-coverage-filter-result.json\" \\",
    "            --policy tools/ci/mobile-coverage-policy.json \\",
    "            --baseline tools/ci/mobile-coverage-baseline.json",
  ].join("\n");
  const upload = [
    "      - name: Upload mobile coverage ratchet evidence",
    "        id: coverage_ratchet_upload",
    "        if: always()",
    "        uses: actions/upload-artifact@65462800fd760344b1a7b4382951275a0abb4808",
    "        with:",
    "          name: mobile-coverage-ratchet-${{ github.event.pull_request.head.sha || github.sha }}",
    "          path: ${{ runner.temp }}/mobile-coverage-ratchet",
    "          retention-days: 5",
    "          if-no-files-found: error",
  ].join("\n");
  const verdict = [
    "      - name: Enforce mobile coverage ratchet verdict",
    "        if: always()",
    "        env:",
    "          OWNER_ISSUE_TOKEN: ${{ secrets.GITHUB_TOKEN }}",
    "        run: |",
    "          node tools/ci/mobile-coverage-ratchet.mjs verdict \\",
    "            --analysis-outcome \"${{ steps.coverage_ratchet_analyze.outcome }}\" \\",
    "            --upload-outcome \"${{ steps.coverage_ratchet_upload.outcome }}\"",
  ].join("\n");
  assert.equal(workflow.includes("tools/ci/mobile-coverage-ratchet.test.mjs"), true);
  for (const block of [analyze, upload, verdict]) {
    assert.equal(workflow.includes(block), true, block);
    const start = workflow.indexOf(block); const end = workflow.indexOf("\n      - name:", start + block.length); const actualStep = workflow.slice(start, end === -1 ? undefined : end);
    assert.equal(actualStep.includes("continue-on-error"), false);
  }
});

test("F2 injected seam은 event payload/ref/unique ancestor contract를 fail-closed로 판정한다", () => {
  const options = { event: "pull_request", pullRequestNumber: "48", eventRef: "refs/pull/48/merge", baseSha: "a".repeat(40), headSha: "b".repeat(40), testedMergeSha: "c".repeat(40) };
  const event = { pull_request: { base: { sha: options.baseSha }, head: { sha: options.headSha } } };
  const calls = []; const git = (args) => { calls.push(args); if (args[0] === "rev-parse") return options.testedMergeSha; if (args.includes("--is-ancestor")) return ""; if (args.includes("--all")) return "d".repeat(40); return ""; };
  assert.deepEqual(validateEventIdentity(options, event, git), { eventMode: "PULL_REQUEST", mergeBaseSha: "d".repeat(40), range: `${"d".repeat(40)}..${options.headSha}` });
  assert.throws(() => validateEventIdentity(options, event, (args) => {
    if (args[0] === "rev-parse") return options.testedMergeSha;
    if (args.includes("--all")) return "d".repeat(40);
    if (args.includes("--is-ancestor") && args.at(-1) === options.testedMergeSha) throw new Error("not a parent");
    return "";
  }), /tested merge/i);
  assert.throws(() => validateEventIdentity({ ...options, event: "push", eventRef: "refs/heads/main", pullRequestNumber: "none", baseSha: "a".repeat(40), headSha: "b".repeat(40), testedMergeSha: "c".repeat(40) }, { ref: "refs/heads/main", before: "a".repeat(40), after: "b".repeat(40) }, git), /push/i);
  assert.throws(() => validateEventIdentity({ ...options, testedMergeSha: options.headSha }, event, (args) => args[0] === "rev-parse" ? options.headSha : git(args)), /pull request/i);
  assert.throws(() => validateEventIdentity({ ...options, eventRef: "refs/heads/main" }, event, git));
  assert.throws(() => validateEventIdentity({ ...options, event: "push", eventRef: "refs/heads/main", pullRequestNumber: "none", baseSha: "0".repeat(40) }, { ref: "refs/heads/main", before: "0".repeat(40), after: options.headSha }, git));
  assert.throws(() => validateEventIdentity({ ...options, event: "workflow_dispatch", pullRequestNumber: "none", eventRef: "refs/heads/main", baseSha: options.headSha, testedMergeSha: options.headSha }, { ref: "refs/heads/other" }, git));
});

test("F2는 PR base·head에서 tested merge로의 조상 관계를 각각 독립적으로 닫는다", () => {
  const options = { event: "pull_request", pullRequestNumber: "48", eventRef: "refs/pull/48/merge", baseSha: "a".repeat(40), headSha: "b".repeat(40), testedMergeSha: "c".repeat(40) };
  const event = { pull_request: { base: { sha: options.baseSha }, head: { sha: options.headSha } } };
  const gitWithRejectedAncestor = (rejectedBase, rejectedTarget) => (args) => {
    if (args[0] === "rev-parse") return options.testedMergeSha;
    if (args.includes("--all")) return "d".repeat(40);
    if (args.includes("--is-ancestor") && args.at(-2) === rejectedBase && args.at(-1) === rejectedTarget) throw new Error("injected non-ancestor");
    return "";
  };
  assert.throws(() => validateEventIdentity(options, event, gitWithRejectedAncestor(options.baseSha, options.testedMergeSha)), /tested merge/i);
  assert.throws(() => validateEventIdentity(options, event, gitWithRejectedAncestor(options.headSha, options.testedMergeSha)), /tested merge/i);
  assert.throws(() => validateEventIdentity(options, event, (args) => args[0] === "rev-parse" ? "e".repeat(40) : gitWithRejectedAncestor("", "")(args)), /does not equal HEAD/i);
  assert.throws(() => validateEventIdentity({ ...options, event: "push", eventRef: "refs/heads/main", pullRequestNumber: "none" }, { ref: "refs/heads/main", before: options.baseSha, after: options.headSha }, (args) => args[0] === "rev-parse" ? options.testedMergeSha : ""), /push/i);
});

test("F1/F3 byte fixture는 raw NUL tuple, deletion 보존, binary/type 거부와 raw/tested blob mismatch를 닫는다", () => {
  const changes = parseNameStatusZ(Buffer.from("M\0apps/mobile/lib/a.dart\0R90\0apps/mobile/lib/old.dart\0apps/mobile/lib/new.dart\0C100\0apps/mobile/lib/copied-from.dart\0apps/mobile/lib/copied-to.dart\0D\0apps/mobile/lib/gone.dart\0"));
  assert.deepEqual(changes, [{ status: "MODIFIED", oldPath: null, newPath: "apps/mobile/lib/a.dart" }, { status: "RENAMED", oldPath: "apps/mobile/lib/old.dart", newPath: "apps/mobile/lib/new.dart" }, { status: "COPIED", oldPath: "apps/mobile/lib/copied-from.dart", newPath: "apps/mobile/lib/copied-to.dart" }, { status: "DELETED", oldPath: "apps/mobile/lib/gone.dart", newPath: null }]);
  const numstat = "1\t0\tapps/mobile/lib/a.dart\0" + "2\t0\t\0apps/mobile/lib/old.dart\0apps/mobile/lib/new.dart\0" + "2\t0\t\0apps/mobile/lib/copied-from.dart\0apps/mobile/lib/copied-to.dart\0" + "0\t1\tapps/mobile/lib/gone.dart\0";
  assert.deepEqual(validateDiffTuples(changes, parseNumstatZ(Buffer.from(numstat))).map(({ status, oldPath, newPath }) => ({ status, oldPath, newPath })), changes);
  assert.throws(() => parseNumstatZ(Buffer.from("-\t-\tapps/mobile/lib/a.dart\0")), /binary/i);
  assert.throws(() => parseNameStatusZ(Buffer.from("T\0apps/mobile/lib/a.dart\0")), /type/i);
  const rawPath = "apps/mobile/lib/a.dart"; const rawBlob = Buffer.from("final raw = 1;\n"); const testedBlob = Buffer.from("final shifted = 1;\n");
  const seam = {
    text: (args) => args.includes("--unified=0") ? `+++ b/${rawPath}\n@@ -1 +1 @@\n` : "",
    bytes: (args) => {
      if (args.includes("--name-status")) return Buffer.from(`M\0${rawPath}\0`);
      if (args.includes("--numstat")) return Buffer.from(`1\t0\t${rawPath}\0`);
      if (args[0] === "ls-tree") return Buffer.from(`100644 blob ${args[2] === "a".repeat(40) ? "1".repeat(40) : "2".repeat(40)}\t${rawPath}\0`);
      if (args[0] === "cat-file") return args.at(-1) === "1".repeat(40) ? rawBlob : testedBlob;
      throw new Error(`unexpected git bytes ${args.join(" ")}`);
    },
  };
  assert.throws(() => changedExecutableLines(`${head}..${head}`, "a".repeat(40), "b".repeat(40), new Map([[rawPath, new Map([[1, 1]])]]), seam), /deterministic line mapping/i);
  const deleted = validateDiffTuples(parseNameStatusZ(Buffer.from("D\0apps/mobile/lib/gone.dart\0")), parseNumstatZ(Buffer.from("0\t1\tapps/mobile/lib/gone.dart\0")));
  assert.equal(deleted[0].status, "DELETED");
});

test("changed executable set은 present SF의 exact DA hit·miss만 사용한다", () => {
  const rawPath = "apps/mobile/lib/domain.dart";
  const source = Buffer.from("import 'dart:ui';\n\nabstract interface class Port {\n  int get value;\n  int run() => 1;\n  int covered() => 2;\n}\n");
  const range = `${head}..${head}`; const productionDiffCalls = [];
  const diff = {
    text: (args) => { productionDiffCalls.push(args); return `+++ b/${rawPath}\n@@ -0,0 +1,7 @@\n`; },
    bytes: (args) => {
      if (args.includes("diff")) productionDiffCalls.push(args);
      if (args.includes("--name-status")) return Buffer.from(`A\0${rawPath}\0`);
      if (args.includes("--numstat")) return Buffer.from(`7\t0\t${rawPath}\0`);
      if (args[0] === "ls-tree") return Buffer.from(`100644 blob ${"a".repeat(40)}\t${rawPath}\0`);
      if (args[0] === "cat-file") return source;
      throw new Error(`unexpected git bytes ${args.join(" ")}`);
    },
  };
  const coverage = new Map([[rawPath, new Map([[5, 0], [6, 2]])]]);
  assert.deepEqual(changedExecutableLines(range, head, head, coverage, diff), {
    state: "APPLICABLE",
    entries: [
      { path: rawPath, line: 5, hits: 0, status: "ADDED" },
      { path: rawPath, line: 6, hits: 2, status: "ADDED" },
    ],
    executableLines: 2,
    coveredLines: 1,
    lineBasisPoints: 5000,
  });
  assert.deepEqual(productionDiffCalls.map((args) => args.find((arg) => ["--name-status", "--numstat", "--unified=0"].includes(arg))).sort(), ["--name-status", "--numstat", "--unified=0"]);
  for (const args of productionDiffCalls) assert.deepEqual(args.slice(-3), [range, "--", ":(glob)apps/mobile/lib/**/*.dart"]);
});

test("F1 changed executable set은 producer coverage-ignore 지시를 fail-closed한다", () => {
  const rawPath = "apps/mobile/lib/ignored.dart";
  const changed = (source) => ({
    text: () => `+++ b/${rawPath}\n@@ -0,0 +1,${source.toString("utf8").trimEnd().split("\n").length} @@\n`,
    bytes: (args) => {
      if (args.includes("--name-status")) return Buffer.from(`A\0${rawPath}\0`);
      if (args.includes("--numstat")) return Buffer.from(`${source.toString("utf8").trimEnd().split("\n").length}\t0\t${rawPath}\0`);
      if (args[0] === "ls-tree") return Buffer.from(`100644 blob ${"a".repeat(40)}\t${rawPath}\0`);
      if (args[0] === "cat-file") return source;
      throw new Error(`unexpected git bytes ${args.join(" ")}`);
    },
  });
  const coverage = new Map([[rawPath, new Map()]]);
  for (const source of [
    Buffer.from("final hidden = 1; // coverage:ignore-line reason_1\n"),
    Buffer.from("// coverage:ignore-start\nfinal hidden = 1;\n// coverage:ignore-end\n"),
    Buffer.from("// coverage:ignore-file generated_reason\nfinal hidden = 1;\n"),
  ]) {
    assert.throws(() => changedExecutableLines(`${head}..${head}`, head, head, coverage, changed(source)), /coverage-ignore directive/i);
  }
  const nearMiss = Buffer.from("// coverage:ignored-line\n");
  assert.deepEqual(changedExecutableLines(`${head}..${head}`, head, head, coverage, changed(nearMiss)), {
    state: "APPLICABLE", entries: [], executableLines: 0, coveredLines: 0, lineBasisPoints: null,
  });
});

test("Journey의 exact validated exclusion만 changed-line LCOV 부재를 건너뛴다", () => {
  const journey = "apps/mobile/lib/generated/journey_v3/journey_v3_contract.dart";
  const ordinary = "apps/mobile/lib/generated/other.dart";
  const seam = (rawPath) => ({
    text: () => `+++ b/${rawPath}\n@@ -0,0 +1 @@\n`,
    bytes: (args) => {
      if (args.includes("--name-status")) return Buffer.from(`A\0${rawPath}\0`);
      if (args.includes("--numstat")) return Buffer.from(`1\t0\t${rawPath}\0`);
      if (args[0] === "ls-tree") return Buffer.from(`100644 blob ${"a".repeat(40)}\t${rawPath}\0`);
      if (args[0] === "cat-file") return Buffer.from("final generated = 1;\n");
      throw new Error(`unexpected git bytes ${args.join(" ")}`);
    },
  });
  assert.deepEqual(changedExecutableLines(`${head}..${head}`, head, head, new Map(), seam(journey), new Set([journey])), { state: "APPLICABLE", entries: [], executableLines: 0, coveredLines: 0, lineBasisPoints: null });
  assert.throws(() => changedExecutableLines(`${head}..${head}`, head, head, new Map(), seam(ordinary), new Set([journey])), /missing LCOV/i);
});

test("F1 basis-point consumer는 실행 줄이 없으면 null을 보존한다", () => {
  const rawPath = "apps/mobile/lib/comment.dart"; const source = Buffer.from("// comment\n");
  const emptyDiff = {
    text: () => `+++ b/${rawPath}\n@@ -0,0 +1 @@\n`,
    bytes: (args) => {
      if (args.includes("--name-status")) return Buffer.from(`M\0${rawPath}\0`);
      if (args.includes("--numstat")) return Buffer.from(`1\t0\t${rawPath}\0`);
      if (args[0] === "ls-tree") return Buffer.from(`100644 blob ${"a".repeat(40)}\t${rawPath}\0`);
      if (args[0] === "cat-file") return source;
      throw new Error(`unexpected git bytes ${args.join(" ")}`);
    },
  };
  assert.deepEqual(changedExecutableLines(`${head}..${head}`, head, head, new Map([[rawPath, new Map()]]), emptyDiff), { state: "APPLICABLE", entries: [], executableLines: 0, coveredLines: 0, lineBasisPoints: null });
  assert.throws(() => changedExecutableLines(`${head}..${head}`, head, head, new Map(), emptyDiff), /changed source is missing LCOV/i);
});

test("F2 artifact pair는 두 번째 rename 실패 후 원래 destination과 clean staging을 복구한다", () => {
  const dir = mkdtempSync(path.join(temporaryRoot, "mobile-ratchet-")); const destination = path.join(dir, "artifacts"); mkdirSync(destination);
  const names = ["mobile-coverage-raw.lcov", "mobile-coverage-normalized.lcov", "mobile-coverage-source-inventory.json", "mobile-coverage-result.json", "mobile-coverage-summary.md"];
  const files = names.map((name) => ({ name, bytes: Buffer.from(name) })); let renameCalls = 0;
  try {
    assert.throws(() => commitArtifactPair(destination, files, { rename: (from, to) => { renameCalls += 1; if (renameCalls === 2) throw new Error("injected second rename failure"); renameSync(from, to); } }), /injected second rename failure/);
    assert.equal(renameCalls, 3);
    assert.deepEqual(readdirSync(destination), []);
    assert.deepEqual(readdirSync(dir).filter((name) => name.startsWith(".mobile-coverage-ratchet-stage-") || name.startsWith(".mobile-coverage-ratchet-backup-")), []);
  } finally { rmSync(dir, { recursive: true, force: true }); }
});

test("F3/F6 tree seam은 tested-merge regular blob inventory만 허용한다", () => {
  const tree = treeSources("a".repeat(40), { bytes: () => Buffer.from(`100644 blob ${"b".repeat(40)}\tapps/mobile/lib/root.dart\0`) });
  assert.deepEqual([...tree], [["apps/mobile/lib/root.dart", "b".repeat(40)]]);
  assert.throws(() => treeSources("a".repeat(40), { bytes: () => Buffer.from(`120000 blob ${"b".repeat(40)}\tapps/mobile/lib/root.dart\0`) }), /non-regular/i);
});

test("F5 verdict 재검증은 analyze 후 artifact mutation을 RED로 만든다", () => {
  const dir = mkdtempSync(path.join(temporaryRoot, "mobile-ratchet-"));
  try {
    analyze(discoveryInput(dir), { repositoryRoot, reportDirectory: path.join(dir, "out") });
    writeFileSync(path.join(dir, "out", "mobile-coverage-summary.md"), "tampered\n");
    assert.throws(() => verifyArtifactDirectory(path.join(dir, "out"), { repositoryRoot }), /cross-schema/i);
  } finally { rmSync(dir, { recursive: true, force: true }); }
});

test("F5 verdict는 nested inventory/result projection mutation을 모두 거부한다", () => {
  const dir = mkdtempSync(path.join(temporaryRoot, "mobile-ratchet-"));
  const mutate = (artifact, file, change) => {
    const target = path.join(artifact, file);
    const value = JSON.parse(readFileSync(target, "utf8"));
    change(value);
    writeFileSync(target, `${JSON.stringify(value, null, 2)}\n`);
  };
  const cases = [
    ["mobile-coverage-source-inventory.json", (inventory) => { inventory.sources[0].sourceSha256 = "0".repeat(64); }],
    ["mobile-coverage-source-inventory.json", (inventory) => { inventory.sources[0].owners = []; }],
    ["mobile-coverage-source-inventory.json", (inventory) => { inventory.summary.sources += 1; }],
    ["mobile-coverage-result.json", (result) => { result.coverage.lcovMissingSources = []; }],
    ["mobile-coverage-result.json", (result) => { result.changedLines.executableLines += 1; }],
    ["mobile-coverage-result.json", (result) => { result.criticalBoundaries[0].lcovMissingSources = []; }],
    ["mobile-coverage-result.json", (result) => { result.exclusions.pop(); }],
    ["mobile-coverage-result.json", (result) => { result.artifacts.files = []; }],
  ];
  try {
    for (const [index, [file, change]] of cases.entries()) {
      const artifact = path.join(dir, `out-${index}`);
      analyze(discoveryInput(dir), { repositoryRoot, reportDirectory: artifact });
      mutate(artifact, file, change);
      assert.throws(() => verifyArtifactDirectory(artifact, { repositoryRoot }), /artifact|cross-schema|producer/i, file);
    }
    const artifact = path.join(dir, "out-producer");
    analyze(discoveryInput(dir), { repositoryRoot, reportDirectory: artifact });
    const inventoryFile = path.join(artifact, "mobile-coverage-source-inventory.json"); const inventory = JSON.parse(readFileSync(inventoryFile, "utf8"));
    inventory.producer.policySha256 = "0".repeat(64); writeFileSync(inventoryFile, `${JSON.stringify(inventory, null, 2)}\n`);
    const resultFile = path.join(artifact, "mobile-coverage-result.json"); const result = JSON.parse(readFileSync(resultFile, "utf8"));
    result.producer.sourceInventorySha256 = sha(readFileSync(inventoryFile)); writeFileSync(resultFile, `${JSON.stringify(result, null, 2)}\n`);
    assert.throws(() => verifyArtifactDirectory(artifact, { repositoryRoot }), /producer/i);
  } finally { rmSync(dir, { recursive: true, force: true }); }
});

test("F7/F8/F9 verdict는 coordinated identity·normalized·tag-subset artifact rewrite를 거부한다", () => {
  const dir = mkdtempSync(path.join(temporaryRoot, "mobile-ratchet-"));
  const refreshInventoryDigest = (artifact) => {
    const inventoryFile = path.join(artifact, "mobile-coverage-source-inventory.json"); const resultFile = path.join(artifact, "mobile-coverage-result.json");
    const result = JSON.parse(readFileSync(resultFile, "utf8")); result.producer.sourceInventorySha256 = sha(readFileSync(inventoryFile)); writeFileSync(resultFile, `${JSON.stringify(result, null, 2)}\n`);
  };
  try {
    for (const [index, file, key, value] of [["inventory-schema", "mobile-coverage-source-inventory.json", "schemaVersion", 2], ["inventory-kind", "mobile-coverage-source-inventory.json", "artifactKind", "other"], ["inventory-repository", "mobile-coverage-source-inventory.json", "repository", "other/repository"], ["result-schema", "mobile-coverage-result.json", "schemaVersion", 2], ["result-kind", "mobile-coverage-result.json", "artifactKind", "other"], ["result-repository", "mobile-coverage-result.json", "repository", "other/repository"]]) {
      const artifact = path.join(dir, `top-level-${index}`); const inputDirectory = path.join(dir, `top-level-input-${index}`); mkdirSync(inputDirectory); analyze(discoveryInput(inputDirectory), { repositoryRoot, reportDirectory: artifact });
      const target = path.join(artifact, file); const valueJson = JSON.parse(readFileSync(target, "utf8")); valueJson[key] = value; writeFileSync(target, `${JSON.stringify(valueJson, null, 2)}\n`); if (file.includes("source-inventory")) refreshInventoryDigest(artifact);
      assert.throws(() => verifyArtifactDirectory(artifact, { repositoryRoot }), /top-level/i, index);
    }
    const parent = execFileSync("git", ["rev-parse", "HEAD^"], { encoding: "utf8" }).trim();
    const identityArtifact = path.join(dir, "identity"); analyze(discoveryInput(dir), { repositoryRoot, reportDirectory: identityArtifact });
    for (const file of ["mobile-coverage-source-inventory.json", "mobile-coverage-result.json"]) {
      const target = path.join(identityArtifact, file); const value = JSON.parse(readFileSync(target, "utf8"));
      value.identity = { ...value.identity, baseSha: parent, headSha: parent, mergeBaseSha: parent, testedMergeSha: parent, range: null }; writeFileSync(target, `${JSON.stringify(value, null, 2)}\n`);
    }
    refreshInventoryDigest(identityArtifact);
    const identityResult = JSON.parse(readFileSync(path.join(identityArtifact, "mobile-coverage-result.json"), "utf8")); writeFileSync(path.join(identityArtifact, "mobile-coverage-summary.md"), `# Mobile coverage ratchet\n\nEvent: ${identityResult.identity.event}\nBase SHA: ${parent}\nHead SHA: ${parent}\nMerge base SHA: ${parent}\nTested merge SHA: ${parent}\nOutcome: DISCOVERY_REMOTE_RED\n`);
    assert.throws(() => verifyArtifactDirectory(identityArtifact, { repositoryRoot }), /identity|HEAD|artifact/i);

    const normalizedArtifact = path.join(dir, "normalized"); const normalizedInputDirectory = path.join(dir, "normalized-input"); mkdirSync(normalizedInputDirectory); const normalizedInput = discoveryInput(normalizedInputDirectory);
    const normalized = readFileSync(normalizedInput.normalizedLcov, "utf8").replace("DA:1,0", "DA:1,1"); writeFileSync(normalizedInput.normalizedLcov, normalized);
    const filter = JSON.parse(readFileSync(normalizedInput.filterResult, "utf8")); filter.outputSha256 = sha(normalized); filter.lines.covered = 1; writeFileSync(normalizedInput.filterResult, `${JSON.stringify(filter)}\n`);
    analyze(normalizedInput, { repositoryRoot, reportDirectory: normalizedArtifact });
    assert.throws(() => verifyArtifactDirectory(normalizedArtifact, { repositoryRoot }), /normalized|artifact/i);

    for (const [index, subset] of [["empty", []], ["reordered", ["LH", "SF"]], ["duplicate", ["SF", "SF"]]]) {
      const artifact = path.join(dir, `tags-${index}`); const inputDirectory = path.join(dir, `tags-input-${index}`); mkdirSync(inputDirectory); analyze(discoveryInput(inputDirectory), { repositoryRoot, reportDirectory: artifact });
      const inventoryFile = path.join(artifact, "mobile-coverage-source-inventory.json"); const inventory = JSON.parse(readFileSync(inventoryFile, "utf8")); inventory.producer.lcovTagSubset = subset; writeFileSync(inventoryFile, `${JSON.stringify(inventory, null, 2)}\n`);
      const resultFile = path.join(artifact, "mobile-coverage-result.json"); const result = JSON.parse(readFileSync(resultFile, "utf8")); result.producer.lcovTagSubset = subset; writeFileSync(resultFile, `${JSON.stringify(result, null, 2)}\n`); refreshInventoryDigest(artifact);
      assert.throws(() => verifyArtifactDirectory(artifact, { repositoryRoot }), /tag|producer|artifact/i, index);
    }
  } finally { rmSync(dir, { recursive: true, force: true }); }
});
