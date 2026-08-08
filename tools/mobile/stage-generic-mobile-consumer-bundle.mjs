import { createHash, randomUUID } from "node:crypto";
import { constants } from "node:fs";
import { execFile as execFileCallback } from "node:child_process";
import { lstat, mkdir, open, readFile, rename, rm, writeFile } from "node:fs/promises";
import { promisify } from "node:util";
import path from "node:path";
import { fileURLToPath } from "node:url";

const execFile = promisify(execFileCallback);
const SHA256 = /^[0-9a-f]{64}$/;
const GIT_SHA = /^[0-9a-f]{40}$/;
const REPOSITORY = /^[A-Za-z0-9][A-Za-z0-9_.-]*\/[A-Za-z0-9][A-Za-z0-9_.-]*$/;
const ISO_TIME = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/;
const RETENTION_MS = 90 * 24 * 60 * 60 * 1000;
const RETENTION_SKEW_MS = 5 * 60 * 1000;

export const BUNDLE_KIND = "generic-mobile-consumer-bundle";
export const RECEIPT_KIND = "generic-mobile-consumer-publication-receipt";

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
const requireTime = (value, label) => {
  if (typeof value !== "string" || !ISO_TIME.test(value) || !Number.isFinite(Date.parse(value))) throw new Error(`${label} must be an ISO timestamp`);
  return value;
};
const canonicalJson = (value) => {
  if (Array.isArray(value)) return `[${value.map(canonicalJson).join(",")}]`;
  if (value && typeof value === "object") return `{${Object.keys(value).sort().map((key) => `${JSON.stringify(key)}:${canonicalJson(value[key])}`).join(",")}}`;
  return JSON.stringify(value);
};

// JSON.parse permits duplicate names by silently retaining the final value. The publication
// format is closed, so reject those bytes before any semantic validation.
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
  exactKeys(lock, ["schemaVersion", "component", "bundleVersion", "producer", "publication", "artifact", "files", "resourceInventorySha256", "payloadSha256", "resources"], "lock");
  if (lock.schemaVersion !== 1 || lock.component !== "mobile" || typeof lock.bundleVersion !== "string" || !lock.bundleVersion) throw new Error("lock has unsupported component or schema");
  exactKeys(lock.producer, ["repository", "gitSha"], "lock.producer");
  requireRepository(lock.producer.repository, "lock.producer.repository"); requireGitSha(lock.producer.gitSha, "lock.producer.gitSha");
  exactKeys(lock.publication, ["repositoryId", "workflowId", "workflowPath", "runId", "runAttempt", "headSha"], "lock.publication");
  requirePositive(lock.publication.repositoryId, "lock.publication.repositoryId"); requirePositive(lock.publication.workflowId, "lock.publication.workflowId"); requirePath(lock.publication.workflowPath, "lock.publication.workflowPath"); requirePositive(lock.publication.runId, "lock.publication.runId"); requirePositive(lock.publication.runAttempt, "lock.publication.runAttempt"); requireGitSha(lock.publication.headSha, "lock.publication.headSha");
  exactKeys(lock.artifact, ["id", "name", "archiveSha256", "sizeBytes", "metadataUrl", "archiveUrl", "createdAt", "expiresAt", "retentionDays"], "lock.artifact");
  requirePositive(lock.artifact.id, "lock.artifact.id"); if (typeof lock.artifact.name !== "string" || !lock.artifact.name) throw new Error("lock.artifact.name is required"); requireSha(lock.artifact.archiveSha256, "lock.artifact.archiveSha256"); requirePositive(lock.artifact.sizeBytes, "lock.artifact.sizeBytes");
  const base = `https://api.github.com/repos/${lock.producer.repository}/actions/artifacts/${lock.artifact.id}`;
  if (lock.artifact.metadataUrl !== base || lock.artifact.archiveUrl !== `${base}/zip`) throw new Error("lock artifact URLs are not immutable GitHub API URLs");
  requireTime(lock.artifact.createdAt, "lock.artifact.createdAt"); requireTime(lock.artifact.expiresAt, "lock.artifact.expiresAt");
  const retentionMs = Date.parse(lock.artifact.expiresAt) - Date.parse(lock.artifact.createdAt);
  if (lock.artifact.retentionDays !== 90 || retentionMs < RETENTION_MS - RETENTION_SKEW_MS || retentionMs > RETENTION_MS) throw new Error("lock artifact retention is invalid");
  exactKeys(lock.files, ["bundle", "receipt"], "lock.files");
  for (const name of ["bundle", "receipt"]) { exactKeys(lock.files[name], ["path", "rawSha256", "sizeBytes"], `lock.files.${name}`); requirePath(lock.files[name].path, `lock.files.${name}.path`); requireSha(lock.files[name].rawSha256, `lock.files.${name}.rawSha256`); requirePositive(lock.files[name].sizeBytes, `lock.files.${name}.sizeBytes`); }
  if (lock.files.bundle.path === lock.files.receipt.path) throw new Error("lock files must be distinct");
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

export function validateArtifactMetadata(metadata, lock) {
  if (!metadata || Array.isArray(metadata) || typeof metadata !== "object") throw new Error("artifact metadata must be an object");
  const expected = validateGenericMobileConsumerBundleLock(lock);
  if (metadata.id !== expected.artifact.id || metadata.name !== expected.artifact.name || metadata.size_in_bytes !== expected.artifact.sizeBytes || metadata.digest !== `sha256:${expected.artifact.archiveSha256}` || metadata.archive_download_url !== expected.artifact.archiveUrl || metadata.expired !== false || metadata.created_at !== expected.artifact.createdAt || metadata.expires_at !== expected.artifact.expiresAt) throw new Error("artifact metadata does not match the immutable lock");
  if (!metadata.workflow_run || Array.isArray(metadata.workflow_run) || typeof metadata.workflow_run !== "object" || metadata.workflow_run.id !== expected.publication.runId || metadata.workflow_run.head_branch !== "main" || metadata.workflow_run.head_sha !== expected.publication.headSha || metadata.workflow_run.repository_id !== expected.publication.repositoryId || metadata.workflow_run.head_repository_id !== expected.publication.repositoryId) throw new Error("artifact workflow identity does not match the immutable lock");
  return metadata;
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

async function runUnzip(execFileImpl, args) {
  try { return await execFileImpl("unzip", args, { encoding: "utf8", maxBuffer: 1024 * 1024 }); } catch { throw new Error("unzip failed"); }
}

function validateArchiveEntries(stdout, lock) {
  const names = stdout.split(/\r?\n/).filter(Boolean);
  const expected = [lock.files.bundle.path, lock.files.receipt.path];
  const invalid = names.some((name) => {
    try { requirePath(name, "ZIP entry"); } catch { return true; }
    return !expected.includes(name);
  });
  if (names.length !== expected.length || new Set(names).size !== names.length || invalid) throw new Error("ZIP entries do not exactly match the immutable lock");
}

function validateBundleAndReceipt(bundleBytes, receiptBytes, lock) {
  const bundle = parseJsonWithoutDuplicateKeys(bundleBytes, "bundle");
  const receipt = parseJsonWithoutDuplicateKeys(receiptBytes, "receipt");
  exactKeys(bundle, ["schemaVersion", "artifactKind", "component", "bundleVersion", "producer", "resources", "resourceInventorySha256", "payloadSha256"], "bundle");
  exactKeys(receipt, ["schemaVersion", "artifactKind", "component", "bundleVersion", "producer", "bundle", "resources", "publication"], "receipt");
  if (bundle.schemaVersion !== 1 || bundle.artifactKind !== BUNDLE_KIND || receipt.schemaVersion !== 1 || receipt.artifactKind !== RECEIPT_KIND || bundle.component !== lock.component || receipt.component !== lock.component || bundle.bundleVersion !== lock.bundleVersion || receipt.bundleVersion !== lock.bundleVersion || canonicalJson(bundle.producer) !== canonicalJson(lock.producer) || canonicalJson(receipt.producer) !== canonicalJson(lock.producer)) throw new Error("bundle or receipt identity does not match the lock");
  if (!Array.isArray(bundle.resources) || !Array.isArray(receipt.resources) || bundle.resources.length !== lock.resources.length || receipt.resources.length !== lock.resources.length) throw new Error("bundle or receipt resource count is invalid");
  const decoded = [];
  for (const [index, expected] of lock.resources.entries()) {
    const resource = bundle.resources[index]; const receiptResource = receipt.resources[index];
    exactKeys(resource, ["resourceId", "mediaType", "schemaVersion", "ownerRepository", "ownerIssue", "sourcePath", "contentBase64", "rawSha256", "sizeBytes"], `bundle.resources[${index}]`);
    exactKeys(receiptResource, ["resourceId", "rawSha256", "sizeBytes"], `receipt.resources[${index}]`);
    for (const key of ["resourceId", "mediaType", "schemaVersion", "ownerRepository", "ownerIssue", "sourcePath", "rawSha256", "sizeBytes"]) if (resource[key] !== expected[key]) throw new Error("bundle resource does not match the lock");
    if (receiptResource.resourceId !== expected.resourceId || receiptResource.rawSha256 !== expected.rawSha256 || receiptResource.sizeBytes !== expected.sizeBytes || typeof resource.contentBase64 !== "string") throw new Error("receipt resource does not match the lock");
    const bytes = Buffer.from(resource.contentBase64, "base64");
    if (bytes.toString("base64") !== resource.contentBase64 || bytes.length !== expected.sizeBytes || sha256(bytes) !== expected.rawSha256) throw new Error("bundle resource base64 or digest is invalid");
    decoded.push(bytes);
  }
  const inventory = bundle.resources.map(({ resourceId, mediaType, schemaVersion, ownerRepository, ownerIssue, sourcePath }) => ({ resourceId, mediaType, schemaVersion, ownerRepository, ownerIssue, sourcePath }));
  const payload = bundle.resources.map(({ resourceId, sizeBytes, rawSha256 }) => ({ resourceId, sizeBytes, rawSha256 }));
  if (bundle.resourceInventorySha256 !== lock.resourceInventorySha256 || bundle.payloadSha256 !== lock.payloadSha256 || sha256(canonicalJson(inventory)) !== lock.resourceInventorySha256 || sha256(canonicalJson(payload)) !== lock.payloadSha256) throw new Error("bundle inventory or payload digest does not match the lock");
  exactKeys(receipt.bundle, ["fileName", "rawSha256", "sizeBytes", "resourceInventorySha256", "payloadSha256"], "receipt.bundle");
  if (receipt.bundle.fileName !== lock.files.bundle.path || receipt.bundle.rawSha256 !== lock.files.bundle.rawSha256 || receipt.bundle.sizeBytes !== lock.files.bundle.sizeBytes || receipt.bundle.resourceInventorySha256 !== lock.resourceInventorySha256 || receipt.bundle.payloadSha256 !== lock.payloadSha256) throw new Error("receipt bundle does not match the lock");
  exactKeys(receipt.publication, ["repository", "workflowPath", "artifactName", "transport", "retentionDays", "overwrite"], "receipt.publication");
  if (receipt.publication.repository !== lock.producer.repository || receipt.publication.workflowPath !== lock.publication.workflowPath || receipt.publication.artifactName !== lock.artifact.name || receipt.publication.transport !== "github-actions-artifact-v4" || receipt.publication.retentionDays !== lock.artifact.retentionDays || receipt.publication.overwrite !== false) throw new Error("receipt publication policy does not match the lock");
  return { bundle, receipt, decoded };
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

export async function stageGenericMobileConsumerBundle({ lock, metadata, archivePath, fixtureRoot, stageRoot, fs = { lstat, mkdir, rename, rm, writeFile }, execFileImpl = execFile } = {}) {
  const expected = validateGenericMobileConsumerBundleLock(lock);
  validateArtifactMetadata(metadata, expected);
  if (!path.isAbsolute(archivePath) || !path.isAbsolute(fixtureRoot) || !path.isAbsolute(stageRoot)) throw new Error("archive, fixture root, and stage root must be absolute paths");
  const archive = await regularFile(archivePath, "archive");
  if (archive.length !== expected.artifact.sizeBytes || sha256(archive) !== expected.artifact.archiveSha256) throw new Error("archive digest does not match the immutable lock");
  const listed = await runUnzip(execFileImpl, ["-Z1", archivePath]);
  validateArchiveEntries(listed.stdout, expected);
  await regularDirectory(stageRoot, "stage root", fs);
  const root = path.resolve(stageRoot); const versions = path.join(root, "versions"); await regularDirectory(versions, "version root", fs);
  const version = path.join(versions, expected.artifact.archiveSha256);
  try { await fs.lstat(version); throw new Error("immutable version directory already exists"); } catch (error) { if (error?.code !== "ENOENT") throw error; }
  const candidate = path.join(root, `.candidate-${randomUUID()}`);
  try {
    await fs.mkdir(candidate, { recursive: false });
    await runUnzip(execFileImpl, ["-qq", archivePath, "-d", candidate]);
    const bundlePath = path.join(candidate, expected.files.bundle.path); const receiptPath = path.join(candidate, expected.files.receipt.path);
    const [bundleBytes, receiptBytes] = await Promise.all([regularFile(bundlePath, "bundle"), regularFile(receiptPath, "receipt")]);
    if (bundleBytes.length !== expected.files.bundle.sizeBytes || sha256(bundleBytes) !== expected.files.bundle.rawSha256 || receiptBytes.length !== expected.files.receipt.sizeBytes || sha256(receiptBytes) !== expected.files.receipt.rawSha256) throw new Error("bundle or receipt raw identity does not match the lock");
    const parsed = validateBundleAndReceipt(bundleBytes, receiptBytes, expected);
    await fixtureParity(expected, fixtureRoot, parsed.decoded);
    const resources = path.join(candidate, "resources"); await fs.mkdir(resources);
    for (const [index, resource] of expected.resources.entries()) { const output = path.join(resources, resource.resourceId); await fs.mkdir(path.dirname(output), { recursive: true }); await fs.writeFile(output, parsed.decoded[index], { flag: "wx", mode: 0o600 }); }
    await fs.rename(candidate, version);
    const pointer = Buffer.from(`${canonicalJson({ archiveSha256: expected.artifact.archiveSha256, versionDirectory: `versions/${expected.artifact.archiveSha256}` })}\n`, "utf8");
    const pointerTemp = path.join(root, `.current-${randomUUID()}.json`);
    try {
      try { await fs.writeFile(pointerTemp, pointer, { flag: "wx", mode: 0o600 }); await fs.rename(pointerTemp, path.join(root, "current.json")); }
      finally { await fs.rm(pointerTemp, { force: true }).catch(() => {}); }
    } catch (error) {
      await fs.rm(version, { recursive: true, force: true });
      throw error;
    }
    return { archiveSha256: expected.artifact.archiveSha256, versionDirectory: version };
  } finally { await fs.rm(candidate, { recursive: true, force: true }).catch(() => {}); }
}

function parseArguments(args) {
  const values = new Map();
  if (args.length !== 10) throw new Error("usage: --lock <file> --metadata <file> --archive <file> --fixture-root <directory> --stage-root <directory>");
  for (let index = 0; index < args.length; index += 2) { const key = args[index]; const value = args[index + 1]; if (!["--lock", "--metadata", "--archive", "--fixture-root", "--stage-root"].includes(key) || !value || values.has(key)) throw new Error("options must be complete, unique, and known"); values.set(key, value); }
  return Object.fromEntries([...values.entries()].map(([key, value]) => [key.slice(2).replaceAll("-", "_"), path.resolve(value)]));
}

async function main() {
  const args = parseArguments(process.argv.slice(2));
  const [lockBytes, metadataBytes] = await Promise.all([regularFile(args.lock, "lock"), regularFile(args.metadata, "metadata")]);
  await stageGenericMobileConsumerBundle({ lock: parseJsonWithoutDuplicateKeys(lockBytes, "lock"), metadata: parseJsonWithoutDuplicateKeys(metadataBytes, "metadata"), archivePath: args.archive, fixtureRoot: args.fixture_root, stageRoot: args.stage_root });
}

if (process.argv[1] === fileURLToPath(import.meta.url)) main().catch((error) => { process.stderr.write(`${error.message}\n`); process.exitCode = 1; });
