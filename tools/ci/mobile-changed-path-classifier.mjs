#!/usr/bin/env node

import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import {
  lstatSync,
  mkdirSync,
  readFileSync,
  readdirSync,
  realpathSync,
  statSync,
  writeFileSync,
} from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const SHA = /^[0-9a-f]{40}$/u;
const MODE = /^[0-7]{6}$/u;
const REQUIREMENT_KEYS = [
  "requiresFullHostTests", "requiresCoverage", "requiresAndroidBuild",
  "requiresIOSCompile", "requiresNativeIntegration", "requiresGolden",
  "requiresContractStaging", "requiresMapCatalogArtifactGate",
  "requiresArchitectureGates", "requiresPrivacyStoreGate",
];
export const FULL_REQUIREMENTS = Object.freeze(Object.fromEntries(REQUIREMENT_KEYS.map((key) => [key, true])));
const FEATURE_ROOTS = ["account", "ads", "attribution", "fare", "favorites", "get_off_alarm", "home", "home_widget", "internal_route", "mobility_profile", "network_map", "notifications", "preferences", "realtime", "route_draft", "routes", "search_history", "service_notice", "settings", "stations", "support", "train_search"];
const LOGICAL_CLASSES = ["APP_COMPOSITION_OR_ENTRYPOINT", "FEATURE", "SHARED_CORE_OR_PUBLIC_API", "GENERATED_CONTRACT_OR_CODEGEN", "GENERIC_CONSUMER_CONTRACT", "MAP_CATALOG_ARTIFACT_OR_ASSET", "INSTALLER_STORAGE_DATABASE_MIGRATION", "PRIVACY_SECURITY_PERMISSION", "FLUTTER_DART_DEPENDENCY_OR_TOOLCHAIN", "ANDROID_NATIVE_OR_BUILD", "IOS_NATIVE_OR_BUILD", "WORKFLOW_CI_TEST_COVERAGE_ARCHITECTURE_TOOL", "GOLDEN_OR_VISUAL_ASSET", "DOC_ONLY_NONEXECUTABLE", "TEMPLATE_POLICY_STORE_DECLARATION", "TEST_OR_FIXTURE", "UNKNOWN"];
const UNCERTAINTY_CODES = ["UNMATCHED_PATH", "UNKNOWN_FEATURE_ROOT", "SYMLINK", "SUBMODULE", "BINARY", "UNKNOWN_FILE_TYPE", "GRAPH_UNCERTAINTY", "SELF_CHANGE", "EMPTY_DIFF", "DOCS_POLICY_UNREVIEWED"];
const BOUNDARIES = ["APP_COMPOSITION", "SHARED_CORE", "FEATURE", "JOURNEY_CONTRACT", "MAP_CATALOG", "ANDROID_NATIVE", "IOS_NATIVE", "PRIVACY_STORE", "TOOLCHAIN", "TEST_INFRA", "WORKFLOW_CI", "UNKNOWN"];
const TOP_LEVEL_POLICY_KEYS = ["schemaVersion", "artifactKind", "repository", "featureRoots", "docsOnlyAllowlist", "riskOrder", "logicalClasses", "uncertaintyCodes", "requirements", "pathRules", "workflowContract"];
const PROFILE_KEYS = ["FULL", "FEATURE", "FEATURE_PRIVACY", "FEATURE_CONTRACT", "FEATURE_CATALOG", "FEATURE_NATIVE", "ANDROID", "IOS", "ASSET"];
const RESULT_KEYS = ["schemaVersion", "artifactKind", "repository", "event", "comparison", "classifier", "changes", "owners", "affectedFeatures", "affectedBoundaries", "requirements", "isProvenDocsOnly", "uncertainty", "summary", "outcome"];
const ARTIFACT_FILES = ["mobile-changed-path-classification.json", "mobile-changed-path-classification-summary.md", "mobile-changed-path-classification.sha256"];
const OUTPUT_KEYS = ["artifact-name", "classification-sha256", "head-sha", "outcome", "requires-full-host-tests", "requires-coverage", "requires-android-build", "requires-ios-compile", "requires-native-integration", "requires-golden", "requires-contract-staging", "requires-map-catalog-artifact-gate", "requires-architecture-gates", "requires-privacy-store-gate", "is-proven-docs-only"];
const STATUS_MAP = { A: "ADDED", M: "MODIFIED", D: "DELETED", R: "RENAMED", C: "COPIED", T: "TYPE_CHANGED", U: "UNMERGED_OR_UNKNOWN" };
const UTF8 = new TextDecoder("utf-8", { fatal: true });
const POLICY_SHA256 = "482fb5f29d5aeeadcced9599ad037b5fba002b189b04fce8e69744f8d0b5c256";
const CLOSED_POLICY = JSON.parse(readFileSync(new URL("./mobile-changed-path-policy.json", import.meta.url), "utf8"));
const POLICY_ORACLE = JSON.stringify(CLOSED_POLICY);
const PATH_RULE_IDS = CLOSED_POLICY.pathRules.map((rule) => rule.id);
const EXPECTED_PATH_RULE_IDS = [
  "self", "workflow", "github-config", "root-policy", "toolchain", "android-native", "ios-native", "app-composition", "shared-core", "journey-contract", "map-catalog", "contracts", "release", "assets", "tests", "tools", "feature-network-map",
  "feature-account", "feature-ads", "feature-attribution", "feature-fare", "feature-favorites", "feature-get_off_alarm", "feature-home", "feature-home_widget", "feature-internal_route", "feature-mobility_profile", "feature-network_map", "feature-notifications", "feature-preferences", "feature-realtime", "feature-route_draft", "feature-routes", "feature-search_history", "feature-service_notice", "feature-settings", "feature-stations", "feature-support", "feature-train_search",
  "feature-privacy", "feature-contract", "feature-catalog", "feature-native",
];
const OWNER_TOKENS = [...FEATURE_ROOTS.map((root) => `FEATURE:${root}`), "APP_COMPOSITION", "SHARED_CORE", "ANDROID_NATIVE", "IOS_NATIVE", "CI_TOOLING", "CONTRACT_ARTIFACT", "MAP_CATALOG", "PRIVACY_STORE", "RELEASE", "UNKNOWN"];

class ClassifierError extends Error {
  constructor(message, exitCode = 1) { super(message); this.exitCode = exitCode; }
}
function fail(message, exitCode = 1) { throw new ClassifierError(`mobile-changed-path-classifier: ${message}`, exitCode); }
function decodeUtf8(value, label) { try { return UTF8.decode(value); } catch { fail(`invalid UTF-8 ${label}`); } }
function cmp(a, b) { return a < b ? -1 : a > b ? 1 : 0; }
function sha256(value) { return createHash("sha256").update(value).digest("hex"); }
function keysEqual(value, keys, label) {
  if (!value || typeof value !== "object" || Array.isArray(value) || JSON.stringify(Object.keys(value)) !== JSON.stringify(keys)) fail(`${label} keys must be exact and ordered`);
}
function exactArray(value, expected, label) {
  if (!Array.isArray(value) || JSON.stringify(value) !== JSON.stringify(expected)) fail(`${label} must match the closed declaration`);
}
function normalizePath(value, label = "path") {
  if (typeof value !== "string" || value.length === 0 || /[\u0000-\u001f\u007f]/u.test(value)) fail(`invalid ${label}`);
  const normalized = value.replaceAll("\\", "/");
  if (normalized.startsWith("/") || /^[A-Za-z]:\//u.test(normalized) || normalized.split("/").some((part) => part === "" || part === "." || part === "..")) fail(`invalid ${label}`);
  return normalized;
}
function validRequirements(value, label) {
  keysEqual(value, REQUIREMENT_KEYS, label);
  for (const key of REQUIREMENT_KEYS) if (typeof value[key] !== "boolean") fail(`${label}.${key} must be boolean`);
  return value;
}
function sortedUnique(values) { return [...new Set(values)].sort(cmp); }
function declarationSorted(values, order) { return [...new Set(values)].sort((a, b) => order.indexOf(a) - order.indexOf(b)); }
function assertSha(value, label) { if (typeof value !== "string" || !SHA.test(value)) fail(`${label} must be a lowercase full SHA`); return value; }
function nullMode(value) { return value === "000000" ? null : MODE.test(value) ? value : fail("invalid raw mode"); }
function nullBlob(value) { return value === "0".repeat(40) ? null : SHA.test(value) ? value : fail("invalid raw blob SHA"); }
function exactSortedUnique(value, expectedOrder, label) {
  if (!Array.isArray(value) || value.some((item) => !expectedOrder.includes(item)) || JSON.stringify(value) !== JSON.stringify(declarationSorted(value, expectedOrder))) fail(`${label} must be closed, declaration-sorted, and unique`);
}
function exactLexicalPaths(value, label) {
  if (!Array.isArray(value)) fail(`${label} must be an array`);
  for (const item of value) normalizePath(item, label);
  if (JSON.stringify(value) !== JSON.stringify(sortedUnique(value))) fail(`${label} must be normalized, UTF-8 sorted, and unique`);
}
function exactReasons(value, label) { exactSortedUnique(value, [...PATH_RULE_IDS, ...UNCERTAINTY_CODES], label); }
function changeTuple(change) { return [change.newPath ?? "", change.oldPath ?? "", change.status, change.oldMode ?? "", change.newMode ?? "", change.oldBlobSha ?? "", change.newBlobSha ?? ""]; }
function equalTuple(left, right) { return left.every((value, index) => value === right[index]); }
function compareTuple(left, right) { for (let index = 0; index < left.length; index += 1) { const order = cmp(left[index], right[index]); if (order !== 0) return order; } return 0; }
function validateChange(change) {
  keysEqual(change, ["status", "oldPath", "newPath", "oldMode", "newMode", "oldBlobSha", "newBlobSha", "isBinary", "reasons"], "result change");
  if (!Object.values(STATUS_MAP).includes(change.status) || typeof change.isBinary !== "boolean") fail("invalid result change");
  for (const [key, value] of [["oldPath", change.oldPath], ["newPath", change.newPath]]) if (value !== null) normalizePath(value, `result change ${key}`);
  for (const [key, value] of [["oldMode", change.oldMode], ["newMode", change.newMode]]) if (value !== null && !MODE.test(value)) fail(`invalid result change ${key}`);
  for (const [key, value] of [["oldBlobSha", change.oldBlobSha], ["newBlobSha", change.newBlobSha]]) if (value !== null) assertSha(value, `result change ${key}`);
  const oldAbsent = change.oldPath === null && change.oldMode === null && change.oldBlobSha === null;
  const newAbsent = change.newPath === null && change.newMode === null && change.newBlobSha === null;
  const oldPresent = change.oldPath !== null && change.oldMode !== null && change.oldBlobSha !== null;
  const newPresent = change.newPath !== null && change.newMode !== null && change.newBlobSha !== null;
  if ((change.status === "ADDED" && (!oldAbsent || !newPresent)) || (change.status === "DELETED" && (!newAbsent || !oldPresent)) || (!["ADDED", "DELETED"].includes(change.status) && (!oldPresent || !newPresent))) fail("invalid status-specific change shape");
  if (["MODIFIED", "TYPE_CHANGED", "UNMERGED_OR_UNKNOWN"].includes(change.status) && change.oldPath !== change.newPath) fail("non-rename change paths must match");
  exactReasons(change.reasons, "result change reasons");
}
function validateOwner(owner) {
  keysEqual(owner, ["owner", "logicalClass", "risks", "reasons", "paths"], "result owner");
  if (!OWNER_TOKENS.includes(owner.owner) || !LOGICAL_CLASSES.includes(owner.logicalClass)) fail("invalid result owner identity");
  exactSortedUnique(owner.risks, ["P0_CRITICAL", "P1_HIGH", "P2_STANDARD", "FULL_REQUIRED_UNCERTAIN"], "result owner risks");
  exactReasons(owner.reasons, "result owner reasons");
  exactLexicalPaths(owner.paths, "result owner paths");
}
function validateSafeRef(value) { if (typeof value !== "string" || value.length === 0 || /[\u0000-\u001f\u007f]/u.test(value)) fail("invalid result event ref"); }

export function parseCliArguments(args) {
  if (args[0] !== "run" || args.length !== 11) fail("expected exact run arguments", 2);
  const allowed = new Set(["--event", "--base-sha", "--head-sha", "--event-ref", "--pull-request-number"]);
  const options = {};
  for (let i = 1; i < args.length; i += 2) {
    if (!allowed.has(args[i]) || Object.hasOwn(options, args[i]) || i + 1 >= args.length) fail("unknown, duplicate, or missing CLI argument", 2);
    options[args[i]] = args[i + 1];
  }
  if (Object.keys(options).length !== allowed.size || !["pull_request", "push", "workflow_dispatch"].includes(options["--event"])) fail("invalid event", 2);
  try { assertSha(options["--base-sha"], "base SHA"); assertSha(options["--head-sha"], "head SHA"); } catch { fail("invalid SHA argument", 2); }
  if (options["--base-sha"] === options["--head-sha"] || typeof options["--event-ref"] !== "string" || options["--event-ref"].length === 0) fail("invalid identity argument", 2);
  const number = options["--pull-request-number"];
  if ((options["--event"] === "pull_request" && !/^[1-9][0-9]*$/u.test(number)) || (options["--event"] !== "pull_request" && number !== "none")) fail("invalid pull request number", 2);
  return { event: options["--event"], baseSha: options["--base-sha"], headSha: options["--head-sha"], eventRef: options["--event-ref"], pullRequestNumber: number === "none" ? null : Number(number) };
}

export function validatePolicy(policy) {
  if (sha256(readFileSync(new URL("./mobile-changed-path-policy.json", import.meta.url))) !== POLICY_SHA256) fail("tracked policy bytes do not match the reviewed policy identity");
  if (JSON.stringify(policy) !== POLICY_ORACLE) fail("policy must exactly match the tracked closed policy declaration");
  keysEqual(policy, TOP_LEVEL_POLICY_KEYS, "policy top-level");
  if (policy.schemaVersion !== 1 || policy.artifactKind !== "mobile-changed-path-policy-v1" || policy.repository !== "AquilaXk/easysubway-mobile") fail("invalid fixed policy identity");
  exactArray(policy.featureRoots, FEATURE_ROOTS, "featureRoots");
  exactArray(policy.docsOnlyAllowlist, [], "docsOnlyAllowlist");
  exactArray(policy.riskOrder, ["P0_CRITICAL", "P1_HIGH", "P2_STANDARD", "FULL_REQUIRED_UNCERTAIN"], "riskOrder");
  exactArray(policy.logicalClasses, LOGICAL_CLASSES, "logicalClasses");
  exactArray(policy.uncertaintyCodes, UNCERTAINTY_CODES, "uncertaintyCodes");
  if (!policy.requirements || typeof policy.requirements !== "object" || Array.isArray(policy.requirements)) fail("requirements profiles must be an object");
  if (JSON.stringify(Object.keys(policy.requirements)) !== JSON.stringify(PROFILE_KEYS)) fail("requirements profile keys must be exact and ordered");
  for (const [name, requirement] of Object.entries(policy.requirements)) validRequirements(requirement, `requirements.${name}`);
  if (!Array.isArray(policy.pathRules) || policy.pathRules.length === 0) fail("pathRules must be non-empty");
  const ids = new Set();
  const ruleIds = [];
  for (const rule of policy.pathRules) {
    keysEqual(rule, ["id", "exactPaths", "prefixes", "owners", "logicalClasses", "risks", "requirements", "boundaries", "reasons"], "pathRule");
    if (typeof rule.id !== "string" || !/^[a-z0-9_-]+$/u.test(rule.id) || ids.has(rule.id)) fail("path rule id must be unique literal");
    ids.add(rule.id); ruleIds.push(rule.id);
    for (const field of ["exactPaths", "prefixes", "owners", "logicalClasses", "risks", "boundaries", "reasons"]) if (!Array.isArray(rule[field])) fail(`pathRule.${field} must be an array`);
    if (rule.exactPaths.length + rule.prefixes.length === 0 || rule.owners.length === 0 || rule.logicalClasses.length === 0 || rule.risks.length === 0 || rule.boundaries.length === 0 || rule.reasons.length === 0) fail("pathRule requires literals and classification");
    for (const item of rule.exactPaths) normalizePath(item, "rule exactPath");
    for (const item of rule.prefixes) { const normalized = normalizePath(item.slice(0, -1), "rule prefix"); if (`${normalized}/` !== item) fail("rule prefix must end with one slash"); }
    if (new Set([...rule.exactPaths, ...rule.prefixes]).size !== rule.exactPaths.length + rule.prefixes.length) fail("duplicate rule path literal");
    for (const owner of rule.owners) if (typeof owner !== "string" || owner.length === 0) fail("invalid owner");
    for (const logicalClass of rule.logicalClasses) if (!LOGICAL_CLASSES.includes(logicalClass)) fail("unknown logical class");
    for (const risk of rule.risks) if (!policy.riskOrder.includes(risk)) fail("unknown risk");
    for (const boundary of rule.boundaries) if (!BOUNDARIES.includes(boundary)) fail("unknown boundary");
    for (const reason of rule.reasons) if (reason !== rule.id && !UNCERTAINTY_CODES.includes(reason)) fail("unknown rule reason");
    validRequirements(rule.requirements, `pathRule.${rule.id}.requirements`);
  }
  exactArray(ruleIds, EXPECTED_PATH_RULE_IDS, "path rule IDs");
  keysEqual(policy.workflowContract, ["classifierJob", "authoritativeJobs", "artifactNameTemplate", "artifactFiles", "jobOutputs"], "workflowContract");
  if (policy.workflowContract.classifierJob !== "classify-changes" || policy.workflowContract.artifactNameTemplate !== "mobile-changed-path-classification-${headSha}") fail("invalid workflow contract fixed values");
  exactArray(policy.workflowContract.artifactFiles, ARTIFACT_FILES, "workflow artifact files");
  exactArray(policy.workflowContract.jobOutputs, OUTPUT_KEYS, "workflow job outputs");
  const jobs = policy.workflowContract.authoritativeJobs;
  if (!Array.isArray(jobs) || JSON.stringify(jobs) !== JSON.stringify([{ id: "mobile", name: "Mobile CI" }, { id: "android", name: "Android CI" }, { id: "dependency-vulnerability-scan", name: "Dependency Vulnerability Scan / osv-scan" }])) fail("invalid authoritative jobs");
  return policy;
}

export function parseRawDiff(buffer) {
  if (!Buffer.isBuffer(buffer)) fail("raw diff must be bytes");
  const fields = decodeUtf8(buffer, "raw diff").split("\0"); if (fields.at(-1) !== "") fail("raw diff must terminate in NUL"); fields.pop();
  const records = []; let index = 0;
  while (index < fields.length) {
    const header = fields[index++];
    const match = /^:([0-7]{6}) ([0-7]{6}) ([0-9a-f]{40}) ([0-9a-f]{40}) ([A-Z])(?:[0-9]{1,3})?$/u.exec(header);
    if (!match) fail("malformed raw diff header");
    const rawStatus = match[5]; const status = STATUS_MAP[rawStatus] ?? "UNMERGED_OR_UNKNOWN";
    const count = rawStatus === "R" || rawStatus === "C" ? 2 : 1;
    if (index + count > fields.length) fail("raw diff path shape missing");
    const paths = fields.slice(index, index + count).map((entry) => normalizePath(entry, "raw diff path")); index += count;
    const [oldMode, newMode, oldBlobSha, newBlobSha] = match.slice(1, 5).map((value, offset) => offset < 2 ? nullMode(value) : nullBlob(value));
    records.push({ status, oldPath: status === "ADDED" ? null : paths[0], newPath: status === "DELETED" ? null : (count === 2 ? paths[1] : paths[0]), oldMode, newMode, oldBlobSha, newBlobSha });
  }
  return records;
}

export function parseNumstat(buffer) {
  if (!Buffer.isBuffer(buffer)) fail("numstat must be bytes");
  const fields = decodeUtf8(buffer, "numstat").split("\0"); if (fields.at(-1) !== "") fail("numstat must terminate in NUL"); fields.pop();
  const records = []; let index = 0;
  while (index < fields.length) {
    const header = fields[index++]; const match = /^([0-9-]+)\t([0-9-]+)\t(.*)$/u.exec(header);
    if (!match || !((/^[0-9]+$/u.test(match[1]) && /^[0-9]+$/u.test(match[2])) || (match[1] === "-" && match[2] === "-"))) fail("malformed numstat header");
    const paths = match[3] === "" ? [fields[index++], fields[index++]] : [match[3]];
    if (paths.some((entry) => entry === undefined)) fail("numstat path shape missing");
    records.push({ paths: paths.map((entry) => normalizePath(entry, "numstat path")), isBinary: match[1] === "-" });
  }
  return records;
}

export function joinDiffStreams(rawRecords, numstatRecords) {
  if (!Array.isArray(rawRecords) || !Array.isArray(numstatRecords) || rawRecords.length !== numstatRecords.length) fail("raw and numstat entry count mismatch");
  const seen = new Set();
  return rawRecords.map((raw, index) => {
    const stat = numstatRecords[index];
    const expected = raw.status === "RENAMED" || raw.status === "COPIED" ? [raw.oldPath, raw.newPath] : [raw.status === "ADDED" ? raw.newPath : raw.oldPath];
    if (JSON.stringify(stat.paths) !== JSON.stringify(expected)) fail("raw and numstat path shape mismatch");
    const key = JSON.stringify([raw.status, raw.oldPath, raw.newPath, raw.oldMode, raw.newMode, raw.oldBlobSha, raw.newBlobSha]);
    if (seen.has(key)) fail("duplicate diff entry"); seen.add(key);
    return { ...raw, isBinary: stat.isBinary, reasons: [] };
  }).sort((left, right) => compareTuple(changeTuple(left), changeTuple(right)));
}

function matchRule(rule, changedPath) { return rule.exactPaths.includes(changedPath) || rule.prefixes.some((prefix) => changedPath.startsWith(prefix)); }
function unionRequirements(current, next) { return Object.fromEntries(REQUIREMENT_KEYS.map((key) => [key, current[key] || next[key]])); }
function emptyRequirements() { return Object.fromEntries(REQUIREMENT_KEYS.map((key) => [key, false])); }
function hasUncertainty(entry) { return entry.reasons.some((reason) => UNCERTAINTY_CODES.includes(reason)); }

export function classifyEntries(entries, policy, { graphUncertainty = [], fanoutPaths = [] } = {}) {
  validatePolicy(policy);
  if (!Array.isArray(entries) || !Array.isArray(graphUncertainty)) fail("entries and graph uncertainty must be arrays");
  const reasonOrder = [...policy.pathRules.map((rule) => rule.id), ...policy.uncertaintyCodes];
  const decorated = entries.map((entry) => ({ ...entry, reasons: [...entry.reasons] }));
  const owners = new Map(); const features = new Set(); const boundaries = new Set(); const fanoutUncertainty = []; let requirements = emptyRequirements();
  const addOwner = (owner, logicalClass, risks, reasons, paths) => {
    const key = `${owner}\0${logicalClass}\0${paths.join("\0")}`; const current = owners.get(key) ?? { owner, logicalClass, risks: [], reasons: [], paths: [] };
    current.risks = declarationSorted([...current.risks, ...risks], policy.riskOrder); current.reasons = declarationSorted([...current.reasons, ...reasons], [...policy.pathRules.map((rule) => rule.id), ...policy.uncertaintyCodes]); current.paths = sortedUnique([...current.paths, ...paths]); owners.set(key, current);
  };
  for (const entry of decorated) {
    const paths = sortedUnique([entry.oldPath, entry.newPath].filter(Boolean)); const matchingPaths = new Map(); const unknownPaths = new Map();
    for (const changedPath of paths) {
      const matches = policy.pathRules.filter((rule) => matchRule(rule, changedPath));
      if (matches.length === 0) unknownPaths.set(changedPath, new Set(["UNMATCHED_PATH"]));
      for (const rule of matches) matchingPaths.set(rule, new Set([...(matchingPaths.get(rule) ?? []), changedPath]));
      if (changedPath.startsWith("apps/mobile/lib/features/") && !policy.featureRoots.some((root) => changedPath.startsWith(`apps/mobile/lib/features/${root}/`))) unknownPaths.set(changedPath, new Set([...(unknownPaths.get(changedPath) ?? []), "UNKNOWN_FEATURE_ROOT"]));
      for (const root of policy.featureRoots) if (changedPath.startsWith(`apps/mobile/lib/features/${root}/`)) features.add(root);
    }
    if (entry.isBinary) entry.reasons.push("BINARY");
    if (entry.status === "UNMERGED_OR_UNKNOWN") entry.reasons.push("UNKNOWN_FILE_TYPE");
    if (entry.oldMode === "120000" || entry.newMode === "120000") entry.reasons.push("SYMLINK");
    if (entry.oldMode === "160000" || entry.newMode === "160000") entry.reasons.push("SUBMODULE");
    for (const [rule, matchedPaths] of matchingPaths) {
      requirements = unionRequirements(requirements, rule.requirements); for (const boundary of rule.boundaries) boundaries.add(boundary);
      entry.reasons.push(...rule.reasons);
      for (const owner of rule.owners) for (const logicalClass of rule.logicalClasses) addOwner(owner, logicalClass, rule.risks, rule.reasons, sortedUnique(matchedPaths));
    }
    if (paths.includes("README.md")) entry.reasons.push("DOCS_POLICY_UNREVIEWED");
    for (const reasons of unknownPaths.values()) entry.reasons.push(...reasons);
    if (entry.reasons.some((reason) => !reasonOrder.includes(reason))) fail("entry reason must be closed");
    entry.reasons = declarationSorted(entry.reasons, reasonOrder);
    if (unknownPaths.size > 0) for (const [unknownPath, reasons] of unknownPaths) { requirements = { ...FULL_REQUIREMENTS }; boundaries.add("UNKNOWN"); addOwner("UNKNOWN", "UNKNOWN", ["FULL_REQUIRED_UNCERTAIN"], declarationSorted(reasons, policy.uncertaintyCodes), [unknownPath]); }
    if (hasUncertainty(entry)) { requirements = { ...FULL_REQUIREMENTS }; boundaries.add("UNKNOWN"); if (unknownPaths.size === 0) addOwner("UNKNOWN", "UNKNOWN", ["FULL_REQUIRED_UNCERTAIN"], entry.reasons.filter((reason) => UNCERTAINTY_CODES.includes(reason)), paths); }
  }
  for (const item of graphUncertainty) {
    const graphPath = normalizePath(item.path, "graph uncertainty path"); if (!policy.uncertaintyCodes.includes(item.code)) fail("unknown graph uncertainty code");
    requirements = { ...FULL_REQUIREMENTS }; boundaries.add("UNKNOWN"); addOwner("UNKNOWN", "UNKNOWN", ["FULL_REQUIRED_UNCERTAIN"], [item.code], [graphPath]);
  }
  for (const item of fanoutPaths) {
    const consumerPath = normalizePath(item, "fan-out consumer path");
    const matches = policy.pathRules.filter((candidate) => matchRule(candidate, consumerPath)); const reasons = [];
    if (matches.length === 0) reasons.push("UNMATCHED_PATH");
    if (consumerPath.startsWith("apps/mobile/lib/features/") && !policy.featureRoots.some((root) => consumerPath.startsWith(`apps/mobile/lib/features/${root}/`))) reasons.push("UNKNOWN_FEATURE_ROOT");
    for (const rule of matches) {
      requirements = unionRequirements(requirements, rule.requirements);
      for (const boundary of rule.boundaries) boundaries.add(boundary);
      for (const owner of rule.owners) for (const logicalClass of rule.logicalClasses) addOwner(owner, logicalClass, rule.risks, rule.reasons, [consumerPath]);
      for (const root of policy.featureRoots) if (consumerPath.startsWith(`apps/mobile/lib/features/${root}/`)) features.add(root);
    }
    if (reasons.length > 0) { const orderedReasons = declarationSorted(reasons, policy.uncertaintyCodes); requirements = { ...FULL_REQUIREMENTS }; boundaries.add("UNKNOWN"); addOwner("UNKNOWN", "UNKNOWN", ["FULL_REQUIRED_UNCERTAIN"], orderedReasons, [consumerPath]); fanoutUncertainty.push(...orderedReasons.map((code) => ({ path: consumerPath, code }))); }
  }
  if (decorated.length === 0) { requirements = { ...FULL_REQUIREMENTS }; boundaries.add("UNKNOWN"); addOwner("UNKNOWN", "UNKNOWN", ["FULL_REQUIRED_UNCERTAIN"], ["EMPTY_DIFF"], []); }
  const uncertaintyCodes = declarationSorted([...decorated.flatMap((entry) => entry.reasons), ...graphUncertainty.map((item) => item.code), ...fanoutUncertainty.map((item) => item.code), ...(decorated.length === 0 ? ["EMPTY_DIFF"] : [])].filter((code) => policy.uncertaintyCodes.includes(code)), policy.uncertaintyCodes);
  const uncertaintyPaths = sortedUnique([...decorated.filter(hasUncertainty).flatMap((entry) => [entry.oldPath, entry.newPath].filter(Boolean)), ...graphUncertainty.map((item) => normalizePath(item.path)), ...fanoutUncertainty.map((item) => item.path)]);
  const uncertainty = { isFullRequired: uncertaintyCodes.length > 0, codes: uncertaintyCodes, paths: uncertaintyPaths };
  if (uncertainty.isFullRequired) requirements = { ...FULL_REQUIREMENTS };
  return { entries: decorated, owners: [...owners.values()].sort((a, b) => cmp(`${a.owner}\0${a.logicalClass}\0${a.paths.join("\0")}`, `${b.owner}\0${b.logicalClass}\0${b.paths.join("\0")}`)), affectedFeatures: sortedUnique(features), affectedBoundaries: declarationSorted(boundaries, BOUNDARIES), requirements, isProvenDocsOnly: false, uncertainty, outcome: uncertainty.isFullRequired ? "FULL_REQUIRED" : "CLASSIFIED" };
}

export function buildResult({ event, comparison, classifier, classification }) {
  assertSha(comparison.baseSha, "baseSha"); assertSha(comparison.headSha, "headSha"); assertSha(comparison.mergeBaseSha, "mergeBaseSha");
  if (comparison.baseSha === comparison.headSha) fail("comparison identity must be distinct");
  for (const key of ["sourceSha256", "policySha256", "workflowSha256"]) if (!/^[0-9a-f]{64}$/u.test(classifier[key])) fail(`invalid classifier digest ${key}`);
  const counts = Object.fromEntries(["changed", "added", "modified", "deleted", "renamed", "copied", "typeChanged", "unknown", "unmatched"].map((key) => [key, 0]));
  counts.changed = classification.entries.length;
  for (const entry of classification.entries) { const key = ({ ADDED: "added", MODIFIED: "modified", DELETED: "deleted", RENAMED: "renamed", COPIED: "copied", TYPE_CHANGED: "typeChanged", UNMERGED_OR_UNKNOWN: "unknown" })[entry.status]; if (key) counts[key] += 1; if (entry.reasons.includes("UNMATCHED_PATH") || entry.reasons.includes("UNKNOWN_FEATURE_ROOT")) counts.unmatched += 1; }
  const result = { schemaVersion: 1, artifactKind: "mobile-changed-path-classification-v1", repository: "AquilaXk/easysubway-mobile", event, comparison: { ...comparison, range: `${comparison.mergeBaseSha}..${comparison.headSha}` }, classifier, changes: classification.entries, owners: classification.owners, affectedFeatures: classification.affectedFeatures, affectedBoundaries: classification.affectedBoundaries, requirements: classification.requirements, isProvenDocsOnly: false, uncertainty: classification.uncertainty, summary: counts, outcome: classification.outcome };
  validateResult(result); return result;
}

export function validateResult(result) {
  keysEqual(result, RESULT_KEYS, "result");
  if (result.schemaVersion !== 1 || result.artifactKind !== "mobile-changed-path-classification-v1" || result.repository !== "AquilaXk/easysubway-mobile") fail("invalid result identity");
  keysEqual(result.event, ["name", "ref", "pullRequestNumber"], "result event");
  validateSafeRef(result.event.ref);
  if (!["pull_request", "push", "workflow_dispatch"].includes(result.event.name) || (result.event.name === "pull_request" ? !(Number.isInteger(result.event.pullRequestNumber) && result.event.pullRequestNumber > 0) : result.event.pullRequestNumber !== null)) fail("invalid result event");
  keysEqual(result.comparison, ["baseSha", "headSha", "mergeBaseSha", "range"], "result comparison");
  for (const key of ["baseSha", "headSha", "mergeBaseSha"]) assertSha(result.comparison[key], key);
  if (result.comparison.baseSha === result.comparison.headSha || result.comparison.range !== `${result.comparison.mergeBaseSha}..${result.comparison.headSha}`) fail("invalid result range");
  keysEqual(result.classifier, ["sourceSha256", "policySha256", "workflowSha256"], "result classifier"); for (const digest of Object.values(result.classifier)) if (typeof digest !== "string" || !/^[0-9a-f]{64}$/u.test(digest)) fail("invalid result classifier digest");
  if (!Array.isArray(result.changes) || !Array.isArray(result.owners) || !Array.isArray(result.affectedFeatures) || !Array.isArray(result.affectedBoundaries)) fail("invalid result arrays");
  for (const change of result.changes) validateChange(change);
  const expectedChanges = [...result.changes].sort((left, right) => compareTuple(changeTuple(left), changeTuple(right)));
  if (result.changes.some((change, index) => !equalTuple(changeTuple(change), changeTuple(expectedChanges[index]))) || result.changes.some((change, index) => index > 0 && equalTuple(changeTuple(change), changeTuple(result.changes[index - 1])))) fail("result changes must be stable sorted and unique");
  for (const owner of result.owners) validateOwner(owner);
  const expectedOwners = [...result.owners].sort((left, right) => cmp(`${left.owner}\0${left.logicalClass}\0${left.paths.join("\0")}`, `${right.owner}\0${right.logicalClass}\0${right.paths.join("\0")}`));
  if (result.owners.some((owner, index) => owner !== expectedOwners[index]) || result.owners.some((owner, index) => index > 0 && owner.owner === result.owners[index - 1].owner && owner.logicalClass === result.owners[index - 1].logicalClass && JSON.stringify(owner.paths) === JSON.stringify(result.owners[index - 1].paths))) fail("result owners must be tuple sorted and unique");
  exactSortedUnique(result.affectedFeatures, FEATURE_ROOTS, "result affected features");
  if (JSON.stringify(result.affectedFeatures) !== JSON.stringify(sortedUnique(result.affectedFeatures))) fail("result affected features must be lexical");
  exactSortedUnique(result.affectedBoundaries, BOUNDARIES, "result affected boundaries");
  validRequirements(result.requirements, "result requirements");
  if (typeof result.isProvenDocsOnly !== "boolean" || result.isProvenDocsOnly) fail("docs-only result is not admitted");
  keysEqual(result.uncertainty, ["isFullRequired", "codes", "paths"], "result uncertainty");
  if (typeof result.uncertainty.isFullRequired !== "boolean") fail("invalid result uncertainty");
  exactSortedUnique(result.uncertainty.codes, UNCERTAINTY_CODES, "result uncertainty codes");
  exactLexicalPaths(result.uncertainty.paths, "result uncertainty paths");
  if (!result.uncertainty.isFullRequired && (result.uncertainty.codes.length !== 0 || result.uncertainty.paths.length !== 0)) fail("classified result cannot contain uncertainty");
  if (result.uncertainty.isFullRequired && (result.uncertainty.codes.length === 0 || (result.uncertainty.paths.length === 0 && !result.uncertainty.codes.includes("EMPTY_DIFF")))) fail("full result requires uncertainty evidence");
  const expectedCounts = { changed: result.changes.length, added: 0, modified: 0, deleted: 0, renamed: 0, copied: 0, typeChanged: 0, unknown: 0, unmatched: 0 }; for (const change of result.changes) { const key = ({ ADDED: "added", MODIFIED: "modified", DELETED: "deleted", RENAMED: "renamed", COPIED: "copied", TYPE_CHANGED: "typeChanged", UNMERGED_OR_UNKNOWN: "unknown" })[change.status]; expectedCounts[key] += 1; if (change.reasons.includes("UNMATCHED_PATH") || change.reasons.includes("UNKNOWN_FEATURE_ROOT")) expectedCounts.unmatched += 1; }
  keysEqual(result.summary, Object.keys(expectedCounts), "result summary"); if (JSON.stringify(result.summary) !== JSON.stringify(expectedCounts)) fail("result summary mismatch");
  if ((result.outcome === "FULL_REQUIRED") !== result.uncertainty.isFullRequired || !["CLASSIFIED", "FULL_REQUIRED"].includes(result.outcome)) fail("result outcome/uncertainty mismatch"); if (result.outcome === "FULL_REQUIRED" && JSON.stringify(result.requirements) !== JSON.stringify(FULL_REQUIREMENTS)) fail("full result must require every gate");
  return result;
}

export function summaryMarkdown(result) {
  return `# Changed Path Classification\n\nOutcome: ${result.outcome}\nChanged: ${result.summary.changed}\nAdded: ${result.summary.added}\nModified: ${result.summary.modified}\nDeleted: ${result.summary.deleted}\nRenamed: ${result.summary.renamed}\nCopied: ${result.summary.copied}\nType changed: ${result.summary.typeChanged}\nUnknown: ${result.summary.unknown}\nUnmatched: ${result.summary.unmatched}\n`;
}

export function validateArtifact(directory, headSha) {
  assertSha(headSha, "artifact head SHA"); const root = realpathSync(directory); const entries = readdirSync(root).sort(cmp);
  if (JSON.stringify(entries) !== JSON.stringify([...ARTIFACT_FILES].sort(cmp))) fail("artifact must contain exactly the three declared files");
  for (const name of ARTIFACT_FILES) { const entry = lstatSync(path.join(root, name)); if (!entry.isFile() || entry.isSymbolicLink()) fail("artifact file must be a regular non-symlink"); }
  const json = readFileSync(path.join(root, ARTIFACT_FILES[0])); const digest = sha256(json); const detached = readFileSync(path.join(root, ARTIFACT_FILES[2]), "utf8");
  if (detached !== `${digest}  ${ARTIFACT_FILES[0]}\n`) fail("artifact detached digest mismatch");
  const text = decodeUtf8(json, "artifact JSON"); let value;
  try { value = JSON.parse(text); } catch { fail("artifact JSON must parse"); }
  if (JSON.stringify(value) !== text) fail("artifact JSON must be canonical bytes");
  validateResult(value); if (value.comparison.headSha !== headSha) fail("artifact head SHA mismatch");
  if (readFileSync(path.join(root, ARTIFACT_FILES[1]), "utf8") !== summaryMarkdown(value)) fail("artifact summary mismatch");
  return { classificationSha256: digest, artifactName: `mobile-changed-path-classification-${headSha}`, result: value };
}

function git(repository, args, input) { return execFileSync("git", ["-C", repository, "-c", "core.quotepath=false", "-c", "diff.renameLimit=10000", "-c", "diff.algorithm=myers", ...args], { encoding: "buffer", input, stdio: ["ignore", "pipe", "pipe"] }); }
function gitText(repository, args) { return decodeUtf8(git(repository, args), "Git text").trim(); }
function isAncestor(repository, base, head) { try { git(repository, ["merge-base", "--is-ancestor", base, head]); return true; } catch { return false; } }
function validateWorkspace(value, label) { if (typeof value !== "string" || !path.isAbsolute(value)) fail(`${label} must be an absolute path`); const info = lstatSync(value); if (!info.isDirectory() || info.isSymbolicLink()) fail(`${label} must be a regular directory`); return realpathSync(value); }
function gitBlob(repository, revision, repositoryPath) { return git(repository, ["show", `${revision}:${normalizePath(repositoryPath)}`]); }
function immutableDartTree(repository, revision) {
  const pubspec = decodeUtf8(gitBlob(repository, revision, "apps/mobile/pubspec.yaml"), "pubspec");
  if (!/^name:\s*easysubway_mobile\s*$/mu.test(pubspec)) fail("mobile package identity mismatch");
  const listing = git(repository, ["ls-tree", "-r", "-z", "--full-tree", revision, "--", "apps/mobile/lib", "apps/mobile/test", "apps/mobile/integration_test", "apps/mobile/test_driver"]);
  const files = {};
  for (const record of decodeUtf8(listing, "tree").split("\0").filter(Boolean)) {
    const match = /^([0-7]{6}) blob [0-9a-f]{40}\t(.+)$/u.exec(record);
    if (!match) fail("immutable Dart tree contains non-blob entry");
    if (match[1] === "120000") fail("immutable Dart tree contains symlink");
    if (match[2].endsWith(".dart")) files[normalizePath(match[2])] = decodeUtf8(gitBlob(repository, revision, match[2]), "Dart blob");
  }
  return buildImmutableDartGraph({ files });
}
function dartTokens(source) {
  if (typeof source !== "string") return { tokens: [], malformed: true };
  const tokens = []; let index = 0; let malformed = false;
  const identifierStart = (value) => /[A-Za-z_$]/u.test(value);
  const identifierPart = (value) => /[A-Za-z0-9_$]/u.test(value);
  const pushString = (raw, quote, start) => {
    const triple = source.slice(index, index + 3) === quote.repeat(3); const delimiter = triple ? quote.repeat(3) : quote;
    index += delimiter.length; let value = ""; let literal = true; let closed = false;
    while (index < source.length) {
      if (source.startsWith(delimiter, index)) { index += delimiter.length; closed = true; break; }
      const character = source[index++];
      if (!raw && character === "\\") {
        literal = false;
        if (index >= source.length) break;
        value += character + source[index++];
      } else {
        if (!raw && character === "$") literal = false;
        value += character;
      }
    }
    if (!closed) malformed = true;
    tokens.push({ type: "string", value, literal: literal && value.length > 0, start });
  };
  while (index < source.length) {
    const character = source[index];
    if (/\s/u.test(character)) { index += 1; continue; }
    if (source.startsWith("//", index)) { const newline = source.indexOf("\n", index + 2); index = newline === -1 ? source.length : newline + 1; continue; }
    if (source.startsWith("/*", index)) {
      index += 2; let depth = 1;
      while (index < source.length && depth > 0) {
        if (source.startsWith("/*", index)) { depth += 1; index += 2; }
        else if (source.startsWith("*/", index)) { depth -= 1; index += 2; }
        else index += 1;
      }
      if (depth !== 0) malformed = true;
      continue;
    }
    const raw = (character === "r" || character === "R") && (source[index + 1] === "'" || source[index + 1] === '"');
    if (raw || character === "'" || character === '"') {
      const start = index; const quote = raw ? source[index + 1] : character; if (raw) index += 1;
      pushString(raw, quote, start); continue;
    }
    if (identifierStart(character)) {
      const start = index; index += 1; while (index < source.length && identifierPart(source[index])) index += 1;
      tokens.push({ type: "identifier", value: source.slice(start, index), start }); continue;
    }
    tokens.push({ type: "symbol", value: character, start: index }); index += 1;
  }
  return { tokens, malformed };
}

function directiveEnd(tokens, start) {
  for (let index = start; index < tokens.length; index += 1) if (tokens[index].value === ";") return index;
  return -1;
}

function parseUriDirective(body) {
  if (body.length === 0 || body[0].type !== "string" || !body[0].literal) return { uncertain: true, directives: [] };
  const directives = [{ kind: "edge", uri: body[0].value }]; let index = 1;
  while (index < body.length) {
    const token = body[index];
    if (token.type !== "identifier") return { uncertain: true, directives };
    if (token.value === "if") {
      if (body[index + 1]?.value !== "(") return { uncertain: true, directives };
      let depth = 1; index += 2;
      let hasConditionToken = false;
      while (index < body.length && depth > 0) {
        if (body[index].value === "(") depth += 1;
        else if (body[index].value === ")") depth -= 1;
        else if (depth > 0) hasConditionToken = true;
        index += 1;
      }
      if (depth !== 0 || !hasConditionToken || body[index]?.type !== "string" || !body[index].literal) return { uncertain: true, directives };
      directives.push({ kind: "edge", uri: body[index].value }); index += 1; continue;
    }
    if (token.value === "deferred") { index += 1; continue; }
    if (token.value === "as") { if (body[index + 1]?.type !== "identifier") return { uncertain: true, directives }; index += 2; continue; }
    if (token.value === "show" || token.value === "hide") {
      index += 1; let expectIdentifier = true;
      while (index < body.length && (body[index].type === "identifier" || body[index].value === ",")) {
        if (expectIdentifier !== (body[index].type === "identifier")) return { uncertain: true, directives };
        expectIdentifier = !expectIdentifier; index += 1;
      }
      if (expectIdentifier) return { uncertain: true, directives };
      continue;
    }
    return { uncertain: true, directives };
  }
  return { uncertain: false, directives };
}

function parsePartDirective(body) {
  if (body.length === 0) return { uncertain: true, directives: [] };
  if (body[0].type === "identifier" && body[0].value === "of") {
    const remainder = body.slice(1);
    if (remainder.length === 1 && remainder[0].type === "string" && remainder[0].literal) return { uncertain: false, directives: [{ kind: "edge", uri: remainder[0].value }] };
    const validName = remainder.length > 0 && remainder[0].type === "identifier" && remainder.every((token, index) => index % 2 === 0 ? token.type === "identifier" : token.value === ".");
    return validName ? { uncertain: false, directives: [{ kind: "named-part" }] } : { uncertain: true, directives: [] };
  }
  return body.length === 1 && body[0].type === "string" && body[0].literal ? { uncertain: false, directives: [{ kind: "part", uri: body[0].value }] } : { uncertain: true, directives: [] };
}

function parseDartDirectives(source) {
  const { tokens, malformed } = dartTokens(source); const directives = []; let uncertain = malformed; let braceDepth = 0;
  for (let index = 0; index < tokens.length; index += 1) {
    const token = tokens[index];
    if (token.value === "{") { braceDepth += 1; continue; }
    if (token.value === "}") { braceDepth = Math.max(0, braceDepth - 1); continue; }
    if (braceDepth !== 0 || token.type !== "identifier" || !["import", "export", "part"].includes(token.value)) continue;
    const end = directiveEnd(tokens, index + 1);
    if (end === -1) { uncertain = true; break; }
    const parsed = token.value === "part" ? parsePartDirective(tokens.slice(index + 1, end)) : parseUriDirective(tokens.slice(index + 1, end));
    directives.push(...parsed.directives); uncertain ||= parsed.uncertain; index = end;
  }
  return { directives, uncertain };
}

function resolveDartUri(uri, from, files, packageName) {
  if (typeof uri !== "string" || uri.length === 0 || /[\\\u0000-\u001f\u007f?#]/u.test(uri)) return { uncertain: true };
  if (uri.startsWith("dart:")) return { external: true };
  let target;
  if (uri.startsWith("package:")) {
    const prefix = `package:${packageName}/`;
    if (uri === `package:${packageName}` || uri.startsWith(`package:${packageName}?`) || uri.startsWith(`package:${packageName}#`)) return { uncertain: true };
    if (!uri.startsWith(prefix)) return { external: true };
    const suffix = uri.slice(prefix.length); if (suffix.length === 0) return { uncertain: true };
    target = `apps/mobile/lib/${suffix}`;
  } else {
    if (uri.startsWith("/") || uri.includes(":")) return { uncertain: true };
    target = path.posix.normalize(path.posix.join(path.posix.dirname(from), uri));
  }
  if (!target.startsWith("apps/mobile/") || !Object.hasOwn(files, target)) return { uncertain: true };
  return { target };
}

export function buildImmutableDartGraph({ files, packageName = "easysubway_mobile" }) {
  if (packageName !== "easysubway_mobile") fail("mobile package identity mismatch");
  const normalizedFiles = {};
  for (const [file, source] of Object.entries(files)) {
    const normalized = normalizePath(file);
    if (Object.hasOwn(normalizedFiles, normalized)) fail("duplicate normalized immutable Dart graph key");
    normalizedFiles[normalized] = source;
  }
  const graph = new Map(); const uncertainPaths = new Set(); const namedParts = new Set(); const backlinks = new Map();
  for (const [file, source] of Object.entries(normalizedFiles)) {
    graph.set(file, new Set()); const parsed = parseDartDirectives(source); if (parsed.uncertain) uncertainPaths.add(file);
    for (const directive of parsed.directives) {
      if (directive.kind === "named-part") { namedParts.add(file); continue; }
      const resolved = resolveDartUri(directive.uri, file, normalizedFiles, packageName);
      if (resolved.uncertain) { uncertainPaths.add(file); continue; }
      if (resolved.external) continue;
      graph.get(file).add(resolved.target);
      if (directive.kind === "part") backlinks.set(resolved.target, new Set([...(backlinks.get(resolved.target) ?? []), file]));
    }
  }
  for (const partFile of namedParts) {
    const libraries = backlinks.get(partFile) ?? new Set();
    if (libraries.size !== 1) uncertainPaths.add(partFile); else graph.get(partFile).add([...libraries][0]);
  }
  const stableGraph = new Map([...graph.entries()].map(([file, targets]) => [file, sortedUnique(targets)])); const reverse = new Map();
  for (const [from, targets] of stableGraph) for (const target of targets) reverse.set(target, sortedUnique([...(reverse.get(target) ?? []), from]));
  return { graph: stableGraph, reverse, uncertainty: sortedUnique(uncertainPaths).map((path) => ({ path, code: "GRAPH_UNCERTAINTY" })) };
}
export function reverseConsumerFanout(graph, changedPaths) {
  const queue = changedPaths.map((value) => normalizePath(value, "changed graph path")); const seen = new Set(queue); const consumers = new Set();
  while (queue.length > 0) for (const consumer of graph.reverse.get(queue.shift()) ?? []) if (!seen.has(consumer)) { seen.add(consumer); consumers.add(consumer); queue.push(consumer); }
  return sortedUnique(consumers);
}
function writeArtifact(directory, result) {
  validateResult(result);
  mkdirSync(directory, { recursive: true }); const json = Buffer.from(JSON.stringify(result)); const digest = sha256(json);
  writeFileSync(path.join(directory, ARTIFACT_FILES[0]), json); writeFileSync(path.join(directory, ARTIFACT_FILES[1]), summaryMarkdown(result)); writeFileSync(path.join(directory, ARTIFACT_FILES[2]), `${digest}  ${ARTIFACT_FILES[0]}\n`); return digest;
}
function appendOutputs(result, digest) {
  const destination = process.env.GITHUB_OUTPUT; if (!destination) return;
  const values = { "artifact-name": `mobile-changed-path-classification-${result.comparison.headSha}`, "classification-sha256": digest, "head-sha": result.comparison.headSha, outcome: result.outcome, ...Object.fromEntries(REQUIREMENT_KEYS.map((key) => [key.replace(/[A-Z]/gu, (letter) => `-${letter.toLowerCase()}`), String(result.requirements[key])])), "is-proven-docs-only": String(result.isProvenDocsOnly) };
  writeFileSync(destination, OUTPUT_KEYS.map((key) => `${key}=${values[key]}\n`).join(""), { flag: "a" });
}
export function runClassifier(options, environment = process.env) {
  const repository = validateWorkspace(environment.GITHUB_WORKSPACE, "GITHUB_WORKSPACE"); const temp = validateWorkspace(environment.RUNNER_TEMP, "RUNNER_TEMP");
  if (options.event === "pull_request") { git(repository, ["fetch", "--no-tags", "origin", `refs/pull/${options.pullRequestNumber}/head`]); if (gitText(repository, ["rev-parse", "FETCH_HEAD"]) !== options.headSha) fail("fetched pull request head does not equal event head"); }
  for (const revision of [options.baseSha, options.headSha]) git(repository, ["cat-file", "-e", `${revision}^{commit}`]);
  let mergeBase = options.baseSha;
  if (options.event === "pull_request") { mergeBase = gitText(repository, ["merge-base", options.baseSha, options.headSha]); assertSha(mergeBase, "merge base"); if (!isAncestor(repository, mergeBase, options.baseSha) || !isAncestor(repository, mergeBase, options.headSha)) fail("merge base must be ancestor of both"); } else if (!isAncestor(repository, options.baseSha, options.headSha)) fail("base must be ancestor of head");
  const source = gitBlob(repository, options.baseSha, "tools/ci/mobile-changed-path-classifier.mjs"); const policyBytes = gitBlob(repository, options.baseSha, "tools/ci/mobile-changed-path-policy.json");
  const executingSource = readFileSync(fileURLToPath(import.meta.url)); const workspacePolicy = readFileSync(path.join(repository, "tools/ci/mobile-changed-path-policy.json"));
  if (sha256(executingSource) !== sha256(source) || !executingSource.equals(source)) fail("executing module bytes do not equal trusted base blob");
  if (sha256(workspacePolicy) !== sha256(policyBytes) || !workspacePolicy.equals(policyBytes)) fail("workspace policy bytes do not equal trusted base blob");
  let policy;
  try { policy = validatePolicy(JSON.parse(decodeUtf8(workspacePolicy, "workspace policy"))); } catch (error) { if (error instanceof ClassifierError) throw error; fail("invalid workspace policy"); }
  const stable = ["diff", "--no-ext-diff", "--no-textconv", "--ignore-submodules=none"]; const raw = git(repository, [...stable, "--raw", "-z", "--abbrev=40", "--find-renames=90%", "--find-copies=90%", "--find-copies-harder", mergeBase, options.headSha, "--"]); const numstat = git(repository, [...stable, "--numstat", "-z", "--find-renames=90%", "--find-copies=90%", "--find-copies-harder", mergeBase, options.headSha, "--"]);
  const baseGraph = immutableDartTree(repository, mergeBase); const headGraph = immutableDartTree(repository, options.headSha); const graphUncertainty = [...baseGraph.uncertainty, ...headGraph.uncertainty]; const changes = joinDiffStreams(parseRawDiff(raw), parseNumstat(numstat)); const fanoutPaths = sortedUnique([...reverseConsumerFanout(baseGraph, changes.map((entry) => entry.oldPath).filter(Boolean)), ...reverseConsumerFanout(headGraph, changes.map((entry) => entry.newPath).filter(Boolean))]); const classification = classifyEntries(changes, policy, { graphUncertainty, fanoutPaths }); let workflow;
  try { workflow = gitBlob(repository, options.headSha, ".github/workflows/mobile-changed-path-classifier.yml"); } catch { fail("required head workflow blob is unavailable"); }
  const result = buildResult({ event: { name: options.event, ref: options.eventRef, pullRequestNumber: options.pullRequestNumber }, comparison: { baseSha: options.baseSha, headSha: options.headSha, mergeBaseSha: mergeBase }, classifier: { sourceSha256: sha256(source), policySha256: sha256(policyBytes), workflowSha256: sha256(workflow) }, classification }); const output = path.join(temp, "mobile-changed-path-classification"); const digest = writeArtifact(output, result); validateArtifact(output, options.headSha); appendOutputs(result, digest); return { result, output, digest };
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  try { runClassifier(parseCliArguments(process.argv.slice(2))); } catch (error) { process.stderr.write(`${error.message}\n`); process.exitCode = error.exitCode ?? 1; }
}
