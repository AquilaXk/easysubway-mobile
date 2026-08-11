#!/usr/bin/env node

import { execFileSync } from "node:child_process";
import { lstatSync, readFileSync } from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";

const TEST_ROOT = "apps/mobile/test";
const GOLDEN_INVOCATION = /\bmatchesGoldenFile\s*\(/gu;
const LITERAL_GOLDEN_REFERENCE =
  /\bmatchesGoldenFile\s*\(\s*(['"])([^'"\r\n]+)\1\s*\)/gu;

const compare = (left, right) => (left < right ? -1 : left > right ? 1 : 0);

const findingKey = (finding) =>
  [
    finding.code,
    finding.path,
    finding.test ?? "",
    ...(finding.tests ?? []),
  ].join("\0");

const isGoldenAsset = (filePath) =>
  filePath.startsWith(`${TEST_ROOT}/`) &&
  filePath.includes("/goldens/") &&
  filePath.endsWith(".png");

const isDartTestSource = (filePath) =>
  filePath.startsWith(`${TEST_ROOT}/`) && filePath.endsWith(".dart");

const decodeUtf8 = (value, filePath) => {
  try {
    return typeof value === "string"
      ? value
      : new TextDecoder("utf-8", { fatal: true }).decode(value);
  } catch {
    throw new Error(`${filePath} must be UTF-8`);
  }
};

const resolveGoldenAsset = (testPath, literal) => {
  if (
    literal.length === 0 ||
    literal.startsWith("/") ||
    literal.includes("\\") ||
    literal.split("/").includes("..") ||
    !literal.endsWith(".png")
  ) {
    return null;
  }
  const resolved = path.posix.normalize(
    path.posix.join(path.posix.dirname(testPath), literal),
  );
  return resolved.startsWith(`${TEST_ROOT}/`) ? resolved : null;
};

export function analyzeGoldenParity(files) {
  if (!(files instanceof Map)) {
    throw new TypeError("files must be a Map of repository-relative paths");
  }

  const assets = [...files.keys()].filter(isGoldenAsset).sort(compare);
  const assetSet = new Set(assets);
  const references = [];
  const findings = [];

  for (const testPath of [...files.keys()].filter(isDartTestSource).sort(compare)) {
    const text = decodeUtf8(files.get(testPath), testPath);
    const invocationCount = [...text.matchAll(GOLDEN_INVOCATION)].length;
    const matches = [...text.matchAll(LITERAL_GOLDEN_REFERENCE)];
    if (invocationCount !== matches.length) {
      findings.push({ code: "AMBIGUOUS_GOLDEN_REFERENCE", path: testPath });
    }

    for (const match of matches) {
      const asset = resolveGoldenAsset(testPath, match[2]);
      if (asset === null) {
        findings.push({ code: "AMBIGUOUS_GOLDEN_REFERENCE", path: testPath });
        continue;
      }
      references.push({ test: testPath, asset });
    }
  }

  references.sort((left, right) =>
    compare(`${left.asset}\0${left.test}`, `${right.asset}\0${right.test}`),
  );

  const referencesByAsset = new Map();
  for (const reference of references) {
    const owners = referencesByAsset.get(reference.asset) ?? [];
    owners.push(reference.test);
    referencesByAsset.set(reference.asset, owners);
    if (!assetSet.has(reference.asset)) {
      findings.push({
        code: "MISSING_GOLDEN_ASSET",
        path: reference.asset,
        test: reference.test,
      });
    }
  }

  for (const [asset, tests] of referencesByAsset) {
    if (tests.length > 1) {
      findings.push({
        code: "DUPLICATE_GOLDEN_REFERENCE",
        path: asset,
        tests: [...new Set(tests)].sort(compare),
      });
    }
  }

  for (const asset of assets) {
    if (!referencesByAsset.has(asset)) {
      findings.push({ code: "ORPHAN_GOLDEN_ASSET", path: asset });
    }
  }

  if (references.length === 0) {
    findings.push({ code: "ZERO_GOLDEN_REFERENCE", path: TEST_ROOT });
  }

  findings.sort((left, right) => compare(findingKey(left), findingKey(right)));
  const tests = [...new Set(references.map(({ test }) => test))].sort(compare);
  return { tests, references, assets, findings };
}

export function readTrackedGoldenFiles(repositoryRoot) {
  const listed = execFileSync(
    "git",
    ["ls-files", "-z", "--", TEST_ROOT],
    { cwd: repositoryRoot },
  )
    .toString("utf8")
    .split("\0")
    .filter(Boolean)
    .filter((filePath) => isDartTestSource(filePath) || isGoldenAsset(filePath))
    .sort(compare);

  const files = new Map();
  for (const filePath of listed) {
    const absolutePath = path.join(repositoryRoot, ...filePath.split("/"));
    const status = lstatSync(absolutePath);
    if (!status.isFile() || status.isSymbolicLink()) {
      throw new Error(`${filePath} must be a regular tracked file`);
    }
    files.set(filePath, readFileSync(absolutePath));
  }
  return files;
}

function main() {
  const result = analyzeGoldenParity(readTrackedGoldenFiles(process.cwd()));
  process.stdout.write(
    `${JSON.stringify({
      schemaVersion: 1,
      artifactKind: "mobile-golden-parity-v1",
      ...result,
      outcome: result.findings.length === 0 ? "PASS" : "FAIL",
    })}\n`,
  );
  if (result.findings.length > 0) process.exitCode = 1;
}

const invokedPath = process.argv[1]
  ? pathToFileURL(path.resolve(process.argv[1])).href
  : null;
if (invokedPath === import.meta.url) main();
