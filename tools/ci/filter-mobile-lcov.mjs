#!/usr/bin/env node
import { mkdirSync, readFileSync, lstatSync, realpathSync, renameSync, unlinkSync, writeFileSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { tmpdir } from "node:os";
import path from "node:path";
import { pathToFileURL } from "node:url";

const TAGS = ["TN", "SF", "FN", "FNDA", "FNF", "FNH", "BRDA", "BRF", "BRH", "DA", "LF", "LH", "end_of_record"];
const EXCLUSIONS = [
  ["DRIFT_CATALOG_DATABASE_GENERATED", "apps/mobile/lib/core/database/catalog/catalog_database.g.dart", "TRACKED_GENERATED_REQUIRED"],
  ["DRIFT_USER_DATABASE_GENERATED", "apps/mobile/lib/core/database/user/user_database.g.dart", "TRACKED_GENERATED_REQUIRED"],
  ["JOURNEY_V3_CONTRACT_GENERATED", "apps/mobile/lib/generated/journey_v3/journey_v3_contract.dart", "RESERVED_ABSENT_OR_TRACKED_GENERATED"],
  ["JOURNEY_V3_ENUMS_GENERATED", "apps/mobile/lib/generated/journey_v3/journey_v3_enums.dart", "RESERVED_ABSENT_OR_TRACKED_GENERATED"],
  ["JOURNEY_V3_ERROR_GENERATED", "apps/mobile/lib/generated/journey_v3/journey_v3_error.dart", "RESERVED_ABSENT_OR_TRACKED_GENERATED"],
  ["JOURNEY_V3_MODELS_GENERATED", "apps/mobile/lib/generated/journey_v3/journey_v3_models.dart", "RESERVED_ABSENT_OR_TRACKED_GENERATED"],
  ["JOURNEY_V3_VALIDATION_GENERATED", "apps/mobile/lib/generated/journey_v3/journey_v3_validation.dart", "RESERVED_ABSENT_OR_TRACKED_GENERATED"],
];
const HEADER = "// GENERATED CODE - DO NOT MODIFY BY HAND";
const DRIFT_METADATA = { reason: "Tracked Drift generated output; handwritten schema and adapters remain covered.", ownerIssueUrl: "https://github.com/AquilaXk/easysubway-mobile/issues/48", ownerIssueTitle: "[Build][Mobile][P1] LCOV·diff coverage ratchet — filter-mobile-lcov 확장과 CI 배선", removalTrigger: "Review immediately when the generated header, Drift generation relationship, source path, coverage producer, or handwritten/generated boundary changes." };
const JOURNEY_METADATA = { reason: "Tracked Journey V3 generated contract output; generator and receipt remain authoritative.", ownerIssueUrl: "https://github.com/AquilaXk/easysubway-mobile/issues/142", ownerIssueTitle: "[CI][Mobile][P1] Journey 생성 소스 classifier·coverage admission", removalTrigger: "Review immediately when the generated header, Journey V3 generator or receipt relationship, source path, coverage producer, or reservation state changes." };
const fail = (message) => { throw new Error(message); };
const sha256 = (value) => createHash("sha256").update(value).digest("hex");

export const defaultIo = {
  readFile: readFileSync, lstat: lstatSync, realpath: realpathSync, mkdir: mkdirSync, rename: renameSync, unlink: unlinkSync, writeFile: writeFileSync,
  isTracked(file, repositoryRoot) { try { execFileSync("git", ["-C", repositoryRoot, "ls-files", "--error-unmatch", "--", path.relative(repositoryRoot, file)], { stdio: "ignore" }); return true; } catch { return false; } },
};
const POLICY_KEYS = ["schemaVersion", "artifactKind", "repository", "transition", "sourceScope", "exclusions", "criticalBoundaryRules", "lcov", "comparison", "thresholds", "artifacts"];
const BOUNDARY_KEYS = ["JOURNEY_ROUTE_INGRESS", "JOURNEY_REPOSITORY_DI_STATE_IDENTITY", "DATAPACK_CATALOG_LIFECYCLE", "ACCESSIBILITY_ERROR_TRUTHFULNESS", "ALARM_WIDGET_REPORT_IO", "CRASHLYTICS_PRIVACY", "CONTRACT_ARTIFACT_IDENTITY"];
function exactKeys(value, keys, label) { if (!value || typeof value !== "object" || Array.isArray(value) || Object.keys(value).join("\0") !== keys.join("\0")) fail(`invalid ${label}`); }

function validatePolicy(policy, { full = false } = {}) {
  if (!policy || typeof policy !== "object") fail("invalid policy");
  if (full) {
    exactKeys(policy, POLICY_KEYS, "policy keys");
    if (policy.schemaVersion !== 1 || policy.artifactKind !== "mobile-coverage-policy-v1" || policy.repository !== "AquilaXk/easysubway-mobile") fail("invalid policy identity");
    if (!((policy.transition?.phase === "DISCOVERY_REMOTE_RED" && policy.transition.baselineReviewed === false) || (policy.transition?.phase === "REVIEWED_BASELINE_ENFORCED" && policy.transition.baselineReviewed === true))) fail("invalid policy transition");
    exactKeys(policy.transition, ["phase", "baselineReviewed"], "transition keys");
    exactKeys(policy.sourceScope, ["root", "include", "kind"], "sourceScope keys");
    exactKeys(policy.lcov, ["closedTags", "pathRoot", "lineCoverage", "functionCoverage", "branchCoverage", "canonicalOrder"], "lcov keys");
    if (policy.lcov.pathRoot !== "apps/mobile" || policy.lcov.lineCoverage !== true || policy.lcov.functionCoverage !== "DISABLED_UNPROVEN" || policy.lcov.branchCoverage !== "DISABLED_UNPROVEN" || policy.lcov.canonicalOrder !== "OFFICIAL_TAG_GROUP_THEN_IDENTITY") fail("invalid policy lcov");
    exactKeys(policy.criticalBoundaryRules, BOUNDARY_KEYS, "criticalBoundaryRules keys");
    for (const paths of Object.values(policy.criticalBoundaryRules)) if (!Array.isArray(paths) || !paths.length || new Set(paths).size !== paths.length || paths.some((item) => typeof item !== "string" || !item || /[^\x20-\x7e]/.test(item))) fail("invalid criticalBoundaryRules");
    const comparisonKeys = ["shaFormat", "pullRequestRange", "pushRange", "manualRange", "coreQuotepath", "diffRenameLimit", "diffAlgorithm", "findRenames", "findCopies", "findCopiesHarder", "nameStatusNullTerminated", "numstatNullTerminated"];
    exactKeys(policy.comparison, comparisonKeys, "comparison keys");
    if (JSON.stringify(policy.comparison) !== JSON.stringify({ shaFormat: "lowercase-40-hex", pullRequestRange: "mergeBase..head", pushRange: "base..head", manualRange: null, coreQuotepath: false, diffRenameLimit: 10000, diffAlgorithm: "myers", findRenames: "90%", findCopies: "90%", findCopiesHarder: true, nameStatusNullTerminated: true, numstatNullTerminated: true })) fail("invalid comparison");
    exactKeys(policy.thresholds, ["repositoryLineBasisPoints", "changedLineBasisPoints", "criticalBoundaryLineBasisPoints"], "threshold keys");
    const phaseOne = policy.transition.phase === "DISCOVERY_REMOTE_RED";
    if (phaseOne) {
      if (policy.thresholds.repositoryLineBasisPoints !== null || policy.thresholds.changedLineBasisPoints !== null || policy.thresholds.criticalBoundaryLineBasisPoints !== null) fail("invalid thresholds");
    } else {
      const withinBasisPoints = (value) => Number.isInteger(value) && value >= 0 && value <= 10000;
      if (!withinBasisPoints(policy.thresholds.repositoryLineBasisPoints) || !withinBasisPoints(policy.thresholds.changedLineBasisPoints)) fail("invalid thresholds");
      exactKeys(policy.thresholds.criticalBoundaryLineBasisPoints, BOUNDARY_KEYS, "critical boundary threshold keys");
      if (Object.values(policy.thresholds.criticalBoundaryLineBasisPoints).some((value) => !withinBasisPoints(value))) fail("invalid thresholds");
    }
    const artifactKeys = ["directory", "name", "files", "uploadAction", "retentionDays", "ifNoFilesFound"];
    exactKeys(policy.artifacts, artifactKeys, "artifact keys");
    if (JSON.stringify(policy.artifacts) !== JSON.stringify({ directory: "${RUNNER_TEMP}/mobile-coverage-ratchet", name: "mobile-coverage-ratchet-${headSha}", files: ["mobile-coverage-raw.lcov", "mobile-coverage-normalized.lcov", "mobile-coverage-source-inventory.json", "mobile-coverage-result.json", "mobile-coverage-summary.md"], uploadAction: "actions/upload-artifact@65462800fd760344b1a7b4382951275a0abb4808", retentionDays: 5, ifNoFilesFound: "error" })) fail("invalid artifacts");
  }
  const scope = policy.sourceScope;
  if (!scope || scope.root !== "apps/mobile/lib" || scope.include !== "apps/mobile/lib/**/*.dart" || scope.kind !== "PRODUCTION_DART") fail("invalid policy sourceScope");
  if (!Array.isArray(policy.lcov?.closedTags) || policy.lcov.closedTags.length !== TAGS.length || policy.lcov.closedTags.some((tag, index) => tag !== TAGS[index])) fail("invalid policy closedTags");
  const expectedExclusions = policy.transition?.phase === "REVIEWED_BASELINE_ENFORCED" ? EXCLUSIONS : EXCLUSIONS.slice(0, 2);
  if (!Array.isArray(policy.exclusions) || policy.exclusions.length !== expectedExclusions.length) fail("invalid policy exclusions");
  policy.exclusions.forEach((entry, index) => {
    const [id, file, availability] = expectedExclusions[index];
    if (full) exactKeys(entry, policy.transition.phase === "REVIEWED_BASELINE_ENFORCED" ? ["id", "availability", "path", "requiredFirstLine", "reason", "ownerIssueUrl", "ownerIssueTitle", "removalTrigger"] : ["id", "path", "requiredFirstLine", "reason", "ownerIssueUrl", "ownerIssueTitle", "removalTrigger"], "exclusion keys");
    const metadata = availability === "TRACKED_GENERATED_REQUIRED" ? DRIFT_METADATA : JOURNEY_METADATA;
    if (!entry || entry.id !== id || entry.path !== file || entry.requiredFirstLine !== HEADER) fail("invalid policy exclusions");
    if (full && policy.transition.phase === "REVIEWED_BASELINE_ENFORCED" && (entry.availability !== availability || entry.reason !== metadata.reason || entry.ownerIssueUrl !== metadata.ownerIssueUrl || entry.ownerIssueTitle !== metadata.ownerIssueTitle || entry.removalTrigger !== metadata.removalTrigger)) fail("invalid policy exclusions");
    if (!full && entry.availability !== undefined && entry.availability !== availability) fail("invalid policy exclusions");
  });
}

export function parsePolicyBytes(bytes) {
  let text;
  try { text = new TextDecoder("utf-8", { fatal: true, ignoreBOM: true }).decode(bytes); } catch { fail("invalid policy UTF-8"); }
  if (text.charCodeAt(0) === 0xfeff) fail("policy BOM is not allowed");
  let value; try { value = JSON.parse(text); } catch { fail("invalid policy JSON"); }
  if (`${JSON.stringify(value, null, 2)}\n` !== text) fail("policy is not canonical");
  validatePolicy(value, { full: true });
  return { value, text, sha256: sha256(bytes) };
}

function assertSafeTracked(absolute, repositoryRoot, io) {
  const rootAbsolute = path.resolve(repositoryRoot); const rootReal = io.realpath(rootAbsolute); const scope = rootAbsolute + path.sep;
  let cursor = path.resolve(absolute);
  while (cursor.startsWith(scope)) { const stat = io.lstat(cursor); if (stat.isSymbolicLink()) fail("source file contains symlink"); if (cursor === repositoryRoot) break; cursor = path.dirname(cursor); }
  const stat = io.lstat(absolute);
  if (!stat.isFile() || stat.isSymbolicLink() || !io.isTracked(absolute, repositoryRoot)) fail("source file is not a tracked regular file");
  if (!io.realpath(absolute).startsWith(rootReal + path.sep)) fail("source outside repository");
  return { size: stat.size, mtimeMs: stat.mtimeMs, digest: sha256(io.readFile(absolute)) };
}
function reservedMissing(error) { return error?.code === "ENOENT"; }
function assertSafeReservedAbsent(absolute, repositoryRoot, io) {
  const rootAbsolute = path.resolve(repositoryRoot); const rootReal = io.realpath(rootAbsolute); const target = path.resolve(absolute); const scope = rootAbsolute + path.sep;
  if (!target.startsWith(scope)) fail("reserved source outside repository");
  try { io.lstat(target); fail("reserved generated source appeared"); } catch (error) { if (!reservedMissing(error)) throw error; }
  for (let cursor = path.dirname(target); ; cursor = path.dirname(cursor)) {
    if (cursor !== rootAbsolute && !cursor.startsWith(scope)) fail("reserved source ancestor outside repository");
    try { const stat = io.lstat(cursor); if (stat.isSymbolicLink() || !stat.isDirectory()) fail("reserved source ancestor is unsafe"); if (!io.realpath(cursor).startsWith(rootReal)) fail("reserved source ancestor outside repository"); } catch (error) { if (!reservedMissing(error)) throw error; }
    if (cursor === rootAbsolute) return;
  }
}
function canonicalSource(raw, repositoryRoot, io) {
  if (typeof raw !== "string" || raw.includes("\\") || raw.includes("%") || /[\x00-\x1f\x7f]/.test(raw) || raw.includes("//")) fail("invalid source path");
  if (!raw.startsWith("lib/")) fail("invalid source path");
  if (/[^\x20-\x7e]/.test(raw)) fail("invalid source path");
  const pieces = raw.split("/");
  if (pieces.some((part) => !part || part === "." || part === "..") || !raw.endsWith(".dart")) fail("invalid source path");
  const canonical = `apps/mobile/${raw}`;
  const absolute = path.resolve(repositoryRoot, canonical);
  const scopeRoot = path.resolve(repositoryRoot, "apps/mobile/lib") + path.sep;
  if (!absolute.startsWith(scopeRoot)) fail("source outside scope");
  try { return { path: canonical, absolute, snapshot: assertSafeTracked(absolute, repositoryRoot, io) }; } catch (error) { if (/ENOENT/.test(error.message)) fail("source file is missing"); throw error; }
}

function number(value, name, { positive = false } = {}) {
  if (!/^(?:0|[1-9]\d*)$/.test(value) || (positive && value === "0")) fail(`invalid ${name}`);
  return Number(value);
}

function parseRecord(lines, repositoryRoot, io) {
  const record = { tn: null, source: null, fn: new Map(), fnda: new Map(), br: new Map(), da: new Map(), stage: 0 };
  const advance = (next) => { if (next < record.stage) fail("misordered LCOV tag"); record.stage = next; };
  for (const line of lines) {
    const colon = line.indexOf(":");
    const tag = colon < 0 ? line : line.slice(0, colon);
    const value = colon < 0 ? "" : line.slice(colon + 1);
    if (!TAGS.includes(tag) || tag === "end_of_record") fail("unknown or malformed LCOV tag");
    if (tag === "TN") {
      if (record.source || record.tn !== null || !value || /[\r\n\x00-\x1f\x7f]/.test(value)) fail("invalid TN");
      record.tn = value; continue;
    }
    if (tag === "SF") {
      if (record.source || record.tn === undefined) fail("invalid SF");
      const source = canonicalSource(value, repositoryRoot, io); record.source = source.path; record.sourceAbsolute = source.absolute; record.sourceSnapshot = source.snapshot; record.stage = 1; continue;
    }
    if (!record.source) fail("data outside LCOV record");
    if (tag === "FN") {
      advance(2); const match = /^(\d+),([^,\r\n\x00-\x1f\x7f]+)$/.exec(value); if (!match) fail("invalid FN");
      const lineNo = number(match[1], "FN", { positive: true }); const name = match[2]; if (record.fn.has(name)) fail("duplicate FN"); record.fn.set(name, lineNo); continue;
    }
    if (tag === "FNDA") {
      advance(3); const match = /^(\d+),([^,\r\n\x00-\x1f\x7f]+)$/.exec(value); if (!match) fail("invalid FNDA");
      if (record.fnda.has(match[2])) fail("duplicate FNDA"); record.fnda.set(match[2], number(match[1], "FNDA")); continue;
    }
    if (tag === "FNF" || tag === "FNH") { advance(tag === "FNF" ? 4 : 5); if (record[tag] !== undefined) fail(`duplicate ${tag}`); record[tag] = number(value, tag); continue; }
    if (tag === "BRDA") {
      advance(6); const match = /^(\d+),(\d+),(\d+),(\d+|-)$/.exec(value); if (!match) fail("invalid BRDA");
      const identity = `${number(match[1], "BRDA", { positive: true })},${number(match[2], "BRDA")},${number(match[3], "BRDA")}`;
      if (record.br.has(identity)) fail("duplicate BRDA"); record.br.set(identity, { hits: match[4] === "-" ? 0 : number(match[4], "BRDA"), taken: match[4] }); continue;
    }
    if (tag === "BRF" || tag === "BRH") { advance(tag === "BRF" ? 7 : 8); if (record[tag] !== undefined) fail(`duplicate ${tag}`); record[tag] = number(value, tag); continue; }
    if (tag === "DA") {
      advance(9); const match = /^(\d+),(\d+)(?:,([^,\r\n\x00-\x1f\x7f]+))?$/.exec(value); if (!match) fail("invalid DA");
      const lineNo = number(match[1], "DA", { positive: true }); if (record.da.has(lineNo)) fail("duplicate DA"); record.da.set(lineNo, { hits: number(match[2], "DA"), checksum: match[3] ?? null }); continue;
    }
    if (tag === "LF" || tag === "LH") { advance(tag === "LF" ? 10 : 11); if (record[tag] !== undefined) fail(`duplicate ${tag}`); record[tag] = number(value, tag); continue; }
  }
  if (!record.source) fail("record missing SF");
  const hasFn = record.fn.size || record.fnda.size || record.FNF !== undefined || record.FNH !== undefined;
  if (hasFn && (record.fn.size !== record.fnda.size || record.FNF === undefined || record.FNH === undefined || [...record.fn.keys()].some((name) => !record.fnda.has(name)))) fail("incomplete function group");
  if (hasFn && (record.FNF !== record.fn.size || record.FNH !== [...record.fnda.values()].filter((hits) => hits > 0).length)) fail("function summary mismatch");
  const hasBr = record.br.size || record.BRF !== undefined || record.BRH !== undefined;
  if (hasBr && (record.BRF === undefined || record.BRH === undefined || record.BRF !== record.br.size || record.BRH !== [...record.br.values()].filter(({ hits }) => hits > 0).length)) fail("branch summary mismatch");
  const hasDa = record.da.size || record.LF !== undefined || record.LH !== undefined;
  if (hasDa && (record.LF === undefined || record.LH === undefined || record.LF !== record.da.size || record.LH !== [...record.da.values()].filter(({ hits }) => hits > 0).length)) fail("line summary mismatch");
  return record;
}

function compareIdentity(a, b) { return a < b ? -1 : a > b ? 1 : 0; }
function render(record) {
  const lines = [];
  if (record.tn !== null) lines.push(`TN:${record.tn}`);
  lines.push(`SF:${record.source.slice("apps/mobile/".length)}`);
  for (const [name, line] of [...record.fn].sort(([a], [b]) => compareIdentity(a, b))) lines.push(`FN:${line},${name}`);
  for (const [name, hits] of [...record.fnda].sort(([a], [b]) => compareIdentity(a, b))) lines.push(`FNDA:${hits},${name}`);
  if (record.FNF !== undefined) lines.push(`FNF:${record.fn.size}`, `FNH:${[...record.fnda.values()].filter((hits) => hits > 0).length}`);
  for (const [identity, hits] of [...record.br].sort(([a], [b]) => {
    const left = a.split(",").map(Number); const right = b.split(",").map(Number);
    return left[0] - right[0] || left[1] - right[1] || left[2] - right[2];
  })) lines.push(`BRDA:${identity},${hits.taken}`);
  if (record.BRF !== undefined) lines.push(`BRF:${record.br.size}`, `BRH:${[...record.br.values()].filter(({ hits }) => hits > 0).length}`);
  for (const [line, data] of [...record.da].sort(([a], [b]) => a - b)) lines.push(`DA:${line},${data.hits}${data.checksum ? `,${data.checksum}` : ""}`);
  if (record.LF !== undefined) lines.push(`LF:${record.da.size}`, `LH:${[...record.da.values()].filter(({ hits }) => hits > 0).length}`);
  return `${lines.join("\n")}\nend_of_record\n`;
}

function sameSnapshot(absolute, snapshot, repositoryRoot, io) {
  const current = assertSafeTracked(absolute, repositoryRoot, io);
  if (current.size !== snapshot.size || current.mtimeMs !== snapshot.mtimeMs || current.digest !== snapshot.digest) fail("source changed during normalization");
}
export function normalizeLcov(content, { policy, repositoryRoot = process.cwd(), policySha256, io = defaultIo } = {}) {
  validatePolicy(policy);
  const exclusionSnapshots = policy.exclusions.map(({ id, path: file, availability = "TRACKED_GENERATED_REQUIRED" }) => {
    const absolute = path.resolve(repositoryRoot, file);
    try {
      const snapshot = assertSafeTracked(absolute, repositoryRoot, io);
      if (io.readFile(absolute, "utf8").split("\n", 1)[0] !== HEADER) fail("invalid generated header");
      return { path: file, absolute, availability, presence: "TRACKED_GENERATED", snapshot };
    } catch (error) {
      if (availability !== "RESERVED_ABSENT_OR_TRACKED_GENERATED" || !reservedMissing(error)) throw error;
      assertSafeReservedAbsent(absolute, repositoryRoot, io);
      return { path: file, absolute, availability, presence: "RESERVED_ABSENT", snapshot: null };
    }
  });
  if (typeof content !== "string" || content.startsWith("\uFEFF") || /[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/.test(content) || /\r(?!\n)/.test(content)) fail("invalid LCOV encoding");
  const lines = content.replaceAll("\r\n", "\n").split("\n");
  if (lines.at(-1) === "") lines.pop();
  const records = []; let current = [];
  for (const line of lines) {
    if (!line) fail("empty LCOV line");
    if (line === "end_of_record") { if (!current.length) fail("empty LCOV record"); records.push(parseRecord(current, repositoryRoot, io)); current = []; }
    else { if (!current.length && !line.startsWith("TN:") && !line.startsWith("SF:")) fail("data outside LCOV record"); current.push(line); }
  }
  if (current.length) fail("record missing end_of_record");
  const seen = new Set(); const excluded = []; const retained = [];
  for (const record of records) {
    if (seen.has(record.source)) fail("duplicate source record"); seen.add(record.source);
    const exclusion = policy.exclusions.find((entry) => entry.path === record.source);
    if (exclusion) {
      if (io.readFile(path.join(repositoryRoot, record.source), "utf8").split("\n", 1)[0] !== exclusion.requiredFirstLine) fail("invalid generated header");
      excluded.push({ path: record.source, reason: exclusion.id, presence: "TRACKED_GENERATED", lcovRecordPresent: true, executableLines: record.da.size, coveredLines: [...record.da.values()].filter(({ hits }) => hits > 0).length });
    } else retained.push(record);
  }
  if (!retained.length) fail("no retained LCOV record");
  const verifySources = () => { for (const item of exclusionSnapshots) { if (item.presence === "TRACKED_GENERATED") sameSnapshot(item.absolute, item.snapshot, repositoryRoot, io); else assertSafeReservedAbsent(item.absolute, repositoryRoot, io); } for (const record of retained) sameSnapshot(record.sourceAbsolute, record.sourceSnapshot, repositoryRoot, io); };
  verifySources();
  retained.sort((a, b) => Buffer.compare(Buffer.from(a.source), Buffer.from(b.source)));
  excluded.sort((a, b) => compareIdentity(a.path, b.path));
  const normalized = retained.map(render).join("");
  const linesCount = retained.reduce((total, record) => ({ executable: total.executable + record.da.size, covered: total.covered + [...record.da.values()].filter(({ hits }) => hits > 0).length }), { executable: 0, covered: 0 });
  const evidence = exclusionSnapshots.map((item) => excluded.find((entry) => entry.path === item.path) ?? { path: item.path, reason: policy.exclusions.find((entry) => entry.path === item.path).id, presence: item.presence, lcovRecordPresent: false, executableLines: 0, coveredLines: 0 });
  return { content: normalized, verifySources, result: { schemaVersion: 1, artifactKind: "mobile-lcov-filter-result-v1", policySha256: policySha256 ?? sha256(JSON.stringify(policy)), inputSha256: sha256(content), outputSha256: sha256(normalized), records: { retained: retained.length, excluded: excluded.length }, lines: linesCount, exclusions: evidence, outcome: "success" } };
}

function usage() { process.stderr.write("usage: node tools/ci/filter-mobile-lcov.mjs normalize --input <raw-lcov> --output <normalized-lcov> --policy <policy-json> --result <filter-result-json>\n"); }
function parseArgs(argv) {
  if (argv[0] !== "normalize") return null;
  const values = {}; for (let i = 1; i < argv.length; i += 2) { const key = argv[i]; if (!/^--(?:input|output|policy|result)$/.test(key) || !argv[i + 1] || values[key]) return null; values[key] = argv[i + 1]; }
  return ["--input", "--output", "--policy", "--result"].every((key) => values[key]) ? values : null;
}
function missing(error) { return error && /ENOENT/.test(error.message); }
function trustedRootFor(absolute, io) {
  const runnerTemp = process.env.RUNNER_TEMP && path.isAbsolute(process.env.RUNNER_TEMP) ? path.resolve(process.env.RUNNER_TEMP) : null;
  for (const candidate of [path.resolve(process.cwd()), path.resolve(tmpdir()), runnerTemp].filter(Boolean)) {
    if (absolute === candidate || absolute.startsWith(candidate + path.sep)) {
      const stat = io.lstat(candidate);
      if (stat.isSymbolicLink() || !stat.isDirectory()) fail("trusted root is not a real directory");
      return candidate;
    }
  }
  fail("path is outside trusted repository or temporary roots");
}
function inspectCliPath(file, { required = false } = {}, io = defaultIo) {
  const absolute = path.resolve(file); const root = trustedRootFor(absolute, io); const parent = path.dirname(absolute);
  let cursor = root;
  for (const part of path.relative(root, parent).split(path.sep).filter(Boolean)) {
    cursor = path.join(cursor, part);
    let stat; try { stat = io.lstat(cursor); } catch (error) { if (missing(error)) fail("path parent does not exist"); throw error; }
    if (stat.isSymbolicLink() || !stat.isDirectory()) fail("path contains symlink or non-directory ancestor");
  }
  let exists = false;
  let endpoint = null;
  try {
    const stat = io.lstat(absolute); exists = true; endpoint = `${stat.dev}\0${stat.ino}`;
    if (stat.isSymbolicLink() || !stat.isFile()) fail("path is not a regular file");
  } catch (error) { if (!missing(error)) throw error; }
  if (required && !exists) fail("required path is missing");
  return { absolute, exists, endpoint, identity: `${io.realpath(parent)}\0${path.basename(absolute)}` };
}
function assertDistinct(paths) {
  if (new Set(paths.map((item) => item.identity)).size !== paths.length) fail("input, policy, output, and result must be distinct");
  const endpoints = paths.map((item) => item.endpoint).filter(Boolean);
  if (new Set(endpoints).size !== endpoints.length) fail("input, policy, output, and result must be distinct");
}
export function commitOutputs(outputs, io = defaultIo, verifySources = () => {}) {
  if (!Array.isArray(outputs) || outputs.length !== 2) fail("exactly two output files are required");
  const staged = outputs.map((output, index) => {
    const inspected = inspectCliPath(output.path, {}, io);
    return { ...output, ...inspected, bytes: Buffer.from(output.bytes), temp: `${inspected.absolute}.tmp-${process.pid}-${index}`, backup: `${inspected.absolute}.bak-${process.pid}-${index}`, old: inspected.exists ? Buffer.from(io.readFile(inspected.absolute)) : null };
  });
  assertDistinct(staged);
  try {
    for (const output of staged) io.writeFile(output.temp, output.bytes, { flag: "wx" });
    verifySources();
    for (const output of staged) if (output.old) io.rename(output.absolute, output.backup);
    verifySources();
    for (const output of staged) io.rename(output.temp, output.absolute);
    for (const output of staged) if (sha256(io.readFile(output.absolute)) !== sha256(output.bytes)) fail("output re-read mismatch");
    verifySources();
  } catch (error) {
    let rollbackFailure = null;
    for (const output of staged) {
      for (const candidate of [output.temp, output.absolute, output.backup]) {
        try { io.unlink(candidate); } catch (cleanupError) { if (!missing(cleanupError) && !rollbackFailure) rollbackFailure = cleanupError; }
      }
      if (output.old) {
        try { io.writeFile(output.absolute, output.old, { flag: "wx" }); } catch (restoreError) { if (!rollbackFailure) rollbackFailure = restoreError; }
      }
    }
    if (rollbackFailure) fail(`output rollback failed: ${rollbackFailure.message}`);
    throw error;
  }
  try { for (const output of staged) if (output.old) io.unlink(output.backup); } catch (error) {
    let rollbackFailure = null;
    for (const output of staged) {
      for (const candidate of [output.absolute, output.backup]) {
        try { io.unlink(candidate); } catch (cleanupError) { if (!missing(cleanupError) && !rollbackFailure) rollbackFailure = cleanupError; }
      }
      if (output.old) {
        try { io.writeFile(output.absolute, output.old, { flag: "wx" }); } catch (restoreError) { if (!rollbackFailure) rollbackFailure = restoreError; }
      }
    }
    if (rollbackFailure) fail(`output rollback failed: ${rollbackFailure.message}`);
    throw error;
  }
}
function main() {
  const args = parseArgs(process.argv.slice(2)); if (!args) { usage(); process.exitCode = 2; return; }
  try {
    const paths = [inspectCliPath(args["--input"], { required: true }), inspectCliPath(args["--policy"], { required: true }), inspectCliPath(args["--output"]), inspectCliPath(args["--result"])]; assertDistinct(paths);
    const input = readFileSync(paths[0].absolute); const text = new TextDecoder("utf-8", { fatal: true, ignoreBOM: true }).decode(input); if (text.charCodeAt(0) === 0xfeff) fail("BOM is not allowed");
    const parsedPolicy = parsePolicyBytes(readFileSync(paths[1].absolute));
    const result = normalizeLcov(text, { policy: parsedPolicy.value, policySha256: parsedPolicy.sha256, repositoryRoot: process.cwd() });
    const resultBytes = Buffer.from(`${JSON.stringify(result.result)}\n`);
    commitOutputs([{ path: paths[2].absolute, bytes: Buffer.from(result.content) }, { path: paths[3].absolute, bytes: resultBytes }], defaultIo, result.verifySources);
  } catch (error) { process.stderr.write(`filter-mobile-lcov: ${error.message}\n`); process.exitCode = 1; }
}
if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) main();
