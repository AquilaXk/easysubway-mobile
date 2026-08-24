#!/usr/bin/env node
import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import {
  existsSync,
  lstatSync,
  mkdirSync,
  readFileSync,
  readdirSync,
  renameSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { request } from "node:https";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { buildImmutableDartSourceGraph } from "./lib/mobile-dart-source-graph.mjs";

const SHA = /^[0-9a-f]{40}$/u;
const DIGEST = /^[0-9a-f]{64}$/u;
const SAFE_TEXT = /^[^\u0000-\u001f\u007f]+$/u;
const POLICY_SHA256 = "9f6b1d38bde18b5d513a8f30d40d8eba5735284211307196bedf8bb753094523";
const BASELINE_SHA256 = "d1ba53818f9891c035accecacc4e31bd14ed7f4f8fa6f6f5aae038f5cf6a5bbe";
const PHASE = "NO_INCREASE";
const REPOSITORY = "AquilaXk/easysubway-mobile";
const POLICY_KEYS = ["schemaVersion", "artifactKind", "repository", "phase", "featureRoots", "rootClassifications", "importerRules", "forbiddenMatrix", "owners", "artifactContract"];
const BASELINE_KEYS = ["schemaVersion", "artifactKind", "repository", "phase", "reviewedHeadSha", "edges"];
const EDGE_KEYS = ["source", "target", "kind", "uri", "uriKind", "conditional"];
const DEBT_EDGE_KEYS = ["source", "target", "kind", "uri", "uriKind", "targetClassification", "ownerIssue", "removalTrigger"];
const CURRENT_DEBT_EDGE_KEYS = ["source", "target", "kind", "uri", "uriKind", "conditional", "targetClassification", "ownerIssue", "removalTrigger"];
const REASONS = ["NEW_FORBIDDEN_EDGE", "UNREVIEWED_ROOT_TARGET", "FORBIDDEN_WRAPPER_OR_BARREL", "OWNER_ISSUE_NOT_OPEN", "BASELINE_IDENTITY_MISMATCH", "GRAPH_UNCERTAINTY", "EVENT_IDENTITY_MISMATCH", "ARTIFACT_MISMATCH"];
const ARTIFACT_FILES = ["mobile-root-import-inventory.json", "mobile-root-import-result.json", "mobile-root-import-summary.md", "mobile-root-import.sha256"];
const INVENTORY_KEYS = ["schemaVersion", "artifactKind", "repository", "phase", "comparison", "producer", "ownerIssues", "rootTargets", "importers", "edges", "forbiddenEdges", "wrapperFindings", "uncertainty", "summary"];
const RESULT_KEYS = ["schemaVersion", "artifactKind", "repository", "phase", "comparison", "producer", "inventorySha256", "baselineSha256", "currentEdges", "newEdges", "removedEdges", "ownerStatus", "reasons", "outcome"];
const COMPARISON_KEYS = ["event", "eventMode", "eventRef", "pullRequestNumber", "baseSha", "pullRequestHeadSha", "headSha", "testedMergeSha", "mergeBaseSha", "range"];
const PRODUCER_KEYS = ["runnerSha256", "helperSha256", "policySha256", "baselineSha256", "sourceTreeSha256"];
const ROOT_ENTRY_KEYS = ["path", "classification", "ownerIssue", "removalTrigger"];
const OWNER_KEYS = ["number", "title", "url", "requiredState", "removalTrigger"];
const OWNER_STATUS_KEYS = ["number", "title", "url", "state"];
const ROOT_CLASSES = ["APPROVED_APP_ENTRYPOINT_OR_COMPOSITION", "APPROVED_NEUTRAL_FOUNDATION", "TEMPORARY_ROOT_IMPLEMENTATION_TO_MOVE", "LEGACY_ROUTE_DELETE", "GENERATED_OR_PLATFORM_OWNER", "TEST_OR_FIXTURE_ONLY", "FORBIDDEN_OR_UNKNOWN"];
const IMPORTER_CLASSES = ["FEATURE_PRODUCTION", "APP_COMPOSITION", "SHARED_NEUTRAL", "ROOT_PRODUCTION", "TEST_OR_FIXTURE", "GENERATED"];
const URI_KINDS = ["RELATIVE", "OWN_PACKAGE", "DART_EXTERNAL", "OTHER_PACKAGE_EXTERNAL", "NAMED_PART"];
const FEATURE_ROOTS = ["account", "ads", "attribution", "fare", "facility_report", "favorites", "get_off_alarm", "home", "home_widget", "internal_route", "journey", "mobility_profile", "network_map", "notifications", "preferences", "realtime", "route_draft", "routes", "search_history", "service_notice", "settings", "stations", "support", "train_search"];
const POLICY_URL = new URL("./mobile-root-import-policy.json", import.meta.url);
const BASELINE_URL = new URL("./mobile-root-import-baseline.json", import.meta.url);
const HELPER_URL = new URL("./lib/mobile-dart-source-graph.mjs", import.meta.url);

const fail = (message, exitCode = 1) => {
  const error = new Error(message);
  error.exitCode = exitCode;
  throw error;
};
const compare = (left, right) => left < right ? -1 : left > right ? 1 : 0;
const hash = (value) => createHash("sha256").update(value).digest("hex");
const exactKeys = (value, keys, name) => {
  if (!value || typeof value !== "object" || Array.isArray(value) || JSON.stringify(Object.keys(value)) !== JSON.stringify(keys)) {
    fail(`${name} keys must be exact and ordered`);
  }
};
const utf8 = (bytes, name, { allowNul = false } = {}) => {
  try {
    const text = new TextDecoder("utf-8", { fatal: true, ignoreBOM: true }).decode(bytes);
    if (text.startsWith("\ufeff") || (!allowNul && text.includes("\0"))) fail(`${name} has forbidden bytes`);
    return text;
  } catch (error) {
    if (error?.exitCode) throw error;
    fail(`${name} must be UTF-8`);
  }
};
const canonicalBytes = (value) => Buffer.from(`${JSON.stringify(value)}\n`);
const canonical = (bytes, name) => {
  const text = utf8(Buffer.from(bytes), name);
  let value;
  try {
    value = JSON.parse(text);
  } catch {
    fail(`${name} must be JSON`);
  }
  if (!canonicalBytes(value).equals(Buffer.from(bytes))) fail(`${name} must be canonical JSON.stringify bytes`);
  return value;
};
const stableUnique = (values, name) => {
  if (!Array.isArray(values) || values.some((value) => typeof value !== "string" || !SAFE_TEXT.test(value))) fail(`${name} must be text values`);
  if (JSON.stringify(values) !== JSON.stringify([...new Set(values)].sort(compare))) fail(`${name} must be sorted and unique`);
  return values;
};
const debtKey = (edge) => CURRENT_DEBT_EDGE_KEYS.map((key) => key === "conditional" ? String(edge.conditional ?? false) : (edge[key] ?? "")).join("\0");
const graphEdgeKey = (edge) => EDGE_KEYS.map((key) => String(edge[key] ?? "")).join("\0");
const wrapperKey = (finding) => `${finding.source}\0${finding.path.join("\0")}\0${finding.target}\0${finding.targetClassification}`;
const wrapperIdentityKey = (finding) => `${finding.source}\0${finding.target}\0${finding.targetClassification}`;

export function strictExternalJson(bytes, name) {
  const text = utf8(Buffer.from(bytes), name);
  const stack = [];
  for (let index = 0; index < text.length; index += 1) {
    if (text[index] === '"') {
      const start = index;
      for (index += 1; index < text.length; index += 1) {
        if (text[index] === "\\") index += 1;
        else if (text[index] === '"') break;
      }
      if (index >= text.length) fail(`${name} has an unterminated string`);
      let key;
      try {
        key = JSON.parse(text.slice(start, index + 1));
      } catch {
        fail(`${name} has an invalid string`);
      }
      let after = index + 1;
      while (/\s/u.test(text[after] ?? "")) after += 1;
      if (text[after] === ":") {
        const keys = stack.at(-1);
        if (!keys || keys.has(key)) fail(`${name} has a duplicate key`);
        keys.add(key);
      }
      continue;
    }
    if (text[index] === "{") stack.push(new Set());
    else if (text[index] === "}") {
      if (!stack.length) fail(`${name} is malformed`);
      stack.pop();
    }
  }
  if (stack.length) fail(`${name} is malformed`);
  try {
    return JSON.parse(text);
  } catch {
    fail(`${name} must be JSON`);
  }
}

function validateDartPath(value, name = "Dart path") {
  if (typeof value !== "string" || !value.endsWith(".dart") || value.startsWith("/") || value.includes("\\") || /[\u0000-\u001f\u007f]/u.test(value)) fail(`${name} is invalid`);
  const pieces = value.split("/");
  if (pieces.some((piece) => piece === "" || piece === "." || piece === "..")) fail(`${name} is ambiguous`);
  return value;
}

export function validatePolicy(value) {
  exactKeys(value, POLICY_KEYS, "policy");
  if (value.schemaVersion !== 1 || value.artifactKind !== "mobile-root-import-policy-v1" || value.repository !== REPOSITORY || value.phase !== PHASE) fail("policy identity is invalid");
  if (JSON.stringify(value.featureRoots) !== JSON.stringify(FEATURE_ROOTS)) fail("policy feature roots changed");
  if (!Array.isArray(value.rootClassifications) || value.rootClassifications.length !== 21) fail("policy root classification count changed");
  let previous = "";
  for (const entry of value.rootClassifications) {
    exactKeys(entry, ROOT_ENTRY_KEYS, "root classification");
    validateDartPath(entry.path, "root classification path");
    if (!/^apps\/mobile\/lib\/[^/]+\.dart$/u.test(entry.path) || entry.path <= previous || !ROOT_CLASSES.includes(entry.classification)) fail("root classifications must be exact and ordered");
    previous = entry.path;
    const approved = ["APPROVED_APP_ENTRYPOINT_OR_COMPOSITION", "APPROVED_NEUTRAL_FOUNDATION"].includes(entry.classification);
    if (approved ? entry.ownerIssue !== null || entry.removalTrigger !== null : !Number.isInteger(entry.ownerIssue) || typeof entry.removalTrigger !== "string") fail("root classification ownership is invalid");
  }
  exactKeys(value.importerRules, ["appExactPaths", "appPrefixes", "sharedExactPaths", "sharedPrefixes", "testPrefixes", "generatedPrefixes", "generatedSuffixes", "generatedHeaders"], "importer rules");
  for (const [key, values] of Object.entries(value.importerRules)) stableUnique(values, `importerRules.${key}`);
  if (JSON.stringify(value.importerRules.appExactPaths) !== JSON.stringify(["apps/mobile/lib/legacy_credential_cleanup.dart", "apps/mobile/lib/main.dart"]) || JSON.stringify(value.importerRules.appPrefixes) !== JSON.stringify(["apps/mobile/lib/app/"]) || JSON.stringify(value.importerRules.sharedPrefixes) !== JSON.stringify(["apps/mobile/lib/core/"]) || JSON.stringify(value.importerRules.testPrefixes) !== JSON.stringify(["apps/mobile/integration_test/", "apps/mobile/test/", "apps/mobile/test_driver/"]) || JSON.stringify(value.importerRules.generatedPrefixes) !== JSON.stringify(["apps/mobile/lib/generated/"]) || JSON.stringify(value.importerRules.generatedSuffixes) !== JSON.stringify([".freezed.dart", ".g.dart"]) || JSON.stringify(value.importerRules.generatedHeaders) !== JSON.stringify(["// GENERATED CODE - DO NOT MODIFY BY HAND"])) fail("importer rules changed");
  exactKeys(value.forbiddenMatrix, ["featureAllowedTargets", "neutralAllowedTargets"], "forbidden matrix");
  if (JSON.stringify(value.forbiddenMatrix) !== JSON.stringify({ featureAllowedTargets: ["APPROVED_NEUTRAL_FOUNDATION", "GENERATED_OR_PLATFORM_OWNER"], neutralAllowedTargets: ["APPROVED_NEUTRAL_FOUNDATION", "GENERATED_OR_PLATFORM_OWNER"] })) fail("forbidden matrix changed");
  if (!Array.isArray(value.owners) || value.owners.length !== 4) fail("policy owner count changed");
  for (const [index, owner] of value.owners.entries()) {
    exactKeys(owner, OWNER_KEYS, "policy owner");
    if (owner.number !== [18, 19, 20, 22][index] || owner.url !== `https://github.com/AquilaXk/easysubway-mobile/issues/${owner.number}` || owner.requiredState !== "OPEN" || typeof owner.title !== "string" || !owner.title || typeof owner.removalTrigger !== "string") fail("policy owner identity changed");
  }
  exactKeys(value.artifactContract, ["directory", "files", "nameTemplate"], "artifact contract");
  if (value.artifactContract.directory !== "mobile-root-import-ratchet" || JSON.stringify(value.artifactContract.files) !== JSON.stringify(ARTIFACT_FILES) || value.artifactContract.nameTemplate !== "mobile-root-import-ratchet-${headSha}") fail("artifact contract changed");
  const ownerMap = new Map(value.owners.map((owner) => [owner.number, owner]));
  for (const root of value.rootClassifications.filter((entry) => entry.ownerIssue !== null)) {
    const owner = ownerMap.get(root.ownerIssue);
    if (!owner || owner.removalTrigger !== root.removalTrigger) fail("root owner projection changed");
  }
  return value;
}

export function parsePolicyBytes(bytes) {
  if (hash(bytes) !== POLICY_SHA256) fail("policy bytes do not match the reviewed pin");
  return validatePolicy(canonical(bytes, "root import policy"));
}

export function validateBaseline(value, policy) {
  exactKeys(value, BASELINE_KEYS, "baseline");
  if (value.schemaVersion !== 1 || value.artifactKind !== "mobile-root-import-baseline-v1" || value.repository !== REPOSITORY || value.phase !== PHASE || value.reviewedHeadSha !== "fc89812dea8bc8d5072468323221fbca7adb21ee" || !Array.isArray(value.edges) || value.edges.length !== 22) fail("baseline identity or count changed");
  const rootMap = new Map(policy.rootClassifications.map((entry) => [entry.path, entry]));
  let previous = "";
  const seen = new Set();
  const ownerCounts = new Map();
  for (const edge of value.edges) {
    exactKeys(edge, DEBT_EDGE_KEYS, "baseline edge");
    validateDartPath(edge.source, "baseline source");
    validateDartPath(edge.target, "baseline target");
    const key = debtKey(edge);
    const root = rootMap.get(edge.target);
    if (key <= previous || seen.has(key) || !edge.source.startsWith("apps/mobile/lib/features/") || edge.kind !== "IMPORT" || edge.uriKind !== "RELATIVE" || !root || edge.targetClassification !== root.classification || edge.ownerIssue !== root.ownerIssue || edge.removalTrigger !== root.removalTrigger) fail("baseline edge identity changed");
    previous = key;
    seen.add(key);
    ownerCounts.set(edge.ownerIssue, (ownerCounts.get(edge.ownerIssue) ?? 0) + 1);
  }
  if (JSON.stringify([...ownerCounts.entries()].sort(([left], [right]) => left - right)) !== JSON.stringify([[22, 22]])) fail("baseline owner partition changed");
  return value;
}

export function parseBaselineBytes(bytes, policy) {
  if (hash(bytes) !== BASELINE_SHA256) fail("baseline bytes do not match the reviewed pin");
  return validateBaseline(canonical(bytes, "root import baseline"), policy);
}

function generatedSource(file, source, policy) {
  const reviewedLocation = policy.importerRules.generatedPrefixes.some((prefix) => file.startsWith(prefix)) || policy.importerRules.generatedSuffixes.some((suffix) => file.endsWith(suffix));
  return reviewedLocation && policy.importerRules.generatedHeaders.some((header) => source.startsWith(`${header}\n`) || source === header);
}

function importerClass(file, source, policy) {
  if (generatedSource(file, source, policy)) return "GENERATED";
  if (policy.importerRules.testPrefixes.some((prefix) => file.startsWith(prefix))) return "TEST_OR_FIXTURE";
  const featureMatch = /^apps\/mobile\/lib\/features\/([^/]+)\//u.exec(file);
  if (featureMatch && policy.featureRoots.includes(featureMatch[1])) return "FEATURE_PRODUCTION";
  if (policy.importerRules.appExactPaths.includes(file) || policy.importerRules.appPrefixes.some((prefix) => file.startsWith(prefix))) return "APP_COMPOSITION";
  if (policy.importerRules.sharedExactPaths.includes(file) || policy.importerRules.sharedPrefixes.some((prefix) => file.startsWith(prefix))) return "SHARED_NEUTRAL";
  if (/^apps\/mobile\/lib\/[^/]+\.dart$/u.test(file)) return "ROOT_PRODUCTION";
  return null;
}

function rootClass(file, source, policy) {
  const reviewed = policy.rootClassifications.find((entry) => entry.path === file);
  if (reviewed) return reviewed;
  return { path: file, classification: "FORBIDDEN_OR_UNKNOWN", ownerIssue: null, removalTrigger: null };
}

function rootPath(file) {
  return /^apps\/mobile\/lib\/[^/]+\.dart$/u.test(file);
}

function findWrapperFindings(graph, importerByPath, rootByPath, policy) {
  const findings = [];
  const origins = [...importerByPath.entries()].filter(([, importer]) => importer === "FEATURE_PRODUCTION" || importer === "SHARED_NEUTRAL").map(([file]) => file).sort(compare);
  for (const origin of origins) {
    const originClass = importerByPath.get(origin);
    const queue = [origin];
    const parents = new Map([[origin, null]]);
    const depths = new Map([[origin, 0]]);
    const byTarget = new Map();
    const pathTo = (target) => {
      const result = [];
      for (let current = target; current !== null; current = parents.get(current)) result.push(current);
      return result.reverse();
    };
    for (let index = 0; index < queue.length; index += 1) {
      const current = queue[index];
      for (const target of graph.graph.get(current) ?? []) {
        const nextDepth = depths.get(current) + 1;
        let allowed = null;
        if (rootPath(target)) {
          const targetClass = rootByPath.get(target)?.classification ?? "FORBIDDEN_OR_UNKNOWN";
          allowed = originClass === "FEATURE_PRODUCTION" ? policy.forbiddenMatrix.featureAllowedTargets : policy.forbiddenMatrix.neutralAllowedTargets;
          const hiddenFeatureChain = originClass === "FEATURE_PRODUCTION" && nextDepth > 1 && !allowed.includes(targetClass);
          const neutralViolation = originClass === "SHARED_NEUTRAL" && !allowed.includes(targetClass);
          if ((hiddenFeatureChain || neutralViolation) && !byTarget.has(target)) {
            byTarget.set(target, { source: origin, path: [...pathTo(current), target], target, targetClassification: targetClass });
          }
          if (!allowed.includes(targetClass)) continue;
        }
        if (parents.has(target)) continue;
        parents.set(target, current);
        depths.set(target, nextDepth);
        queue.push(target);
      }
    }
    findings.push(...byTarget.values());
  }
  return findings.sort((left, right) => compare(wrapperKey(left), wrapperKey(right)));
}

function ownerProjection(status, policy) {
  const owner = policy.owners.find((candidate) => candidate.number === status?.number);
  if (!owner || !status || Object.keys(status).length !== OWNER_STATUS_KEYS.length || JSON.stringify(Object.keys(status)) !== JSON.stringify(OWNER_STATUS_KEYS) || status.title !== owner.title || status.url !== owner.url || !["OPEN", "CLOSED"].includes(status.state)) return null;
  return status;
}

function validateGraphProjection(graph, files) {
  if (!graph || !Array.isArray(graph.sources) || !Array.isArray(graph.edges) || !(graph.graph instanceof Map) || !(graph.reverse instanceof Map) || !Array.isArray(graph.uncertainty)) fail("immutable graph shape is invalid");
  let previousSource = "";
  for (const source of graph.sources) {
    exactKeys(source, ["path", "blobSha256"], "graph source");
    validateDartPath(source.path, "graph source path");
    if (source.path <= previousSource || !DIGEST.test(source.blobSha256) || !Object.hasOwn(files, source.path) || hash(files[source.path]) !== source.blobSha256) fail("graph source identity is invalid");
    previousSource = source.path;
  }
  if (JSON.stringify(graph.sources.map((source) => source.path)) !== JSON.stringify(Object.keys(files).sort(compare))) fail("graph source set is incomplete");
  let previousEdge = "";
  for (const edge of graph.edges) {
    exactKeys(edge, EDGE_KEYS, "graph edge");
    validateDartPath(edge.source, "graph edge source");
    if (edge.target !== null) validateDartPath(edge.target, "graph edge target");
    const key = graphEdgeKey(edge);
    if (key <= previousEdge || !["IMPORT", "EXPORT", "PART", "PART_OF"].includes(edge.kind) || !URI_KINDS.includes(edge.uriKind) || typeof edge.uri !== "string" || typeof edge.conditional !== "boolean") fail("graph edge identity is invalid");
    previousEdge = key;
  }
}

export function classifyRootImportGraph({ graph, files = {}, policy, baseline, baseForbiddenEdges = [], baseWrapperFindings = [], ownerStatus = [] }) {
  validateGraphProjection(graph, files);
  const sourceHashes = new Map(graph.sources.map((source) => [source.path, source.blobSha256]));
  const importerByPath = new Map();
  const uncertainty = [...graph.uncertainty];
  for (const source of graph.sources) {
    const importer = importerClass(source.path, files[source.path] ?? "", policy);
    if (importer && IMPORTER_CLASSES.includes(importer)) importerByPath.set(source.path, importer);
    else if (source.path.startsWith("apps/mobile/lib/") || source.path.startsWith("apps/mobile/test/") || source.path.startsWith("apps/mobile/integration_test/") || source.path.startsWith("apps/mobile/test_driver/")) uncertainty.push({ path: source.path, code: "IMPORTER_CLASSIFICATION_UNKNOWN" });
  }
  const actualRoots = graph.sources.map((source) => source.path).filter(rootPath);
  const rootPaths = [...new Set([...policy.rootClassifications.map((entry) => entry.path), ...actualRoots])].sort(compare);
  const rootByPath = new Map(rootPaths.map((file) => [file, rootClass(file, files[file] ?? "", policy)]));
  const rootTargets = rootPaths.map((file) => {
    const entry = rootByPath.get(file);
    return { ...entry, exists: sourceHashes.has(file), blobSha256: sourceHashes.get(file) ?? null };
  });
  const importers = [...importerByPath.entries()].sort(([left], [right]) => compare(left, right)).map(([file, importer]) => ({ path: file, importerClass: importer, blobSha256: sourceHashes.get(file) }));
  const forbiddenEdges = [];
  for (const edge of graph.edges) {
    if (!edge.target || !rootPath(edge.target)) continue;
    const importer = importerByPath.get(edge.source);
    const root = rootByPath.get(edge.target) ?? { classification: "FORBIDDEN_OR_UNKNOWN", ownerIssue: null, removalTrigger: null };
    const featureForbidden = importer === "FEATURE_PRODUCTION" && !policy.forbiddenMatrix.featureAllowedTargets.includes(root.classification);
    const appUnknown = importer === "APP_COMPOSITION" && root.classification === "FORBIDDEN_OR_UNKNOWN";
    if (featureForbidden || appUnknown) forbiddenEdges.push({ source: edge.source, target: edge.target, kind: edge.kind, uri: edge.uri, uriKind: edge.uriKind, conditional: edge.conditional, targetClassification: root.classification, ownerIssue: root.ownerIssue, removalTrigger: root.removalTrigger });
  }
  forbiddenEdges.sort((left, right) => compare(debtKey(left), debtKey(right)));
  const wrapperFindings = findWrapperFindings(graph, importerByPath, rootByPath, policy);
  const baseWrapperKeys = new Set(baseWrapperFindings.map(wrapperIdentityKey));
  const newWrapperFindings = wrapperFindings.filter((finding) => !baseWrapperKeys.has(wrapperIdentityKey(finding)));
  const projectedBaseline = baseline.edges.map((edge) => ({ source: edge.source, target: edge.target, kind: edge.kind, uri: edge.uri, uriKind: edge.uriKind, conditional: false, targetClassification: edge.targetClassification, ownerIssue: edge.ownerIssue, removalTrigger: edge.removalTrigger }));
  const baselineKeys = new Set(projectedBaseline.map(debtKey));
  const baseKeys = new Set(baseForbiddenEdges.map(debtKey));
  const newEdges = forbiddenEdges.filter((edge) => !baselineKeys.has(debtKey(edge)) || !baseKeys.has(debtKey(edge)));
  const currentKeys = new Set(forbiddenEdges.map(debtKey));
  const removedEdges = projectedBaseline.filter((edge) => !currentKeys.has(debtKey(edge)));
  const neededOwners = [...new Set(forbiddenEdges.map((edge) => edge.ownerIssue).filter(Number.isInteger))].sort((left, right) => left - right);
  const validOwnerStatus = ownerStatus.map((status) => ownerProjection(status, policy)).filter(Boolean).sort((left, right) => left.number - right.number);
  const ownerOpen = neededOwners.every((number) => validOwnerStatus.some((status) => status.number === number && status.state === "OPEN")) && validOwnerStatus.length === neededOwners.length;
  const reasons = [];
  if (newEdges.length) reasons.push("NEW_FORBIDDEN_EDGE");
  if (rootTargets.some((root) => root.exists && root.classification === "FORBIDDEN_OR_UNKNOWN")) reasons.push("UNREVIEWED_ROOT_TARGET");
  if (newWrapperFindings.length) reasons.push("FORBIDDEN_WRAPPER_OR_BARREL");
  if (!ownerOpen) reasons.push("OWNER_ISSUE_NOT_OPEN");
  if (uncertainty.length) reasons.push("GRAPH_UNCERTAINTY");
  reasons.sort((left, right) => REASONS.indexOf(left) - REASONS.indexOf(right));
  return {
    rootTargets,
    importers,
    forbiddenEdges,
    wrapperFindings,
    newWrapperFindings,
    uncertainty: uncertainty.sort((left, right) => compare(`${left.path}\0${left.code}`, `${right.path}\0${right.code}`)),
    currentEdges: forbiddenEdges,
    newEdges,
    removedEdges,
    neededOwners,
    ownerStatus: validOwnerStatus,
    reasons,
    outcome: reasons.length ? "FAIL" : "PASS",
  };
}

function defaultGit(repositoryRoot) {
  const bytes = (args) => {
    try {
      return execFileSync("git", args, { cwd: repositoryRoot, encoding: "buffer", shell: false, maxBuffer: 32 * 1024 * 1024, stdio: ["ignore", "pipe", "pipe"] });
    } catch {
      fail(`git command failed: ${args[0]}`);
    }
  };
  return { bytes, text: (args) => utf8(bytes(args), `git ${args[0]}`).trimEnd() };
}

function ensureCommit(commit, comparison, gitApi) {
  try {
    gitApi.bytes(["cat-file", "-e", `${commit}^{commit}`]);
  } catch {
    if (comparison.event !== "pull_request" || commit !== comparison.headSha || !Number.isInteger(comparison.pullRequestNumber)) throw new Error("required commit is unavailable");
    gitApi.bytes(["fetch", "--no-tags", "--depth=1", "origin", `pull/${comparison.pullRequestNumber}/head`]);
    if (gitApi.text(["rev-parse", "FETCH_HEAD"]) !== commit) fail("fetched pull request head mismatch");
  }
}

function isAncestor(base, target, gitApi) {
  try {
    gitApi.bytes(["merge-base", "--is-ancestor", base, target]);
    return true;
  } catch {
    return false;
  }
}

export function validateComparison(options, { repositoryRoot = process.cwd(), gitApi = defaultGit(repositoryRoot) } = {}) {
  for (const key of ["baseSha", "headSha", "testedMergeSha"]) if (!SHA.test(options[key] ?? "")) fail(`${key} must be lowercase 40-hex`, 2);
  if (!SAFE_TEXT.test(options.eventRef ?? "")) fail("event-ref is invalid", 2);
  const pullRequestNumber = options.pullRequestNumber === "none" ? null : Number(options.pullRequestNumber);
  if (pullRequestNumber !== null && (!Number.isInteger(pullRequestNumber) || pullRequestNumber <= 0 || String(pullRequestNumber) !== options.pullRequestNumber)) fail("pull-request-number is invalid", 2);
  const eventMode = ({ pull_request: "PULL_REQUEST", push: "PUSH_MAIN", workflow_dispatch: "MANUAL_FULL" })[options.event];
  if (!eventMode || (options.event === "pull_request") !== (pullRequestNumber !== null)) fail("event identity is invalid", 2);
  if (options.event === "pull_request" ? options.eventRef !== `refs/pull/${pullRequestNumber}/merge` : options.eventRef !== "refs/heads/main") fail("event ref is invalid", 2);
  const comparison = { event: options.event, eventMode, eventRef: options.eventRef, pullRequestNumber, baseSha: options.baseSha, pullRequestHeadSha: options.event === "pull_request" ? options.headSha : null, headSha: options.headSha, testedMergeSha: options.testedMergeSha, mergeBaseSha: null, range: null };
  ensureCommit(options.baseSha, comparison, gitApi);
  ensureCommit(options.headSha, comparison, gitApi);
  ensureCommit(options.testedMergeSha, comparison, gitApi);
  if (gitApi.text(["rev-parse", "HEAD"]) !== options.testedMergeSha) fail("EVENT_IDENTITY_MISMATCH: tested merge does not equal repository HEAD");
  if (options.event === "pull_request") {
    const mergeBases = gitApi.text(["merge-base", "--all", options.baseSha, options.headSha]).split("\n").filter(Boolean);
    if (options.baseSha === options.headSha || options.baseSha === options.testedMergeSha || options.headSha === options.testedMergeSha || mergeBases.length !== 1 || !isAncestor(options.baseSha, options.testedMergeSha, gitApi) || !isAncestor(options.headSha, options.testedMergeSha, gitApi)) fail("EVENT_IDENTITY_MISMATCH: pull request graph is invalid");
    comparison.mergeBaseSha = mergeBases[0];
    comparison.range = `${options.baseSha}..${options.testedMergeSha}`;
  } else if (options.event === "push") {
    if (/^0{40}$/u.test(options.baseSha) || options.baseSha === options.headSha || options.headSha !== options.testedMergeSha || !isAncestor(options.baseSha, options.headSha, gitApi)) fail("EVENT_IDENTITY_MISMATCH: push graph is invalid");
    comparison.mergeBaseSha = options.baseSha;
    comparison.range = `${options.baseSha}..${options.headSha}`;
  } else {
    if (options.baseSha !== options.headSha || options.headSha !== options.testedMergeSha) fail("EVENT_IDENTITY_MISMATCH: manual graph is invalid");
    comparison.mergeBaseSha = options.headSha;
  }
  return comparison;
}

function pubspecPackageName(bytes) {
  const lines = utf8(bytes, "immutable mobile pubspec").split(/\r?\n/u);
  const declarations = lines.filter((line) => /^name\s*:/u.test(line));
  if (declarations.length !== 1) fail("immutable mobile pubspec package name is missing or duplicated");
  const match = /^name: ([a-z][a-z0-9_]*)$/u.exec(declarations[0]);
  if (!match) fail("immutable mobile pubspec package name is invalid");
  return match[1];
}

export function loadImmutableMobileTree(commit, { repositoryRoot = process.cwd(), gitApi = defaultGit(repositoryRoot) } = {}) {
  if (!SHA.test(commit)) fail("immutable tree commit is invalid");
  const raw = gitApi.bytes(["ls-tree", "-r", "-z", "--full-tree", commit, "--", "apps/mobile/lib", "apps/mobile/test", "apps/mobile/integration_test", "apps/mobile/test_driver", "apps/mobile/pubspec.yaml"]);
  const entries = utf8(raw, "git ls-tree", { allowNul: true }).split("\0");
  if (entries.pop() !== "") fail("git ls-tree stream is malformed");
  const files = {};
  let packageName = null;
  for (const record of entries) {
    const match = /^(\d{6}) ([a-z]+) ([0-9a-f]{40})\t(.+)$/u.exec(record);
    if (!match) fail("git ls-tree record is malformed");
    const [, mode, type, object, file] = match;
    if (file === "apps/mobile/pubspec.yaml") {
      if (packageName !== null || mode !== "100644" || type !== "blob") fail("immutable mobile pubspec must be one regular blob");
      packageName = pubspecPackageName(gitApi.bytes(["cat-file", "blob", object]));
      continue;
    }
    if (!file.endsWith(".dart")) continue;
    validateDartPath(file, "immutable tree path");
    if (!/^100(?:644|755)$/u.test(mode) || type !== "blob") fail("immutable Dart source must be a regular blob");
    if (Object.hasOwn(files, file)) fail("duplicate immutable Dart tree path");
    files[file] = utf8(gitApi.bytes(["cat-file", "blob", object]), `Dart blob ${file}`, { allowNul: true });
  }
  if (packageName === null) fail("immutable mobile pubspec is missing");
  return { files, packageName };
}

export function loadImmutableDartTree(commit, options = {}) {
  return loadImmutableMobileTree(commit, options).files;
}

function sourceTreeDigest(graph) {
  return hash(Buffer.from(graph.sources.map((source) => `${source.path}\0${source.blobSha256}\0`).join("")));
}

function summaryFor(inventory, result) {
  return [
    "# Mobile root import ratchet",
    "",
    `- phase: ${result.phase}`,
    `- outcome: ${result.outcome}`,
    `- tested merge: ${result.comparison.testedMergeSha}`,
    `- current forbidden edges: ${result.currentEdges.length}`,
    `- new forbidden edges: ${result.newEdges.length}`,
    `- removed reviewed edges: ${result.removedEdges.length}`,
    `- wrapper findings: ${inventory.wrapperFindings.length}`,
    `- graph uncertainty: ${inventory.uncertainty.length}`,
    `- reasons: ${result.reasons.length ? result.reasons.join(", ") : "none"}`,
    "",
  ].join("\n");
}

function producerFor(graph, policyBytes, baselineBytes) {
  return {
    runnerSha256: hash(readFileSync(fileURLToPath(import.meta.url))),
    helperSha256: hash(readFileSync(fileURLToPath(HELPER_URL))),
    policySha256: hash(policyBytes),
    baselineSha256: hash(baselineBytes),
    sourceTreeSha256: sourceTreeDigest(graph),
  };
}

function buildEvidence({ comparison, graph, files, baseGraph, baseFiles, policy, baseline, policyBytes, baselineBytes, ownerStatus }) {
  const base = classifyRootImportGraph({ graph: baseGraph, files: baseFiles, policy, baseline, baseForbiddenEdges: baseline.edges, ownerStatus: policy.owners.map((owner) => ({ number: owner.number, title: owner.title, url: owner.url, state: "OPEN" })) });
  const decision = classifyRootImportGraph({ graph, files, policy, baseline, baseForbiddenEdges: base.forbiddenEdges, baseWrapperFindings: base.wrapperFindings, ownerStatus });
  const producer = producerFor(graph, policyBytes, baselineBytes);
  const summary = { rootTargets: decision.rootTargets.length, importers: decision.importers.length, edges: graph.edges.length, forbiddenEdges: decision.forbiddenEdges.length, wrapperFindings: decision.wrapperFindings.length, uncertainty: decision.uncertainty.length };
  const inventory = { schemaVersion: 1, artifactKind: "mobile-root-import-inventory-v1", repository: REPOSITORY, phase: PHASE, comparison, producer, ownerIssues: decision.ownerStatus, rootTargets: decision.rootTargets, importers: decision.importers, edges: graph.edges, forbiddenEdges: decision.forbiddenEdges, wrapperFindings: decision.wrapperFindings, uncertainty: decision.uncertainty, summary };
  const inventoryBytes = canonicalBytes(inventory);
  const result = { schemaVersion: 1, artifactKind: "mobile-root-import-result-v1", repository: REPOSITORY, phase: PHASE, comparison, producer, inventorySha256: hash(inventoryBytes), baselineSha256: hash(baselineBytes), currentEdges: decision.currentEdges, newEdges: decision.newEdges, removedEdges: decision.removedEdges, ownerStatus: decision.ownerStatus, reasons: decision.reasons, outcome: decision.outcome };
  return { inventory, inventoryBytes, result, resultBytes: canonicalBytes(result), summary: summaryFor(inventory, result) };
}

function safeArtifactDirectory(directory, create = false) {
  if (!path.isAbsolute(directory)) fail("artifact directory must be absolute");
  if (!existsSync(directory)) {
    if (!create) fail("artifact directory is missing");
    mkdirSync(directory, { recursive: false, mode: 0o700 });
  }
  const stat = lstatSync(directory);
  if (!stat.isDirectory() || stat.isSymbolicLink()) fail("artifact directory must be a regular directory");
  return directory;
}

function safeArtifactFile(directory, name) {
  const file = path.join(directory, name);
  const stat = lstatSync(file);
  if (!stat.isFile() || stat.isSymbolicLink()) fail("artifact entry must be a regular file");
  return readFileSync(file);
}

export function writeArtifactDirectory(directory, evidence) {
  safeArtifactDirectory(directory, true);
  if (readdirSync(directory).length) fail("artifact directory must start empty");
  const values = [evidence.inventoryBytes, evidence.resultBytes, Buffer.from(evidence.summary), Buffer.from(`${hash(evidence.inventoryBytes)}  ${ARTIFACT_FILES[0]}\n${hash(evidence.resultBytes)}  ${ARTIFACT_FILES[1]}\n`)];
  const staged = [];
  try {
    for (const [index, name] of ARTIFACT_FILES.entries()) {
      const temporary = path.join(directory, `.${name}.stage`);
      writeFileSync(temporary, values[index], { flag: "wx", mode: 0o600 });
      staged.push(temporary);
    }
    for (const [index, name] of ARTIFACT_FILES.entries()) renameSync(staged[index], path.join(directory, name));
  } catch (error) {
    for (const file of [...staged, ...ARTIFACT_FILES.map((name) => path.join(directory, name))]) if (existsSync(file)) rmSync(file, { force: true });
    throw error;
  }
}

function readProductionContract() {
  const policyBytes = readFileSync(fileURLToPath(POLICY_URL));
  const baselineBytes = readFileSync(fileURLToPath(BASELINE_URL));
  const policy = parsePolicyBytes(policyBytes);
  const baseline = parseBaselineBytes(baselineBytes, policy);
  return { policyBytes, baselineBytes, policy, baseline };
}

function validateOwnerStatusValues(values, neededOwners, policy) {
  if (!Array.isArray(values)) fail("owner status must be an array");
  const sorted = [...values].sort((left, right) => left.number - right.number);
  if (JSON.stringify(values) !== JSON.stringify(sorted) || JSON.stringify(values.map((value) => value.number)) !== JSON.stringify(neededOwners)) fail("owner status set changed");
  for (const value of values) if (!ownerProjection(value, policy)) fail("owner status identity changed");
  return values;
}

export function verifyArtifactDirectory(directory, { repositoryRoot = process.cwd(), gitApi = defaultGit(repositoryRoot) } = {}) {
  safeArtifactDirectory(directory);
  if (JSON.stringify(readdirSync(directory).sort(compare)) !== JSON.stringify([...ARTIFACT_FILES].sort(compare))) fail("ARTIFACT_MISMATCH: artifact file set changed");
  const inventoryBytes = safeArtifactFile(directory, ARTIFACT_FILES[0]);
  const resultBytes = safeArtifactFile(directory, ARTIFACT_FILES[1]);
  const summaryBytes = safeArtifactFile(directory, ARTIFACT_FILES[2]);
  const manifestBytes = safeArtifactFile(directory, ARTIFACT_FILES[3]);
  const inventory = canonical(inventoryBytes, "root import inventory");
  const result = canonical(resultBytes, "root import result");
  exactKeys(inventory, INVENTORY_KEYS, "inventory");
  exactKeys(result, RESULT_KEYS, "result");
  exactKeys(inventory.comparison, COMPARISON_KEYS, "inventory comparison");
  exactKeys(result.comparison, COMPARISON_KEYS, "result comparison");
  exactKeys(inventory.producer, PRODUCER_KEYS, "inventory producer");
  exactKeys(result.producer, PRODUCER_KEYS, "result producer");
  if (!inventoryBytes.equals(canonicalBytes(inventory)) || !resultBytes.equals(canonicalBytes(result)) || !DIGEST.test(result.inventorySha256) || result.inventorySha256 !== hash(inventoryBytes) || result.baselineSha256 !== BASELINE_SHA256 || JSON.stringify(inventory.comparison) !== JSON.stringify(result.comparison) || JSON.stringify(inventory.producer) !== JSON.stringify(result.producer)) fail("ARTIFACT_MISMATCH: cross-file identity changed");
  const expectedManifest = Buffer.from(`${hash(inventoryBytes)}  ${ARTIFACT_FILES[0]}\n${hash(resultBytes)}  ${ARTIFACT_FILES[1]}\n`);
  if (!manifestBytes.equals(expectedManifest)) fail("ARTIFACT_MISMATCH: detached manifest changed");
  const contract = readProductionContract();
  const comparison = validateComparison({ event: result.comparison.event, eventRef: result.comparison.eventRef, pullRequestNumber: result.comparison.pullRequestNumber === null ? "none" : String(result.comparison.pullRequestNumber), baseSha: result.comparison.baseSha, headSha: result.comparison.headSha, testedMergeSha: result.comparison.testedMergeSha }, { repositoryRoot, gitApi });
  if (JSON.stringify(comparison) !== JSON.stringify(result.comparison)) fail("ARTIFACT_MISMATCH: comparison changed");
  const tree = loadImmutableMobileTree(comparison.testedMergeSha, { repositoryRoot, gitApi });
  const baseTree = loadImmutableMobileTree(comparison.baseSha, { repositoryRoot, gitApi });
  const files = tree.files;
  const baseFiles = baseTree.files;
  const graph = buildImmutableDartSourceGraph({ files, packageName: tree.packageName });
  const baseGraph = buildImmutableDartSourceGraph({ files: baseFiles, packageName: baseTree.packageName });
  const preliminary = classifyRootImportGraph({ graph, files, policy: contract.policy, baseline: contract.baseline, baseForbiddenEdges: [], ownerStatus: [] });
  validateOwnerStatusValues(result.ownerStatus, preliminary.neededOwners, contract.policy);
  const expected = buildEvidence({ comparison, graph, files, baseGraph, baseFiles, ...contract, ownerStatus: result.ownerStatus });
  if (!inventoryBytes.equals(expected.inventoryBytes) || !resultBytes.equals(expected.resultBytes) || utf8(summaryBytes, "root import summary") !== expected.summary) fail("ARTIFACT_MISMATCH: evidence does not recompute exactly");
  return result;
}

export function validateOwnerIssueResponse(response, owner) {
  if (!response || response.statusCode !== 200 || response.redirected) fail("owner issue request failed");
  const value = strictExternalJson(Buffer.isBuffer(response.body) ? response.body : Buffer.from(response.body ?? ""), "owner issue response");
  if (!value || Array.isArray(value) || value.number !== owner.number || value.title !== owner.title || value.html_url !== owner.url || !["open", "closed"].includes(value.state) || Object.hasOwn(value, "pull_request")) fail("owner issue identity is not reviewed");
  return { number: owner.number, title: owner.title, url: owner.url, state: value.state.toUpperCase() };
}

function providerError(response) {
  const error = new Error(`owner issue request failed statusCode=${Number.isInteger(response.statusCode) ? response.statusCode : "invalid"}`);
  error.statusCode = response.statusCode;
  error.retryAfter = response.headers?.["retry-after"];
  error.rateLimitRemaining = response.headers?.["x-ratelimit-remaining"];
  error.rateLimitReset = response.headers?.["x-ratelimit-reset"];
  error.hasRateLimitHeaders = Object.hasOwn(response.headers ?? {}, "x-ratelimit-remaining") || Object.hasOwn(response.headers ?? {}, "x-ratelimit-reset");
  return error;
}

function requestOwnerAttempt({ owner, token, requestImpl, timeoutMs, maxBytes }) {
  return new Promise((resolve, reject) => {
    let settled = false;
    let call;
    const done = (error, value) => {
      if (settled) return;
      settled = true;
      clearTimeout(deadline);
      error ? reject(error) : resolve(value);
    };
    call = requestImpl({ protocol: "https:", hostname: "api.github.com", path: `/repos/AquilaXk/easysubway-mobile/issues/${owner.number}`, method: "GET", headers: { Accept: "application/vnd.github+json", "X-GitHub-Api-Version": "2026-03-10", "User-Agent": "easysubway-mobile-root-import-ratchet", Authorization: `Bearer ${token}` } }, (response) => {
      const chunks = [];
      let size = 0;
      response.once("error", (error) => done(error));
      response.on("data", (chunk) => {
        size += chunk.length;
        if (size > maxBytes) {
          call.destroy(new Error("owner issue response exceeds maximum bytes"));
          done(new Error("owner issue response exceeds maximum bytes"));
        } else chunks.push(chunk);
      });
      response.once("end", () => {
        if (response.statusCode !== 200) done(providerError(response));
        else done(null, { statusCode: 200, redirected: false, body: Buffer.concat(chunks) });
      });
    });
    const deadline = setTimeout(() => {
      call.destroy(new Error("owner issue request timed out"));
      done(new Error("owner issue request timed out"));
    }, timeoutMs);
    call.once("error", (error) => done(error));
    call.end();
  });
}

export async function requestOwnerIssue(owner, { token, requestImpl = request, timeoutMs = 10000, maxBytes = 65536, sleeper = (delay) => new Promise((resolve) => setTimeout(resolve, delay)), clock = () => Math.floor(Date.now() / 1000) } = {}) {
  if (typeof token !== "string" || !token) fail("OWNER_ISSUE_TOKEN is required");
  for (let attempt = 0; attempt < 2; attempt += 1) {
    try {
      return await requestOwnerAttempt({ owner, token, requestImpl, timeoutMs, maxBytes });
    } catch (error) {
      if (attempt === 1) throw error;
      let delay = null;
      if (Number.isInteger(error.statusCode) && error.statusCode >= 500 && error.statusCode <= 599) delay = 1000;
      else if (error.statusCode === 403 || error.statusCode === 429) {
        if (error.retryAfter !== undefined) {
          if (typeof error.retryAfter === "string" && /^\d{1,2}$/u.test(error.retryAfter) && Number(error.retryAfter) <= 60) delay = Number(error.retryAfter) * 1000;
        } else if (error.hasRateLimitHeaders) {
          const remaining = error.rateLimitRemaining;
          const reset = error.rateLimitReset;
          const now = clock();
          if (remaining === "0" && typeof reset === "string" && /^\d{1,10}$/u.test(reset) && Number(reset) >= now && Number(reset) - now <= 60) delay = (Number(reset) - now) * 1000;
        } else delay = 60000;
      }
      if (delay === null) throw error;
      await sleeper(delay);
    }
  }
  fail("owner issue request failed");
}

export async function analyze(options, { repositoryRoot = process.cwd(), gitApi = defaultGit(repositoryRoot), requestOwnerIssueFn = requestOwnerIssue, environment = process.env } = {}) {
  if (!path.isAbsolute(environment.RUNNER_TEMP ?? "") || typeof environment.OWNER_ISSUE_TOKEN !== "string" || !environment.OWNER_ISSUE_TOKEN) fail("RUNNER_TEMP and OWNER_ISSUE_TOKEN are required");
  const comparison = validateComparison(options, { repositoryRoot, gitApi });
  const contract = readProductionContract();
  const tree = loadImmutableMobileTree(comparison.testedMergeSha, { repositoryRoot, gitApi });
  const baseTree = loadImmutableMobileTree(comparison.baseSha, { repositoryRoot, gitApi });
  const files = tree.files;
  const baseFiles = baseTree.files;
  const graph = buildImmutableDartSourceGraph({ files, packageName: tree.packageName });
  const baseGraph = buildImmutableDartSourceGraph({ files: baseFiles, packageName: baseTree.packageName });
  const base = classifyRootImportGraph({ graph: baseGraph, files: baseFiles, policy: contract.policy, baseline: contract.baseline, baseForbiddenEdges: contract.baseline.edges, ownerStatus: contract.policy.owners.map((owner) => ({ number: owner.number, title: owner.title, url: owner.url, state: "OPEN" })) });
  const preliminary = classifyRootImportGraph({ graph, files, policy: contract.policy, baseline: contract.baseline, baseForbiddenEdges: base.forbiddenEdges, baseWrapperFindings: base.wrapperFindings, ownerStatus: [] });
  const ownerStatus = [];
  for (const number of preliminary.neededOwners) {
    const owner = contract.policy.owners.find((candidate) => candidate.number === number);
    const response = await requestOwnerIssueFn(owner, { token: environment.OWNER_ISSUE_TOKEN });
    ownerStatus.push(validateOwnerIssueResponse(response, owner));
  }
  const evidence = buildEvidence({ comparison, graph, files, baseGraph, baseFiles, ...contract, ownerStatus });
  writeArtifactDirectory(path.join(environment.RUNNER_TEMP, contract.policy.artifactContract.directory), evidence);
  return evidence.result;
}

function parseArgs(argv, command) {
  const required = command === "analyze" ? ["event", "base-sha", "head-sha", "tested-merge-sha", "event-ref", "pull-request-number"] : ["analysis-outcome", "upload-outcome"];
  const values = {};
  for (let index = 0; index < argv.length; index += 2) {
    const flag = argv[index];
    const key = flag?.startsWith("--") ? flag.slice(2) : "";
    if (!required.includes(key) || Object.hasOwn(values, key) || argv[index + 1] === undefined) fail("invalid arguments", 2);
    values[key] = argv[index + 1];
  }
  if (required.some((key) => !Object.hasOwn(values, key))) fail("missing arguments", 2);
  return values;
}

export async function runCli(argv, { analyzeFn = analyze, verifyFn = verifyArtifactDirectory, environment = process.env } = {}) {
  const command = argv[0];
  if (command === "analyze") {
    const values = parseArgs(argv.slice(1), command);
    return analyzeFn({ event: values.event, baseSha: values["base-sha"], headSha: values["head-sha"], testedMergeSha: values["tested-merge-sha"], eventRef: values["event-ref"], pullRequestNumber: values["pull-request-number"] }, { environment });
  }
  if (command === "verdict") {
    const values = parseArgs(argv.slice(1), command);
    if (values["analysis-outcome"] !== "success" || values["upload-outcome"] !== "success") fail("analysis or upload failed");
    if (!path.isAbsolute(environment.RUNNER_TEMP ?? "")) fail("RUNNER_TEMP must be absolute");
    const result = verifyFn(path.join(environment.RUNNER_TEMP, "mobile-root-import-ratchet"));
    if (result.outcome !== "PASS") fail("mobile root import no-increase gate failed");
    return result;
  }
  fail("usage", 2);
}

async function main() {
  const result = await runCli(process.argv.slice(2));
  if (process.argv[2] === "analyze") process.stdout.write(`${JSON.stringify({ outcome: result.outcome, headSha: result.comparison.headSha })}\n`);
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  main().catch((error) => {
    process.stderr.write(`mobile-root-import-ratchet: ${error.message}\n`);
    process.exitCode = error.exitCode ?? 1;
  });
}
