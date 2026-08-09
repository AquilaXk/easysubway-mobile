import assert from "node:assert/strict";
import { execFileSync, spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { mkdtempSync, readFileSync, realpathSync, rmSync, writeFileSync } from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { analyze, changedExecutableLines, classifyDartLines, parseBaselineBytes, parseNameStatusZ, parseNumstatZ, parsePolicyBytes, treeSources, validateDiffTuples, validateEventIdentity, verifyArtifactDirectory } from "./mobile-coverage-ratchet.mjs";

const policyFile = new URL("./mobile-coverage-policy.json", import.meta.url);
const baselineFile = new URL("./mobile-coverage-baseline.json", import.meta.url);
const repositoryRoot = path.resolve(".");
const temporaryRoot = realpathSync(os.tmpdir());

test("Phase 1 canonical policy와 baseline skeleton을 닫힌 계약으로 허용한다", () => {
  const policy = parsePolicyBytes(readFileSync(policyFile));
  const baseline = parseBaselineBytes(readFileSync(baselineFile));
  assert.equal(policy.transition.phase, "DISCOVERY_REMOTE_RED");
  assert.equal(baseline.reviewState.phase, "UNREVIEWED_DISCOVERY");
  assert.deepEqual(baseline.paths, []);
  assert.deepEqual(baseline.criticalBoundaries, []);
});

test("비정규 policy/baseline과 Phase 1 측정값을 거부한다", () => {
  const policy = JSON.parse(readFileSync(policyFile, "utf8"));
  assert.throws(() => parsePolicyBytes(Buffer.from(JSON.stringify(policy))));
  const baseline = JSON.parse(readFileSync(baselineFile, "utf8"));
  baseline.floors.repositoryLineBasisPoints = 0;
  assert.throws(() => parseBaselineBytes(Buffer.from(`${JSON.stringify(baseline, null, 2)}\n`)));
});

test("Dart lexical scanner는 comment-only만 제외하고 문자열 속 주석 표시는 코드로 남긴다", () => {
  assert.deepEqual(classifyDartLines(Buffer.from("// comment\n/* outer\n * inner */\nfinal value = '// code';\n")), ["COMMENT_ONLY", "COMMENT_ONLY", "COMMENT_ONLY", "CODE"]);
  assert.throws(() => classifyDartLines(Buffer.from("/* unclosed")), /unterminated/i);
});

test("Dart lexical scanner는 nested block comment와 raw/triple 문자열을 fail-closed로 구분한다", () => {
  assert.deepEqual(classifyDartLines(Buffer.from("/* outer /* nested */ done */\nfinal raw = r'// literal';\nfinal text = '''/* literal */\nnext''';\n")), ["COMMENT_ONLY", "CODE", "CODE", "CODE"]);
  assert.throws(() => classifyDartLines(Buffer.from("final text = '''unterminated")), /unterminated/i);
  assert.throws(() => classifyDartLines(Buffer.from("final text = 'unterminated\n")), /unterminated/i);
});

const sha = (value) => createHash("sha256").update(value).digest("hex");
const head = execFileSync("git", ["rev-parse", "HEAD"], { encoding: "utf8" }).trim();
function discoveryInput(dir, event = "workflow_dispatch") {
  const raw = Buffer.from("SF:lib/accessible_design.dart\nDA:1,0\nLF:1\nLH:0\nend_of_record\n");
  const rawFile = path.join(dir, "raw.lcov"); const normalizedFile = path.join(dir, "normalized.lcov"); const filterFile = path.join(dir, "filter.json"); const eventFile = path.join(dir, "event.json");
  writeFileSync(rawFile, raw); writeFileSync(normalizedFile, raw);
  writeFileSync(eventFile, JSON.stringify(event === "pull_request" ? { pull_request: { base: { sha: head }, head: { sha: head } } } : { ref: "refs/heads/main", after: head }));
  writeFileSync(filterFile, `${JSON.stringify({ schemaVersion: 1, artifactKind: "mobile-lcov-filter-result-v1", policySha256: sha(readFileSync(policyFile)), inputSha256: sha(raw), outputSha256: sha(raw), records: { retained: 1, excluded: 2 }, lines: { executable: 1, covered: 0 }, exclusions: [{ path: "apps/mobile/lib/core/database/catalog/catalog_database.g.dart", reason: "DRIFT_CATALOG_DATABASE_GENERATED", executableLines: 0, coveredLines: 0 }, { path: "apps/mobile/lib/core/database/user/user_database.g.dart", reason: "DRIFT_USER_DATABASE_GENERATED", executableLines: 0, coveredLines: 0 }], outcome: "success" })}\n`);
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
    assert.equal(readFileSync(path.join(dir, "manual", "mobile-coverage-result.json"), "utf8"), `${JSON.stringify(manual, null, 2)}\n`);
    assert.equal(verifyArtifactDirectory(path.join(dir, "manual")).outcome, "DISCOVERY_REMOTE_RED");
    assert.deepEqual(manual.exclusions.map(({ id }) => id), ["DRIFT_CATALOG_DATABASE_GENERATED", "DRIFT_USER_DATABASE_GENERATED"]);
    assert.deepEqual(manual.criticalBoundaries.map(({ id }) => id), ["JOURNEY_ROUTE_INGRESS", "JOURNEY_REPOSITORY_DI_STATE_IDENTITY", "DATAPACK_CATALOG_LIFECYCLE", "ACCESSIBILITY_ERROR_TRUTHFULNESS", "ALARM_WIDGET_REPORT_IO", "CRASHLYTICS_PRIVACY", "CONTRACT_ARTIFACT_IDENTITY"]);
    assert.equal(manual.exclusions.length, 2);
    assert.equal(manual.coverage.lcovMissingSources.includes("apps/mobile/lib/core/database/catalog/catalog_database.g.dart"), true);
    assert.equal(manual.coverage.lcovMissingSources.includes("apps/mobile/lib/core/database/user/user_database.g.dart"), true);
    const inventory = JSON.parse(readFileSync(path.join(dir, "manual", "mobile-coverage-source-inventory.json"), "utf8"));
    assert.equal(inventory.sources.some((source) => source.path === "apps/mobile/lib/accessible_design.dart"), true);
    assert.equal(inventory.sources.every((source) => source.owners.length >= 1 && source.owners.length <= 4 && !source.owners.includes("UNKNOWN")), true);
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

test("F1/F3 byte fixture는 raw NUL tuple, deletion 보존, binary/type 거부와 raw/tested blob mismatch를 닫는다", () => {
  const changes = parseNameStatusZ(Buffer.from("M\0apps/mobile/lib/a.dart\0R90\0apps/mobile/lib/old.dart\0apps/mobile/lib/new.dart\0D\0apps/mobile/lib/gone.dart\0"));
  assert.deepEqual(changes, [{ status: "MODIFIED", oldPath: null, newPath: "apps/mobile/lib/a.dart" }, { status: "RENAMED", oldPath: "apps/mobile/lib/old.dart", newPath: "apps/mobile/lib/new.dart" }, { status: "DELETED", oldPath: "apps/mobile/lib/gone.dart", newPath: null }]);
  const numstat = "1\t0\tapps/mobile/lib/a.dart\0" + "2\t0\t\0apps/mobile/lib/old.dart\0apps/mobile/lib/new.dart\0" + "0\t1\tapps/mobile/lib/gone.dart\0";
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
