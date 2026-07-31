import { createHash, randomUUID } from "node:crypto";
import { mkdir, rename, rm, writeFile } from "node:fs/promises";
import path from "node:path";
import { codepointCompare } from "../lib/codepoint-compare.mjs";

export const CONTRACT_VERSION = "mobile-datapack-contract-v1";
const SHA256 = /^[0-9a-f]{64}$/;
const GIT_SHA = /^[0-9a-f]{40}$/;
const SAFE_RELATIVE_PATH = /^[a-zA-Z0-9][a-zA-Z0-9._/-]*$/;
const REPOSITORY = /^[A-Za-z0-9][A-Za-z0-9_.-]*\/[A-Za-z0-9][A-Za-z0-9_.-]*$/;
const ISSUE_REF = /^[A-Za-z0-9][A-Za-z0-9_.-]*\/[A-Za-z0-9][A-Za-z0-9_.-]*#\d+$/;

export function canonicalJson(value) {
  if (value === null || typeof value === "string" || typeof value === "boolean") {
    return JSON.stringify(value);
  }
  if (typeof value === "number") {
    if (!Number.isFinite(value) || Math.abs(value) > Number.MAX_SAFE_INTEGER) throw new Error("canonical JSON requires finite numbers within safe magnitude");
    return JSON.stringify(value);
  }
  if (Array.isArray(value)) {
    const keys = Object.keys(value);
    if (keys.length !== value.length || keys.some((key, index) => key !== String(index))) {
      throw new Error("canonical JSON requires dense arrays");
    }
    return `[${Array.from({ length: value.length }, (_, index) => canonicalJson(value[index])).join(",")}]`;
  }
  if (!value || typeof value !== "object" || Object.getPrototypeOf(value) !== Object.prototype || Reflect.ownKeys(value).length !== Object.keys(value).length) {
    throw new Error("canonical JSON requires plain JSON records");
  }
  return `{${Object.keys(value).sort().map((key) => `${JSON.stringify(key)}:${canonicalJson(value[key])}`).join(",")}}`;
}

export function sha256(value) {
  return createHash("sha256").update(value).digest("hex");
}

function requireObject(value, label) {
  if (!value || Array.isArray(value) || typeof value !== "object") throw new Error(`${label} must be an object`);
  return value;
}

function requireSha256(value, label) {
  if (typeof value !== "string" || value.length !== 64 || !SHA256.test(value)) throw new Error(`${label} must be a lowercase SHA-256`);
  return value;
}

function requirePositiveInteger(value, label) {
  if (!Number.isSafeInteger(value) || value < 1) throw new Error(`${label} must be a positive integer`);
  return value;
}

function requireSafePath(value, label) {
  if (typeof value !== "string" || value.endsWith("/") || !SAFE_RELATIVE_PATH.test(value) || path.posix.normalize(value) !== value) throw new Error(`${label} must be a canonical POSIX relative path`);
  return value;
}

function requireExactKeys(value, keys, label) {
  if (Object.keys(value).length !== keys.length || Object.keys(value).some((key) => !keys.includes(key))) {
    throw new Error(`${label} contains unknown or missing fields`);
  }
}

function requireFullMatch(value, expression, label) {
  const match = typeof value === "string" ? value.match(expression) : null;
  if (!match || match[0].length !== value.length) throw new Error(`${label} has an invalid format`);
  return value;
}

function validatePack(pack, label) {
  requireObject(pack, label);
  requireExactKeys(pack, ["id", "path", "sha256"], label);
  if (typeof pack.id !== "string" || !pack.id) throw new Error(`${label}.id is required`);
  const packPath = requireSafePath(pack.path, `${label}.path`);
  if (packPath === "index.json") throw new Error(`${label}.path is reserved for the datapack manifest`);
  return {
    id: pack.id,
    path: packPath,
    sha256: requireSha256(pack.sha256, `${label}.sha256`),
  };
}

function validateIdentity(value, label) {
  requireObject(value, label);
  requireExactKeys(value, ["schemaVersion", "contractVersion", "releaseSequence", "manifestSha256", "packs"], label);
  if (value.schemaVersion !== 1) throw new Error(`${label}.schemaVersion must be 1`);
  if (value.contractVersion !== CONTRACT_VERSION) throw new Error(`${label}.contractVersion is unsupported`);
  const packs = value.packs;
  if (!Array.isArray(packs) || packs.length === 0) throw new Error(`${label}.packs must be a non-empty array`);
  const normalizedPacks = packs.map((pack, index) => validatePack(pack, `${label}.packs[${index}]`));
  const ids = new Set(normalizedPacks.map((pack) => pack.id));
  const paths = new Set(normalizedPacks.map((pack) => pack.path));
  if (ids.size !== normalizedPacks.length || paths.size !== normalizedPacks.length) throw new Error(`${label}.packs contains duplicate identities`);
  return {
    schemaVersion: 1,
    contractVersion: CONTRACT_VERSION,
    releaseSequence: requirePositiveInteger(value.releaseSequence, `${label}.releaseSequence`),
    manifestSha256: requireSha256(value.manifestSha256, `${label}.manifestSha256`),
    packs: normalizedPacks.sort((a, b) => codepointCompare(a.id, b.id)),
  };
}

// JSON Schema는 pack 객체의 구조를 고정하고, id/path별 배열 유일성은 이 소비 entrypoint가
// 함께 강제한다. 표준 JSON Schema의 uniqueItems만으로는 이 두 property를 표현할 수 없다.
export function validateDatapackLock(lock) {
  return validateIdentity(lock, "lock");
}

export function validateOfflineCandidate({ lock, candidateManifest }) {
  const expected = validateDatapackLock(lock);
  const candidate = validateIdentity(candidateManifest, "candidateManifest");
  if (canonicalJson(expected) !== canonicalJson(candidate)) throw new Error("candidate manifest identity does not match the pinned lock");
  return candidate;
}

export async function writeAtomicStagingPlan({ targetPath, lock, candidateManifest, writeFileImpl = writeFile }) {
  const identity = validateOfflineCandidate({ lock, candidateManifest });
  const plan = {
    schemaVersion: 1,
    contractVersion: CONTRACT_VERSION,
    manifestSha256: identity.manifestSha256,
    releaseSequence: identity.releaseSequence,
    packs: identity.packs.map((pack) => ({ destination: `assets/datapacks/${pack.path}`, ...pack })),
  };
  await writeAtomicText(targetPath, `${canonicalJson(plan)}\n`, writeFileImpl);
  return plan;
}

async function writeAtomicText(targetPath, text, writeFileImpl) {
  const directory = path.dirname(targetPath);
  let temporaryPath;
  try {
    await mkdir(directory, { recursive: true });
    temporaryPath = path.join(directory, `.${path.basename(targetPath)}.tmp-${randomUUID()}`);
    await writeFileImpl(temporaryPath, text, { encoding: "utf8", flag: "wx" });
    await rename(temporaryPath, targetPath);
  } catch (error) {
    throw new Error("failed to write contract output");
  } finally {
    if (temporaryPath) await rm(temporaryPath, { force: true }).catch(() => {});
  }
}

export function verifyTrustedAabEntries({ identity, entries }) {
  const expected = validateIdentity(identity, "identity");
  if (!Array.isArray(entries)) throw new Error("trusted AAB entries must be an array");
  const expectedByName = new Map([
    ["assets/datapacks/index.json", expected.manifestSha256],
    ...expected.packs.map((pack) => [`assets/datapacks/${pack.path}`, pack.sha256]),
  ]);
  const actualNames = new Set();
  for (const entry of entries) {
    requireObject(entry, "trusted AAB entry");
    const name = requireSafePath(entry.name, "trusted AAB entry.name");
    if (actualNames.has(name)) throw new Error("trusted AAB entries contain a duplicate entry");
    actualNames.add(name);
    const expectedHash = expectedByName.get(name);
    if (!expectedHash) throw new Error("trusted AAB entries contain an unexpected entry");
    if (!Buffer.isBuffer(entry.bytes)) throw new Error("trusted AAB entry.bytes must be a Buffer");
    if (sha256(entry.bytes) !== expectedHash) throw new Error("trusted AAB entry hash does not match the pinned identity");
  }
  if (actualNames.size !== expectedByName.size) throw new Error("trusted AAB entries are missing an expected entry");
  return { manifestSha256: expected.manifestSha256, packCount: expected.packs.length };
}

export function buildMobileComponentManifest(input) {
  requireObject(input, "component manifest input");
  requireExactKeys(input, ["repository", "gitSha", "versionName", "versionCode", "aabSha256", "bundledDataManifestSha256", "contractVersion", "evidence", "evidenceSha256", "issueRefs"], "component manifest input");
  requireFullMatch(input.repository, REPOSITORY, "repository");
  if (typeof input.gitSha !== "string" || input.gitSha.length !== 40 || !GIT_SHA.test(input.gitSha)) throw new Error("gitSha must be a full lowercase Git SHA");
  if (typeof input.versionName !== "string" || !input.versionName) throw new Error("versionName is required");
  requirePositiveInteger(input.versionCode, "versionCode");
  requireSha256(input.aabSha256, "aabSha256");
  requireSha256(input.bundledDataManifestSha256, "bundledDataManifestSha256");
  requireSha256(input.evidenceSha256, "evidenceSha256");
  if (input.contractVersion !== CONTRACT_VERSION) throw new Error("component manifest contractVersion is unsupported");
  if (!Array.isArray(input.issueRefs) || input.issueRefs.length === 0 || !input.issueRefs.every((ref) => {
    try { requireFullMatch(ref, ISSUE_REF, "issueRefs entry"); return true; } catch { return false; }
  })) throw new Error("issueRefs must be repo-qualified issue references");
  if (new Set(input.issueRefs).size !== input.issueRefs.length) throw new Error("issueRefs must not contain duplicates");
  const evidence = requireObject(input.evidence, "evidence");
  if (sha256(canonicalJson(evidence)) !== input.evidenceSha256) throw new Error("evidenceSha256 does not match canonical evidence");
  const manifest = {
    aabSha256: input.aabSha256,
    bundledDataManifestSha256: input.bundledDataManifestSha256,
    contractVersion: CONTRACT_VERSION,
    evidenceSha256: input.evidenceSha256,
    gitSha: input.gitSha,
    issueRefs: [...input.issueRefs].sort(codepointCompare),
    repository: input.repository,
    schemaVersion: 1,
    versionCode: input.versionCode,
    versionName: input.versionName,
  };
  return { manifest, text: `${canonicalJson(manifest)}\n`, sha256: sha256(canonicalJson(manifest)) };
}

export async function writeMobileComponentManifest({ targetPath, input, writeFileImpl = writeFile }) {
  const component = buildMobileComponentManifest(input);
  await writeAtomicText(targetPath, component.text, writeFileImpl);
  return component;
}
