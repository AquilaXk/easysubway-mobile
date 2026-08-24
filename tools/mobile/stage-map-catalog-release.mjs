import { createHash, randomUUID } from "node:crypto";
import { constants } from "node:fs";
import { lstat, mkdir, open, readdir, rename, rm, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const SHA256 = /^[a-f0-9]{64}$/;
const GIT_SHA = /^[a-f0-9]{40}$/;
const CONTRACT_VERSION = "mobile-map-catalog-content-lock-v1";
const ARTIFACTS = [
  { kind: "map-pack", id: "mapPackId", manifestPath: "map-pack/manifest.json", payloadPaths: ["map-pack/payload/metropolitan.svg", "map-pack/payload/stations-layout.json", "map-pack/payload/line-styles.json", "map-pack/payload/interchange-layout.json"] },
  { kind: "station-catalog-pack", id: "catalogPackId", manifestPath: "station-catalog-pack/manifest.json", payloadPaths: ["station-catalog-pack/payload/catalog.sqlite"] },
];

export const canonicalJson = (value) => Array.isArray(value)
  ? `[${value.map(canonicalJson).join(",")}]`
  : value && typeof value === "object"
    ? `{${Object.keys(value).sort().map((key) => `${JSON.stringify(key)}:${canonicalJson(value[key])}`).join(",")}}`
    : JSON.stringify(value);
export const sha256 = (value) => createHash("sha256").update(value).digest("hex");
const bytewise = (left, right) => Buffer.compare(Buffer.from(left), Buffer.from(right));
const exactKeys = (value, keys, label) => { if (!value || Array.isArray(value) || typeof value !== "object" || Object.keys(value).length !== keys.length || Object.keys(value).some((key) => !keys.includes(key))) throw new Error(`${label} has unknown or missing fields`); };
const requireSha = (value, label) => { if (typeof value !== "string" || !SHA256.test(value)) throw new Error(`${label} must be a lowercase SHA-256`); return value; };
const requirePositive = (value, label) => { if (!Number.isSafeInteger(value) || value < 1) throw new Error(`${label} must be a positive integer`); return value; };
const requirePath = (value, label) => { if (typeof value !== "string" || !value || value.includes("\\") || path.posix.isAbsolute(value) || path.posix.normalize(value) !== value || value.split("/").some((part) => !part || part === "." || part === "..")) throw new Error(`${label} must be a canonical relative path`); return value; };

export function parseJsonWithoutDuplicateKeys(bytes, label = "JSON") {
  const text = Buffer.isBuffer(bytes) ? bytes.toString("utf8") : bytes;
  if (typeof text !== "string") throw new Error(`${label} must be UTF-8 JSON`);
  let index = 0;
  const space = () => { while (/\s/.test(text[index] ?? "")) index += 1; };
  const string = () => { const start = index; if (text[index++] !== '"') throw new Error(`${label} has invalid JSON`); while (index < text.length) { const char = text[index++]; if (char === '"') return JSON.parse(text.slice(start, index)); if (char === "\\") index += 1; else if (char < " ") break; } throw new Error(`${label} has invalid JSON`); };
  const value = () => { space(); if (text[index] === '"') return string(); if (text[index] === "{") { index += 1; space(); const output = {}; const seen = new Set(); if (text[index] === "}") { index += 1; return output; } while (true) { space(); const key = string(); if (seen.has(key)) throw new Error(`${label} has duplicate key ${key}`); seen.add(key); space(); if (text[index++] !== ":") throw new Error(`${label} has invalid JSON`); output[key] = value(); space(); if (text[index] === "}") { index += 1; return output; } if (text[index++] !== ",") throw new Error(`${label} has invalid JSON`); } } if (text[index] === "[") { index += 1; space(); const output = []; if (text[index] === "]") { index += 1; return output; } while (true) { output.push(value()); space(); if (text[index] === "]") { index += 1; return output; } if (text[index++] !== ",") throw new Error(`${label} has invalid JSON`); } } const primitive = /^(true|false|null|-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?)/.exec(text.slice(index)); if (!primitive) throw new Error(`${label} has invalid JSON`); index += primitive[0].length; return JSON.parse(primitive[0]); };
  const parsed = value(); space(); if (index !== text.length) throw new Error(`${label} has invalid JSON`); return parsed;
}

function validateFile(value, label, expectedPath) {
  exactKeys(value, ["path", "sizeBytes", "sha256"], label);
  if (requirePath(value.path, `${label}.path`) !== expectedPath) throw new Error(`${label}.path is not the required payload path`);
  return { path: value.path, sizeBytes: requirePositive(value.sizeBytes, `${label}.sizeBytes`), sha256: requireSha(value.sha256, `${label}.sha256`) };
}

function validateArtifact(value, shape, index) {
  const label = `lock.artifacts[${index}]`; exactKeys(value, ["artifactKind", "manifest", "payload"], label);
  if (value.artifactKind !== shape.kind) throw new Error(`${label}.artifactKind is out of order`);
  const manifest = value.manifest; const manifestKeys = ["path", "sizeBytes", "sha256", "manifestVersion", "artifactKind", shape.id, "stationSetSha256", "payloadSha256"];
  exactKeys(manifest, manifestKeys, `${label}.manifest`);
  if (requirePath(manifest.path, `${label}.manifest.path`) !== shape.manifestPath || manifest.manifestVersion !== 1 || manifest.artifactKind !== shape.kind || typeof manifest[shape.id] !== "string" || !manifest[shape.id].trim()) throw new Error(`${label}.manifest has invalid component semantics`);
  const checkedManifest = { path: manifest.path, sizeBytes: requirePositive(manifest.sizeBytes, `${label}.manifest.sizeBytes`), sha256: requireSha(manifest.sha256, `${label}.manifest.sha256`), manifestVersion: 1, artifactKind: shape.kind, [shape.id]: manifest[shape.id], stationSetSha256: requireSha(manifest.stationSetSha256, `${label}.manifest.stationSetSha256`), payloadSha256: requireSha(manifest.payloadSha256, `${label}.manifest.payloadSha256`) };
  if (!Array.isArray(value.payload) || value.payload.length !== shape.payloadPaths.length) throw new Error(`${label}.payload has an invalid count`);
  return { artifactKind: shape.kind, manifest: checkedManifest, payload: value.payload.map((file, itemIndex) => validateFile(file, `${label}.payload[${itemIndex}]`, shape.payloadPaths[itemIndex])) };
}

export function validateMapCatalogReleaseLock(lock) {
  exactKeys(lock, ["schemaVersion", "contractVersion", "dataRelease", "artifacts"], "lock");
  if (lock.schemaVersion !== 1 || lock.contractVersion !== CONTRACT_VERSION) throw new Error("lock schema or contract version is unsupported");
  exactKeys(lock.dataRelease, ["producerRepository", "producerGitSha", "releaseSequence", "signedFinalDescriptorSha256", "publicationReceiptSha256"], "lock.dataRelease");
  if (lock.dataRelease.producerRepository !== "AquilaXk/easysubway-data" || typeof lock.dataRelease.producerGitSha !== "string" || !GIT_SHA.test(lock.dataRelease.producerGitSha)) throw new Error("lock data release producer identity is invalid");
  const dataRelease = { producerRepository: lock.dataRelease.producerRepository, producerGitSha: lock.dataRelease.producerGitSha, releaseSequence: requirePositive(lock.dataRelease.releaseSequence, "lock.dataRelease.releaseSequence"), signedFinalDescriptorSha256: requireSha(lock.dataRelease.signedFinalDescriptorSha256, "lock.dataRelease.signedFinalDescriptorSha256"), publicationReceiptSha256: requireSha(lock.dataRelease.publicationReceiptSha256, "lock.dataRelease.publicationReceiptSha256") };
  if (!Array.isArray(lock.artifacts) || lock.artifacts.length !== ARTIFACTS.length) throw new Error("lock must contain map-pack then station-catalog-pack");
  const artifacts = lock.artifacts.map((artifact, index) => validateArtifact(artifact, ARTIFACTS[index], index));
  if (artifacts[0].manifest.stationSetSha256 !== artifacts[1].manifest.stationSetSha256) throw new Error("map and catalog station-set identities must match");
  return { schemaVersion: 1, contractVersion: CONTRACT_VERSION, dataRelease, artifacts };
}

async function regularFile(target, label) { const stat = await lstat(target); if (!stat.isFile() || stat.isSymbolicLink()) throw new Error(`${label} must be a regular non-symlink file`); const handle = await open(target, constants.O_RDONLY | constants.O_NOFOLLOW | constants.O_NONBLOCK); try { if (!(await handle.stat()).isFile()) throw new Error(`${label} must be a regular file`); return await handle.readFile(); } finally { await handle.close(); } }
async function regularDirectory(target, label) { const stat = await lstat(target); if (!stat.isDirectory() || stat.isSymbolicLink()) throw new Error(`${label} must be a regular non-symlink directory`); }
async function listFiles(root, current = root, output = []) { for (const entry of await readdir(current, { withFileTypes: true })) { const target = path.join(current, entry.name); if (entry.isSymbolicLink()) throw new Error("input contains a symlink"); if (entry.isDirectory()) await listFiles(root, target, output); else if (entry.isFile()) output.push(path.relative(root, target).split(path.sep).join("/")); else throw new Error("input contains a non-regular entry"); } return output; }

function manifestExpectation(artifact) { const { path: _path, sizeBytes: _sizeBytes, sha256: _sha256, ...expected } = artifact.manifest; return expected; }
export async function validateMapCatalogContent({ lock, inputRoot } = {}) {
  const expected = validateMapCatalogReleaseLock(lock); if (!path.isAbsolute(inputRoot)) throw new Error("input root must be absolute"); await regularDirectory(inputRoot, "input root");
  const expectedFiles = expected.artifacts.flatMap(({ manifest, payload }) => [manifest, ...payload]); const names = await listFiles(inputRoot);
  if (names.length !== expectedFiles.length || names.some((name) => !expectedFiles.some((file) => file.path === name))) throw new Error("input inventory does not exactly match the lock");
  const content = new Map();
  for (const file of expectedFiles) { const target = path.resolve(inputRoot, file.path); const relative = path.relative(inputRoot, target); if (relative.startsWith("..") || path.isAbsolute(relative)) throw new Error("locked path escapes input root"); const bytes = await regularFile(target, `input ${file.path}`); if (bytes.length !== file.sizeBytes || sha256(bytes) !== file.sha256) throw new Error(`input ${file.path} does not match the lock`); content.set(file.path, bytes); }
  for (const artifact of expected.artifacts) {
    const actual = parseJsonWithoutDuplicateKeys(content.get(artifact.manifest.path), artifact.manifest.path); const shape = ARTIFACTS.find((item) => item.kind === artifact.artifactKind); const expectedKeys = ["manifestVersion", "artifactKind", shape.id, "stationSetSha256", "payloadSha256"];
    exactKeys(actual, expectedKeys, `${artifact.artifactKind} manifest`); if (canonicalJson(actual) !== canonicalJson(manifestExpectation(artifact))) throw new Error(`${artifact.artifactKind} manifest semantics do not match the lock`);
    const inventory = artifact.payload.map((file) => { const bytes = content.get(file.path); return { path: file.path.replace(`${artifact.artifactKind}/`, ""), sizeBytes: bytes.length, sha256: sha256(bytes) }; }).sort((left, right) => bytewise(left.path, right.path));
    if (sha256(Buffer.from(canonicalJson(inventory), "utf8")) !== artifact.manifest.payloadSha256) throw new Error(`${artifact.artifactKind} payload inventory digest does not match the manifest`);
  }
  return { lock: expected, lockSha256: sha256(Buffer.from(canonicalJson(expected), "utf8")), content };
}

export async function stageMapCatalogRelease({ lock, inputRoot, stageRoot } = {}) {
  const validated = await validateMapCatalogContent({ lock, inputRoot }); if (!path.isAbsolute(stageRoot)) throw new Error("stage root must be absolute");
  await mkdir(stageRoot, { recursive: true }); await regularDirectory(stageRoot, "stage root"); const versions = path.join(stageRoot, "versions"); await mkdir(versions, { recursive: true }); await regularDirectory(versions, "versions root");
  const versionDirectory = path.join(versions, validated.lockSha256); try { await lstat(versionDirectory); throw new Error("immutable stage version already exists"); } catch (error) { if (error?.code !== "ENOENT") throw error; }
  const candidate = path.join(versions, `.${validated.lockSha256}.candidate-${randomUUID()}`);
  try { await mkdir(candidate); for (const [entryPath, bytes] of validated.content) { const target = path.join(candidate, entryPath); await mkdir(path.dirname(target), { recursive: true }); await writeFile(target, bytes, { flag: "wx" }); } await rename(candidate, versionDirectory); return { lockSha256: validated.lockSha256, versionDirectory }; } catch (error) { await rm(candidate, { recursive: true, force: true }); throw error; }
}

function parseArguments(args) { if (args.length !== 6) throw new Error("usage: --lock <file> --input-root <directory> --stage-root <directory>"); const values = new Map(); for (let index = 0; index < args.length; index += 2) { const key = args[index]; const value = args[index + 1]; if (!['--lock', '--input-root', '--stage-root'].includes(key) || !value || values.has(key)) throw new Error("options must be complete, unique, and known"); values.set(key, value); } return Object.fromEntries([...values.entries()].map(([key, value]) => [key.slice(2).replaceAll("-", "_"), path.resolve(value)])); }
async function main() { const args = parseArguments(process.argv.slice(2)); const lock = parseJsonWithoutDuplicateKeys(await regularFile(args.lock, "lock"), "lock"); await stageMapCatalogRelease({ lock, inputRoot: args.input_root, stageRoot: args.stage_root }); }
if (process.argv[1] === fileURLToPath(import.meta.url)) main().catch((error) => { process.stderr.write(`${error.message}\n`); process.exitCode = 1; });
