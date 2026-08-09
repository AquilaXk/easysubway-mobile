import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { linkSync, mkdirSync, mkdtempSync, readFileSync, rmSync, symlinkSync, unlinkSync, writeFileSync } from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import test from "node:test";
import { commitOutputs, defaultIo, normalizeLcov, parsePolicyBytes } from "./filter-mobile-lcov.mjs";

const repositoryRoot = path.resolve(".");
const exclusionValues = [
  ["DRIFT_CATALOG_DATABASE_GENERATED", "apps/mobile/lib/core/database/catalog/catalog_database.g.dart"],
  ["DRIFT_USER_DATABASE_GENERATED", "apps/mobile/lib/core/database/user/user_database.g.dart"],
];
const exclusions = exclusionValues.map(([id, file]) => ({
  id, path: file, requiredFirstLine: "// GENERATED CODE - DO NOT MODIFY BY HAND",
  reason: "Tracked Drift generated output; handwritten schema and adapters remain covered.",
  ownerIssueUrl: "https://github.com/AquilaXk/easysubway-mobile/issues/48",
  ownerIssueTitle: "[Build][Mobile][P1] LCOV·diff coverage ratchet — filter-mobile-lcov 확장과 CI 배선",
  removalTrigger: "Review immediately when the generated header, Drift generation relationship, source path, coverage producer, or handwritten/generated boundary changes.",
}));
const policy = {
  schemaVersion: 1, artifactKind: "mobile-coverage-policy-v1", repository: "AquilaXk/easysubway-mobile",
  transition: { phase: "DISCOVERY_REMOTE_RED", baselineReviewed: false },
  sourceScope: { root: "apps/mobile/lib", include: "apps/mobile/lib/**/*.dart", kind: "PRODUCTION_DART" },
  exclusions, criticalBoundaryRules: {
    JOURNEY_ROUTE_INGRESS: ["a"], JOURNEY_REPOSITORY_DI_STATE_IDENTITY: ["b"], DATAPACK_CATALOG_LIFECYCLE: ["c"], ACCESSIBILITY_ERROR_TRUTHFULNESS: ["d"], ALARM_WIDGET_REPORT_IO: ["e"], CRASHLYTICS_PRIVACY: ["f"], CONTRACT_ARTIFACT_IDENTITY: ["g"],
  },
  lcov: { closedTags: ["TN", "SF", "FN", "FNDA", "FNF", "FNH", "BRDA", "BRF", "BRH", "DA", "LF", "LH", "end_of_record"], pathRoot: "apps/mobile", lineCoverage: true, functionCoverage: "DISABLED_UNPROVEN", branchCoverage: "DISABLED_UNPROVEN", canonicalOrder: "OFFICIAL_TAG_GROUP_THEN_IDENTITY" },
  comparison: { shaFormat: "lowercase-40-hex", pullRequestRange: "mergeBase..head", pushRange: "base..head", manualRange: null, coreQuotepath: false, diffRenameLimit: 10000, diffAlgorithm: "myers", findRenames: "90%", findCopies: "90%", findCopiesHarder: true, nameStatusNullTerminated: true, numstatNullTerminated: true },
  thresholds: { repositoryLineBasisPoints: null, changedLineBasisPoints: null, criticalBoundaryLineBasisPoints: null },
  artifacts: { directory: "${RUNNER_TEMP}/mobile-coverage-ratchet", name: "mobile-coverage-ratchet-${headSha}", files: ["mobile-coverage-raw.lcov", "mobile-coverage-normalized.lcov", "mobile-coverage-source-inventory.json", "mobile-coverage-result.json", "mobile-coverage-summary.md"], uploadAction: "actions/upload-artifact@65462800fd760344b1a7b4382951275a0abb4808", retentionDays: 5, ifNoFilesFound: "error" },
};
const record = (source, details = ["DA:2,1"]) => [`SF:${source}`, ...details, "LF:1", "LH:1", "end_of_record"].join("\n");
const writeExclusionTargets = (root) => exclusions.forEach(({ path: file, requiredFirstLine }) => { const target = path.join(root, file); mkdirSync(path.dirname(target), { recursive: true }); writeFileSync(target, `${requiredFirstLine}\n`); });

test("정상 일반 소스를 정규화하고 결과를 재계산한다", () => {
  const result = normalizeLcov(record("lib/accessible_design.dart"), { policy, repositoryRoot });
  assert.equal(result.content, "SF:lib/accessible_design.dart\nDA:2,1\nLF:1\nLH:1\nend_of_record\n");
  assert.deepEqual(result.result.records, { retained: 1, excluded: 0 });
  assert.deepEqual(result.result.lines, { executable: 1, covered: 1 });
});

test("F1: canonical full policy bytes와 exact 7-key exclusion만 허용한다", () => {
  const bytes = Buffer.from(`${JSON.stringify(policy, null, 2)}\n`);
  assert.deepEqual(parsePolicyBytes(bytes).value, policy);
  assert.throws(() => parsePolicyBytes(Buffer.from(JSON.stringify(policy))), /canonical/i);
  const altered = structuredClone(policy); altered.exclusions[0].id = "OTHER";
  assert.throws(() => parsePolicyBytes(Buffer.from(`${JSON.stringify(altered, null, 2)}\n`)), /exclusion/i);
});

for (const [name, mutate] of [
  ["comparison", (value) => { value.comparison.extra = true; }],
  ["thresholds", (value) => { value.thresholds.repositoryLineBasisPoints = 1; }],
  ["artifacts", (value) => { value.artifacts.files = []; }],
]) test(`F1: malformed ${name} section is rejected`, () => { const value = structuredClone(policy); mutate(value); assert.throws(() => parsePolicyBytes(Buffer.from(`${JSON.stringify(value, null, 2)}\n`))); });

test("F1: Phase 2 thresholds require the exact ordered seven-boundary 0..10000 map", () => {
  const phaseTwo = structuredClone(policy);
  phaseTwo.transition = { phase: "REVIEWED_BASELINE_ENFORCED", baselineReviewed: true };
  phaseTwo.thresholds = {
    repositoryLineBasisPoints: 1,
    changedLineBasisPoints: 2,
    criticalBoundaryLineBasisPoints: Object.fromEntries(Object.keys(policy.criticalBoundaryRules).map((id, index) => [id, index])),
  };
  assert.deepEqual(parsePolicyBytes(Buffer.from(`${JSON.stringify(phaseTwo, null, 2)}\n`)).value, phaseTwo);
  for (const mutate of [
    (value) => { value.thresholds.criticalBoundaryLineBasisPoints = {}; },
    (value) => { value.thresholds.criticalBoundaryLineBasisPoints = []; },
    (value) => { delete value.thresholds.criticalBoundaryLineBasisPoints.JOURNEY_ROUTE_INGRESS; },
    (value) => { value.thresholds.criticalBoundaryLineBasisPoints.EXTRA = 1; },
    (value) => { value.thresholds.criticalBoundaryLineBasisPoints = Object.fromEntries(Object.entries(value.thresholds.criticalBoundaryLineBasisPoints).reverse()); },
    (value) => { value.thresholds.repositoryLineBasisPoints = 1.5; },
    (value) => { value.thresholds.changedLineBasisPoints = 10001; },
    (value) => { value.thresholds.criticalBoundaryLineBasisPoints.JOURNEY_ROUTE_INGRESS = -1; },
  ]) { const altered = structuredClone(phaseTwo); mutate(altered); assert.throws(() => parsePolicyBytes(Buffer.from(`${JSON.stringify(altered, null, 2)}\n`)), /threshold/i); }
});

test("F2: apps/mobile alias and Unicode SF are rejected", () => {
  assert.throws(() => normalizeLcov(record("apps/mobile/lib/accessible_design.dart"), { policy, repositoryRoot }));
  assert.throws(() => normalizeLcov(record("lib/접근.dart"), { policy, repositoryRoot }));
});

test("F1: exclusion header is validated even when absent from LCOV", () => {
  const io = { ...defaultIo, readFile(file, encoding) { const text = defaultIo.readFile(file, encoding); return file.endsWith("user_database.g.dart") ? "wrong\n" : text; } };
  assert.throws(() => normalizeLcov(record("lib/accessible_design.dart"), { policy, repositoryRoot, io }), /header/i);
});

test("F3: paired zero summary groups are valid and canonical output keeps them", () => {
  const input = ["SF:lib/accessible_design.dart", "FNF:0", "FNH:0", "BRF:0", "BRH:0", "LF:0", "LH:0", "end_of_record"].join("\n");
  assert.match(normalizeLcov(input, { policy, repositoryRoot }).content, /FNF:0\nFNH:0\nBRF:0\nBRH:0\nLF:0\nLH:0/);
});

test("F4: source snapshot drift is terminal through an injectable read seam", () => {
  let reads = 0;
  const io = { ...defaultIo, readFile(file, encoding) { reads += 1; return reads === 1 ? defaultIo.readFile(file, encoding) : `${defaultIo.readFile(file, encoding)}// changed`; } };
  assert.throws(() => normalizeLcov(record("lib/accessible_design.dart"), { policy, repositoryRoot, io }), /changed during normalization/i);
});

test("F5: failed second output commit restores both final files", () => {
  const dir = mkdtempSync(path.join(os.tmpdir(), "mobile-lcov-commit-"));
  const output = path.join(dir, "output"); const result = path.join(dir, "result");
  writeFileSync(output, "old output"); writeFileSync(result, "old result");
  const io = { ...defaultIo, rename(from, to) { if (to === result && from.includes(".tmp-")) throw new Error("injected rename failure"); return defaultIo.rename(from, to); } };
  assert.throws(() => commitOutputs([{ path: output, bytes: Buffer.from("new output") }, { path: result, bytes: Buffer.from("new result") }], io));
  assert.equal(readFileSync(output, "utf8"), "old output"); assert.equal(readFileSync(result, "utf8"), "old result");
  rmSync(dir, { recursive: true, force: true });
});

test("F5: pre-commit source drift restores the old pair", () => {
  const dir = mkdtempSync(path.join(os.tmpdir(), "mobile-lcov-commit-"));
  const output = path.join(dir, "output"); const result = path.join(dir, "result");
  writeFileSync(output, "old output"); writeFileSync(result, "old result");
  assert.throws(() => commitOutputs([{ path: output, bytes: Buffer.from("new output") }, { path: result, bytes: Buffer.from("new result") }], defaultIo, () => { throw new Error("source changed during normalization"); }));
  assert.equal(readFileSync(output, "utf8"), "old output"); assert.equal(readFileSync(result, "utf8"), "old result");
  rmSync(dir, { recursive: true, force: true });
});

test("F5: post-commit source drift and re-read mismatch restore the old pair", () => {
  const dir = mkdtempSync(path.join(os.tmpdir(), "mobile-lcov-commit-"));
  const output = path.join(dir, "output"); const result = path.join(dir, "result");
  writeFileSync(output, "old output"); writeFileSync(result, "old result");
  let checks = 0;
  assert.throws(() => commitOutputs([{ path: output, bytes: Buffer.from("new output") }, { path: result, bytes: Buffer.from("new result") }], defaultIo, () => { checks += 1; if (checks === 2) throw new Error("source changed during normalization"); }));
  assert.equal(readFileSync(output, "utf8"), "old output"); assert.equal(readFileSync(result, "utf8"), "old result");
  const io = { ...defaultIo, readFile(file, encoding) { if (file === output && checks > 2) return Buffer.from("tampered"); return defaultIo.readFile(file, encoding); } };
  assert.throws(() => commitOutputs([{ path: output, bytes: Buffer.from("new output") }, { path: result, bytes: Buffer.from("new result") }], io, () => { checks += 1; }), /re-read mismatch/);
  assert.equal(readFileSync(output, "utf8"), "old output"); assert.equal(readFileSync(result, "utf8"), "old result");
  rmSync(dir, { recursive: true, force: true });
});

test("F5: absent old pair leaves no new final when the second commit fails", () => {
  const dir = mkdtempSync(path.join(os.tmpdir(), "mobile-lcov-commit-"));
  const output = path.join(dir, "output"); const result = path.join(dir, "result");
  const io = { ...defaultIo, rename(from, to) { if (to === result && from.includes(".tmp-")) throw new Error("injected rename failure"); return defaultIo.rename(from, to); } };
  assert.throws(() => commitOutputs([{ path: output, bytes: Buffer.from("new output") }, { path: result, bytes: Buffer.from("new result") }], io));
  assert.throws(() => readFileSync(output)); assert.throws(() => readFileSync(result));
  rmSync(dir, { recursive: true, force: true });
});

test("F5: backup cleanup failure restores the old pair", () => {
  const dir = mkdtempSync(path.join(os.tmpdir(), "mobile-lcov-commit-"));
  const output = path.join(dir, "output"); const result = path.join(dir, "result");
  writeFileSync(output, "old output"); writeFileSync(result, "old result");
  let failOnce = true;
  const io = { ...defaultIo, unlink(file) { if (failOnce && file.includes(".bak-")) { failOnce = false; throw new Error("injected cleanup failure"); } return defaultIo.unlink(file); } };
  assert.throws(() => commitOutputs([{ path: output, bytes: Buffer.from("new output") }, { path: result, bytes: Buffer.from("new result") }], io), /cleanup failure/);
  assert.equal(readFileSync(output, "utf8"), "old output"); assert.equal(readFileSync(result, "utf8"), "old result");
  rmSync(dir, { recursive: true, force: true });
});

test("정확히 선언된 생성 데이터베이스 두 파일만 제외한다", () => {
  const input = [record("lib/core/database/catalog/catalog_database.g.dart"), record("lib/core/database/user/user_database.g.dart"), record("lib/accessible_design.dart")].join("\n");
  const result = normalizeLcov(input, { policy, repositoryRoot });
  assert.equal(result.result.records.retained, 1);
  assert.deepEqual(result.result.exclusions.map((entry) => entry.reason), exclusions.map((entry) => entry.id));
  assert.doesNotMatch(result.content, /database\.g\.dart/);
});

test("다른 generated Dart는 유효한 현재 소스면 유지 대상이며 없는 경로는 거부한다", () => {
  const fixtureRoot = mkdtempSync(path.join(os.tmpdir(), "mobile-lcov-root-"));
  writeExclusionTargets(fixtureRoot);
  const source = path.join(fixtureRoot, "apps/mobile/lib/custom.g.dart");
  mkdirSync(path.dirname(source), { recursive: true });
  writeFileSync(source, "void main() {}\n");
  assert.equal(normalizeLcov(record("lib/custom.g.dart"), { policy, repositoryRoot: fixtureRoot, io: { ...defaultIo, isTracked: () => true } }).result.records.retained, 1);
  rmSync(fixtureRoot, { recursive: true, force: true });
  assert.throws(() => normalizeLcov(record("lib/features/home/home_page.g.dart"), { policy, repositoryRoot }), /source file/i);
});

test("TN, 함수, 브랜치의 완전한 레코드를 정렬하고 요약을 다시 만든다", () => {
  const input = ["TN:suite", "SF:lib/accessible_design.dart", "FN:9,z", "FN:2,a", "FNDA:0,z", "FNDA:3,a", "FNF:2", "FNH:1", "BRDA:5,1,2,0", "BRDA:3,0,0,4", "BRF:2", "BRH:1", "DA:9,0", "DA:2,4", "LF:2", "LH:1", "end_of_record"].join("\n");
  const { content } = normalizeLcov(input, { policy, repositoryRoot });
  assert.match(content, /FN:2,a\nFN:9,z\nFNDA:3,a\nFNDA:0,z\nFNF:2\nFNH:1/);
  assert.match(content, /BRDA:3,0,0,4\nBRDA:5,1,2,0\nBRF:2\nBRH:1/);
  assert.match(content, /DA:2,4\nDA:9,0\nLF:2\nLH:1/);
});

test("최소 라인 그룹과 CRLF는 허용하며 정규화는 idempotent하다", () => {
  const once = normalizeLcov("SF:lib/accessible_design.dart\r\nDA:2,0\r\nLF:1\r\nLH:0\r\nend_of_record\r\n", { policy, repositoryRoot }).content;
  assert.equal(normalizeLcov(once, { policy, repositoryRoot }).content, once);
});

for (const [name, input] of [
  ["알 수 없는 태그", "SF:lib/accessible_design.dart\nXX:1\nend_of_record"],
  ["중복 소스", `${record("lib/accessible_design.dart")}\n${record("lib/accessible_design.dart")}`],
  ["요약 불일치", "SF:lib/accessible_design.dart\nDA:2,1\nLF:2\nLH:1\nend_of_record"],
  ["경로 alias", record("lib//accessible_design.dart")],
  ["경로 traversal", record("lib/../lib/accessible_design.dart")],
  ["레코드 밖 데이터", "DA:1,1"],
]) test(`${name}는 거부한다`, () => assert.throws(() => normalizeLcov(input, { policy, repositoryRoot })));

test("CLI는 인자 오류와 input/output alias를 거부한다", () => {
  const dir = mkdtempSync(path.join(os.tmpdir(), "mobile-lcov-"));
  const input = path.join(dir, "raw.info");
  const policyFile = path.join(dir, "policy.json");
  writeFileSync(input, record("lib/accessible_design.dart"));
  writeFileSync(policyFile, JSON.stringify(policy));
  const base = ["tools/ci/filter-mobile-lcov.mjs", "normalize", "--input", input, "--policy", policyFile, "--result", path.join(dir, "result.json")];
  assert.equal(spawnSync("node", [...base, "--output", input]).status, 1);
  assert.equal(spawnSync("node", ["tools/ci/filter-mobile-lcov.mjs", "normalize", "--wat"]).status, 2);
});

test("F5: CLI는 네 경로의 symlink ancestor와 존재하지 않는 alias parent를 거부한다", () => {
  const dir = mkdtempSync(path.join(os.tmpdir(), "mobile-lcov-path-"));
  const real = path.join(dir, "real"); const linked = path.join(dir, "linked"); mkdirSync(real); symlinkSync(real, linked);
  const input = path.join(real, "raw.info"); const policyFile = path.join(real, "policy.json"); writeFileSync(input, record("lib/accessible_design.dart")); writeFileSync(policyFile, `${JSON.stringify(policy, null, 2)}\n`);
  const run = (args) => spawnSync("node", ["tools/ci/filter-mobile-lcov.mjs", "normalize", ...args]).status;
  for (const [flag, value] of [["--input", path.join(linked, "raw.info")], ["--policy", path.join(linked, "policy.json")], ["--output", path.join(linked, "output")], ["--result", path.join(linked, "result")]]) {
    const args = ["--input", input, "--policy", policyFile, "--output", path.join(real, "output"), "--result", path.join(real, "result")]; args[args.indexOf(flag) + 1] = value;
    assert.equal(run(args), 1);
  }
  assert.equal(run(["--input", input, "--policy", policyFile, "--output", path.join(real, "new", "output"), "--result", path.join(linked, "new", "result")]), 1);
  rmSync(dir, { recursive: true, force: true });
});

test("F5: CLI는 input/policy/output/result의 모든 hard-link 별칭 쌍을 거부한다", () => {
  const flags = ["--input", "--policy", "--output", "--result"];
  for (let left = 0; left < flags.length; left += 1) for (let right = left + 1; right < flags.length; right += 1) {
    const dir = mkdtempSync(path.join(os.tmpdir(), "mobile-lcov-hardlink-"));
    const files = flags.map((_, index) => path.join(dir, `file-${index}`));
    writeFileSync(files[0], record("lib/accessible_design.dart")); writeFileSync(files[1], `${JSON.stringify(policy, null, 2)}\n`); writeFileSync(files[2], "old output"); writeFileSync(files[3], "old result");
    unlinkSync(files[right]); linkSync(files[left], files[right]);
    assert.equal(spawnSync("node", ["tools/ci/filter-mobile-lcov.mjs", "normalize", ...flags.flatMap((flag, index) => [flag, files[index]])]).status, 1);
    rmSync(dir, { recursive: true, force: true });
  }
});

test("CLI는 canonical policy로 exact output/result bytes를 쓴다", () => {
  const dir = mkdtempSync(path.join(os.tmpdir(), "mobile-lcov-cli-"));
  const input = path.join(dir, "raw.info"); const output = path.join(dir, "normalized.info"); const policyFile = path.join(dir, "policy.json"); const result = path.join(dir, "result.json");
  writeFileSync(input, record("lib/accessible_design.dart")); writeFileSync(policyFile, `${JSON.stringify(policy, null, 2)}\n`);
  assert.equal(spawnSync("node", ["tools/ci/filter-mobile-lcov.mjs", "normalize", "--input", input, "--output", output, "--policy", policyFile, "--result", result]).status, 0);
  const outputBytes = readFileSync(output); const payload = JSON.parse(readFileSync(result, "utf8"));
  assert.equal(payload.outputSha256, createHash("sha256").update(outputBytes).digest("hex"));
  assert.equal(payload.inputSha256, createHash("sha256").update(readFileSync(input)).digest("hex"));
  rmSync(dir, { recursive: true, force: true });
});

test("CLI와 Mobile CI는 검증된 RUNNER_TEMP 출력 계약을 사용한다", () => {
  const dir = mkdtempSync(path.join(os.tmpdir(), "mobile-lcov-runner-temp-"));
  const input = path.join(dir, "raw.info"); const policyFile = path.join(dir, "policy.json");
  const output = path.join(dir, "mobile-coverage-normalized.lcov"); const result = path.join(dir, "mobile-coverage-filter-result.json");
  writeFileSync(input, record("lib/accessible_design.dart")); writeFileSync(policyFile, `${JSON.stringify(policy, null, 2)}\n`);
  assert.equal(spawnSync("node", ["tools/ci/filter-mobile-lcov.mjs", "normalize", "--input", input, "--output", output, "--policy", policyFile, "--result", result], { env: { ...process.env, RUNNER_TEMP: dir } }).status, 0);
  const workflow = readFileSync(".github/workflows/ci.yml", "utf8");
  for (const token of ["filter-mobile-lcov.mjs normalize", "--input apps/mobile/coverage/lcov.info", "--output \"${RUNNER_TEMP}/mobile-coverage-normalized.lcov\"", "--policy tools/ci/mobile-coverage-policy.json", "--result \"${RUNNER_TEMP}/mobile-coverage-filter-result.json\""]) assert.match(workflow, new RegExp(token.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")));
  rmSync(dir, { recursive: true, force: true });
});

test("symlink source와 no-retained 레코드를 거부한다", () => {
  const fixtureRoot = mkdtempSync(path.join(os.tmpdir(), "mobile-lcov-root-"));
  writeExclusionTargets(fixtureRoot);
  const sourceDir = path.join(fixtureRoot, "apps/mobile/lib");
  mkdirSync(sourceDir, { recursive: true });
  symlinkSync(path.join(repositoryRoot, "apps/mobile/lib/accessible_design.dart"), path.join(sourceDir, "linked.dart"));
  assert.throws(() => normalizeLcov(record("lib/linked.dart"), { policy, repositoryRoot: fixtureRoot, io: { ...defaultIo, isTracked: () => true } }), /source file/i);
  rmSync(fixtureRoot, { recursive: true, force: true });
  assert.throws(() => normalizeLcov(record("lib/core/database/catalog/catalog_database.g.dart"), { policy, repositoryRoot }), /retained/i);
});
