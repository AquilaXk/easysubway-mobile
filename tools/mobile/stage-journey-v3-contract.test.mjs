import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { existsSync, lstatSync, mkdtempSync, mkdirSync, readFileSync, readdirSync, rmSync, symlinkSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, relative } from 'node:path';
import test from 'node:test';
import { stageJourneyV3ContractForTest } from './stage-journey-v3-contract.mjs';

const repository = join(import.meta.dirname, '..', '..');
const stager = join(repository, 'tools/mobile/stage-journey-v3-contract.mjs');
const sha256 = (value) => createHash('sha256').update(value).digest('hex');
function tokenFiles(root, token) { const found = []; const walk = (directory) => { for (const entry of readdirSync(directory).sort()) { const file = join(directory, entry); const stat = lstatSync(file); if (stat.isSymbolicLink()) continue; if (stat.isDirectory()) walk(file); else if (stat.isFile() && readFileSync(file).includes(token)) found.push(relative(root, file).split('\\').join('/')); } }; walk(join(root, 'tools')); return found.sort(); }

function fixture(root) {
  mkdirSync(root, { recursive: true });
  const files = [
    ['contracts/api/journey-v3-error-catalog.json', '{"errors":[]}'],
    ['contracts/api/journey-v3-error-disposition.json', '{"dispositions":[]}'],
    ['contracts/api/journey-v3.openapi.yaml', 'openapi: 3.1.0\n'],
  ];
  const lock = {
    schemaVersion: 2, component: 'backend', bundleVersion: '2.0.0',
    producer: { repository: 'owner/backend', gitSha: 'b'.repeat(40) },
    artifact: { repository: 'registry.example/backend', manifestDigest: `sha256:${'a'.repeat(64)}`, artifactType: 'application/vnd.example.journey.v2' },
    payload: { fileName: 'journey-v3-contract-bundle-v2.json', mediaType: 'application/vnd.example.journey.v2+json', sha256: '' },
    publicationReceiptSha256: 'c'.repeat(64),
    resources: files.map(([path, content], index) => ({ id: ['journey-v3-error-catalog', 'journey-v3-error-disposition', 'journey-v3-openapi'][index], path, owner: 'owner/backend', mediaType: path.endsWith('.yaml') ? 'application/yaml' : 'application/json', sha256: sha256(content) })),
  };
  const payload = { schemaVersion: 2, bundleVersion: lock.bundleVersion, component: lock.component, producerRepository: lock.producer.repository, producerSha: lock.producer.gitSha, resources: files.map(([path, content], index) => ({ ...lock.resources[index], contentBase64: Buffer.from(content).toString('base64') })) };
  lock.payload.sha256 = sha256(JSON.stringify(payload));
  const lockPath = join(root, 'lock.json');
  const inputPath = join(root, lock.payload.fileName);
  writeFileSync(lockPath, `${JSON.stringify(lock, null, 2)}\n`);
  writeFileSync(inputPath, JSON.stringify(payload));
  return { lock, payload, lockPath, inputPath };
}

function persist({ lock, payload, lockPath, inputPath }) {
  lock.payload.sha256 = sha256(JSON.stringify(payload));
  writeFileSync(lockPath, `${JSON.stringify(lock, null, 2)}\n`);
  writeFileSync(inputPath, JSON.stringify(payload));
}

function run(fixture_, output) {
  return stageJourneyV3ContractForTest({ lockPath: fixture_.lockPath, inputPath: fixture_.inputPath, outputPath: output, buildRoot: fixture_.buildRoot });
}

function fails(fixture_, output, message) {
  assert.throws(() => run(fixture_, output), new RegExp(`stage-journey-v3-contract: ${message}`));
}

test('stages only the exact lock-bound bundle and receipt', () => {
  const root = mkdtempSync(join(tmpdir(), 'journey-stage-'));
  let output;
  try {
    const { lock, lockPath, inputPath } = fixture(root);
    output = join(repository, 'build', `journey-stage-test-${process.pid}-${Date.now()}`);
    const fixture_ = { lock, payload: JSON.parse(readFileSync(inputPath, 'utf8')), lockPath, inputPath };
    run(fixture_, output);
    assert.equal(readFileSync(join(output, lock.resources[0].path), 'utf8'), '{"errors":[]}');
    const receipt = JSON.parse(readFileSync(join(output, 'journey-v3-contract-stage-receipt.json'), 'utf8'));
    assert.equal(receipt.payloadSha256, lock.payload.sha256);
    assert.equal(receipt.lockSha256, sha256(readFileSync(lockPath)));
    assert.deepEqual(Object.keys(receipt.resources), lock.resources.map(({ path }) => path));
    fails(fixture_, output, 'output must be absent');
  } finally { if (output) rmSync(output, { recursive: true, force: true }); rmSync(root, { recursive: true, force: true }); }
});

test('fails closed for identity, semantic, duplicate, unsafe, or non-canonical payloads', () => {
  const root = mkdtempSync(join(tmpdir(), 'journey-stage-'));
  try {
    const output = join(repository, 'build', `journey-stage-test-${process.pid}-${Date.now()}`);
    const producer = fixture(join(root, 'producer')); persist(producer); producer.payload.producerRepository = 'other/backend'; persist(producer); fails(producer, output, 'payload identity or resource set does not match lock');
    const count = fixture(join(root, 'count')); persist(count); count.payload.resources.push(count.payload.resources[0]); persist(count); fails(count, output, 'payload identity or resource set does not match lock');
    const unsafe = fixture(join(root, 'unsafe')); persist(unsafe); unsafe.lock.resources[0].path = '../escape'; unsafe.payload.resources[0].path = '../escape'; persist(unsafe); fails(unsafe, output, 'lock.resources\\[0\\].path is unsafe');
    const base64 = fixture(join(root, 'base64')); persist(base64); base64.payload.resources[0].contentBase64 = 'YQ'; persist(base64); fails(base64, output, 'payload resource 0 is not canonical base64');
    const duplicate = fixture(join(root, 'duplicate')); persist(duplicate); writeFileSync(duplicate.inputPath, '{"schemaVersion":2,"schemaVersion":2}'); fails(duplicate, output, 'payload has duplicate key schemaVersion');
  } finally { rmSync(root, { recursive: true, force: true }); }
});

test('rejects symlink inputs and output outside a safe absent directory below build', () => {
  const root = mkdtempSync(join(tmpdir(), 'journey-stage-'));
  try {
    const fixture_ = fixture(root);
    const output = join(repository, 'build', `journey-stage-test-${process.pid}-${Date.now()}`);
    const inputLink = join(root, 'payload-link.json'); symlinkSync(fixture_.inputPath, inputLink); fails({ ...fixture_, inputPath: inputLink }, output, 'input must be a regular non-symlink file');
    fails(fixture_, join(root, 'outside-build'), 'output must be an absent direct child below repository build');
    const linkParent = join(repository, 'build', `journey-stage-link-${process.pid}-${Date.now()}`); symlinkSync(root, linkParent); fails(fixture_, join(linkParent, 'output'), 'output must be an absent direct child below repository build'); rmSync(linkParent);
  } finally { rmSync(root, { recursive: true, force: true }); }
});

test('production CLI rejects a self-consistent alternate lock and never replaces incomplete output', () => {
  const root = mkdtempSync(join(tmpdir(), 'journey-stage-'));
  let output; let sibling;
  try {
    const fixture_ = fixture(root); persist(fixture_);
    output = join(repository, 'build', `journey-stage-test-${process.pid}-${Date.now()}`);
    assert.throws(() => execFileSync(process.execPath, [stager, '--lock', fixture_.lockPath, '--input', fixture_.inputPath, '--output', output], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }), /lock must be the tracked journey-v3-client lock/);
    sibling = `${output}.sibling`; writeFileSync(sibling, 'sibling-unchanged');
    mkdirSync(output); writeFileSync(join(output, 'partial'), 'unchanged');
    fails(fixture_, output, 'output must be absent');
    assert.equal(readFileSync(join(output, 'partial'), 'utf8'), 'unchanged');
    assert.equal(readFileSync(sibling, 'utf8'), 'sibling-unchanged');
  } finally { if (output) rmSync(output, { recursive: true, force: true }); if (sibling) rmSync(sibling, { force: true }); rmSync(root, { recursive: true, force: true }); }
});

test('creates an absent non-symlink build root and keeps the test seam private', () => {
  const root = mkdtempSync(join(tmpdir(), 'journey-stage-'));
  try {
    const fixture_ = fixture(join(root, 'fixture')); persist(fixture_);
    const testBuildRoot = join(root, 'build');
    run({ ...fixture_, buildRoot: testBuildRoot }, join(testBuildRoot, 'stage'));
    assert.equal(readFileSync(join(testBuildRoot, 'stage', fixture_.lock.resources[2].path), 'utf8'), 'openapi: 3.1.0\n');
    const symlinkBuildRoot = join(root, 'symlink-build'); symlinkSync(root, symlinkBuildRoot);
    fails({ ...fixture_, buildRoot: symlinkBuildRoot }, join(symlinkBuildRoot, 'stage'), 'build root must be an existing non-symlink directory');
    const references = tokenFiles(repository, 'stageJourneyV3ContractForTest');
    assert.deepEqual(references, ['tools/mobile/stage-journey-v3-contract.mjs', 'tools/mobile/stage-journey-v3-contract.test.mjs']);
  } finally { rmSync(root, { recursive: true, force: true }); }
});
