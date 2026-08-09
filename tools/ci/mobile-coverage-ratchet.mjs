#!/usr/bin/env node
import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { lstatSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, renameSync, rmSync, writeFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const SHA = /^[0-9a-f]{40}$/u;
const DIGEST = /^[0-9a-f]{64}$/u;
const POLICY_SHA256 = "9d3ee666456b1978c54454ac37f31aee7524844fcb41e267f1e397453afd38d6";
const POLICY_KEYS = ["schemaVersion", "artifactKind", "repository", "transition", "sourceScope", "exclusions", "criticalBoundaryRules", "lcov", "comparison", "thresholds", "artifacts"];
const BASELINE_KEYS = ["schemaVersion", "artifactKind", "repository", "reviewState", "provenance", "producer", "floors", "paths", "criticalBoundaries"];
const BOUNDARIES = ["JOURNEY_ROUTE_INGRESS", "JOURNEY_REPOSITORY_DI_STATE_IDENTITY", "DATAPACK_CATALOG_LIFECYCLE", "ACCESSIBILITY_ERROR_TRUTHFULNESS", "ALARM_WIDGET_REPORT_IO", "CRASHLYTICS_PRIVACY", "CONTRACT_ARTIFACT_IDENTITY"];
const TAGS = ["TN", "SF", "FN", "FNDA", "FNF", "FNH", "BRDA", "BRF", "BRH", "DA", "LF", "LH", "end_of_record"];
const ARTIFACT_FILES = ["mobile-coverage-raw.lcov", "mobile-coverage-normalized.lcov", "mobile-coverage-source-inventory.json", "mobile-coverage-result.json", "mobile-coverage-summary.md"];
const RESULT_KEYS = ["schemaVersion", "artifactKind", "repository", "phase", "identity", "producer", "coverage", "changedLines", "criticalBoundaries", "exclusions", "artifacts", "reasons", "outcome"];
const INVENTORY_KEYS = ["schemaVersion", "artifactKind", "repository", "identity", "producer", "sources", "summary"];
const fail = (message, exitCode = 1) => { const error = new Error(message); error.exitCode = exitCode; throw error; };
const hash = (value) => createHash("sha256").update(value).digest("hex");
const compare = (left, right) => left < right ? -1 : left > right ? 1 : 0;
const exactKeys = (value, keys, name) => { if (!value || typeof value !== "object" || Array.isArray(value) || JSON.stringify(Object.keys(value)) !== JSON.stringify(keys)) fail(`${name} keys must be exact and ordered`); };
const utf8 = (bytes, name) => { try { return new TextDecoder("utf-8", { fatal: true, ignoreBOM: true }).decode(bytes); } catch { fail(`${name} must be UTF-8`); } };
const canonical = (bytes, name) => { const text = utf8(bytes, name); if (text.startsWith("\ufeff")) fail(`${name} BOM is forbidden`); let value; try { value = JSON.parse(text); } catch { fail(`${name} must be JSON`); } if (`${JSON.stringify(value, null, 2)}\n` !== text) fail(`${name} must be canonical`); return value; };
const parsedJson = (bytes, name) => { try { return JSON.parse(utf8(bytes, name)); } catch { fail(`${name} must be JSON`); } };
const safeDartPath = (value, name = "Dart path") => {
  if (typeof value !== "string" || !value.startsWith("apps/mobile/lib/") || !value.endsWith(".dart") || value.includes("//") || /(?:^|\/)\.{1,2}(?:\/|$)|[\\\u0000-\u001f]/u.test(value)) fail(`${name} is ambiguous`);
  return value;
};
const json = (bytes, name) => canonical(bytes, name);
const bp = (covered, executable) => executable === 0 ? 0 : Math.floor((covered * 10000) / executable);

export function parseNameStatusZ(bytes) {
  const parts = utf8(Buffer.from(bytes), "name-status stream").split("\0");
  if (parts.pop() !== "" || parts.some((part) => !part || /[\r\n\t]/u.test(part))) fail("invalid name-status -z stream");
  const changes = [];
  for (let index = 0; index < parts.length;) {
    const token = parts[index++];
    if (!/^(?:A|M|D|R\d{1,3}|C\d{1,3})$/u.test(token)) fail("unsupported, unmerged, or type name-status entry");
    const code = token[0]; const renamed = code === "R" || code === "C";
    const oldPath = code === "D" || renamed ? parts[index++] : null;
    const newPath = code === "D" ? null : parts[index++];
    if (oldPath !== null) safeDartPath(oldPath, "old changed path");
    if (newPath !== null) safeDartPath(newPath, "new changed path");
    changes.push({ status: ({ A: "ADDED", M: "MODIFIED", D: "DELETED", R: "RENAMED", C: "COPIED" })[code], oldPath, newPath });
  }
  return changes;
}

export function parseNumstatZ(bytes) {
  const parts = utf8(Buffer.from(bytes), "numstat stream").split("\0");
  if (parts.pop() !== "") fail("invalid numstat -z stream");
  const values = [];
  for (let index = 0; index < parts.length;) {
    const header = parts[index++]; const match = /^(\d+|-)\t(\d+|-)\t(.*)$/u.exec(header);
    if (!match || match[1] === "-" || match[2] === "-") fail("binary or malformed numstat entry");
    let oldPath = null; let newPath = match[3];
    if (newPath === "") { oldPath = parts[index++]; newPath = parts[index++]; if (oldPath === undefined || newPath === undefined) fail("truncated rename numstat tuple"); }
    safeDartPath(oldPath ?? newPath, "numstat path"); if (oldPath !== null) safeDartPath(newPath, "numstat path");
    values.push({ oldPath, newPath, added: Number(match[1]), deleted: Number(match[2]) });
  }
  return values;
}

export function validateDiffTuples(changes, numstats) {
  if (changes.length !== numstats.length) fail("name-status/numstat tuple count mismatch");
  for (let index = 0; index < changes.length; index += 1) {
    const change = changes[index]; const stat = numstats[index];
    const matches = change.status === "DELETED" ? stat.oldPath === null && stat.newPath === change.oldPath : change.oldPath === stat.oldPath && change.newPath === stat.newPath;
    if (!matches) fail("name-status/numstat tuple path mismatch");
    if (change.status === "DELETED" && stat.added !== 0) fail("deleted path has added numstat lines");
  }
  return changes.map((change, index) => ({ ...change, added: numstats[index].added, deleted: numstats[index].deleted }));
}

export function validateEventIdentity(options, event, gitApi) {
  for (const key of ["baseSha", "headSha", "testedMergeSha"]) if (!SHA.test(options[key])) fail(`invalid ${key}`);
  const head = gitApi(["rev-parse", "HEAD"]); if (head !== options.testedMergeSha) fail("tested merge SHA does not equal HEAD");
  const ancestor = (base, target) => { try { gitApi(["merge-base", "--is-ancestor", base, target]); return true; } catch { return false; } };
  if (options.event === "pull_request") {
    if (!/^\d+$/u.test(options.pullRequestNumber) || Number(options.pullRequestNumber) < 1 || options.testedMergeSha === options.headSha || options.eventRef !== `refs/pull/${options.pullRequestNumber}/merge` || event.pull_request?.base?.sha !== options.baseSha || event.pull_request?.head?.sha !== options.headSha || event.pull_request?.number !== undefined && event.pull_request.number !== Number(options.pullRequestNumber)) fail("invalid pull request payload/ref identity");
    const mergeBases = gitApi(["merge-base", "--all", options.baseSha, options.headSha]).split("\n").filter(Boolean);
    if (mergeBases.length !== 1 || !SHA.test(mergeBases[0]) || !ancestor(mergeBases[0], options.baseSha) || !ancestor(mergeBases[0], options.headSha) || !ancestor(options.baseSha, options.testedMergeSha) || !ancestor(options.headSha, options.testedMergeSha)) fail("pull request merge base/tested merge is not unique/ancestral");
    return { eventMode: "PULL_REQUEST", mergeBaseSha: mergeBases[0], range: `${mergeBases[0]}..${options.headSha}` };
  }
  if (options.event === "push") {
    if (options.eventRef !== "refs/heads/main" || event.ref !== options.eventRef || options.pullRequestNumber !== "none" || event.before !== options.baseSha || event.after !== options.headSha || options.baseSha === "0".repeat(40) || options.baseSha === options.headSha || options.headSha !== options.testedMergeSha || !ancestor(options.baseSha, options.headSha)) fail("invalid push payload/ref identity");
    return { eventMode: "PUSH_MAIN", mergeBaseSha: options.baseSha, range: `${options.baseSha}..${options.headSha}` };
  }
  if (options.event === "workflow_dispatch") {
    if (options.pullRequestNumber !== "none" || event.ref !== options.eventRef || event.after !== undefined && event.after !== options.headSha || options.baseSha !== options.headSha || options.headSha !== options.testedMergeSha) fail("invalid manual payload/ref identity");
    return { eventMode: "MANUAL_FULL", mergeBaseSha: options.headSha, range: null };
  }
  fail("unsupported event");
}

function gitText(root, args) { return execFileSync("git", ["-C", root, ...args], { encoding: "utf8" }).trim(); }
function gitBytes(root, args) { return execFileSync("git", ["-C", root, ...args]); }
function defaultGit(root) { return { text: (args) => gitText(root, args), bytes: (args) => gitBytes(root, args) }; }
function parseLsTreeZ(bytes) {
  const parts = utf8(Buffer.from(bytes), "ls-tree stream").split("\0"); if (parts.pop() !== "") fail("invalid ls-tree -z stream");
  const tree = new Map();
  for (const record of parts) {
    const match = /^(\d{6}) (blob|tree|commit) ([0-9a-f]{40})\t(.+)$/u.exec(record);
    if (!match) fail("malformed ls-tree entry");
    const [, mode, type, blob, file] = match;
    if (!file.startsWith("apps/mobile/lib/") || /(?:^|\/)\.{1,2}(?:\/|$)|[\\\u0000-\u001f]/u.test(file)) fail("ambiguous tree path");
    if (file.endsWith(".dart")) {
      safeDartPath(file, "tree source path");
      if (mode !== "100644" || type !== "blob" || tree.has(file)) fail("non-regular Dart tree source");
      tree.set(file, blob);
    }
  }
  return tree;
}
export function treeSources(testedMergeSha, gitApi) {
  if (!SHA.test(testedMergeSha)) fail("invalid tree SHA");
  const tree = parseLsTreeZ(gitApi.bytes(["ls-tree", "-rz", testedMergeSha, "--", "apps/mobile/lib"]));
  if (!tree.size) fail("tested merge has no production Dart sources");
  return new Map([...tree].sort(([left], [right]) => compare(left, right)));
}
function blobAt(sha, file, gitApi) {
  const tree = parseLsTreeZ(gitApi.bytes(["ls-tree", "-rz", sha, "--", file])); const blob = tree.get(file);
  if (!blob) fail("Dart blob is unavailable at required SHA");
  return gitApi.bytes(["cat-file", "blob", blob]);
}

function assertSafeAncestorDirectories(directory, allowMissingLeaf = false) {
  const resolved = path.resolve(directory); const parent = allowMissingLeaf ? path.dirname(resolved) : resolved; const chain = [];
  for (let current = parent;; current = path.dirname(current)) { chain.push(current); if (current === path.dirname(current)) break; }
  for (const current of chain.reverse()) { let stat; try { stat = lstatSync(current); } catch { fail("artifact ancestor is missing"); } if (stat.isSymbolicLink() || !stat.isDirectory()) fail("artifact ancestor is unsafe"); }
}
function safeDirectory(directory, { empty = false } = {}) { assertSafeAncestorDirectories(directory); const stat = lstatSync(path.resolve(directory)); if (stat.isSymbolicLink() || !stat.isDirectory()) fail("artifact directory is unsafe"); if (empty && readdirSync(directory).length) fail("artifact directory is not empty"); }
function safeArtifactFile(directory, name) { const target = path.join(directory, name); const stat = lstatSync(target); if (stat.isSymbolicLink() || !stat.isFile()) fail("artifact endpoint is unsafe"); return readFileSync(target); }

export function commitArtifactPair(directory, files) {
  if (files.length !== ARTIFACT_FILES.length || files.some(({ name }, index) => name !== ARTIFACT_FILES[index])) fail("invalid artifact file set");
  const destination = path.resolve(directory); assertSafeAncestorDirectories(destination, true);
  try { lstatSync(destination); safeDirectory(destination, { empty: true }); } catch (error) { if (error.code !== "ENOENT") throw error; mkdirSync(destination); safeDirectory(destination, { empty: true }); }
  const parent = path.dirname(destination); const staged = mkdtempSync(path.join(parent, ".mobile-coverage-ratchet-stage-")); const backup = mkdtempSync(path.join(parent, ".mobile-coverage-ratchet-backup-")); rmSync(backup, { recursive: true });
  try {
    safeDirectory(staged, { empty: true });
    for (const file of files) { if (!Buffer.isBuffer(file.bytes)) fail("artifact bytes must be bytes"); writeFileSync(path.join(staged, file.name), file.bytes, { flag: "wx" }); }
    if (JSON.stringify(readdirSync(staged).sort(compare)) !== JSON.stringify([...ARTIFACT_FILES].sort(compare))) fail("staged artifact set changed");
    renameSync(destination, backup); renameSync(staged, destination); safeDirectory(destination); for (const name of ARTIFACT_FILES) safeArtifactFile(destination, name); rmSync(backup, { recursive: true });
  } catch (error) {
    try { if (!lstatSync(destination).isSymbolicLink() && lstatSync(backup).isDirectory()) { rmSync(destination, { recursive: true, force: true }); renameSync(backup, destination); } } catch { /* preserve the original error; caller must fail closed */ }
    rmSync(staged, { recursive: true, force: true }); throw error;
  }
}

export function parsePolicyBytes(bytes) {
  const value = canonical(bytes, "policy"); if (hash(bytes) !== POLICY_SHA256) fail("policy does not match the reviewed closed declaration"); exactKeys(value, POLICY_KEYS, "policy");
  if (value.schemaVersion !== 1 || value.artifactKind !== "mobile-coverage-policy-v1" || value.repository !== "AquilaXk/easysubway-mobile") fail("invalid policy identity");
  exactKeys(value.transition, ["phase", "baselineReviewed"], "transition"); if (JSON.stringify(value.transition) !== JSON.stringify({ phase: "DISCOVERY_REMOTE_RED", baselineReviewed: false })) fail("invalid Phase 1 transition");
  exactKeys(value.sourceScope, ["root", "include", "kind"], "sourceScope"); if (JSON.stringify(value.sourceScope) !== JSON.stringify({ root: "apps/mobile/lib", include: "apps/mobile/lib/**/*.dart", kind: "PRODUCTION_DART" })) fail("invalid source scope");
  if (!Array.isArray(value.exclusions) || value.exclusions.length !== 2) fail("invalid exclusions");
  for (const [index, [id, suffix]] of [["DRIFT_CATALOG_DATABASE_GENERATED", "catalog/catalog_database.g.dart"], ["DRIFT_USER_DATABASE_GENERATED", "user/user_database.g.dart"]].entries()) { const entry = value.exclusions[index]; exactKeys(entry, ["id", "path", "requiredFirstLine", "reason", "ownerIssueUrl", "ownerIssueTitle", "removalTrigger"], "exclusion"); if (entry.id !== id || entry.path !== `apps/mobile/lib/core/database/${suffix}` || entry.requiredFirstLine !== "// GENERATED CODE - DO NOT MODIFY BY HAND" || entry.reason !== "Tracked Drift generated output; handwritten schema and adapters remain covered." || entry.ownerIssueUrl !== "https://github.com/AquilaXk/easysubway-mobile/issues/48" || entry.ownerIssueTitle !== "[Build][Mobile][P1] LCOV·diff coverage ratchet — filter-mobile-lcov 확장과 CI 배선" || entry.removalTrigger !== "Review immediately when the generated header, Drift generation relationship, source path, coverage producer, or handwritten/generated boundary changes.") fail("invalid exclusion declaration"); }
  exactKeys(value.criticalBoundaryRules, BOUNDARIES, "criticalBoundaryRules"); for (const entries of Object.values(value.criticalBoundaryRules)) if (!Array.isArray(entries) || !entries.length || new Set(entries).size !== entries.length || entries.some((entry) => typeof entry !== "string" || !entry || /[^\x20-\x7e]/u.test(entry))) fail("invalid critical boundary declaration");
  exactKeys(value.lcov, ["closedTags", "pathRoot", "lineCoverage", "functionCoverage", "branchCoverage", "canonicalOrder"], "lcov"); if (JSON.stringify(value.lcov) !== JSON.stringify({ closedTags: TAGS, pathRoot: "apps/mobile", lineCoverage: true, functionCoverage: "DISABLED_UNPROVEN", branchCoverage: "DISABLED_UNPROVEN", canonicalOrder: "OFFICIAL_TAG_GROUP_THEN_IDENTITY" })) fail("invalid lcov declaration");
  exactKeys(value.comparison, ["shaFormat", "pullRequestRange", "pushRange", "manualRange", "coreQuotepath", "diffRenameLimit", "diffAlgorithm", "findRenames", "findCopies", "findCopiesHarder", "nameStatusNullTerminated", "numstatNullTerminated"], "comparison"); if (JSON.stringify(value.comparison) !== JSON.stringify({ shaFormat: "lowercase-40-hex", pullRequestRange: "mergeBase..head", pushRange: "base..head", manualRange: null, coreQuotepath: false, diffRenameLimit: 10000, diffAlgorithm: "myers", findRenames: "90%", findCopies: "90%", findCopiesHarder: true, nameStatusNullTerminated: true, numstatNullTerminated: true })) fail("invalid comparison declaration");
  exactKeys(value.thresholds, ["repositoryLineBasisPoints", "changedLineBasisPoints", "criticalBoundaryLineBasisPoints"], "thresholds"); if (Object.values(value.thresholds).some((entry) => entry !== null)) fail("Phase 1 thresholds must be null");
  exactKeys(value.artifacts, ["directory", "name", "files", "uploadAction", "retentionDays", "ifNoFilesFound"], "artifacts"); if (JSON.stringify(value.artifacts) !== JSON.stringify({ directory: "${RUNNER_TEMP}/mobile-coverage-ratchet", name: "mobile-coverage-ratchet-${headSha}", files: ARTIFACT_FILES, uploadAction: "actions/upload-artifact@65462800fd760344b1a7b4382951275a0abb4808", retentionDays: 5, ifNoFilesFound: "error" })) fail("invalid artifact declaration");
  return value;
}
export function parseBaselineBytes(bytes) {
  const value = canonical(bytes, "baseline"); exactKeys(value, BASELINE_KEYS, "baseline"); if (value.schemaVersion !== 1 || value.artifactKind !== "mobile-coverage-baseline-v1" || value.repository !== "AquilaXk/easysubway-mobile") fail("invalid baseline identity"); exactKeys(value.reviewState, ["phase", "reviewed"], "baseline reviewState"); exactKeys(value.provenance, ["runUrl", "baseSha", "headSha", "testedMergeSha", "mergeBaseSha", "rawLcovSha256", "normalizedLcovSha256", "sourceInventorySha256", "resultSha256"], "baseline provenance"); exactKeys(value.producer, ["policySha256", "filterSha256", "ratchetSha256", "flutterVersion", "lcovTagSubset"], "baseline producer"); exactKeys(value.floors, ["repositoryLineBasisPoints", "changedLineBasisPoints", "criticalBoundaryLineBasisPoints"], "baseline floors"); if (JSON.stringify(value.reviewState) !== JSON.stringify({ phase: "UNREVIEWED_DISCOVERY", reviewed: false }) || [...Object.values(value.provenance), ...Object.values(value.producer), ...Object.values(value.floors)].some((entry) => entry !== null) || JSON.stringify(value.paths) !== "[]" || JSON.stringify(value.criticalBoundaries) !== "[]") fail("invalid Phase 1 baseline skeleton"); return value;
}

export function classifyDartLines(bytes) {
  const source = utf8(bytes, "Dart source"); if (source.includes("\0")) fail("Dart NUL is forbidden"); const output = []; let state = "CODE"; let depth = 0; let quote = ""; let raw = false; let seenCode = false;
  const finish = () => { output.push(seenCode ? "CODE" : "COMMENT_ONLY"); seenCode = false; };
  for (let index = 0; index < source.length; index += 1) { const char = source[index]; const next = source[index + 1] ?? ""; const triple = source.slice(index, index + 3); if (char === "\n") { if (state === "LINE") state = "CODE"; else if (state === "SINGLE" || state === "DOUBLE") fail("unterminated normal string"); finish(); continue; } if (state === "LINE") continue; if (state === "BLOCK") { if (char === "/" && next === "*") { depth += 1; index += 1; } else if (char === "*" && next === "/") { depth -= 1; index += 1; if (!depth) state = "CODE"; } continue; } if (state === "TRIPLE") { seenCode = true; if (triple === quote.repeat(3)) { index += 2; state = "CODE"; } continue; } if (state === "SINGLE" || state === "DOUBLE") { seenCode = true; if (!raw && char === "\\") { index += 1; continue; } if (char === quote) state = "CODE"; continue; } if (/\s/u.test(char)) continue; if (char === "/" && next === "/") { state = "LINE"; index += 1; continue; } if (char === "/" && next === "*") { state = "BLOCK"; depth = 1; index += 1; continue; } raw = char === "r" && (next === "'" || next === '"'); if (raw) index += 1; const opener = raw ? source[index] : char; if (opener === "'" || opener === '"') { quote = opener; if (source.slice(index, index + 3) === opener.repeat(3)) { state = "TRIPLE"; index += 2; } else state = opener === "'" ? "SINGLE" : "DOUBLE"; seenCode = true; continue; } seenCode = true; }
  if (state === "BLOCK" || state === "TRIPLE") fail("unterminated Dart lexical construct"); if (source.length && !source.endsWith("\n")) finish(); return output;
}
function parseNormalizedLcov(bytes) { const text = utf8(bytes, "normalized LCOV"); const records = new Map(); let source = null; let lines = new Map(); for (const line of text.split("\n")) { if (!line) continue; if (line.startsWith("SF:")) { if (source) fail("nested LCOV source"); source = safeDartPath(`apps/mobile/${line.slice(3)}`, "normalized LCOV source"); lines = new Map(); continue; } if (line.startsWith("DA:")) { const match = /^DA:(\d+),(\d+)(?:,[^,]+)?$/u.exec(line); if (!source || !match || Number(match[1]) < 1 || lines.has(Number(match[1]))) fail("invalid normalized DA"); lines.set(Number(match[1]), Number(match[2])); continue; } if (line === "end_of_record") { if (!source || records.has(source)) fail("invalid normalized record"); records.set(source, lines); source = null; continue; } } if (source) fail("incomplete normalized LCOV"); return records; }
function ownersFor(file, changedPolicy) { if (!Array.isArray(changedPolicy?.pathRules)) fail("invalid #50 path rules"); const owners = []; for (const rule of changedPolicy.pathRules) { if (!Array.isArray(rule.exactPaths) || !Array.isArray(rule.prefixes) || !Array.isArray(rule.owners)) fail("invalid #50 path rule"); if (rule.exactPaths.includes(file) || rule.prefixes.some((prefix) => file.startsWith(prefix))) for (const owner of rule.owners) if (typeof owner !== "string" || !owner || owner === "UNKNOWN") fail("invalid direct owner"); else if (!owners.includes(owner)) owners.push(owner); } if (owners.length < 1 || owners.length > 4) fail("source must have one to four direct #50 owners"); return owners; }
function boundariesFor(file, policy) { const relative = file.slice("apps/mobile/lib/".length); return BOUNDARIES.filter((id) => policy.criticalBoundaryRules[id].some((entry) => entry.endsWith("/") ? relative.startsWith(entry) : relative === entry)); }
function diffArgs(range, kind, extra = []) { return ["-c", "core.quotepath=false", "-c", "diff.renameLimit=10000", "diff", "--no-ext-diff", kind, "--find-renames=90%", "--find-copies=90%", "--find-copies-harder", "--diff-algorithm=myers", ...extra, range, "--", "apps/mobile/lib"]; }
function patchHunks(patch, changes) { const byNew = new Map(changes.filter((entry) => entry.newPath).map((entry) => [entry.newPath, entry])); const hunks = new Map(); let file = null; for (const row of patch.split("\n")) { if (row.startsWith("+++ b/")) { file = row.slice(6); if (file) safeDartPath(file, "patch path"); continue; } const match = /^@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@/u.exec(row); if (!match || !file || !byNew.has(file)) continue; const start = Number(match[1]); const count = Number(match[2] ?? 1); if (count === 0) continue; const entries = hunks.get(file) ?? []; for (let line = start; line < start + count; line += 1) entries.push(line); hunks.set(file, entries); } return hunks; }
export function changedExecutableLines(range, headSha, testedMergeSha, coverage, gitApi) {
  const changes = validateDiffTuples(parseNameStatusZ(gitApi.bytes(diffArgs(range, "--name-status", ["-z"]))), parseNumstatZ(gitApi.bytes(diffArgs(range, "--numstat", ["-z"]))));
  const hunks = patchHunks(gitApi.text(diffArgs(range, "--unified=0")), changes); const entries = [];
  for (const change of changes) {
    if (change.status === "DELETED") continue;
    const lines = hunks.get(change.newPath) ?? []; if (change.added !== lines.length) fail("numstat/patch added-line mismatch");
    const rawBlob = blobAt(headSha, change.newPath, gitApi); const testedBlob = blobAt(testedMergeSha, change.newPath, gitApi); if (!rawBlob.equals(testedBlob)) fail("raw-head/tested-merge Dart blob differs; deterministic line mapping is required");
    if (!lines.length) continue;
    const lexical = classifyDartLines(rawBlob); const sourceLines = utf8(rawBlob, "raw head Dart source").split("\n"); const covered = coverage.get(change.newPath) ?? new Map();
    for (const line of lines) { if (covered.has(line)) entries.push({ path: change.newPath, line, hits: covered.get(line), status: change.status }); else if (lexical[line - 1] !== "COMMENT_ONLY" && !/^\s*$/u.test(sourceLines[line - 1] ?? "")) fail("AMBIGUOUS_UNMAPPED_DART_LINE"); }
  }
  entries.sort((left, right) => compare(left.path, right.path) || left.line - right.line || compare(left.status, right.status)); const coveredLines = entries.filter((entry) => entry.hits > 0).length; return { state: "APPLICABLE", entries, executableLines: entries.length, coveredLines, lineBasisPoints: bp(coveredLines, entries.length) };
}
function parseArgs(argv, command) { const required = command === "analyze" ? ["event", "event-path", "base-sha", "head-sha", "tested-merge-sha", "event-ref", "pull-request-number", "raw-lcov", "normalized-lcov", "filter-result", "policy", "baseline"] : ["analysis-outcome", "upload-outcome"]; const values = {}; for (let index = 0; index < argv.length; index += 2) { const key = argv[index]?.slice(2); if (!key || !required.includes(key) || values[key] || argv[index + 1] === undefined) fail("invalid arguments", 2); values[key] = argv[index + 1]; } if (required.some((key) => values[key] === undefined)) fail("missing arguments", 2); return values; }
function validateFilter(filter, policy, policyBytes, raw, normalized, coverage) { exactKeys(filter, ["schemaVersion", "artifactKind", "policySha256", "inputSha256", "outputSha256", "records", "lines", "exclusions", "outcome"], "filter result"); exactKeys(filter.records, ["retained", "excluded"], "filter records"); exactKeys(filter.lines, ["executable", "covered"], "filter lines"); if (filter.schemaVersion !== 1 || filter.artifactKind !== "mobile-lcov-filter-result-v1" || filter.outcome !== "success" || filter.policySha256 !== hash(policyBytes) || filter.inputSha256 !== hash(raw) || filter.outputSha256 !== hash(normalized) || filter.records.retained !== coverage.size || filter.records.excluded !== policy.exclusions.length || !Number.isInteger(filter.lines.executable) || !Number.isInteger(filter.lines.covered) || filter.lines.executable < filter.lines.covered || !Array.isArray(filter.exclusions) || filter.exclusions.length !== policy.exclusions.length) fail("filter identity/counter mismatch"); const evidence = new Map(); for (const entry of filter.exclusions) { exactKeys(entry, ["path", "reason", "executableLines", "coveredLines"], "filter exclusion"); const declared = policy.exclusions.find((item) => item.path === entry.path && item.id === entry.reason); if (!declared || evidence.has(entry.path) || !Number.isInteger(entry.executableLines) || !Number.isInteger(entry.coveredLines) || entry.executableLines < entry.coveredLines || coverage.has(entry.path)) fail("invalid filter exclusion evidence"); evidence.set(entry.path, entry); } for (const declared of policy.exclusions) if (!evidence.has(declared.path)) fail("missing declared filter exclusion evidence"); return evidence; }
function summaryFor(result) { return `# Mobile coverage ratchet\n\nEvent: ${result.identity.event}\nBase SHA: ${result.identity.baseSha}\nHead SHA: ${result.identity.headSha}\nMerge base SHA: ${result.identity.mergeBaseSha}\nTested merge SHA: ${result.identity.testedMergeSha}\nOutcome: ${result.outcome}\n`; }

export function analyze(options, { repositoryRoot = process.cwd(), reportDirectory = process.env.RUNNER_TEMP && path.resolve(process.env.RUNNER_TEMP, "mobile-coverage-ratchet"), gitApi = defaultGit(repositoryRoot), readFile = readFileSync } = {}) {
  if (!reportDirectory || !path.isAbsolute(reportDirectory)) fail("RUNNER_TEMP must be an absolute path"); if (path.resolve(repositoryRoot) !== path.resolve(gitApi.text(["rev-parse", "--show-toplevel"]))) fail("cwd must be repository root");
  const policyBytes = readFile(path.resolve(repositoryRoot, options.policy)); const baselineBytes = readFile(path.resolve(repositoryRoot, options.baseline)); const policy = parsePolicyBytes(policyBytes); parseBaselineBytes(baselineBytes); const event = parsedJson(readFile(options.eventPath), "event payload"); const eventIdentity = validateEventIdentity(options, event, gitApi.text);
  const raw = readFile(options.rawLcov); const normalized = readFile(options.normalizedLcov); const filter = parsedJson(readFile(options.filterResult), "filter result"); const coverage = parseNormalizedLcov(normalized); const filterEvidence = validateFilter(filter, policy, policyBytes, raw, normalized, coverage); const changedPolicy = parsedJson(readFile(path.join(repositoryRoot, "tools/ci/mobile-changed-path-policy.json")), "#50 changed path policy");
  const testedTree = treeSources(options.testedMergeSha, gitApi); const sourcePaths = [...testedTree.keys()]; for (const [id, entries] of Object.entries(policy.criticalBoundaryRules)) for (const entry of entries) { const target = `apps/mobile/lib/${entry}`; if (!sourcePaths.some((file) => entry.endsWith("/") ? file.startsWith(target) : file === target)) fail(`critical boundary path does not resolve: ${id}:${entry}`); }
  for (const exclusion of policy.exclusions) { const blob = testedTree.get(exclusion.path); if (!blob) fail("generated exclusion is absent from tested merge tree"); const first = utf8(gitApi.bytes(["cat-file", "blob", blob]), "generated exclusion blob").split("\n", 1)[0]; if (first !== exclusion.requiredFirstLine) fail("invalid generated exclusion target"); }
  const sources = sourcePaths.map((file) => { const blob = testedTree.get(file); const sourceBytes = gitApi.bytes(["cat-file", "blob", blob]); const excluded = policy.exclusions.find((entry) => entry.path === file); const lines = coverage.get(file); const executable = lines?.size ?? null; const covered = lines ? [...lines.values()].filter((hits) => hits > 0).length : null; return { path: file, sourceSha256: hash(sourceBytes), kind: "PRODUCTION_DART", owners: ownersFor(file, changedPolicy), criticalBoundaries: boundariesFor(file, policy), lcovPresent: Boolean(lines), absenceDisposition: null, executableLines: executable, coveredLines: covered, uncoveredLines: lines ? executable - covered : null, exclusion: excluded ? { excluded: true, reason: excluded.id } : { excluded: false, reason: null } }; });
  const included = sources.filter((source) => !source.exclusion.excluded && source.lcovPresent); const totals = (items) => ({ executableLines: items.reduce((sum, item) => sum + item.executableLines, 0), coveredLines: items.reduce((sum, item) => sum + item.coveredLines, 0) }); const all = totals(included); const identity = { event: options.event, eventMode: eventIdentity.eventMode, baseSha: options.baseSha, headSha: options.headSha, mergeBaseSha: eventIdentity.mergeBaseSha, testedMergeSha: options.testedMergeSha, range: eventIdentity.range };
  const filterBytes = readFile(path.join(repositoryRoot, "tools/ci/filter-mobile-lcov.mjs")); const ratchetBytes = readFile(fileURLToPath(import.meta.url)); const lcovTagSubset = TAGS.filter((tag) => new RegExp(`^${tag === "end_of_record" ? tag : `${tag}:`}`, "m").test(utf8(normalized, "normalized LCOV"))); const producer = { policySha256: hash(policyBytes), baselineSha256: hash(baselineBytes), filterSha256: hash(filterBytes), ratchetSha256: hash(ratchetBytes), rawLcovSha256: hash(raw), normalizedLcovSha256: hash(normalized), lcovTagSubset };
  const inventory = { schemaVersion: 1, artifactKind: "mobile-coverage-source-inventory-v1", repository: policy.repository, identity, producer: { policySha256: producer.policySha256, filterSha256: producer.filterSha256, ratchetSha256: producer.ratchetSha256, lcovTagSubset }, sources, summary: { sources: sources.length, included: sources.filter((source) => !source.exclusion.excluded).length, excluded: sources.filter((source) => source.exclusion.excluded).length, lcovPresent: sources.filter((source) => source.lcovPresent).length, lcovMissing: sources.filter((source) => !source.lcovPresent).length, executableLines: all.executableLines, coveredLines: all.coveredLines, lineBasisPoints: bp(all.coveredLines, all.executableLines) } }; const inventoryBytes = Buffer.from(`${JSON.stringify(inventory, null, 2)}\n`);
  const changedLines = eventIdentity.eventMode === "MANUAL_FULL" ? { state: "NOT_APPLICABLE_MANUAL_FULL", entries: [], executableLines: 0, coveredLines: 0, lineBasisPoints: null } : changedExecutableLines(eventIdentity.range, options.headSha, options.testedMergeSha, coverage, gitApi); const boundaries = BOUNDARIES.map((id) => { const total = totals(included.filter((source) => source.criticalBoundaries.includes(id))); return { id, executableLines: total.executableLines, coveredLines: total.coveredLines, uncoveredLines: total.executableLines - total.coveredLines, lineBasisPoints: bp(total.coveredLines, total.executableLines), lcovMissingSources: sources.filter((source) => !source.lcovPresent && source.criticalBoundaries.includes(id)).map((source) => source.path) }; });
  const result = { schemaVersion: 1, artifactKind: "mobile-coverage-ratchet-result-v1", repository: policy.repository, phase: "DISCOVERY_REMOTE_RED", identity, producer: { ...producer, sourceInventorySha256: hash(inventoryBytes) }, coverage: { executableLines: all.executableLines, coveredLines: all.coveredLines, uncoveredLines: all.executableLines - all.coveredLines, lineBasisPoints: bp(all.coveredLines, all.executableLines), lcovMissingSources: sources.filter((source) => !source.lcovPresent).map((source) => source.path) }, changedLines, criticalBoundaries: boundaries, exclusions: policy.exclusions.map((entry) => { const evidence = filterEvidence.get(entry.path); return { id: entry.id, path: entry.path, reason: entry.id, executableLines: evidence.executableLines, coveredLines: evidence.coveredLines }; }), artifacts: { directory: policy.artifacts.directory, name: policy.artifacts.name, files: ARTIFACT_FILES }, reasons: ["BASELINE_UNREVIEWED"], outcome: "DISCOVERY_REMOTE_RED" };
  commitArtifactPair(reportDirectory, [{ name: ARTIFACT_FILES[0], bytes: raw }, { name: ARTIFACT_FILES[1], bytes: normalized }, { name: ARTIFACT_FILES[2], bytes: inventoryBytes }, { name: ARTIFACT_FILES[3], bytes: Buffer.from(`${JSON.stringify(result, null, 2)}\n`) }, { name: ARTIFACT_FILES[4], bytes: Buffer.from(summaryFor(result)) }]); return result;
}

function validateArtifactNestedEvidence(directory) {
  const inventory = canonical(safeArtifactFile(directory, ARTIFACT_FILES[2]), "source inventory");
  const result = canonical(safeArtifactFile(directory, ARTIFACT_FILES[3]), "result");
  exactKeys(result.coverage, ["executableLines", "coveredLines", "uncoveredLines", "lineBasisPoints", "lcovMissingSources"], "coverage");
  exactKeys(result.changedLines, ["state", "entries", "executableLines", "coveredLines", "lineBasisPoints"], "changedLines");
  exactKeys(result.artifacts, ["directory", "name", "files"], "artifacts");
  if (!Array.isArray(inventory.sources) || !Array.isArray(result.changedLines.entries)) fail("artifact nested evidence shape mismatch");
  const included = inventory.sources.filter((source) => !source.exclusion?.excluded && source.lcovPresent);
  const executableLines = included.reduce((sum, source) => sum + source.executableLines, 0);
  const coveredLines = included.reduce((sum, source) => sum + source.coveredLines, 0);
  if (result.coverage.executableLines !== executableLines || result.coverage.coveredLines !== coveredLines || result.coverage.uncoveredLines !== executableLines - coveredLines || result.coverage.lineBasisPoints !== bp(coveredLines, executableLines) || result.coverage.lcovMissingSources.length !== inventory.sources.filter((source) => !source.lcovPresent).length) fail("artifact coverage does not recompute from inventory");
  if (result.changedLines.entries.some((entry) => !entry || typeof entry.path !== "string" || !Number.isInteger(entry.line) || entry.line < 1)) fail("artifact changed-line identity is invalid");
}

export function verifyArtifactDirectory(directory, { repositoryRoot = process.cwd(), readFile = readFileSync } = {}) {
  safeDirectory(directory); validateArtifactNestedEvidence(directory);
  safeDirectory(directory); const names = readdirSync(directory).sort(compare); if (JSON.stringify(names) !== JSON.stringify([...ARTIFACT_FILES].sort(compare))) fail("artifact file set changed"); const raw = safeArtifactFile(directory, ARTIFACT_FILES[0]); const normalized = safeArtifactFile(directory, ARTIFACT_FILES[1]); const inventoryBytes = safeArtifactFile(directory, ARTIFACT_FILES[2]); const resultBytes = safeArtifactFile(directory, ARTIFACT_FILES[3]); const summary = safeArtifactFile(directory, ARTIFACT_FILES[4]); const inventory = canonical(inventoryBytes, "source inventory"); const result = canonical(resultBytes, "result"); exactKeys(inventory, INVENTORY_KEYS, "source inventory"); exactKeys(result, RESULT_KEYS, "result"); if (result.phase !== "DISCOVERY_REMOTE_RED" || result.outcome !== "DISCOVERY_REMOTE_RED" || JSON.stringify(result.reasons) !== JSON.stringify(["BASELINE_UNREVIEWED"]) || result.producer?.rawLcovSha256 !== hash(raw) || result.producer?.normalizedLcovSha256 !== hash(normalized) || result.producer?.sourceInventorySha256 !== hash(inventoryBytes) || JSON.stringify(result.identity) !== JSON.stringify(inventory.identity) || JSON.stringify(result.producer.lcovTagSubset) !== JSON.stringify(inventory.producer?.lcovTagSubset) || !result.producer.lcovTagSubset.every((tag) => TAGS.includes(tag)) || utf8(summary, "summary") !== summaryFor(result)) fail("artifact result cross-schema identity mismatch"); const policyBytes = readFile(path.join(repositoryRoot, "tools/ci/mobile-coverage-policy.json")); const baselineBytes = readFile(path.join(repositoryRoot, "tools/ci/mobile-coverage-baseline.json")); const filterBytes = readFile(path.join(repositoryRoot, "tools/ci/filter-mobile-lcov.mjs")); const ratchetBytes = readFile(fileURLToPath(import.meta.url)); parsePolicyBytes(policyBytes); parseBaselineBytes(baselineBytes); if (result.producer.policySha256 !== hash(policyBytes) || result.producer.baselineSha256 !== hash(baselineBytes) || result.producer.filterSha256 !== hash(filterBytes) || result.producer.ratchetSha256 !== hash(ratchetBytes) || !DIGEST.test(result.producer.rawLcovSha256) || !DIGEST.test(result.producer.normalizedLcovSha256) || !DIGEST.test(result.producer.sourceInventorySha256)) fail("artifact producer digest mismatch"); return result;
}

function main() { const command = process.argv[2]; if (command === "analyze") { const result = analyze(Object.fromEntries(Object.entries(parseArgs(process.argv.slice(3), command)).map(([key, value]) => [key.replace(/-([a-z])/gu, (_, char) => char.toUpperCase()), value]))); process.stdout.write(`${JSON.stringify({ outcome: result.outcome, headSha: result.identity.headSha })}\n`); return; } if (command === "verdict") { const options = parseArgs(process.argv.slice(3), command); if (options["analysis-outcome"] !== "success" || options["upload-outcome"] !== "success") fail("analysis or upload failed"); if (!process.env.RUNNER_TEMP || !path.isAbsolute(process.env.RUNNER_TEMP)) fail("RUNNER_TEMP must be an absolute path"); verifyArtifactDirectory(path.resolve(process.env.RUNNER_TEMP, "mobile-coverage-ratchet")); fail("DISCOVERY_REMOTE_RED"); } fail("usage", 2); }
if (process.argv[1] === fileURLToPath(import.meta.url)) try { main(); } catch (error) { process.stderr.write(`mobile-coverage-ratchet: ${error.message}\n`); process.exitCode = error.exitCode ?? 1; }
