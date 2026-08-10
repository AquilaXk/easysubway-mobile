import assert from "node:assert/strict";
import { execFileSync, spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { mkdirSync, mkdtempSync, readFileSync, readdirSync, realpathSync, renameSync, rmSync, writeFileSync } from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { analyze, changedExecutableLines, classifyDartLines, commitArtifactPair, parseBaselineBytes, parseNameStatusZ, parseNumstatZ, parsePolicyBytes, treeSources, validateDiffTuples, validateEventIdentity, verifyArtifactDirectory } from "./mobile-coverage-ratchet.mjs";

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

test("Dart lexical scanner는 non-raw triple의 escaped delimiter와 raw delimiter를 구분한다", () => {
  assert.deepEqual(classifyDartLines(Buffer.from(`final single = '''escaped \\''' delimiter''' ;
final double = """escaped \\""" delimiter""" ;
`)), ["CODE", "CODE"]);
  assert.throws(() => classifyDartLines(Buffer.from(`final raw = r'''escaped \\''' delimiter''' ;`)), /unterminated/i);
  assert.throws(() => classifyDartLines(Buffer.from(`final text = """escaped \\""" delimiter`)), /unterminated/i);
});

const sha = (value) => createHash("sha256").update(value).digest("hex");
const head = execFileSync("git", ["rev-parse", "HEAD"], { encoding: "utf8" }).trim();
function discoveryInput(dir, event = "workflow_dispatch") {
  const normalized = Buffer.from("SF:lib/accessible_design.dart\nDA:1,0\nLF:1\nLH:0\nend_of_record\n");
  const raw = Buffer.from(`${normalized}SF:lib/core/database/catalog/catalog_database.g.dart\nDA:1,0\nLF:1\nLH:0\nend_of_record\nSF:lib/core/database/user/user_database.g.dart\nDA:1,0\nLF:1\nLH:0\nend_of_record\n`);
  const rawFile = path.join(dir, "raw.lcov"); const normalizedFile = path.join(dir, "normalized.lcov"); const filterFile = path.join(dir, "filter.json"); const eventFile = path.join(dir, "event.json");
  writeFileSync(rawFile, raw); writeFileSync(normalizedFile, normalized);
  writeFileSync(eventFile, JSON.stringify(event === "pull_request" ? { pull_request: { base: { sha: head }, head: { sha: head } } } : { ref: "refs/heads/main", after: head }));
  writeFileSync(filterFile, `${JSON.stringify({ schemaVersion: 1, artifactKind: "mobile-lcov-filter-result-v1", policySha256: sha(readFileSync(policyFile)), inputSha256: sha(raw), outputSha256: sha(normalized), records: { retained: 1, excluded: 2 }, lines: { executable: 1, covered: 0 }, exclusions: [{ path: "apps/mobile/lib/core/database/catalog/catalog_database.g.dart", reason: "DRIFT_CATALOG_DATABASE_GENERATED", executableLines: 1, coveredLines: 0 }, { path: "apps/mobile/lib/core/database/user/user_database.g.dart", reason: "DRIFT_USER_DATABASE_GENERATED", executableLines: 1, coveredLines: 0 }], outcome: "success" })}\n`);
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

test("Phase 1 workflow는 ratchet 분석·artifact·intentional verdict를 고정 배선한다", () => {
  const workflow = readFileSync(path.join(repositoryRoot, ".github/workflows/ci.yml"), "utf8");
  const analyze = [
    "      - name: Analyze mobile coverage ratchet",
    "        id: coverage_ratchet_analyze",
    "        env:",
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
    "        run: |",
    "          node tools/ci/mobile-coverage-ratchet.mjs verdict \\",
    "            --analysis-outcome \"${{ steps.coverage_ratchet_analyze.outcome }}\" \\",
    "            --upload-outcome \"${{ steps.coverage_ratchet_upload.outcome }}\"",
  ].join("\n");
  assert.equal(workflow.includes("tools/ci/mobile-coverage-ratchet.test.mjs"), true);
  for (const block of [analyze, upload, verdict]) {
    assert.equal(workflow.includes(block), true, block);
    assert.equal(block.includes("continue-on-error"), false);
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
  assert.deepEqual(changedExecutableLines(`${head}..${head}`, head, head, new Map(), emptyDiff), { state: "APPLICABLE", entries: [], executableLines: 0, coveredLines: 0, lineBasisPoints: null });
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
