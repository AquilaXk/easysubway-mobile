import { createHash, randomUUID } from "node:crypto";
import { constants } from "node:fs";
import { lstat, mkdir, open, readFile, rename, rm, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const SHA256 = /^[0-9a-f]{64}$/;
const GIT_SHA = /^[0-9a-f]{40}$/;
const REPOSITORY = /^[A-Za-z0-9][A-Za-z0-9_.-]*\/[A-Za-z0-9][A-Za-z0-9_.-]*$/;

export const BUNDLE_KIND = "generic-mobile-consumer-bundle";

const sha256 = (value) => createHash("sha256").update(value).digest("hex");
const exactKeys = (value, keys, label) => {
  if (!value || Array.isArray(value) || typeof value !== "object" || Object.keys(value).length !== keys.length || Object.keys(value).some((key) => !keys.includes(key))) throw new Error(`${label} has unknown or missing fields`);
};
const requireSha = (value, label) => {
  if (typeof value !== "string" || !SHA256.test(value)) throw new Error(`${label} must be a lowercase SHA-256`);
  return value;
};
const requirePositive = (value, label) => {
  if (!Number.isSafeInteger(value) || value < 1) throw new Error(`${label} must be a positive integer`);
  return value;
};
const requirePath = (value, label) => {
  if (typeof value !== "string" || !value || value.includes("\\") || path.posix.isAbsolute(value) || path.posix.normalize(value) !== value || value.split("/").some((part) => !part || part === "." || part === "..")) throw new Error(`${label} must be a canonical relative path`);
  return value;
};
const requireRepository = (value, label) => {
  if (typeof value !== "string" || !REPOSITORY.test(value)) throw new Error(`${label} must be a repository`);
  return value;
};
const requireGitSha = (value, label) => {
  if (typeof value !== "string" || !GIT_SHA.test(value)) throw new Error(`${label} must be a lowercase Git SHA`);
  return value;
};
const canonicalJson = (value) => {
  if (Array.isArray(value)) return `[${value.map(canonicalJson).join(",")}]`;
  if (value && typeof value === "object") return `{${Object.keys(value).sort().map((key) => `${JSON.stringify(key)}:${canonicalJson(value[key])}`).join(",")}}`;
  return JSON.stringify(value);
};

export function parseJsonWithoutDuplicateKeys(bytes, label = "JSON") {
  const text = Buffer.isBuffer(bytes) ? bytes.toString("utf8") : bytes;
  if (typeof text !== "string") throw new Error(`${label} must be UTF-8 JSON`);
  let index = 0;
  const space = () => { while (/\s/.test(text[index] ?? "")) index += 1; };
  const string = () => {
    const start = index;
    if (text[index++] !== '"') throw new Error(`${label} has invalid JSON`);
    while (index < text.length) {
      const char = text[index++];
      if (char === '"') return JSON.parse(text.slice(start, index));
      if (char === "\\") { index += 1; if (index > text.length) break; }
      else if (char < " ") break;
    }
    throw new Error(`${label} has invalid JSON`);
  };
  const value = () => {
    space();
    if (text[index] === '"') return string();
    if (text[index] === "{") {
      index += 1; space(); const out = {}; const seen = new Set();
      if (text[index] === "}") { index += 1; return out; }
      while (true) {
        space(); const key = string();
        if (seen.has(key)) throw new Error(`${label} has duplicate key ${key}`);
        seen.add(key); space(); if (text[index++] !== ":") throw new Error(`${label} has invalid JSON`);
        out[key] = value(); space();
        if (text[index] === "}") { index += 1; return out; }
        if (text[index++] !== ",") throw new Error(`${label} has invalid JSON`);
      }
    }
    if (text[index] === "[") {
      index += 1; space(); const out = [];
      if (text[index] === "]") { index += 1; return out; }
      while (true) { out.push(value()); space(); if (text[index] === "]") { index += 1; return out; } if (text[index++] !== ",") throw new Error(`${label} has invalid JSON`); }
    }
    const rest = text.slice(index);
    const match = /^(true|false|null|-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?)/.exec(rest);
    if (!match) throw new Error(`${label} has invalid JSON`);
    index += match[0].length;
    return JSON.parse(match[0]);
  };
  const parsed = value(); space();
  if (index !== text.length) throw new Error(`${label} has invalid JSON`);
  return parsed;
}

export function validateGenericMobileConsumerBundleLock(lock) {
  exactKeys(lock, ["schemaVersion", "component", "bundleVersion", "producer", "bundle", "resourceInventorySha256", "payloadSha256", "resources"], "lock");
  if (lock.schemaVersion !== 1 || lock.component !== "mobile" || typeof lock.bundleVersion !== "string" || !lock.bundleVersion) throw new Error("lock has unsupported component or schema");
  exactKeys(lock.producer, ["repository", "gitSha"], "lock.producer");
  requireRepository(lock.producer.repository, "lock.producer.repository");
  requireGitSha(lock.producer.gitSha, "lock.producer.gitSha");
  exactKeys(lock.bundle, ["url", "path", "rawSha256", "sizeBytes"], "lock.bundle");
  const expectedPrefix = `https://raw.githubusercontent.com/${lock.producer.repository}/`;
  const expectedSuffix = `/${lock.bundle.path}`;
  if (!lock.bundle.url.startsWith(expectedPrefix) || !lock.bundle.url.endsWith(expectedSuffix)) {
    throw new Error("lock bundle URL is not immutable raw GitHub URL");
  }
  const urlSha = lock.bundle.url.slice(expectedPrefix.length, -expectedSuffix.length);
  requireGitSha(urlSha, "lock.bundle.url gitSha");
  requirePath(lock.bundle.path, "lock.bundle.path");
  requireSha(lock.bundle.rawSha256, "lock.bundle.rawSha256");
  requirePositive(lock.bundle.sizeBytes, "lock.bundle.sizeBytes");
  requireSha(lock.resourceInventorySha256, "lock.resourceInventorySha256"); requireSha(lock.payloadSha256, "lock.payloadSha256");
  if (!Array.isArray(lock.resources) || lock.resources.length !== 2) throw new Error("lock must contain exactly two resources");
  const ids = new Set();
  for (const [index, resource] of lock.resources.entries()) {
    exactKeys(resource, ["resourceId", "mediaType", "schemaVersion", "ownerRepository", "ownerIssue", "sourcePath", "rawSha256", "sizeBytes", "fixturePath"], `lock.resources[${index}]`);
    requirePath(resource.resourceId, `lock.resources[${index}].resourceId`); if (ids.has(resource.resourceId)) throw new Error("lock resource IDs must be unique"); ids.add(resource.resourceId);
    if (resource.mediaType !== "application/json" || (resource.schemaVersion !== null && resource.schemaVersion !== 1)) throw new Error("lock resource media type or schema is invalid");
    requireRepository(resource.ownerRepository, `lock.resources[${index}].ownerRepository`); requirePositive(resource.ownerIssue, `lock.resources[${index}].ownerIssue`); requirePath(resource.sourcePath, `lock.resources[${index}].sourcePath`); requireSha(resource.rawSha256, `lock.resources[${index}].rawSha256`); requirePositive(resource.sizeBytes, `lock.resources[${index}].sizeBytes`); requirePath(resource.fixturePath, `lock.resources[${index}].fixturePath`);
  }
  return lock;
}

export function validateBundle(bundleBytes, lock) {
  if (bundleBytes.length !== lock.bundle.sizeBytes || sha256(bundleBytes) !== lock.bundle.rawSha256) {
    throw new Error("bundle raw identity does not match the lock");
  }
  const bundle = parseJsonWithoutDuplicateKeys(bundleBytes, "bundle");
  exactKeys(bundle, ["schemaVersion", "artifactKind", "component", "bundleVersion", "producer", "resources", "resourceInventorySha256", "payloadSha256"], "bundle");
  if (bundle.schemaVersion !== 1 || bundle.artifactKind !== BUNDLE_KIND || bundle.component !== lock.component || bundle.bundleVersion !== lock.bundleVersion || canonicalJson(bundle.producer) !== canonicalJson(lock.producer)) {
    throw new Error("bundle identity does not match the lock");
  }
  if (!Array.isArray(bundle.resources) || bundle.resources.length !== lock.resources.length) {
    throw new Error("bundle resource count is invalid");
  }
  const decoded = [];
  for (const [index, expected] of lock.resources.entries()) {
    const resource = bundle.resources[index];
    exactKeys(resource, ["resourceId", "mediaType", "schemaVersion", "ownerRepository", "ownerIssue", "sourcePath", "contentBase64", "rawSha256", "sizeBytes"], `bundle.resources[${index}]`);
    for (const key of ["resourceId", "mediaType", "schemaVersion", "ownerRepository", "ownerIssue", "sourcePath", "rawSha256", "sizeBytes"]) {
      if (resource[key] !== expected[key]) throw new Error("bundle resource does not match the lock");
    }
    if (typeof resource.contentBase64 !== "string") throw new Error("bundle resource contentBase64 is required");
    const bytes = Buffer.from(resource.contentBase64, "base64");
    if (bytes.toString("base64") !== resource.contentBase64 || bytes.length !== expected.sizeBytes || sha256(bytes) !== expected.rawSha256) {
      throw new Error("bundle resource base64 or digest is invalid");
    }
    decoded.push(bytes);
  }
  const inventory = bundle.resources.map(({ resourceId, mediaType, schemaVersion, ownerRepository, ownerIssue, sourcePath }) => ({ resourceId, mediaType, schemaVersion, ownerRepository, ownerIssue, sourcePath }));
  const payload = bundle.resources.map(({ resourceId, sizeBytes, rawSha256 }) => ({ resourceId, sizeBytes, rawSha256 }));
  if (bundle.resourceInventorySha256 !== lock.resourceInventorySha256 || bundle.payloadSha256 !== lock.payloadSha256 || sha256(canonicalJson(inventory)) !== lock.resourceInventorySha256 || sha256(canonicalJson(payload)) !== lock.payloadSha256) {
    throw new Error("bundle inventory or payload digest does not match the lock");
  }
  return { bundle, decoded };
}

async function regularFile(target, label) {
  const stat = await lstat(target);
  if (!stat.isFile() || stat.isSymbolicLink()) throw new Error(`${label} must be a regular non-symlink file`);
  const handle = await open(target, constants.O_RDONLY | constants.O_NOFOLLOW | constants.O_NONBLOCK);
  try { const opened = await handle.stat(); if (!opened.isFile()) throw new Error(`${label} must be a regular file`); return await handle.readFile(); } finally { await handle.close(); }
}

async function regularDirectory(target, label, fs = { lstat, mkdir }) {
  await fs.mkdir(target, { recursive: true });
  const stat = await fs.lstat(target);
  if (!stat.isDirectory() || stat.isSymbolicLink()) throw new Error(`${label} must be a regular non-symlink directory`);
}

async function fixtureParity(lock, fixtureRoot, decoded) {
  const root = path.resolve(fixtureRoot);
  const rootStat = await lstat(root);
  if (!rootStat.isDirectory() || rootStat.isSymbolicLink()) throw new Error("fixture root must be a regular directory");
  for (const [index, resource] of lock.resources.entries()) {
    const fixture = path.resolve(root, resource.fixturePath);
    if (path.relative(root, fixture).startsWith("..") || path.isAbsolute(path.relative(root, fixture))) throw new Error("fixture path escapes root");
    const bytes = await regularFile(fixture, "fixture");
    if (!bytes.equals(decoded[index])) throw new Error("tracked fixture does not match the published resource");
  }
}

export async function stageGenericMobileConsumerBundle({ lock, bundleBytes, fixtureRoot, stageRoot, fs = { lstat, mkdir, rename, rm, writeFile } } = {}) {
  const expected = validateGenericMobileConsumerBundleLock(lock);
  if (!path.isAbsolute(fixtureRoot) || !path.isAbsolute(stageRoot)) throw new Error("fixture root and stage root must be absolute paths");
  const parsed = validateBundle(bundleBytes, expected);
  await fixtureParity(expected, fixtureRoot, parsed.decoded);
  await regularDirectory(stageRoot, "stage root", fs);
  const root = path.resolve(stageRoot);
  const versions = path.join(root, "versions");
  await regularDirectory(versions, "version root", fs);
  const version = path.join(versions, expected.bundle.rawSha256);
  try { await fs.lstat(version); throw new Error("immutable version directory already exists"); } catch (error) { if (error?.code !== "ENOENT") throw error; }
  const candidate = path.join(root, `.candidate-${randomUUID()}`);
  try {
    await fs.mkdir(candidate, { recursive: false });
    const resources = path.join(candidate, "resources");
    await fs.mkdir(resources);
    for (const [index, resource] of expected.resources.entries()) {
      const output = path.join(resources, resource.resourceId);
      await fs.mkdir(path.dirname(output), { recursive: true });
      await fs.writeFile(output, parsed.decoded[index], { flag: "wx", mode: 0o600 });
    }
    await fs.rename(candidate, version);
    const pointer = Buffer.from(`${canonicalJson({ rawSha256: expected.bundle.rawSha256, versionDirectory: `versions/${expected.bundle.rawSha256}` })}\n`, "utf8");
    const pointerTemp = path.join(root, `.current-${randomUUID()}.json`);
    try {
      try {
        await fs.writeFile(pointerTemp, pointer, { flag: "wx", mode: 0o600 });
        await fs.rename(pointerTemp, path.join(root, "current.json"));
      } finally {
        await fs.rm(pointerTemp, { force: true }).catch(() => {});
      }
    } catch (error) {
      await fs.rm(version, { recursive: true, force: true }).catch(() => {});
      throw error;
    }
    return { rawSha256: expected.bundle.rawSha256, versionDirectory: version };
  } finally {
    await fs.rm(candidate, { recursive: true, force: true }).catch(() => {});
  }
}

function parseArguments(args) {
  const values = new Map();
  if (args.length !== 8) throw new Error("usage: --lock <file> --bundle <file> --fixture-root <directory> --stage-root <directory>");
  for (let index = 0; index < args.length; index += 2) {
    const key = args[index];
    const value = args[index + 1];
    if (!["--lock", "--bundle", "--fixture-root", "--stage-root"].includes(key) || !value || values.has(key)) {
      throw new Error("options must be complete, unique, and known");
    }
    values.set(key, value);
  }
  return Object.fromEntries([...values.entries()].map(([key, value]) => [key.slice(2).replaceAll("-", "_"), path.resolve(value)]));
}

async function main() {
  const args = parseArguments(process.argv.slice(2));
  const [lockBytes, bundleBytes] = await Promise.all([regularFile(args.lock, "lock"), regularFile(args.bundle, "bundle")]);
  await stageGenericMobileConsumerBundle({
    lock: parseJsonWithoutDuplicateKeys(lockBytes, "lock"),
    bundleBytes,
    fixtureRoot: args.fixture_root,
    stageRoot: args.stage_root,
  });
}

if (process.argv[1] === fileURLToPath(import.meta.url)) main().catch((error) => { process.stderr.write(`${error.message}\n`); process.exitCode = 1; });
