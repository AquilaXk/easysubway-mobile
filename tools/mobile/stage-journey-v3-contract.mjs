import { createHash } from 'node:crypto';
import { closeSync, constants, fstatSync, lstatSync, mkdirSync, openSync, readFileSync, writeFileSync } from 'node:fs';
import { basename, dirname, isAbsolute, join, relative, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

const repositoryRoot = resolve(import.meta.dirname, '..', '..');
const buildRoot = join(repositoryRoot, 'build');
const trackedLockPath = join(repositoryRoot, 'contracts/mobile/journey-v3-client.lock.json');
const resourcePaths = [
  'contracts/api/journey-v3-error-catalog.json',
  'contracts/api/journey-v3-error-disposition.json',
  'contracts/api/journey-v3.openapi.yaml',
];
const sha256 = (bytes) => createHash('sha256').update(bytes).digest('hex');
const fail = (message) => { throw new Error(`stage-journey-v3-contract: ${message}`); };

function duplicateFreeJson(text, label) {
  let index = 0;
  const whitespace = () => { while (/\s/.test(text[index] ?? '')) index += 1; };
  const string = () => {
    const start = index; index += 1;
    let escaped = false;
    while (index < text.length) {
      const character = text[index++];
      if (!escaped && character === '"') return JSON.parse(text.slice(start, index));
      if (!escaped && character < ' ') fail(`${label} has an invalid JSON string`);
      escaped = !escaped && character === '\\';
      if (character !== '\\') escaped = false;
    }
    fail(`${label} has an unterminated JSON string`);
  };
  const value = () => {
    whitespace();
    const character = text[index];
    if (character === '"') { string(); return; }
    if (character === '{') {
      index += 1; whitespace(); const keys = new Set();
      if (text[index] === '}') { index += 1; return; }
      while (true) {
        whitespace(); if (text[index] !== '"') fail(`${label} has malformed JSON object`);
        const key = string(); if (keys.has(key)) fail(`${label} has duplicate key ${key}`); keys.add(key);
        whitespace(); if (text[index++] !== ':') fail(`${label} has malformed JSON object`);
        value(); whitespace();
        if (text[index] === '}') { index += 1; return; }
        if (text[index++] !== ',') fail(`${label} has malformed JSON object`);
      }
    }
    if (character === '[') {
      index += 1; whitespace(); if (text[index] === ']') { index += 1; return; }
      while (true) { value(); whitespace(); if (text[index] === ']') { index += 1; return; } if (text[index++] !== ',') fail(`${label} has malformed JSON array`); }
    }
    const primitive = /^(?:true|false|null|-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?)/.exec(text.slice(index));
    if (!primitive) fail(`${label} has malformed JSON value`);
    index += primitive[0].length;
  };
  try { value(); whitespace(); if (index !== text.length) fail(`${label} has trailing JSON content`); return JSON.parse(text); } catch (error) { if (error.message.startsWith('stage-journey-v3-contract:')) throw error; fail(`${label} is not valid JSON`); }
}

function exactKeys(object, keys, label) {
  if (!object || Array.isArray(object) || Object.keys(object).length !== keys.length || keys.some((key) => !(key in object))) fail(`${label} has unexpected or missing fields`);
}
function stringField(value, label) { if (typeof value !== 'string' || value.length === 0) fail(`${label} must be a non-empty string`); }
function hashField(value, label) { if (!/^[a-f0-9]{64}$/.test(value)) fail(`${label} must be a SHA-256 hex digest`); }
function safePath(value, label) { stringField(value, label); if (isAbsolute(value) || value.split('/').some((part) => part === '' || part === '.' || part === '..') || value.includes('\\')) fail(`${label} is unsafe`); }
function readRegular(path, label) {
  if (constants.O_NOFOLLOW === undefined) fail('O_NOFOLLOW is required for regular input identity');
  let descriptor;
  try {
    descriptor = openSync(path, constants.O_RDONLY | constants.O_NOFOLLOW);
    const stat = fstatSync(descriptor);
    if (!stat.isFile()) fail(`${label} must be a regular non-symlink file`);
    return readFileSync(descriptor);
  } catch (error) {
    if (error.message.startsWith('stage-journey-v3-contract:')) throw error;
    fail(`${label} must be a regular non-symlink file`);
  } finally { if (descriptor !== undefined) closeSync(descriptor); }
}

function validateLock(lock) {
  exactKeys(lock, ['schemaVersion', 'component', 'bundleVersion', 'producer', 'artifact', 'payload', 'publicationReceiptSha256', 'resources'], 'lock');
  exactKeys(lock.producer, ['repository', 'gitSha'], 'lock.producer'); exactKeys(lock.artifact, ['repository', 'manifestDigest', 'artifactType'], 'lock.artifact'); exactKeys(lock.payload, ['fileName', 'mediaType', 'sha256'], 'lock.payload');
  if (lock.schemaVersion !== 2 || lock.component !== 'backend' || lock.bundleVersion !== '2.0.0') fail('lock component or bundle version is not supported');
  for (const [value, label] of [[lock.producer.repository, 'lock.producer.repository'], [lock.artifact.repository, 'lock.artifact.repository'], [lock.artifact.artifactType, 'lock.artifact.artifactType'], [lock.payload.mediaType, 'lock.payload.mediaType']]) stringField(value, label);
  if (!/^[a-f0-9]{40}$/.test(lock.producer.gitSha) || !/^sha256:[a-f0-9]{64}$/.test(lock.artifact.manifestDigest)) fail('lock producer or artifact identity is invalid');
  safePath(lock.payload.fileName, 'lock.payload.fileName'); hashField(lock.payload.sha256, 'lock.payload.sha256'); hashField(lock.publicationReceiptSha256, 'lock.publicationReceiptSha256');
  if (!Array.isArray(lock.resources) || lock.resources.length !== resourcePaths.length) fail('lock.resources must contain exactly the required resources');
  const paths = new Set();
  lock.resources.forEach((resource, index) => {
    exactKeys(resource, ['id', 'path', 'owner', 'mediaType', 'sha256'], `lock.resources[${index}]`);
    stringField(resource.id, `lock.resources[${index}].id`); safePath(resource.path, `lock.resources[${index}].path`);
    if (resource.path !== resourcePaths[index] || paths.has(resource.path)) fail('lock.resources has an invalid order or duplicate path');
    paths.add(resource.path); stringField(resource.owner, `lock.resources[${index}].owner`); stringField(resource.mediaType, `lock.resources[${index}].mediaType`); hashField(resource.sha256, `lock.resources[${index}].sha256`);
  });
}

function validatePayload(payload, lock, bytes) {
  exactKeys(payload, ['schemaVersion', 'bundleVersion', 'component', 'producerRepository', 'producerSha', 'resources'], 'payload');
  if (sha256(bytes) !== lock.payload.sha256) fail('payload SHA-256 does not match lock');
  if (payload.schemaVersion !== 2 || payload.component !== lock.component || payload.bundleVersion !== lock.bundleVersion || payload.producerRepository !== lock.producer.repository || payload.producerSha !== lock.producer.gitSha || !Array.isArray(payload.resources) || payload.resources.length !== lock.resources.length) fail('payload identity or resource set does not match lock');
  return payload.resources.map((resource, index) => {
    exactKeys(resource, ['id', 'path', 'owner', 'mediaType', 'sha256', 'contentBase64'], `payload.resources[${index}]`);
    const expected = lock.resources[index];
    for (const key of ['id', 'path', 'owner', 'mediaType', 'sha256']) if (resource[key] !== expected[key]) fail(`payload resource ${index} does not match lock`);
    if (typeof resource.contentBase64 !== 'string' || !/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(resource.contentBase64)) fail(`payload resource ${index} is not canonical base64`);
    const content = Buffer.from(resource.contentBase64, 'base64');
    if (content.toString('base64') !== resource.contentBase64 || sha256(content) !== expected.sha256) fail(`payload resource ${index} content does not match lock`);
    return { ...expected, content };
  });
}

function prepareOutput(output, allowedBuildRoot) {
  if (!isAbsolute(output)) fail('output must be absolute');
  const resolvedBuildRoot = resolve(allowedBuildRoot); const resolved = resolve(output); const fromBuild = relative(resolvedBuildRoot, resolved);
  if (fromBuild === '' || fromBuild.startsWith(`..${sep}`) || fromBuild === '..' || isAbsolute(fromBuild) || fromBuild.includes(sep)) fail('output must be an absent direct child below repository build');
  const buildMetadata = lstatSync(resolvedBuildRoot, { throwIfNoEntry: false });
  if (!buildMetadata) mkdirSync(resolvedBuildRoot);
  else if (!buildMetadata.isDirectory() || buildMetadata.isSymbolicLink()) fail('build root must be an existing non-symlink directory');
  if (lstatSync(resolved, { throwIfNoEntry: false })) fail('output must be absent');
  return resolved;
}

function parseArguments(argv) {
  if (argv.length !== 6 || argv[0] !== '--lock' || argv[2] !== '--input' || argv[4] !== '--output') fail('usage is --lock <lock> --input <payload> --output <absent-directory-below-build>');
  return { lock: argv[1], input: argv[3], output: argv[5] };
}

function stage({ lockPath, inputPath, outputPath, enforceTrackedLock, allowedBuildRoot = buildRoot }) {
  if (enforceTrackedLock && resolve(lockPath) !== trackedLockPath) fail('lock must be the tracked journey-v3-client lock');
  const lockBytes = readRegular(lockPath, 'lock');
  const inputBytes = readRegular(inputPath, 'input');
  const lock = duplicateFreeJson(lockBytes.toString('utf8'), 'lock'); validateLock(lock);
  if (basename(inputPath) !== lock.payload.fileName) fail('input file name does not match locked payload');
  const resources = validatePayload(duplicateFreeJson(inputBytes.toString('utf8'), 'payload'), lock, inputBytes);
  const output = prepareOutput(outputPath, allowedBuildRoot);
  mkdirSync(output);
  try {
    for (const resource of resources) { const destination = join(output, resource.path); mkdirSync(dirname(destination), { recursive: true }); writeFileSync(destination, resource.content, { flag: 'wx' }); }
    const receipt = { schemaVersion: 1, lockSha256: sha256(lockBytes), payloadSha256: lock.payload.sha256, publicationReceiptSha256: lock.publicationReceiptSha256, artifact: lock.artifact, resources: Object.fromEntries(resources.map(({ path, sha256: digest }) => [path, digest])) };
    writeFileSync(join(output, 'journey-v3-contract-stage-receipt.json'), `${JSON.stringify(receipt, null, 2)}\n`, { flag: 'wx' });
  } catch (error) { throw error; }
}

export function stageJourneyV3ContractForTest(options) { return stage({ ...options, allowedBuildRoot: options.buildRoot ?? buildRoot, enforceTrackedLock: false }); }

if (process.argv[1] === fileURLToPath(import.meta.url)) try {
  const arguments_ = parseArguments(process.argv.slice(2));
  stage({ lockPath: arguments_.lock, inputPath: arguments_.input, outputPath: arguments_.output, enforceTrackedLock: true });
} catch (error) {
  process.stderr.write(`${error.message}\n`); process.exitCode = 1;
}
