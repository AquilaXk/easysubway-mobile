import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { EventEmitter } from "node:events";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import test from "node:test";

import { buildImmutableDartSourceGraph, reverseConsumerFanout } from "./lib/mobile-dart-source-graph.mjs";
import {
  analyze,
  classifyRootImportGraph,
  loadImmutableDartTree,
  parseBaselineBytes,
  parsePolicyBytes,
  requestOwnerIssue,
  runCli,
  strictExternalJson,
  validateComparison,
  validateOwnerIssueResponse,
  verifyArtifactDirectory,
} from "./mobile-root-import-ratchet.mjs";

const POLICY_BYTES = readFileSync("tools/ci/mobile-root-import-policy.json");
const BASELINE_BYTES = readFileSync("tools/ci/mobile-root-import-baseline.json");
const POLICY = parsePolicyBytes(POLICY_BYTES);
const BASELINE = parseBaselineBytes(BASELINE_BYTES, POLICY);
const OPEN = (number) => {
  const owner = POLICY.owners.find((candidate) => candidate.number === number);
  return { number, title: owner.title, url: owner.url, state: "OPEN" };
};
const RESPONSE = (owner, extra = {}) => ({ statusCode: 200, redirected: false, body: Buffer.from(JSON.stringify({ number: owner.number, title: owner.title, html_url: owner.url, state: "open", ...extra })) });

test("shared graph parser handles directive-only Dart grammar and fails closed", () => {
  const files = {
    "apps/mobile/lib/features/home/library.dart": `
      @Deprecated('metadata')
      library sample.library;
      import '../../accessible_design.dart' deferred as tokens show Accessible;
      import 'default.dart' if (dart.library.io) 'io.dart' if (dart.library.html) 'web.dart';
      import 'package:easysubway_mobile/design_tokens.dart';
      import 'dart:async';
      import 'package:foreign/foreign.dart';
      export 'barrel.dart' hide Hidden;
      part 'part.dart';
      part 'named.dart';
      String quoted(String value) => '"\${value.replaceAll('"', '""')}"';
    `,
    "apps/mobile/lib/features/home/default.dart": "class Default {}",
    "apps/mobile/lib/features/home/generic.dart": "@GraphAnnotation<Map<String, List<int>>>.named() import '../../network_map.dart'; class Generic {}",
    "apps/mobile/lib/features/home/io.dart": "class Io {}",
    "apps/mobile/lib/features/home/web.dart": "class Web {}",
    "apps/mobile/lib/features/home/barrel.dart": "class Barrel {}",
    "apps/mobile/lib/features/home/part.dart": "part of 'library.dart';",
    "apps/mobile/lib/features/home/named.dart": "part of sample.library;",
    "apps/mobile/lib/accessible_design.dart": "class Accessible {}",
    "apps/mobile/lib/design_tokens.dart": "class Tokens {}",
    "apps/mobile/lib/network_map.dart": "class NetworkMap {}",
  };
  const graph = buildImmutableDartSourceGraph({ files });
  assert.deepEqual(graph.uncertainty, []);
  assert.deepEqual(graph.edges.filter((edge) => edge.source.endsWith("library.dart")).map((edge) => [edge.kind, edge.uri, edge.uriKind, edge.conditional]).sort((left, right) => `${left[0]}:${left[1]}`.localeCompare(`${right[0]}:${right[1]}`)), [
    ["EXPORT", "barrel.dart", "RELATIVE", false],
    ["IMPORT", "../../accessible_design.dart", "RELATIVE", false],
    ["IMPORT", "dart:async", "DART_EXTERNAL", false],
    ["IMPORT", "default.dart", "RELATIVE", false],
    ["IMPORT", "io.dart", "RELATIVE", true],
    ["IMPORT", "package:easysubway_mobile/design_tokens.dart", "OWN_PACKAGE", false],
    ["IMPORT", "package:foreign/foreign.dart", "OTHER_PACKAGE_EXTERNAL", false],
    ["IMPORT", "web.dart", "RELATIVE", true],
    ["PART", "named.dart", "RELATIVE", false],
    ["PART", "part.dart", "RELATIVE", false],
  ].sort((left, right) => `${left[0]}:${left[1]}`.localeCompare(`${right[0]}:${right[1]}`)));
  assert.ok(graph.edges.some((edge) => edge.source.endsWith("named.dart") && edge.kind === "PART_OF" && edge.uriKind === "NAMED_PART"));
  assert.ok(graph.edges.some((edge) => edge.source.endsWith("part.dart") && edge.kind === "PART_OF" && edge.target?.endsWith("library.dart")));
  assert.ok(graph.edges.some((edge) => edge.source.endsWith("generic.dart") && edge.target?.endsWith("network_map.dart")));
  assert.ok(reverseConsumerFanout(graph, ["apps/mobile/lib/features/home/barrel.dart"]).includes("apps/mobile/lib/features/home/library.dart"));

  for (const source of [
    "import '${name}.dart';",
    "import 'missing.dart';",
    "import 'package:easysubway_mobile/features/../design_tokens.dart';",
    "/* unterminated",
    "import 'default.dart' import 'io.dart';",
    "@Foo<int() import '../../network_map.dart';",
  ]) {
    const malformed = buildImmutableDartSourceGraph({ files: { ...files, "apps/mobile/lib/features/home/malformed.dart": source } });
    assert.ok(malformed.uncertainty.some((entry) => entry.path.endsWith("malformed.dart")), source);
  }
});

test("tracked policy, baseline, and current immutable graph match the reviewed ceiling", () => {
  assert.throws(() => parsePolicyBytes(Buffer.from(POLICY_BYTES.toString().replace("NO_INCREASE", "NO_INCREASED"))), /reviewed pin/);
  assert.throws(() => parseBaselineBytes(Buffer.from(BASELINE_BYTES.toString().replace("\"ownerIssue\":22", "\"ownerIssue\":23")), POLICY), /reviewed pin/);
  const commit = BASELINE.reviewedHeadSha;
  assert.notEqual(requireGitText(["rev-parse", "HEAD"]), commit);
  const files = loadImmutableDartTree(commit);
  const graph = buildImmutableDartSourceGraph({ files });
  const production = graph.sources.filter((source) => source.path.startsWith("apps/mobile/lib/"));
  const featureSources = production.filter((source) => source.path.startsWith("apps/mobile/lib/features/"));
  const directRoots = production.filter((source) => /^apps\/mobile\/lib\/[^/]+\.dart$/u.test(source.path));
  const directFeatureRootEdges = graph.edges.filter((edge) => edge.source.startsWith("apps/mobile/lib/features/") && /^apps\/mobile\/lib\/[^/]+\.dart$/u.test(edge.target ?? ""));
  const baseDecision = classifyRootImportGraph({ graph, files, policy: POLICY, baseline: BASELINE, baseForbiddenEdges: BASELINE.edges, ownerStatus: POLICY.owners.map((owner) => OPEN(owner.number)) });
  const decision = classifyRootImportGraph({ graph, files, policy: POLICY, baseline: BASELINE, baseForbiddenEdges: BASELINE.edges, baseWrapperFindings: baseDecision.wrapperFindings, ownerStatus: [OPEN(22)] });
  assert.deepEqual({ production: production.length, features: featureSources.length, roots: directRoots.length, directFeatureRootEdges: directFeatureRootEdges.length, neutralEdges: directFeatureRootEdges.length - decision.forbiddenEdges.length, forbidden: decision.forbiddenEdges.length }, { production: 240, features: 168, roots: 19, directFeatureRootEdges: 127, neutralEdges: 101, forbidden: 26 });
  assert.deepEqual(decision.forbiddenEdges.map(({ conditional, ...edge }) => (assert.equal(conditional, false), edge)), BASELINE.edges);
  assert.deepEqual(decision.reasons, []);
  assert.equal(decision.outcome, "PASS");
  assert.deepEqual(Object.fromEntries([18, 19, 20, 22].map((number) => [number, decision.currentEdges.filter((edge) => edge.ownerIssue === number).length])), { 18: 0, 19: 0, 20: 0, 22: 26 });
});

test("terminal predecessor handoff leaves only the open successor responsible for live root debt", () => {
  const routeSearch = POLICY.rootClassifications.find((entry) => entry.path === "apps/mobile/lib/route_search.dart");
  assert.deepEqual(routeSearch, {
    path: "apps/mobile/lib/route_search.dart",
    classification: "LEGACY_ROUTE_DELETE",
    ownerIssue: 22,
    removalTrigger: "MOBILE_22_ROOT_CLEANUP_ZERO",
  });
  assert.equal(BASELINE.edges.some((edge) => edge.ownerIssue === 18), false);

  const files = loadImmutableDartTree(BASELINE.reviewedHeadSha);
  const graph = buildImmutableDartSourceGraph({ files });
  const base = classifyRootImportGraph({ graph, files, policy: POLICY, baseline: BASELINE, baseForbiddenEdges: BASELINE.edges, ownerStatus: POLICY.owners.map((owner) => OPEN(owner.number)) });
  const accepted = classifyRootImportGraph({ graph, files, policy: POLICY, baseline: BASELINE, baseForbiddenEdges: BASELINE.edges, baseWrapperFindings: base.wrapperFindings, ownerStatus: [OPEN(22)] });
  assert.deepEqual(accepted.neededOwners, [22]);
  assert.deepEqual(accepted.reasons, []);
  assert.equal(accepted.outcome, "PASS");

  const successorEdge = BASELINE.edges.find((edge) => edge.ownerIssue === 22);
  const successorFiles = {
    [successorEdge.source]: `import '${successorEdge.uri}';`,
    [successorEdge.target]: "final class Target {}",
  };
  const successorGraph = buildImmutableDartSourceGraph({ files: successorFiles });
  const closedSuccessor = classifyRootImportGraph({ graph: successorGraph, files: successorFiles, policy: POLICY, baseline: BASELINE, baseForbiddenEdges: [successorEdge], ownerStatus: [{ ...OPEN(22), state: "CLOSED" }] });
  assert.deepEqual(closedSuccessor.reasons, ["OWNER_ISSUE_NOT_OPEN"]);
  const missingSuccessor = classifyRootImportGraph({ graph: successorGraph, files: successorFiles, policy: POLICY, baseline: BASELINE, baseForbiddenEdges: [successorEdge], ownerStatus: [] });
  assert.deepEqual(missingSuccessor.reasons, ["OWNER_ISSUE_NOT_OPEN"]);
});

test("Journey domain and data fixtures are classified as feature production", () => {
  const files = {
    "apps/mobile/lib/features/journey/data/journey_api_repository.dart": "final class JourneyApiRepository {}\n",
    "apps/mobile/lib/features/journey/domain/journey_repository.dart": "abstract interface class JourneyRepository {}\n",
  };
  const graph = buildImmutableDartSourceGraph({ files });
  const beforeJourneyRoot = { ...POLICY, featureRoots: POLICY.featureRoots.filter((root) => root !== "journey") };
  const before = classifyRootImportGraph({ graph, files, policy: beforeJourneyRoot, baseline: BASELINE });
  assert.deepEqual(before.importers, []);
  assert.deepEqual(before.uncertainty, [
    { path: "apps/mobile/lib/features/journey/data/journey_api_repository.dart", code: "IMPORTER_CLASSIFICATION_UNKNOWN" },
    { path: "apps/mobile/lib/features/journey/domain/journey_repository.dart", code: "IMPORTER_CLASSIFICATION_UNKNOWN" },
  ]);

  const after = classifyRootImportGraph({ graph, files, policy: POLICY, baseline: BASELINE });
  assert.deepEqual(after.importers.map(({ path: importerPath, importerClass }) => [importerPath, importerClass]), [
    ["apps/mobile/lib/features/journey/data/journey_api_repository.dart", "FEATURE_PRODUCTION"],
    ["apps/mobile/lib/features/journey/domain/journey_repository.dart", "FEATURE_PRODUCTION"],
  ]);
  assert.deepEqual(after.uncertainty, []);
});

test("immutable pubspec package identity binds self-package imports", async () => {
  const module = await import("./mobile-root-import-ratchet.mjs");
  assert.equal(typeof module.loadImmutableMobileTree, "function");
  const commit = "a".repeat(40);
  const pubspecObject = "b".repeat(40);
  const featureObject = "c".repeat(40);
  const rootObject = "d".repeat(40);
  const objects = new Map([
    [pubspecObject, "name: easysubway_mobile\nversion: 1.0.0\n"],
    [featureObject, "import 'package:easysubway_mobile/network_map.dart';"],
    [rootObject, "class NetworkMap {}"],
  ]);
  const gitApi = {
    bytes: (args) => {
      if (args[0] === "ls-tree") return Buffer.from([
        `100644 blob ${featureObject}\tapps/mobile/lib/features/home/home.dart`,
        `100644 blob ${rootObject}\tapps/mobile/lib/network_map.dart`,
        `100644 blob ${pubspecObject}\tapps/mobile/pubspec.yaml`,
        "",
      ].join("\0"));
      return Buffer.from(objects.get(args[2]) ?? "");
    },
    text: () => "",
  };
  const tree = module.loadImmutableMobileTree(commit, { gitApi });
  assert.equal(tree.packageName, "easysubway_mobile");
  const graph = buildImmutableDartSourceGraph({ files: tree.files, packageName: tree.packageName });
  assert.ok(graph.edges.some((edge) => edge.uriKind === "OWN_PACKAGE" && edge.target === "apps/mobile/lib/network_map.dart"));
  objects.set(pubspecObject, "name: renamed_mobile\n");
  const renamed = module.loadImmutableMobileTree(commit, { gitApi });
  assert.throws(() => buildImmutableDartSourceGraph({ files: renamed.files, packageName: renamed.packageName }), /package identity mismatch/);
  objects.set(pubspecObject, "name: first_mobile\nname: second_mobile\n");
  assert.throws(() => module.loadImmutableMobileTree(commit, { gitApi }), /missing or duplicated/);
  objects.set(pubspecObject, "name: Renamed-Mobile\n");
  assert.throws(() => module.loadImmutableMobileTree(commit, { gitApi }), /package name is invalid/);
});

test("Facility Report feature root is classified without graph uncertainty", () => {
  const files = {
    "apps/mobile/lib/features/facility_report/domain/facility_report_photo.dart":
      "final class FacilityReportPhoto {}\n",
  };
  const decision = classifyRootImportGraph({
    graph: buildImmutableDartSourceGraph({ files }),
    files,
    policy: POLICY,
    baseline: BASELINE,
    baseForbiddenEdges: [],
    ownerStatus: [],
  });

  assert.deepEqual(decision.uncertainty, []);
  assert.deepEqual(
    decision.importers.map(({ path: importerPath, importerClass }) => [
      importerPath,
      importerClass,
    ]),
    [
      [
        "apps/mobile/lib/features/facility_report/domain/facility_report_photo.dart",
        "FEATURE_PRODUCTION",
      ],
    ],
  );
});

function requireGitText(args) {
  return new TextDecoder().decode(execFileSync("git", args, { encoding: "buffer" })).trim();
}

test("no-increase decision distinguishes neutral, new, wrapper, removal, and reintroduction", () => {
  const neutralFiles = {
    "apps/mobile/lib/accessible_design.dart": "class Accessible {}",
    "apps/mobile/lib/features/home/home.dart": "import '../../accessible_design.dart';",
  };
  const neutralGraph = buildImmutableDartSourceGraph({ files: neutralFiles });
  assert.equal(classifyRootImportGraph({ graph: neutralGraph, files: neutralFiles, policy: POLICY, baseline: BASELINE, baseForbiddenEdges: [], ownerStatus: [] }).outcome, "PASS");

  const newFiles = {
    "apps/mobile/lib/network_map.dart": "class NetworkMap {}",
    "apps/mobile/lib/features/home/home.dart": "import '../../network_map.dart';",
  };
  const newGraph = buildImmutableDartSourceGraph({ files: newFiles });
  const created = classifyRootImportGraph({ graph: newGraph, files: newFiles, policy: POLICY, baseline: BASELINE, baseForbiddenEdges: [], ownerStatus: [OPEN(19)] });
  assert.deepEqual(created.reasons, ["NEW_FORBIDDEN_EDGE"]);

  const reviewedRoot = BASELINE.edges[0];
  const fallback = path.posix.join(path.posix.dirname(reviewedRoot.source), "fallback.dart");
  const conditionalFiles = {
    [reviewedRoot.target]: "class Root {}",
    [fallback]: "class Fallback {}",
    [reviewedRoot.source]: `import 'fallback.dart' if (dart.library.io) '${reviewedRoot.uri}';`,
  };
  const conditional = classifyRootImportGraph({ graph: buildImmutableDartSourceGraph({ files: conditionalFiles }), files: conditionalFiles, policy: POLICY, baseline: BASELINE, baseForbiddenEdges: [reviewedRoot], ownerStatus: [OPEN(22)] });
  assert.equal(conditional.currentEdges[0].conditional, true);
  assert.deepEqual(conditional.newEdges, conditional.currentEdges);

  const wrapperFiles = {
    ...neutralFiles,
    "apps/mobile/lib/network_map.dart": "class NetworkMap {}",
    "apps/mobile/lib/accessible_design.dart": "import 'network_map.dart'; class Accessible {}",
  };
  const wrapped = classifyRootImportGraph({ graph: buildImmutableDartSourceGraph({ files: wrapperFiles }), files: wrapperFiles, policy: POLICY, baseline: BASELINE, baseForbiddenEdges: [], ownerStatus: [] });
  assert.ok(wrapped.reasons.includes("FORBIDDEN_WRAPPER_OR_BARREL"));
  assert.deepEqual(wrapped.wrapperFindings.map((finding) => finding.path), [
    ["apps/mobile/lib/accessible_design.dart", "apps/mobile/lib/network_map.dart"],
    ["apps/mobile/lib/features/home/home.dart", "apps/mobile/lib/accessible_design.dart", "apps/mobile/lib/network_map.dart"],
  ]);

  const removed = classifyRootImportGraph({ graph: buildImmutableDartSourceGraph({ files: neutralFiles }), files: neutralFiles, policy: POLICY, baseline: BASELINE, baseForbiddenEdges: [], ownerStatus: [] });
  assert.equal(removed.outcome, "PASS");
  assert.equal(removed.removedEdges.length, 26);

  const reviewed = BASELINE.edges[0];
  const reintroducedFiles = { [reviewed.source]: `import '${reviewed.uri}';`, [reviewed.target]: "class Target {}" };
  const reintroduced = classifyRootImportGraph({ graph: buildImmutableDartSourceGraph({ files: reintroducedFiles }), files: reintroducedFiles, policy: POLICY, baseline: BASELINE, baseForbiddenEdges: [], ownerStatus: [OPEN(reviewed.ownerIssue)] });
  assert.deepEqual(reintroduced.reasons, ["NEW_FORBIDDEN_EDGE"]);
});

test("canonical generated prefix requires the generated header", () => {
  const canonicalHeader = "// GENERATED CODE - DO NOT MODIFY BY HAND";
  const generatedFiles = {
    "apps/mobile/lib/generated/journey_v3/journey_v3_contract.dart": `${canonicalHeader}\nexport 'journey_v3_models.dart';\n`,
    "apps/mobile/lib/generated/journey_v3/journey_v3_models.dart": `${canonicalHeader}\nfinal class JourneyV3Model {}\n`,
    "apps/mobile/lib/core/database/catalog/catalog_database.g.dart": `${canonicalHeader}\nfinal class ExistingGeneratedModel {}\n`,
  };
  const generated = classifyRootImportGraph({
    graph: buildImmutableDartSourceGraph({ files: generatedFiles }),
    files: generatedFiles,
    policy: POLICY,
    baseline: BASELINE,
    baseForbiddenEdges: [],
    ownerStatus: [],
  });
  assert.deepEqual(generated.uncertainty, []);
  assert.deepEqual(generated.importers.map(({ path: importerPath, importerClass }) => [importerPath, importerClass]), [
    ["apps/mobile/lib/core/database/catalog/catalog_database.g.dart", "GENERATED"],
    ["apps/mobile/lib/generated/journey_v3/journey_v3_contract.dart", "GENERATED"],
    ["apps/mobile/lib/generated/journey_v3/journey_v3_models.dart", "GENERATED"],
  ]);

  for (const files of [
    { "apps/mobile/lib/generated/journey_v3/handwritten.dart": "final class Handwritten {}\n" },
    { "apps/mobile/lib/unreviewed/header_only.dart": `${canonicalHeader}\nfinal class HeaderOnly {}\n` },
  ]) {
    const decision = classifyRootImportGraph({
      graph: buildImmutableDartSourceGraph({ files }),
      files,
      policy: POLICY,
      baseline: BASELINE,
      baseForbiddenEdges: [],
      ownerStatus: [],
    });
    assert.deepEqual(decision.reasons, ["GRAPH_UNCERTAINTY"]);
    assert.equal(decision.uncertainty[0].code, "IMPORTER_CLASSIFICATION_UNKNOWN");
  }
});

test("wrapper discovery emits one bounded canonical witness per origin and target", () => {
  const files = {
    "apps/mobile/lib/network_map.dart": "class NetworkMap {}",
    "apps/mobile/lib/features/home/origin.dart": "import 'left.dart'; import 'right.dart';",
    "apps/mobile/lib/features/home/left.dart": "import 'join.dart';",
    "apps/mobile/lib/features/home/right.dart": "import 'join.dart';",
    "apps/mobile/lib/features/home/join.dart": "import '../../network_map.dart';",
  };
  const decision = classifyRootImportGraph({
    graph: buildImmutableDartSourceGraph({ files }),
    files,
    policy: POLICY,
    baseline: BASELINE,
    baseForbiddenEdges: [],
    ownerStatus: [OPEN(19)],
  });
  const originFindings = decision.wrapperFindings.filter((finding) => finding.source.endsWith("origin.dart") && finding.target.endsWith("network_map.dart"));
  assert.deepEqual(originFindings.map((finding) => finding.path), [[
    "apps/mobile/lib/features/home/origin.dart",
    "apps/mobile/lib/features/home/left.dart",
    "apps/mobile/lib/features/home/join.dart",
    "apps/mobile/lib/network_map.dart",
  ]]);
  const rightOnly = { ...files, "apps/mobile/lib/features/home/origin.dart": "import 'right.dart';" };
  const afterRemoval = classifyRootImportGraph({
    graph: buildImmutableDartSourceGraph({ files: rightOnly }),
    files: rightOnly,
    policy: POLICY,
    baseline: BASELINE,
    baseForbiddenEdges: [],
    baseWrapperFindings: decision.wrapperFindings,
    ownerStatus: [OPEN(19)],
  });
  assert.equal(afterRemoval.newWrapperFindings.filter((finding) => finding.source.endsWith("origin.dart") && finding.target.endsWith("network_map.dart")).length, 0);
});

test("owner issue evidence is strict and bounded retry never leaks credentials", async () => {
  const owner = POLICY.owners.find((candidate) => candidate.number === 22);
  assert.deepEqual(validateOwnerIssueResponse(RESPONSE(owner, { labels: [] }), owner), OPEN(owner.number));
  assert.throws(() => validateOwnerIssueResponse({ statusCode: 200, body: Buffer.from(`{"number":${owner.number},"number":${owner.number},"title":${JSON.stringify(owner.title)},"html_url":${JSON.stringify(owner.url)},"state":"open"}`) }, owner), /duplicate key/);
  assert.equal(validateOwnerIssueResponse(RESPONSE(owner, { state: "closed" }), owner).state, "CLOSED");
  const reviewed = BASELINE.edges.find((edge) => edge.ownerIssue === owner.number);
  const files = { [reviewed.source]: `import '${reviewed.uri}';`, [reviewed.target]: "class Target {}" };
  const closedDecision = classifyRootImportGraph({ graph: buildImmutableDartSourceGraph({ files }), files, policy: POLICY, baseline: BASELINE, baseForbiddenEdges: [reviewed], ownerStatus: [{ ...OPEN(owner.number), state: "CLOSED" }] });
  assert.deepEqual(closedDecision.reasons, ["OWNER_ISSUE_NOT_OPEN"]);
  assert.throws(() => strictExternalJson(Buffer.from("\ufeff{}"), "proof"), /forbidden bytes/);
  await assert.rejects(requestOwnerIssue(owner, { token: "" }), /OWNER_ISSUE_TOKEN/);

  const requests = [];
  const delays = [];
  const requestImpl = fakeRequests([
    { statusCode: 500, headers: {}, body: "ignored-secret" },
    { statusCode: 200, headers: {}, body: JSON.stringify({ number: owner.number, title: owner.title, html_url: owner.url, state: "open" }) },
  ], requests);
  const response = await requestOwnerIssue(owner, { token: "owner-token", requestImpl, sleeper: async (delay) => delays.push(delay) });
  assert.deepEqual(delays, [1000]);
  assert.equal(requests.length, 2);
  assert.equal(requests[0].headers.Authorization, "Bearer owner-token");
  assert.equal(validateOwnerIssueResponse(response, owner).number, owner.number);

  await assert.rejects(requestOwnerIssue(owner, { token: "secret", requestImpl: fakeRequests([{ statusCode: 200, headers: {}, body: "oversize" }]), maxBytes: 2 }), (error) => !error.message.includes("secret") && /maximum bytes/.test(error.message));
  await assert.rejects(requestOwnerIssue(owner, { token: "secret", requestImpl: fakeRequests([{ neverRespond: true }]), timeoutMs: 5 }), /timed out/);
});

function fakeRequests(responses, seen = []) {
  return (options, callback) => {
    seen.push(options);
    const requestEmitter = new EventEmitter();
    requestEmitter.destroy = (error) => queueMicrotask(() => requestEmitter.emit("error", error));
    requestEmitter.end = () => queueMicrotask(() => {
      const item = responses.shift();
      if (!item || item.neverRespond) return;
      const response = new EventEmitter();
      response.statusCode = item.statusCode;
      response.headers = item.headers ?? {};
      callback(response);
      if (item.body) response.emit("data", Buffer.from(item.body));
      response.emit("end");
    });
    return requestEmitter;
  };
}

test("event identity closes PR, push, and manual relationships", () => {
  const base = "a".repeat(40);
  const head = "b".repeat(40);
  const tested = "c".repeat(40);
  const gitApi = {
    bytes: () => Buffer.alloc(0),
    text: (args) => args[0] === "rev-parse" ? tested : base,
  };
  assert.deepEqual(validateComparison({ event: "pull_request", eventRef: "refs/pull/49/merge", pullRequestNumber: "49", baseSha: base, headSha: head, testedMergeSha: tested }, { gitApi }), { event: "pull_request", eventMode: "PULL_REQUEST", eventRef: "refs/pull/49/merge", pullRequestNumber: 49, baseSha: base, pullRequestHeadSha: head, headSha: head, testedMergeSha: tested, mergeBaseSha: base, range: `${base}..${tested}` });
  assert.equal(validateComparison({ event: "push", eventRef: "refs/heads/main", pullRequestNumber: "none", baseSha: base, headSha: tested, testedMergeSha: tested }, { gitApi }).range, `${base}..${tested}`);
  const manualGit = { bytes: () => Buffer.alloc(0), text: (args) => args[0] === "rev-parse" ? tested : tested };
  assert.equal(validateComparison({ event: "workflow_dispatch", eventRef: "refs/heads/main", pullRequestNumber: "none", baseSha: tested, headSha: tested, testedMergeSha: tested }, { gitApi: manualGit }).range, null);
  assert.throws(() => validateComparison({ event: "pull_request", eventRef: "refs/pull/49/merge", pullRequestNumber: "49", baseSha: base, headSha: head, testedMergeSha: tested }, { gitApi: { bytes: () => Buffer.alloc(0), text: (args) => args[0] === "rev-parse" ? head : base } }), /EVENT_IDENTITY_MISMATCH/);
});

test("analyze writes exact evidence and verdict recomputes coordinated mutations", async (t) => {
  const root = mkdtempSync(path.join(tmpdir(), "mobile-root-import-49-"));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const head = requireGitText(["rev-parse", "HEAD"]);
  const options = { event: "workflow_dispatch", eventRef: "refs/heads/main", pullRequestNumber: "none", baseSha: head, headSha: head, testedMergeSha: head };
  const result = await analyze(options, { environment: { RUNNER_TEMP: root, OWNER_ISSUE_TOKEN: "test-token" }, requestOwnerIssueFn: async (owner) => RESPONSE(owner) });
  assert.equal(result.outcome, "PASS");
  const directory = path.join(root, "mobile-root-import-ratchet");
  assert.equal(verifyArtifactDirectory(directory).outcome, "PASS");
  const resultPath = path.join(directory, "mobile-root-import-result.json");
  const inventoryPath = path.join(directory, "mobile-root-import-inventory.json");
  const changed = JSON.parse(readFileSync(resultPath));
  changed.outcome = "FAIL";
  changed.reasons = ["NEW_FORBIDDEN_EDGE"];
  const changedBytes = Buffer.from(`${JSON.stringify(changed)}\n`);
  writeFileSync(resultPath, changedBytes);
  writeFileSync(path.join(directory, "mobile-root-import-summary.md"), "forged\n");
  writeFileSync(path.join(directory, "mobile-root-import.sha256"), `${sha(readFileSync(inventoryPath))}  mobile-root-import-inventory.json\n${sha(changedBytes)}  mobile-root-import-result.json\n`);
  assert.throws(() => verifyArtifactDirectory(directory), /ARTIFACT_MISMATCH/);
});

function sha(bytes) {
  return createHash("sha256").update(bytes).digest("hex");
}

test("CLI ordering and Phase A2 trusted workflow wiring fail closed", async () => {
  let analyzed = 0;
  await assert.rejects(runCli(["analyze", "--event", "push"], { analyzeFn: async () => { analyzed += 1; }, environment: {} }), (error) => error.exitCode === 2);
  assert.equal(analyzed, 0);
  let verified = 0;
  await assert.rejects(runCli(["verdict", "--analysis-outcome", "failure", "--upload-outcome", "success"], { verifyFn: () => { verified += 1; }, environment: { RUNNER_TEMP: "/tmp" } }), /analysis or upload failed/);
  assert.equal(verified, 0);
  const workflow = readFileSync(".github/workflows/ci.yml", "utf8");
  assert.equal(workflow.match(/tools\/ci\/mobile-root-import-ratchet\.test\.mjs/gu)?.length, 1);
  const stage = [
    "      - name: Stage trusted mobile root import ratchet",
    "        if: always()",
    "        env:",
    "          ROOT_IMPORT_TRUSTED_BASE_SHA: ${{ github.event.pull_request.base.sha || github.event.before || github.sha }}",
    "          ROOT_IMPORT_TRUSTED_ROOT: ${{ runner.temp }}/mobile-root-import-ratchet-trusted-${{ github.run_id }}-${{ github.run_attempt }}",
    "        run: |",
    "          umask 077",
    "          if [[ ! \"$ROOT_IMPORT_TRUSTED_BASE_SHA\" =~ ^[0-9a-f]{40}$ ]]; then",
    "            echo \"trusted root import base SHA is invalid\" >&2",
    "            exit 1",
    "          fi",
    "          if [[ -e \"$ROOT_IMPORT_TRUSTED_ROOT\" || -L \"$ROOT_IMPORT_TRUSTED_ROOT\" ]]; then",
    "            echo \"trusted root import stage path already exists\" >&2",
    "            exit 1",
    "          fi",
    "          git cat-file -e \"${ROOT_IMPORT_TRUSTED_BASE_SHA}^{commit}\"",
    "          mkdir \"$ROOT_IMPORT_TRUSTED_ROOT\"",
    "          mkdir \"$ROOT_IMPORT_TRUSTED_ROOT/tools\"",
    "          mkdir \"$ROOT_IMPORT_TRUSTED_ROOT/tools/ci\"",
    "          mkdir \"$ROOT_IMPORT_TRUSTED_ROOT/tools/ci/lib\"",
    "          for source in \\",
    "            tools/ci/mobile-root-import-ratchet.mjs \\",
    "            tools/ci/lib/mobile-dart-source-graph.mjs \\",
    "            tools/ci/mobile-root-import-policy.json \\",
    "            tools/ci/mobile-root-import-baseline.json",
    "          do",
    "            IFS=$'\\t' read -r metadata resolved_path <<< \"$(git ls-tree \"$ROOT_IMPORT_TRUSTED_BASE_SHA\" -- \"$source\")\"",
    "            if [[ ! \"$metadata\" =~ ^100644\\ blob\\ [0-9a-f]{40}$ || \"$resolved_path\" != \"$source\" ]]; then",
    "              echo \"trusted root import blob identity is invalid\" >&2",
    "              exit 1",
    "            fi",
    "            git show \"${ROOT_IMPORT_TRUSTED_BASE_SHA}:${source}\" > \"${ROOT_IMPORT_TRUSTED_ROOT}/${source}\"",
    "          done",
  ].join("\n");
  const analyzeBlock = [
    "      - name: Analyze mobile root import ratchet",
    "        id: root_import_ratchet_analyze",
    "        if: always()",
    "        env:",
    "          OWNER_ISSUE_TOKEN: ${{ secrets.GITHUB_TOKEN }}",
    "          ROOT_IMPORT_TRUSTED_RUNNER: ${{ runner.temp }}/mobile-root-import-ratchet-trusted-${{ github.run_id }}-${{ github.run_attempt }}/tools/ci/mobile-root-import-ratchet.mjs",
    "          ROOT_IMPORT_EVENT: ${{ github.event_name }}",
    "          ROOT_IMPORT_BASE_SHA: ${{ github.event.pull_request.base.sha || github.event.before || github.sha }}",
    "          ROOT_IMPORT_HEAD_SHA: ${{ github.event.pull_request.head.sha || github.sha }}",
    "          ROOT_IMPORT_TESTED_MERGE_SHA: ${{ github.sha }}",
    "          ROOT_IMPORT_EVENT_REF: ${{ github.ref }}",
    "          ROOT_IMPORT_PR_NUMBER: ${{ github.event.pull_request.number || 'none' }}",
    "        run: |",
    "          node \"$ROOT_IMPORT_TRUSTED_RUNNER\" analyze \\",
    "            --event \"$ROOT_IMPORT_EVENT\" \\",
    "            --base-sha \"$ROOT_IMPORT_BASE_SHA\" \\",
    "            --head-sha \"$ROOT_IMPORT_HEAD_SHA\" \\",
    "            --tested-merge-sha \"$ROOT_IMPORT_TESTED_MERGE_SHA\" \\",
    "            --event-ref \"$ROOT_IMPORT_EVENT_REF\" \\",
    "            --pull-request-number \"$ROOT_IMPORT_PR_NUMBER\"",
  ].join("\n");
  const upload = [
    "      - name: Upload mobile root import ratchet evidence",
    "        id: root_import_ratchet_upload",
    "        if: always()",
    "        uses: actions/upload-artifact@65462800fd760344b1a7b4382951275a0abb4808",
    "        with:",
    "          name: mobile-root-import-ratchet-${{ github.event.pull_request.head.sha || github.sha }}",
    "          path: ${{ runner.temp }}/mobile-root-import-ratchet",
    "          retention-days: 5",
    "          if-no-files-found: error",
  ].join("\n");
  const verdict = [
    "      - name: Enforce mobile root import ratchet verdict",
    "        if: always()",
    "        env:",
    "          ROOT_IMPORT_TRUSTED_RUNNER: ${{ runner.temp }}/mobile-root-import-ratchet-trusted-${{ github.run_id }}-${{ github.run_attempt }}/tools/ci/mobile-root-import-ratchet.mjs",
    "        run: |",
    "          node \"$ROOT_IMPORT_TRUSTED_RUNNER\" verdict \\",
    "            --analysis-outcome \"${{ steps.root_import_ratchet_analyze.outcome }}\" \\",
    "            --upload-outcome \"${{ steps.root_import_ratchet_upload.outcome }}\"",
    "          cat \"$RUNNER_TEMP/mobile-root-import-ratchet/mobile-root-import-summary.md\" >> \"$GITHUB_STEP_SUMMARY\"",
  ].join("\n");
  for (const block of [stage, analyzeBlock, upload, verdict]) {
    assert.equal(workflow.includes(block), true, block);
    const start = workflow.indexOf(block);
    const end = workflow.indexOf("\n      - name:", start + block.length);
    const actualStep = workflow.slice(start, end === -1 ? undefined : end);
    assert.equal(actualStep.includes("continue-on-error"), false);
  }
  const setupNode = workflow.indexOf("      - name: Set up Node");
  const stageStart = workflow.indexOf(stage);
  const firstRepositoryCommand = workflow.indexOf("      - name: Fetch exact generic mobile consumer bundle");
  assert.equal(setupNode >= 0 && setupNode < stageStart && stageStart < firstRepositoryCommand, true);
});
