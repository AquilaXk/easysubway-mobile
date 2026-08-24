#!/usr/bin/env node
import { createHash } from "node:crypto";
import { readFileSync, readdirSync } from "node:fs";
import path from "node:path";

import {
  buildImmutableDartSourceGraph,
  tokenizeDartStructure,
} from "./lib/mobile-dart-source-graph.mjs";

const POLICY_PATH = "tools/ci/mobile-cross-feature-boundary-policy.json";
const POLICY_KEYS = [
  "schemaVersion",
  "artifactKind",
  "repository",
  "inventoryPath",
  "inventorySha256",
  "featurePrefix",
  "forbiddenTargetSegments",
  "terminalZeroRequired",
];
const INVENTORY_KEYS = [
  "schemaVersion",
  "artifactKind",
  "repository",
  "featureRoots",
  "appCompositionPrefix",
  "sharedNeutralPrefixes",
  "generatedOwnerPrefix",
  "generatedAdapterPaths",
  "publicApis",
  "migrationExceptions",
];
const PUBLIC_API_KEYS = [
  "path",
  "ownerFeature",
  "classification",
  "contractKind",
  "terminalDisposition",
];
const EXCEPTION_KEYS = [
  "source",
  "target",
  "kind",
  "ownerIssue",
  "reason",
  "removalTrigger",
];
const FEATURE_PATH = /^apps\/mobile\/lib\/features\/([^/]+)\/(.+)$/u;
const DIGEST = /^[0-9a-f]{64}$/u;
const FEATURE_NAME = /^[a-z][a-z0-9_]*$/u;
const FORBIDDEN_SEGMENTS = ["application", "data", "infrastructure", "presentation"];
const compare = (left, right) => left < right ? -1 : left > right ? 1 : 0;
const edgeKey = (edge) => [edge.source, edge.target, edge.kind].join("\0");

function exactKeys(value, keys, label) {
  if (!value || typeof value !== "object" || Array.isArray(value) || JSON.stringify(Object.keys(value)) !== JSON.stringify(keys)) {
    throw new Error(`${label} identity is invalid`);
  }
}

function normalizedRepositoryPath(value, label) {
  if (
    typeof value !== "string"
    || value.length === 0
    || value.startsWith("/")
    || value.includes("\\")
    || value.split("/").some((piece) => piece === "" || piece === "." || piece === "..")
  ) {
    throw new Error(`${label} identity is invalid`);
  }
  return value;
}

function sortedUniqueStrings(value, label, predicate = () => true) {
  if (
    !Array.isArray(value)
    || value.some((entry) => typeof entry !== "string" || !predicate(entry))
    || JSON.stringify(value) !== JSON.stringify([...new Set(value)].sort(compare))
  ) {
    throw new Error(`${label} identity is invalid`);
  }
  return value;
}

function parsedJson(bytes, label) {
  try {
    return JSON.parse(Buffer.from(bytes).toString("utf8"));
  } catch {
    throw new Error(`${label} must be JSON`);
  }
}

export function parsePolicy(bytes) {
  const value = parsedJson(bytes, "cross-feature boundary policy");
  exactKeys(value, POLICY_KEYS, "cross-feature boundary policy");
  if (
    value.schemaVersion !== 2
    || value.artifactKind !== "mobile-cross-feature-boundary-policy-v2"
    || value.repository !== "AquilaXk/easysubway-mobile"
    || value.inventoryPath !== "tools/ci/mobile-cross-feature-boundary-inventory.json"
    || !DIGEST.test(value.inventorySha256)
    || value.featurePrefix !== "apps/mobile/lib/features/"
    || JSON.stringify(value.forbiddenTargetSegments) !== JSON.stringify(FORBIDDEN_SEGMENTS)
    || typeof value.terminalZeroRequired !== "boolean"
  ) {
    throw new Error("cross-feature boundary policy identity is invalid");
  }
  return value;
}

export function parseInventory(bytes) {
  const value = parsedJson(bytes, "cross-feature boundary inventory");
  exactKeys(value, INVENTORY_KEYS, "cross-feature boundary inventory");
  if (
    value.schemaVersion !== 1
    || value.artifactKind !== "mobile-cross-feature-boundary-inventory-v1"
    || value.repository !== "AquilaXk/easysubway-mobile"
    || value.appCompositionPrefix !== "apps/mobile/lib/app/"
    || value.generatedOwnerPrefix !== "apps/mobile/lib/generated/"
  ) {
    throw new Error("cross-feature boundary inventory identity is invalid");
  }
  sortedUniqueStrings(value.featureRoots, "cross-feature boundary inventory", (entry) => FEATURE_NAME.test(entry));
  if (value.featureRoots.length === 0) throw new Error("cross-feature boundary inventory identity is invalid");
  sortedUniqueStrings(value.sharedNeutralPrefixes, "cross-feature boundary inventory", (entry) => entry.endsWith("/") && normalizedRepositoryPath(entry.slice(0, -1), "shared prefix"));
  sortedUniqueStrings(value.generatedAdapterPaths, "cross-feature boundary inventory", (entry) => normalizedRepositoryPath(entry, "generated adapter"));
  if (!Array.isArray(value.publicApis) || !Array.isArray(value.migrationExceptions)) {
    throw new Error("cross-feature boundary inventory identity is invalid");
  }
  for (const entry of value.publicApis) {
    exactKeys(entry, PUBLIC_API_KEYS, "public API entry");
    const match = FEATURE_PATH.exec(normalizedRepositoryPath(entry.path, "public API path"));
    if (
      !match
      || match[1] !== entry.ownerFeature
      || !value.featureRoots.includes(entry.ownerFeature)
      || entry.classification !== "PUBLIC_API"
      || !["TYPED_DOMAIN", "TYPED_APPLICATION_PORT"].includes(entry.contractKind)
      || entry.terminalDisposition !== "RETAIN_TYPED_CONTRACT"
      || FORBIDDEN_SEGMENTS.includes(match[2].split("/")[0])
    ) {
      throw new Error("public API entry identity is invalid");
    }
  }
  if (JSON.stringify(value.publicApis.map((entry) => entry.path)) !== JSON.stringify(value.publicApis.map((entry) => entry.path).sort(compare))) {
    throw new Error("cross-feature boundary inventory identity is invalid");
  }
  for (const entry of value.migrationExceptions) {
    exactKeys(entry, EXCEPTION_KEYS, "migration exception");
    const source = FEATURE_PATH.exec(normalizedRepositoryPath(entry.source, "migration source"));
    const target = FEATURE_PATH.exec(normalizedRepositoryPath(entry.target, "migration target"));
    if (
      !source
      || !target
      || source[1] === target[1]
      || !value.featureRoots.includes(source[1])
      || !value.featureRoots.includes(target[1])
      || !["IMPORT", "EXPORT"].includes(entry.kind)
      || !Number.isInteger(entry.ownerIssue)
      || entry.ownerIssue < 1
      || typeof entry.reason !== "string"
      || entry.reason.trim().length < 8
      || typeof entry.removalTrigger !== "string"
      || entry.removalTrigger.trim().length < 8
    ) {
      throw new Error("migration exception identity is invalid");
    }
  }
  const exceptionKeys = value.migrationExceptions.map(edgeKey);
  if (JSON.stringify(exceptionKeys) !== JSON.stringify([...new Set(exceptionKeys)].sort(compare))) {
    throw new Error("cross-feature boundary inventory identity is invalid");
  }
  return value;
}

export function verifyInventoryBinding(policy, inventoryBytes) {
  const digest = createHash("sha256").update(inventoryBytes).digest("hex");
  if (digest !== policy.inventorySha256) throw new Error("cross-feature boundary inventory SHA-256 mismatch");
  return parseInventory(inventoryBytes);
}

function featurePath(file, policy) {
  return file.startsWith(policy.featurePrefix) ? FEATURE_PATH.exec(file) : null;
}

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

export function classifyDartSourceSets({
  productionFiles,
  testFixtureFiles,
  packageName = "easysubway_mobile",
}) {
  const productionPaths = Object.keys(productionFiles).sort(compare);
  const testFixturePaths = Object.keys(testFixtureFiles).sort(compare);
  for (const sourcePath of productionPaths) {
    if (!sourcePath.startsWith("apps/mobile/lib/") || !sourcePath.endsWith(".dart")) {
      throw new Error(`production source is outside apps/mobile/lib: ${sourcePath}`);
    }
  }
  for (const sourcePath of testFixturePaths) {
    if (!sourcePath.startsWith("apps/mobile/test/") || !sourcePath.endsWith(".dart")) {
      throw new Error(`test/fixture source is outside apps/mobile/test: ${sourcePath}`);
    }
    if (Object.hasOwn(productionFiles, sourcePath)) {
      throw new Error(`production and test/fixture source sets overlap: ${sourcePath}`);
    }
  }
  const graph = buildImmutableDartSourceGraph({
    files: { ...productionFiles, ...testFixtureFiles },
    packageName,
  });
  if (graph.uncertainty.length) throw new Error("source-set import classification uncertainty");
  const production = new Set(productionPaths);
  const testFixture = new Set(testFixturePaths);
  const classifiedEdges = graph.edges.filter((edge) => ["IMPORT", "EXPORT"].includes(edge.kind));
  return {
    productionEdges: classifiedEdges.filter((edge) => production.has(edge.source)),
    testFixtureEdges: classifiedEdges.filter((edge) => testFixture.has(edge.source)),
  };
}

function violation(code, edge) {
  return { code, source: edge.source, target: edge.target, kind: edge.kind };
}

const sequenceAt = (values, index, sequence) => sequence.every((value, offset) => values[index + offset] === value);
const registryName = (value) => /^(?:_)?(?:registry|services|handlers|factories)$/iu.test(value ?? "");

export function exactGlobalCompositionViolations(files, policy) {
  const violations = [];
  for (const file of Object.keys(files).sort(compare)) {
    if (!featurePath(file, policy)) continue;
    const tokens = tokenizeDartStructure(files[file]);
    const values = tokens.map((token) => token.value);
    const codes = new Set();
    let braceDepth = 0;

    for (let index = 0; index < values.length; index += 1) {
      const value = values[index];
      if (
        sequenceAt(values, index, ["GetIt", ".", "instance"])
        || sequenceAt(values, index, ["GetIt", ".", "I"])
        || sequenceAt(values, index, ["ServiceLocator", ".", "instance"])
        || sequenceAt(values, index, ["serviceLocator", ".", "get"])
      ) {
        codes.add("GLOBAL_SERVICE_LOCATOR");
      }
      if (
        sequenceAt(values, index, ["EventBus", "("])
        || (
          value === "eventBus"
          && values[index + 1] === "."
          && ["emit", "fire", "on", "subscribe"].includes(values[index + 2])
        )
      ) {
        codes.add("GLOBAL_EVENT_BUS");
      }
      if (
        braceDepth === 0
        && sequenceAt(values, index, ["GlobalKey", "<", "NavigatorState", ">", "("])
      ) {
        codes.add("GLOBAL_NAVIGATOR_KEY");
      }

      if (value === "static") {
        const statementEnd = values.indexOf(";", index + 1);
        if (statementEnd !== -1) {
          const assignment = values.indexOf("=", index + 1);
          if (assignment !== -1 && assignment < statementEnd) {
            const declaredName = tokens
              .slice(index + 1, assignment)
              .filter((token) => token.type === "identifier")
              .at(-1)?.value;
            if (["instance", "_instance"].includes(declaredName)) {
              codes.add("STATIC_SINGLETON");
            }
            if (registryName(declaredName)) codes.add("STATIC_REGISTRY");
          }
        }
      }

      if (braceDepth === 0 && ["final", "late", "var"].includes(value)) {
        const statementEnd = values.indexOf(";", index + 1);
        if (statementEnd !== -1) {
          const assignment = values.indexOf("=", index + 1);
          if (assignment !== -1 && assignment < statementEnd) {
            const declaredName = tokens
              .slice(index + 1, assignment)
              .filter((token) => token.type === "identifier")
              .at(-1)?.value;
            if (registryName(declaredName)) codes.add("TOP_LEVEL_REGISTRY");
          }
        }
      }

      if (value === "{") braceDepth += 1;
      if (value === "}") braceDepth = Math.max(0, braceDepth - 1);
    }

    for (const code of codes) {
      violations.push({ code, source: file, target: null, kind: "DECLARATION" });
    }
  }
  return violations;
}

export function auditCrossFeatureBoundaries({ files, policy, inventory, packageName = "easysubway_mobile" }) {
  if (policy.terminalZeroRequired && inventory.migrationExceptions.length > 0) {
    throw new Error("terminal zero forbids migration exceptions");
  }
  const graph = buildImmutableDartSourceGraph({ files, packageName });
  if (graph.uncertainty.length) throw new Error("cross-feature graph uncertainty");
  const publicApiByPath = new Map(inventory.publicApis.map((entry) => [entry.path, entry]));
  const publicPaths = new Set(publicApiByPath.keys());
  const generatedAdapters = new Set(inventory.generatedAdapterPaths);
  const exceptions = new Map(inventory.migrationExceptions.map((entry) => [edgeKey(entry), entry]));
  const matchedExceptions = new Set();
  const violations = exactGlobalCompositionViolations(files, policy);

  for (const file of Object.keys(files).sort(compare)) {
    const feature = featurePath(file, policy);
    if (feature && !inventory.featureRoots.includes(feature[1])) {
      violations.push({ code: "UNLISTED_FEATURE_ROOT", source: file, target: null, kind: "SOURCE" });
    }
  }
  for (const edge of graph.edges) {
    if (!edge.target || !["IMPORT", "EXPORT"].includes(edge.kind)) continue;
    const source = featurePath(edge.source, policy);
    const target = featurePath(edge.target, policy);
    if (source && edge.target.startsWith(inventory.generatedOwnerPrefix) && !generatedAdapters.has(edge.source)) {
      violations.push(violation("UNREVIEWED_GENERATED_CONSUMER", edge));
      continue;
    }
    if (
      publicPaths.has(edge.source)
      && target
      && source
      && source[1] === target[1]
      && edge.kind === "EXPORT"
      && policy.forbiddenTargetSegments.includes(target[2].split("/")[0])
    ) {
      violations.push(violation("PUBLIC_API_REEXPORTS_INTERNAL", edge));
      continue;
    }
    if (!source || !target || source[1] === target[1]) continue;
    if (edge.conditional) {
      violations.push(violation("CONDITIONAL_CROSS_FEATURE_EDGE", edge));
      continue;
    }
    if (publicPaths.has(edge.target)) continue;
    const key = edgeKey(edge);
    if (exceptions.has(key)) {
      matchedExceptions.add(key);
      continue;
    }
    const targetSegment = target[2].split("/")[0];
    violations.push(violation(
      policy.forbiddenTargetSegments.includes(targetSegment)
        ? "UNREVIEWED_CONCRETE_EDGE"
        : "UNLISTED_CROSS_FEATURE_API",
      edge,
    ));
  }
  for (const [key, entry] of exceptions) {
    if (!matchedExceptions.has(key)) violations.push(violation("STALE_MIGRATION_EXCEPTION", entry));
  }
  violations.sort((left, right) => compare([left.code, left.source, left.target ?? "", left.kind].join("\0"), [right.code, right.source, right.target ?? "", right.kind].join("\0")));
  const crossFeatureEdges = graph.edges.filter((edge) => {
    if (!edge.target || !["IMPORT", "EXPORT"].includes(edge.kind)) return false;
    const source = featurePath(edge.source, policy);
    const target = featurePath(edge.target, policy);
    return source && target && source[1] !== target[1];
  });
  const classifiedEdges = crossFeatureEdges.map((edge) => {
    const source = featurePath(edge.source, policy);
    const target = featurePath(edge.target, policy);
    const publicApi = publicApiByPath.get(edge.target);
    return {
      source: edge.source,
      target: edge.target,
      kind: edge.kind,
      sourceOwner: source[1],
      targetOwner: target[1],
      terminalDisposition: publicApi?.terminalDisposition ?? (exceptions.has(edgeKey(edge)) ? "MIGRATION_EXCEPTION" : null),
    };
  });
  return {
    graph,
    crossFeatureEdges,
    classifiedEdges,
    forbiddenEdges: forbiddenConcreteEdges(graph, policy),
    violations,
  };
}

function readTree(directory) {
  const files = {};
  const walk = (entry) => {
    for (const child of readdirSync(entry, { withFileTypes: true })) {
      const resolved = path.join(entry, child.name);
      if (child.isSymbolicLink()) throw new Error(`Dart source tree contains a symbolic link: ${resolved}`);
      if (child.isDirectory()) walk(resolved);
      else if (child.isFile() && resolved.endsWith(".dart")) {
        files[path.relative(process.cwd(), resolved).split(path.sep).join("/")] = readFileSync(resolved, "utf8");
      }
    }
  };
  walk(directory);
  return files;
}

export function runCli() {
  const policy = parsePolicy(readFileSync(POLICY_PATH));
  const inventoryBytes = readFileSync(policy.inventoryPath);
  const inventory = verifyInventoryBinding(policy, inventoryBytes);
  const productionFiles = readTree("apps/mobile/lib");
  const testFixtureFiles = readTree("apps/mobile/test");
  const sourceSets = classifyDartSourceSets({ productionFiles, testFixtureFiles });
  const result = auditCrossFeatureBoundaries({ files: productionFiles, policy, inventory });
  if (result.violations.length > 0) {
    throw new Error(`cross-feature boundary violation(s): ${result.violations.map((entry) => `${entry.code} ${entry.kind} ${entry.source} -> ${entry.target ?? "<none>"}`).join(", ")}`);
  }
  process.stdout.write(`mobile cross-feature boundary ratchet: PASS (crossFeature=${result.crossFeatureEdges.length}, classified=${result.classifiedEdges.length}, concrete=${result.forbiddenEdges.length}, exceptions=${inventory.migrationExceptions.length}, terminalZero=${policy.terminalZeroRequired}, productionImports=${sourceSets.productionEdges.length}, testFixtureImports=${sourceSets.testFixtureEdges.length})\n`);
}

if (import.meta.url === `file://${process.argv[1]}`) runCli();
