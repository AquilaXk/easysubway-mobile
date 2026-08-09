import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { mkdtempSync, writeFileSync, mkdirSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import test from "node:test";

import {
  FULL_REQUIREMENTS,
  GIT_MAX_BUFFER_BYTES,
  buildResult,
  buildImmutableDartGraph,
  classifyEntries,
  joinDiffStreams,
  parseCliArguments,
  parseNumstat,
  parseRawDiff,
  reverseConsumerFanout,
  runClassifier,
  validateArtifact,
  validatePolicy,
  validateResult,
  summaryMarkdown,
} from "./mobile-changed-path-classifier.mjs";

const sha = (character) => character.repeat(40);
const policy = JSON.parse(readFileSync(new URL("./mobile-changed-path-policy.json", import.meta.url), "utf8"));
const featureChange = { status: "MODIFIED", oldPath: "apps/mobile/lib/features/home/a.dart", newPath: "apps/mobile/lib/features/home/a.dart", oldMode: "100644", newMode: "100644", oldBlobSha: sha("a"), newBlobSha: sha("b"), isBinary: false, reasons: [] };
function classifiedResult() {
  return buildResult({
    event: { name: "push", ref: "refs/heads/main", pullRequestNumber: null },
    comparison: { baseSha: sha("a"), headSha: sha("b"), mergeBaseSha: sha("a") },
    classifier: { sourceSha256: "c".repeat(64), policySha256: "d".repeat(64), workflowSha256: "e".repeat(64) },
    classification: classifyEntries([featureChange], validatePolicy(policy)),
  });
}

test("policy schema is closed and literal path rules classify a feature", () => {
  const checked = validatePolicy(policy);
  assert.equal(checked.repository, "AquilaXk/easysubway-mobile");
  const classified = classifyEntries([
    { status: "MODIFIED", oldPath: "apps/mobile/lib/features/home/a.dart", newPath: "apps/mobile/lib/features/home/a.dart", oldMode: "100644", newMode: "100644", oldBlobSha: sha("a"), newBlobSha: sha("b"), isBinary: false, reasons: [] },
  ], checked);
  assert.equal(classified.outcome, "CLASSIFIED");
  assert.deepEqual(classified.owners.map((owner) => owner.owner), ["FEATURE:home"]);
  assert.equal(classified.requirements.requiresAndroidBuild, false);
  assert.throws(() => validatePolicy({ ...policy, extra: true }), /exactly match/i);
  for (const mutate of [
    (value) => { value.requirements.FEATURE.requiresCoverage = false; },
    (value) => { value.pathRules[0].exactPaths[0] = "other"; },
    (value) => { value.pathRules[0].owners[0] = "OTHER"; },
    (value) => { value.pathRules.reverse(); },
    (value) => { value.pathRules.pop(); },
    (value) => { value.pathRules.push(structuredClone(value.pathRules[0])); },
  ]) { const changed = structuredClone(policy); mutate(changed); assert.throws(() => validatePolicy(changed), /exactly match/i); }
});

test("raw and numstat streams are parsed independently and joined by exact shape", () => {
  const raw = Buffer.from(`:100644 100644 ${sha("a")} ${sha("b")} M\0apps/mobile/lib/features/home/a.dart\0:100644 100644 ${sha("c")} ${sha("d")} R090\0apps/mobile/lib/features/home/old.dart\0apps/mobile/lib/features/home/new.dart\0`);
  const numstat = Buffer.from("1\t2\tapps/mobile/lib/features/home/a.dart\0" + "3\t4\t\0apps/mobile/lib/features/home/old.dart\0apps/mobile/lib/features/home/new.dart\0");
  const entries = joinDiffStreams(parseRawDiff(raw), parseNumstat(numstat));
  assert.deepEqual(entries.map(({ status, oldPath, newPath }) => [status, oldPath, newPath]), [
    ["MODIFIED", "apps/mobile/lib/features/home/a.dart", "apps/mobile/lib/features/home/a.dart"],
    ["RENAMED", "apps/mobile/lib/features/home/old.dart", "apps/mobile/lib/features/home/new.dart"],
  ]);
  assert.throws(() => joinDiffStreams(parseRawDiff(raw), parseNumstat(Buffer.from("1\t2\tother.dart\0"))), /count|mismatch/i);
  const punctuationRaw = Buffer.from(`:100644 100644 ${sha("a")} ${sha("b")} M\0apps/mobile/lib/a#.dart\0:100644 100644 ${sha("c")} ${sha("d")} M\0apps/mobile/lib/a".dart\0`);
  const punctuationNumstat = Buffer.from("1\t1\tapps/mobile/lib/a#.dart\0" + "1\t1\tapps/mobile/lib/a\".dart\0");
  assert.deepEqual(joinDiffStreams(parseRawDiff(punctuationRaw), parseNumstat(punctuationNumstat)).map((entry) => entry.newPath), ["apps/mobile/lib/a\".dart", "apps/mobile/lib/a#.dart"]);
});

test("unknown paths and graph uncertainty are valid conservative full requirements", () => {
  const checked = validatePolicy(policy);
  const result = classifyEntries([
    { status: "ADDED", oldPath: null, newPath: "unowned/file.txt", oldMode: null, newMode: "100644", oldBlobSha: null, newBlobSha: sha("a"), isBinary: false, reasons: [] },
  ], checked, { graphUncertainty: [{ path: "apps/mobile/lib/features/home/a.dart", code: "GRAPH_UNCERTAINTY" }] });
  assert.equal(result.outcome, "FULL_REQUIRED");
  assert.deepEqual(result.uncertainty.codes, ["UNMATCHED_PATH", "GRAPH_UNCERTAINTY"]);
  assert.deepEqual(result.requirements, FULL_REQUIREMENTS);
});

test("old and new paths and fanout consumers fail closed independently", () => {
  const knownToUnowned = { status: "RENAMED", oldPath: "apps/mobile/lib/features/home/old.dart", newPath: "unowned/new.dart", oldMode: "100644", newMode: "100644", oldBlobSha: sha("a"), newBlobSha: sha("b"), isBinary: false, reasons: [] };
  const unownedToKnown = { status: "COPIED", oldPath: "unowned/copied.dart", newPath: "apps/mobile/lib/features/account/new.dart", oldMode: "100644", newMode: "100644", oldBlobSha: sha("c"), newBlobSha: sha("d"), isBinary: false, reasons: [] };
  const unknownFeature = { status: "MODIFIED", oldPath: "apps/mobile/lib/features/not_a_root/a.dart", newPath: "apps/mobile/lib/features/not_a_root/a.dart", oldMode: "100644", newMode: "100644", oldBlobSha: sha("e"), newBlobSha: sha("f"), isBinary: false, reasons: [] };
  const result = classifyEntries([knownToUnowned, unownedToKnown, unknownFeature], validatePolicy(policy));
  assert.equal(result.outcome, "FULL_REQUIRED");
  assert.deepEqual(result.entries.map((entry) => entry.reasons), [
    ["feature-home", "UNMATCHED_PATH"],
    ["feature-account", "feature-privacy", "UNMATCHED_PATH"],
    ["UNMATCHED_PATH", "UNKNOWN_FEATURE_ROOT"],
  ]);
  const unknownPaths = result.owners.filter((owner) => owner.owner === "UNKNOWN").flatMap((owner) => owner.paths).sort();
  assert.deepEqual(unknownPaths, ["apps/mobile/lib/features/not_a_root/a.dart", "unowned/copied.dart", "unowned/new.dart"]);
  assert.ok(result.affectedBoundaries.includes("UNKNOWN"));
  const fanout = classifyEntries([featureChange], validatePolicy(policy), { fanoutPaths: ["unowned/consumer.dart"] });
  assert.equal(fanout.outcome, "FULL_REQUIRED");
  assert.deepEqual(fanout.uncertainty, { isFullRequired: true, codes: ["UNMATCHED_PATH"], paths: ["unowned/consumer.dart"] });
  assert.deepEqual(fanout.owners.filter((owner) => owner.owner === "UNKNOWN").flatMap((owner) => owner.paths), ["unowned/consumer.dart"]);
});

test("policy fixes generic feature identifiers and README-only docs uncertainty", () => {
  assert.deepEqual(policy.pathRules.map((rule) => rule.id).slice(17, 39), [
    "feature-account", "feature-ads", "feature-attribution", "feature-fare", "feature-favorites", "feature-get_off_alarm", "feature-home", "feature-home_widget", "feature-internal_route", "feature-mobility_profile", "feature-network_map", "feature-notifications", "feature-preferences", "feature-realtime", "feature-route_draft", "feature-routes", "feature-search_history", "feature-service_notice", "feature-settings", "feature-stations", "feature-support", "feature-train_search",
  ]);
  assert.deepEqual(policy.pathRules.find((rule) => rule.id === "root-policy").reasons, ["root-policy"]);
  const rootFiles = [".gitattributes", ".gitignore", "README.md"].map((changedPath, index) => ({ status: "MODIFIED", oldPath: changedPath, newPath: changedPath, oldMode: "100644", newMode: "100644", oldBlobSha: sha(String.fromCharCode(97 + index)), newBlobSha: sha(String.fromCharCode(100 + index)), isBinary: false, reasons: [] }));
  const classified = classifyEntries(rootFiles, validatePolicy(policy));
  assert.deepEqual(classified.entries.map((entry) => entry.reasons), [["root-policy"], ["root-policy"], ["root-policy", "DOCS_POLICY_UNREVIEWED"]]);
});

test("CLI rejects duplicate and unknown arguments with usage exit semantics", () => {
  const duplicate = ["run", "--event", "push", "--event", "push", "--base-sha", sha("a"), "--head-sha", sha("b"), "--event-ref", "refs/heads/main"];
  const unknown = ["run", "--unknown", "x", "--event", "push", "--base-sha", sha("a"), "--head-sha", sha("b"), "--event-ref", "refs/heads/main"];
  assert.equal(duplicate.length, 11); assert.equal(unknown.length, 11);
  for (const args of [duplicate, unknown]) assert.throws(() => parseCliArguments(args), (error) => error.exitCode === 2 && /unknown, duplicate, or missing CLI argument/u.test(error.message));
  assert.throws(() => parseCliArguments(["run", "--event", "push"]), (error) => error.exitCode === 2 && /expected exact run arguments/u.test(error.message));
  assert.deepEqual(parseCliArguments(["run", "--event", "push", "--base-sha", sha("a"), "--head-sha", sha("b"), "--event-ref", "refs/heads/main", "--pull-request-number", "none"]).event, "push");
});

test("Git capture binds every production Git invocation to the closed max buffer", () => {
  assert.equal(GIT_MAX_BUFFER_BYTES, 64 * 1024 * 1024);
  const source = readFileSync(new URL("./mobile-changed-path-classifier.mjs", import.meta.url), "utf8");
  assert.match(source, /function git\([^]*maxBuffer: GIT_MAX_BUFFER_BYTES[^]*\}/u);
  assert.equal((source.match(/execFileSync\("git"/gu) ?? []).length, 1);
});

test("canonical result and artifact require exactly three regular files and exact detached digest", () => {
  const result = classifiedResult();
  assert.equal(result.outcome, "CLASSIFIED");
  const root = mkdtempSync(path.join(tmpdir(), "mobile-classifier-"));
  const json = Buffer.from(JSON.stringify(result));
  const digest = createHash("sha256").update(json).digest("hex");
  writeFileSync(path.join(root, "mobile-changed-path-classification.json"), json);
  writeFileSync(path.join(root, "mobile-changed-path-classification-summary.md"), summaryMarkdown(result));
  writeFileSync(path.join(root, "mobile-changed-path-classification.sha256"), `${digest}  mobile-changed-path-classification.json\n`);
  assert.equal(validateArtifact(root, sha("b")).classificationSha256, digest);
  mkdirSync(path.join(root, "extra"));
  assert.throws(() => validateArtifact(root, sha("b")), /exactly|extra/i);
});

test("result contract rejects noncanonical nested, ordering, and outcome mutations without type errors", () => {
  const result = classifiedResult();
  const mutations = [
    (value) => { value.event.pullRequestNumber = 1; },
    (value) => { value.event.ref = "\u0000unsafe"; },
    (value) => { value.changes[0].newMode = null; },
    (value) => { value.changes[0].reasons = ["SELF_CHANGE", "feature-home"]; },
    (value) => { value.changes.push(structuredClone(value.changes[0])); },
    (value) => { value.owners[0].owner = "NOT_AN_OWNER"; },
    (value) => { value.owners[0].risks = ["P2_STANDARD", "P1_HIGH"]; },
    (value) => { value.owners[0].reasons = ["SELF_CHANGE", "feature-home"]; },
    (value) => { value.owners[0].paths = ["z.dart", "a.dart"]; },
    (value) => { value.affectedFeatures = ["home", "account"]; },
    (value) => { value.affectedBoundaries = ["UNKNOWN", "FEATURE"]; },
    (value) => { value.uncertainty = { isFullRequired: false, codes: ["SELF_CHANGE"], paths: [] }; },
    (value) => { value.summary.changed = 2; },
    (value) => { value.outcome = "FULL_REQUIRED"; },
    (value) => { value.owners = [null]; },
  ];
  for (const mutate of mutations) {
    const changed = structuredClone(result);
    mutate(changed);
    assert.throws(() => validateResult(changed), /mobile-changed-path-classifier:/);
  }
});

test("artifact verification recomputes canonical bytes and one summary function", () => {
  const root = mkdtempSync(path.join(tmpdir(), "mobile-classifier-artifact-"));
  const writeArtifact = (value, summary = summaryMarkdown(value), detachedDigest) => {
    const json = Buffer.from(JSON.stringify(value));
    const digest = detachedDigest ?? createHash("sha256").update(json).digest("hex");
    writeFileSync(path.join(root, "mobile-changed-path-classification.json"), json);
    writeFileSync(path.join(root, "mobile-changed-path-classification-summary.md"), summary);
    writeFileSync(path.join(root, "mobile-changed-path-classification.sha256"), `${digest}  mobile-changed-path-classification.json\n`);
  };
  const result = classifiedResult();
  writeArtifact(result);
  assert.equal(validateArtifact(root, sha("b")).result.outcome, "CLASSIFIED");

  writeFileSync(path.join(root, "mobile-changed-path-classification.json"), JSON.stringify(result, null, 2));
  const whitespaceDigest = createHash("sha256").update(readFileSync(path.join(root, "mobile-changed-path-classification.json"))).digest("hex");
  writeFileSync(path.join(root, "mobile-changed-path-classification.sha256"), `${whitespaceDigest}  mobile-changed-path-classification.json\n`);
  assert.throws(() => validateArtifact(root, sha("b")), /canonical|keys must be exact/i);

  const reordered = { repository: result.repository, schemaVersion: result.schemaVersion, artifactKind: result.artifactKind, event: result.event, comparison: result.comparison, classifier: result.classifier, changes: result.changes, owners: result.owners, affectedFeatures: result.affectedFeatures, affectedBoundaries: result.affectedBoundaries, requirements: result.requirements, isProvenDocsOnly: result.isProvenDocsOnly, uncertainty: result.uncertainty, summary: result.summary, outcome: result.outcome };
  const reorderedJson = Buffer.from(JSON.stringify(reordered));
  writeFileSync(path.join(root, "mobile-changed-path-classification.json"), reorderedJson);
  writeFileSync(path.join(root, "mobile-changed-path-classification.sha256"), `${createHash("sha256").update(reorderedJson).digest("hex")}  mobile-changed-path-classification.json\n`);
  assert.throws(() => validateArtifact(root, sha("b")), /canonical|keys must be exact/i);

  const nestedTamper = structuredClone(result);
  nestedTamper.owners[0].paths = [5];
  writeArtifact(nestedTamper);
  assert.throws(() => validateArtifact(root, sha("b")), /mobile-changed-path-classifier:/);

  writeArtifact(result, "# detached tamper\n");
  assert.throws(() => validateArtifact(root, sha("b")), /summary/i);

  writeArtifact(result, summaryMarkdown(result), "0".repeat(64));
  assert.throws(() => validateArtifact(root, sha("b")), /detached/i);
});

test("old and new immutable graphs union reverse consumers while external leaves stay safe", () => {
  const oldGraph = buildImmutableDartGraph({ files: {
    "apps/mobile/lib/features/home/consumer.dart": "import '../../shared.dart';",
    "apps/mobile/lib/shared.dart": "",
  } });
  const newGraph = buildImmutableDartGraph({ files: {
    "apps/mobile/lib/features/account/consumer.dart": "import '../../shared.dart'; import 'package:flutter/widgets.dart';",
    "apps/mobile/lib/shared.dart": "",
  } });
  assert.deepEqual(reverseConsumerFanout(oldGraph, ["apps/mobile/lib/shared.dart"]), ["apps/mobile/lib/features/home/consumer.dart"]);
  const union = classifyEntries([], validatePolicy(policy), { fanoutPaths: [...reverseConsumerFanout(oldGraph, ["apps/mobile/lib/shared.dart"]), ...reverseConsumerFanout(newGraph, ["apps/mobile/lib/shared.dart"])] });
  assert.deepEqual(union.affectedFeatures, ["account", "home"]);
  assert.equal(newGraph.uncertainty.length, 0);
  assert.equal(buildImmutableDartGraph({ files: { "apps/mobile/lib/a.dart": "import 'missing.dart';" } }).uncertainty[0].code, "GRAPH_UNCERTAINTY");
});

test("immutable Dart graph parses directives conservatively and follows every valid branch", () => {
  const graph = buildImmutableDartGraph({ files: {
    "apps/mobile/lib/library.dart": "part 'quoted.part.dart';",
    "apps/mobile/lib/quoted.part.dart": "part of 'library.dart';",
    "apps/mobile/lib/named.dart": "part 'named.part.dart';",
    "apps/mobile/lib/named.part.dart": "part of namedLibrary;",
    "apps/mobile/lib/conditional.dart": "import 'a.dart' if (dart.library.io) 'b.dart'; export 'c.dart' if (dart.library.html) 'd.dart';",
    "apps/mobile/lib/a.dart": "",
    "apps/mobile/lib/b.dart": "",
    "apps/mobile/lib/c.dart": "",
    "apps/mobile/lib/d.dart": "",
    "apps/mobile/lib/external.dart": "import 'dart:async'; import 'package:flutter/widgets.dart';",
    "apps/mobile/lib/comments.dart": "// import 'missing.dart';\nfinal text = \"export 'missing.dart';\";",
    "apps/mobile/lib/first.dart": "part 'ambiguous.part.dart';",
    "apps/mobile/lib/second.dart": "part 'ambiguous.part.dart';",
    "apps/mobile/lib/ambiguous.part.dart": "part of ambiguous;",
    "apps/mobile/lib/orphan.part.dart": "part of orphan;",
    "apps/mobile/lib/missing.dart": "import 'not-present.dart';",
    "apps/mobile/lib/escape.dart": "import '../../../../outside.dart';",
    "apps/mobile/lib/nonliteral.dart": "import dynamicUri;",
    "apps/mobile/lib/malformed.dart": "import 'a.dart' unexpected;",
    "apps/mobile/lib/empty.dart": "import '';",
    "apps/mobile/lib/no-semicolon.dart": "import 'a.dart'",
    "apps/mobile/lib/cycle-a.dart": "import 'cycle-b.dart';",
    "apps/mobile/lib/cycle-b.dart": "export 'cycle-a.dart';",
  } });

  assert.deepEqual(graph.graph.get("apps/mobile/lib/conditional.dart"), [
    "apps/mobile/lib/a.dart", "apps/mobile/lib/b.dart", "apps/mobile/lib/c.dart", "apps/mobile/lib/d.dart",
  ]);
  assert.deepEqual(graph.graph.get("apps/mobile/lib/quoted.part.dart"), ["apps/mobile/lib/library.dart"]);
  assert.deepEqual(graph.graph.get("apps/mobile/lib/named.part.dart"), ["apps/mobile/lib/named.dart"]);
  assert.deepEqual(graph.graph.get("apps/mobile/lib/external.dart"), []);
  assert.deepEqual(graph.graph.get("apps/mobile/lib/comments.dart"), []);
  assert.deepEqual(reverseConsumerFanout(graph, ["apps/mobile/lib/cycle-a.dart"]), ["apps/mobile/lib/cycle-b.dart"]);
  assert.deepEqual(graph.uncertainty.map((item) => item.path), [
    "apps/mobile/lib/ambiguous.part.dart",
    "apps/mobile/lib/empty.dart",
    "apps/mobile/lib/escape.dart",
    "apps/mobile/lib/malformed.dart",
    "apps/mobile/lib/missing.dart",
    "apps/mobile/lib/no-semicolon.dart",
    "apps/mobile/lib/nonliteral.dart",
    "apps/mobile/lib/orphan.part.dart",
  ]);
  assert.ok(graph.uncertainty.every((item) => item.code === "GRAPH_UNCERTAINTY"));
});

test("entry reasons are declaration-ordered before conservative result validation", () => {
  const self = { status: "MODIFIED", oldPath: "tools/ci/mobile-changed-path-classifier.mjs", newPath: "tools/ci/mobile-changed-path-classifier.mjs", oldMode: "100644", newMode: "100644", oldBlobSha: sha("a"), newBlobSha: sha("b"), isBinary: false, reasons: [] };
  const binary = { ...featureChange, isBinary: true };
  const classification = classifyEntries([binary, self], validatePolicy(policy));
  assert.deepEqual(classification.entries.map((entry) => entry.reasons), [
    ["feature-home", "BINARY"],
    ["self", "tools", "SELF_CHANGE"],
  ]);
  assert.equal(classification.outcome, "FULL_REQUIRED");
  assert.doesNotThrow(() => validateResult(buildResult({
    event: { name: "push", ref: "refs/heads/main", pullRequestNumber: null },
    comparison: { baseSha: sha("a"), headSha: sha("b"), mergeBaseSha: sha("a") },
    classifier: { sourceSha256: "c".repeat(64), policySha256: "d".repeat(64), workflowSha256: "e".repeat(64) },
    classification,
  })));
});

test("immutable Dart graph rejects normalized-key aliases and empty conditional expressions", () => {
  assert.throws(() => buildImmutableDartGraph({ files: {
    "apps/mobile/lib/a.dart": "",
    "apps\\mobile\\lib\\a.dart": "",
  } }), /duplicate normalized/i);
  const graph = buildImmutableDartGraph({ files: {
    "apps/mobile/lib/a.dart": "",
    "apps/mobile/lib/conditional.dart": "import 'a.dart' if () 'a.dart';",
  } });
  assert.deepEqual(graph.uncertainty, [{ path: "apps/mobile/lib/conditional.dart", code: "GRAPH_UNCERTAINTY" }]);
});

test("runner fails closed when workspace policy bytes differ from its trusted base blob", () => {
  const repository = mkdtempSync(path.join(tmpdir(), "mobile-classifier-git-"));
  const runTemp = path.join(repository, "runner-temp");
  const runGit = (...args) => execFileSync("git", ["-C", repository, ...args], { stdio: "ignore" });
  const write = (relative, value) => { const target = path.join(repository, relative); mkdirSync(path.dirname(target), { recursive: true }); writeFileSync(target, value); };
  const sourceBytes = readFileSync(new URL("./mobile-changed-path-classifier.mjs", import.meta.url));
  const policyBytes = readFileSync(new URL("./mobile-changed-path-policy.json", import.meta.url));
  runGit("init"); runGit("config", "user.email", "classifier@example.invalid"); runGit("config", "user.name", "Classifier Test");
  write("tools/ci/mobile-changed-path-classifier.mjs", sourceBytes);
  write("tools/ci/mobile-changed-path-policy.json", policyBytes);
  write("apps/mobile/pubspec.yaml", "name: easysubway_mobile\n");
  runGit("add", "."); runGit("commit", "-m", "base");
  const baseSha = execFileSync("git", ["-C", repository, "rev-parse", "HEAD"], { encoding: "utf8" }).trim();
  write("apps/mobile/lib/features/home/change.dart", "");
  runGit("add", "."); runGit("commit", "-m", "head");
  const headSha = execFileSync("git", ["-C", repository, "rev-parse", "HEAD"], { encoding: "utf8" }).trim();
  write("tools/ci/mobile-changed-path-policy.json", Buffer.concat([policyBytes, Buffer.from("\n")]));
  mkdirSync(runTemp);
  assert.throws(() => runClassifier({ event: "push", baseSha, headSha, eventRef: "refs/heads/main", pullRequestNumber: null }, { GITHUB_WORKSPACE: repository, RUNNER_TEMP: runTemp }), /workspace policy bytes.*base blob/i);
});

test("runner requires the exact head workflow blob", () => {
  const repository = mkdtempSync(path.join(tmpdir(), "mobile-classifier-workflow-"));
  const runTemp = path.join(repository, "runner-temp");
  const runGit = (...args) => execFileSync("git", ["-C", repository, ...args], { stdio: "ignore" });
  const write = (relative, value) => { const target = path.join(repository, relative); mkdirSync(path.dirname(target), { recursive: true }); writeFileSync(target, value); };
  runGit("init"); runGit("config", "user.email", "classifier@example.invalid"); runGit("config", "user.name", "Classifier Test");
  write("tools/ci/mobile-changed-path-classifier.mjs", readFileSync(new URL("./mobile-changed-path-classifier.mjs", import.meta.url)));
  write("tools/ci/mobile-changed-path-policy.json", readFileSync(new URL("./mobile-changed-path-policy.json", import.meta.url)));
  write("apps/mobile/pubspec.yaml", "name: easysubway_mobile\n");
  runGit("add", "."); runGit("commit", "-m", "base");
  const baseSha = execFileSync("git", ["-C", repository, "rev-parse", "HEAD"], { encoding: "utf8" }).trim();
  write("apps/mobile/lib/features/home/change.dart", "");
  runGit("add", "."); runGit("commit", "-m", "head");
  const headSha = execFileSync("git", ["-C", repository, "rev-parse", "HEAD"], { encoding: "utf8" }).trim();
  mkdirSync(runTemp);
  assert.throws(() => runClassifier({ event: "push", baseSha, headSha, eventRef: "refs/heads/main", pullRequestNumber: null }, { GITHUB_WORKSPACE: repository, RUNNER_TEMP: runTemp }), /required head workflow blob/i);
});

test("pull request fanout includes target-base consumers and emits closed requirement outputs", () => {
  const repository = mkdtempSync(path.join(tmpdir(), "mobile-classifier-pr-"));
  const runTemp = path.join(repository, "runner-temp"); const output = path.join(repository, "github-output");
  const runGit = (...args) => execFileSync("git", ["-C", repository, ...args], { stdio: "ignore" });
  const revision = (value) => execFileSync("git", ["-C", repository, "rev-parse", value], { encoding: "utf8" }).trim();
  const write = (relative, value) => { const target = path.join(repository, relative); mkdirSync(path.dirname(target), { recursive: true }); writeFileSync(target, value); };
  runGit("init"); runGit("config", "user.email", "classifier@example.invalid"); runGit("config", "user.name", "Classifier Test");
  write("tools/ci/mobile-changed-path-classifier.mjs", readFileSync(new URL("./mobile-changed-path-classifier.mjs", import.meta.url)));
  write("tools/ci/mobile-changed-path-policy.json", readFileSync(new URL("./mobile-changed-path-policy.json", import.meta.url)));
  write("apps/mobile/pubspec.yaml", "name: easysubway_mobile\n");
  write("apps/mobile/lib/shared.dart", "const shared = 1;\n");
  write(".github/workflows/mobile-changed-path-classifier.yml", "name: fixture\n");
  runGit("add", "."); runGit("commit", "-m", "merge base");
  const mergeBaseSha = revision("HEAD");
  runGit("checkout", "-b", "target");
  write("apps/mobile/lib/features/home_widget/native_consumer.dart", "import '../../shared.dart';\n");
  runGit("add", "."); runGit("commit", "-m", "target consumer");
  const baseSha = revision("HEAD");
  runGit("checkout", "-b", "pr-source", mergeBaseSha);
  write("apps/mobile/lib/shared.dart", "const shared = 2;\n");
  runGit("add", "."); runGit("commit", "-m", "head shared change");
  const headSha = revision("HEAD");
  runGit("update-ref", "refs/pull/7/head", headSha); runGit("remote", "add", "origin", repository);
  mkdirSync(runTemp);
  const run = runClassifier({ event: "pull_request", baseSha, headSha, eventRef: "refs/pull/7/merge", pullRequestNumber: 7 }, { GITHUB_WORKSPACE: repository, RUNNER_TEMP: runTemp, GITHUB_OUTPUT: output });
  assert.equal(run.result.comparison.mergeBaseSha, mergeBaseSha);
  assert.ok(run.result.affectedFeatures.includes("home_widget"));
  assert.equal(run.result.requirements.requiresNativeIntegration, true);
  assert.equal(run.result.requirements.requiresArchitectureGates, true);
  const lines = readFileSync(output, "utf8").trimEnd().split("\n");
  assert.deepEqual(lines.map((line) => line.slice(0, line.indexOf("="))), ["artifact-name", "classification-sha256", "head-sha", "outcome", "requires-full-host-tests", "requires-coverage", "requires-android-build", "requires-ios-compile", "requires-native-integration", "requires-golden", "requires-contract-staging", "requires-map-catalog-artifact-gate", "requires-architecture-gates", "requires-privacy-store-gate", "is-proven-docs-only"]);
  assert.ok(lines.every((line) => !line.includes("undefined")));
  assert.ok(lines.includes("requires-ios-compile=true"));
  assert.ok(!lines.some((line) => line.startsWith("requires-i-o-s-compile=")));
  assert.ok(lines.every((line) => !line.startsWith("requires-") || /=(true|false)$/u.test(line)));
});
