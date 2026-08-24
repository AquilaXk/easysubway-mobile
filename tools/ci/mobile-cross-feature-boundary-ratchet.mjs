#!/usr/bin/env node
import { execFileSync } from "node:child_process";
import { readFileSync, readdirSync } from "node:fs";
import path from "node:path";

import { buildImmutableDartSourceGraph } from "./lib/mobile-dart-source-graph.mjs";

const POLICY_PATH = "tools/ci/mobile-cross-feature-boundary-policy.json";
const FEATURE_PATH = /^apps\/mobile\/lib\/features\/([^/]+)\/(.+)$/u;
const SHA = /^[0-9a-f]{40}$/u;
const EXPECTED_KEYS = ["schemaVersion", "artifactKind", "repository", "reviewedHeadSha", "featurePrefix", "forbiddenTargetSegments"];
const compare = (left, right) => left < right ? -1 : left > right ? 1 : 0;
const edgeKey = (edge) => [edge.source, edge.target, edge.kind, edge.uri, edge.uriKind, String(edge.conditional)].join("\0");

export function parsePolicy(bytes) {
  let value;
  try { value = JSON.parse(Buffer.from(bytes).toString("utf8")); } catch { throw new Error("cross-feature boundary policy must be JSON"); }
  if (JSON.stringify(Object.keys(value)) !== JSON.stringify(EXPECTED_KEYS) || value.schemaVersion !== 1 || value.artifactKind !== "mobile-cross-feature-boundary-policy-v1" || value.repository !== "AquilaXk/easysubway-mobile" || !SHA.test(value.reviewedHeadSha) || value.featurePrefix !== "apps/mobile/lib/features/" || JSON.stringify(value.forbiddenTargetSegments) !== JSON.stringify(["application", "data", "infrastructure", "presentation"])) throw new Error("cross-feature boundary policy identity is invalid");
  return value;
}

function featurePath(file, policy) { return file.startsWith(policy.featurePrefix) ? FEATURE_PATH.exec(file) : null; }

export function forbiddenConcreteEdges(graph, policy) {
  if (graph.uncertainty.length) throw new Error("cross-feature graph uncertainty");
  return graph.edges.filter((edge) => {
    if (!edge.target || !["IMPORT", "EXPORT"].includes(edge.kind)) return false;
    const source = featurePath(edge.source, policy);
    const target = featurePath(edge.target, policy);
    return source && target && source[1] !== target[1] && policy.forbiddenTargetSegments.includes(target[2].split("/")[0]);
  }).sort((left, right) => compare(edgeKey(left), edgeKey(right)));
}

export function compareGraphs({ baseFiles, currentFiles, policy, packageName = "easysubway_mobile" }) {
  const baseline = forbiddenConcreteEdges(buildImmutableDartSourceGraph({ files: baseFiles, packageName }), policy);
  const current = forbiddenConcreteEdges(buildImmutableDartSourceGraph({ files: currentFiles, packageName }), policy);
  const known = new Set(baseline.map(edgeKey));
  return { baseline, current, newEdges: current.filter((edge) => !known.has(edgeKey(edge))) };
}

function readTree(directory) {
  const files = {};
  const walk = (entry) => { for (const child of readdirSync(entry, { withFileTypes: true })) { const resolved = path.join(entry, child.name); if (child.isDirectory()) walk(resolved); else if (child.isFile() && resolved.endsWith(".dart")) files[path.relative(process.cwd(), resolved).split(path.sep).join("/")] = readFileSync(resolved, "utf8"); } };
  walk(directory);
  return files;
}

function readGitTree(commit) {
  const output = execFileSync("git", ["ls-tree", "-r", "-z", "--name-only", commit, "--", "apps/mobile/lib"], { encoding: "utf8" });
  return Object.fromEntries(output.split("\0").filter((file) => file.endsWith(".dart")).map((file) => [file, execFileSync("git", ["show", `${commit}:${file}`], { encoding: "utf8" })]));
}

export function runCli() {
  const policy = parsePolicy(readFileSync(POLICY_PATH));
  const result = compareGraphs({ baseFiles: readGitTree(policy.reviewedHeadSha), currentFiles: readTree("apps/mobile/lib"), policy });
  if (result.newEdges.length) throw new Error(`new forbidden cross-feature concrete edge(s): ${result.newEdges.map((edge) => `${edge.kind} ${edge.source} -> ${edge.target}`).join(", ")}`);
  process.stdout.write(`mobile cross-feature boundary ratchet: PASS (baseline=${result.baseline.length}, current=${result.current.length})\n`);
}

if (import.meta.url === `file://${process.argv[1]}`) runCli();
