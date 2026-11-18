#!/usr/bin/env node

import { execFileSync } from "node:child_process";
import { lstatSync, readFileSync } from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";

const TEST_ROOT = "apps/mobile/test";
const GOLDEN_MATCHER = "matchesGoldenFile";

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

const isIdentifierStart = (character) =>
  character !== undefined && /[A-Za-z_$]/u.test(character);

const isIdentifierPart = (character) =>
  character !== undefined && /[A-Za-z0-9_$]/u.test(character);

const readDartString = (source, start, raw) => {
  const quoteStart = raw ? start + 1 : start;
  const quote = source[quoteStart];
  const triple = source.slice(quoteStart, quoteStart + 3) === quote.repeat(3);
  const delimiterLength = triple ? 3 : 1;
  const contentStart = quoteStart + delimiterLength;
  let cursor = contentStart;

  while (cursor < source.length) {
    if (source.slice(cursor, cursor + delimiterLength) === quote.repeat(delimiterLength)) {
      const content = source.slice(contentStart, cursor);
      const supported = raw || (!content.includes("\\") && !content.includes("$"));
      return {
        end: cursor + delimiterLength,
        token: { type: "string", value: supported ? content : null },
      };
    }
    if (!raw && source[cursor] === "\\") {
      cursor += 2;
      continue;
    }
    if (!triple && (source[cursor] === "\n" || source[cursor] === "\r")) {
      return { end: cursor, token: { type: "string", value: null } };
    }
    cursor += 1;
  }

  return { end: source.length, token: { type: "string", value: null } };
};

const tokenizeDart = (source) => {
  const tokens = [];
  let cursor = 0;

  while (cursor < source.length) {
    const character = source[cursor];
    const next = source[cursor + 1];

    if (/\s/u.test(character)) {
      cursor += 1;
      continue;
    }
    if (character === "/" && next === "/") {
      const lineEnd = source.indexOf("\n", cursor + 2);
      cursor = lineEnd === -1 ? source.length : lineEnd + 1;
      continue;
    }
    if (character === "/" && next === "*") {
      let depth = 1;
      cursor += 2;
      while (cursor < source.length && depth > 0) {
        if (source[cursor] === "/" && source[cursor + 1] === "*") {
          depth += 1;
          cursor += 2;
        } else if (source[cursor] === "*" && source[cursor + 1] === "/") {
          depth -= 1;
          cursor += 2;
        } else {
          cursor += 1;
        }
      }
      continue;
    }

    const rawString = character === "r" && (next === "'" || next === '"');
    if (rawString || character === "'" || character === '"') {
      const result = readDartString(source, cursor, rawString);
      tokens.push(result.token);
      cursor = result.end;
      continue;
    }
    if (isIdentifierStart(character)) {
      let end = cursor + 1;
      while (isIdentifierPart(source[end])) end += 1;
      tokens.push({ type: "identifier", value: source.slice(cursor, end) });
      cursor = end;
      continue;
    }
    if (/[0-9]/u.test(character)) {
      let end = cursor + 1;
      while (/[0-9A-Fa-f_xX]/u.test(source[end] ?? "")) end += 1;
      tokens.push({ type: "integer", value: source.slice(cursor, end) });
      cursor = end;
      continue;
    }

    tokens.push({ type: character, value: character });
    cursor += 1;
  }

  return tokens;
};

const parseDartInteger = (value) => {
  const normalized = value.replaceAll("_", "");
  if (!/^(?:0[xX][0-9A-Fa-f]+|[0-9]+)$/u.test(normalized)) return null;
  try {
    return BigInt(normalized).toString();
  } catch {
    return null;
  }
};

const parseGoldenInvocation = (tokens, start) => {
  let cursor = start + 2;
  const literalToken = tokens[cursor];
  if (literalToken?.type !== "string" || literalToken.value === null) return null;
  cursor += 1;

  let version = null;
  if (tokens[cursor]?.type === ",") {
    cursor += 1;
    if (tokens[cursor]?.type !== ")") {
      if (
        tokens[cursor]?.type !== "identifier" ||
        tokens[cursor]?.value !== "version" ||
        tokens[cursor + 1]?.type !== ":"
      ) {
        return null;
      }
      cursor += 2;
      let sign = "";
      if (tokens[cursor]?.type === "-" || tokens[cursor]?.type === "+") {
        sign = tokens[cursor].type === "-" ? "-" : "";
        cursor += 1;
      }
      if (tokens[cursor]?.type !== "integer") return null;
      const parsedVersion = parseDartInteger(tokens[cursor].value);
      if (parsedVersion === null) return null;
      version = `${sign}${parsedVersion}`;
      cursor += 1;
      if (tokens[cursor]?.type === ",") cursor += 1;
    }
  }
  if (tokens[cursor]?.type !== ")") return null;

  return { literal: literalToken.value, version };
};

const findGoldenInvocations = (source) => {
  const tokens = tokenizeDart(source);
  const invocations = [];
  for (let index = 0; index < tokens.length - 1; index += 1) {
    if (
      tokens[index].type === "identifier" &&
      tokens[index].value === GOLDEN_MATCHER &&
      tokens[index + 1].type === "("
    ) {
      invocations.push(parseGoldenInvocation(tokens, index));
    }
  }
  return invocations;
};

const applyGoldenVersion = (literal, version) => {
  if (version === null) return literal;
  const extension = path.posix.extname(literal);
  if (extension.length === 0) return null;
  return `${literal.split(extension).join("")}.${version}${extension}`;
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
    const invocations = findGoldenInvocations(text);

    for (const invocation of invocations) {
      const literal = invocation
        ? applyGoldenVersion(invocation.literal, invocation.version)
        : null;
      const asset = literal === null ? null : resolveGoldenAsset(testPath, literal);
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
