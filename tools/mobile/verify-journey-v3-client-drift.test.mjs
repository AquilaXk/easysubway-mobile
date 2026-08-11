import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { chmodSync, cpSync, existsSync, mkdtempSync, mkdirSync, readFileSync, readdirSync, rmSync, symlinkSync, unlinkSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';

import { generateJourneyV3ClientForTest, journeyV3ReceiptV2ContractForTest, selectJourneyV3GenerationReceiptForDrift, validateJourneyV3MobileSourceForTest, validateJourneyV3NodeRuntimeForTest } from './generate-journey-v3-client.mjs';
import { verifyJourneyV3ClientDriftForTest } from './verify-journey-v3-client-drift.mjs';

const repository = join(import.meta.dirname, '..', '..');
const generator = join(repository, 'tools/mobile/generate-journey-v3-client.mjs');
const verifier = join(repository, 'tools/mobile/verify-journey-v3-client-drift.mjs');
const ciWorkflow = join(repository, '.github/workflows/ci.yml');
const fixtureRoot = join(repository, 'tools/mobile/fixtures/journey-v3-contract-v2');
const lockPath = join(repository, 'contracts/mobile/journey-v3-client.lock.json');
const receiptName = 'journey_v3_generation_receipt.json';
const sha256 = (bytes) => createHash('sha256').update(bytes).digest('hex');

function stage(root) {
  const contractRoot = join(root, 'contract');
  const apiRoot = join(contractRoot, 'contracts/api');
  mkdirSync(join(contractRoot, 'contracts'), { recursive: true });
  cpSync(join(fixtureRoot, 'contracts/api'), apiRoot, { recursive: true });
  const lock = JSON.parse(readFileSync(lockPath));
  const receipt = {
    schemaVersion: 1,
    lockSha256: sha256(readFileSync(lockPath)),
    payloadSha256: lock.payload.sha256,
    publicationReceiptSha256: lock.publicationReceiptSha256,
    artifact: lock.artifact,
    resources: Object.fromEntries(lock.resources.map(({ path, sha256: digest }) => [path, digest])),
  };
  writeFileSync(join(contractRoot, 'journey-v3-contract-stage-receipt.json'), `${JSON.stringify(receipt)}\n`);
  return contractRoot;
}

function generate(contractRoot, outputRoot, receiptPath = join(outputRoot, receiptName)) {
  execFileSync(process.execPath, [generator, '--contract-root', contractRoot, '--lock', lockPath, '--output-root', outputRoot, '--receipt', receiptPath], { encoding: 'utf8', stdio: 'pipe' });
}

function treeBytes(root) {
  return Object.fromEntries(readdirSync(root).sort().map((name) => [name, readFileSync(join(root, name))]));
}

function copyTree(source, destination) {
  cpSync(source, destination, { recursive: true });
  return destination;
}

test('validates the v2 receipt identity and source commit proof seams fail closed', () => {
  const contract = journeyV3ReceiptV2ContractForTest();
  const sourceSha = 'a'.repeat(40); const generatorBytes = Buffer.from('generator'); const lockBytes = Buffer.from('lock');
  const git = (args) => {
    if (args[0] === 'merge-base') return { status: 0 };
    if (args[0] === 'log') return { status: 0, stdout: Buffer.from(`${sourceSha}\n`) };
    if (args[1].endsWith('generate-journey-v3-client.mjs')) return { status: 0, stdout: generatorBytes };
    if (args[1].endsWith('journey-v3-client.lock.json')) return { status: 0, stdout: lockBytes };
    return { status: 1 };
  };
  assert.equal(validateJourneyV3MobileSourceForTest({ sourceSha, gitApi: git, generatorBytes, lockBytes }), sourceSha);
  for (const invalid of ['', 'A'.repeat(40), 'a'.repeat(39)]) assert.throws(() => validateJourneyV3MobileSourceForTest({ sourceSha: invalid, gitApi: git, generatorBytes, lockBytes }), /lowercase 40-hex/);
  assert.throws(() => validateJourneyV3MobileSourceForTest({ sourceSha, gitApi: () => ({ status: 1 }), generatorBytes, lockBytes }), /ancestor of HEAD/);
  assert.throws(() => validateJourneyV3MobileSourceForTest({ sourceSha, gitApi: (args) => args[0] === 'merge-base' ? { status: 0 } : args[0] === 'log' ? { status: 0, stdout: Buffer.from(`${'b'.repeat(40)}\n`) } : { status: 0, stdout: generatorBytes }, generatorBytes, lockBytes }), /latest generator and lock source revision/);
  assert.throws(() => validateJourneyV3MobileSourceForTest({ sourceSha, gitApi: (args) => args[0] === 'merge-base' ? { status: 0 } : args[0] === 'log' ? { status: 0, stdout: Buffer.from(`${sourceSha}\n`) } : { status: 0, stdout: Buffer.from('wrong') }, generatorBytes, lockBytes }), /generate-journey-v3-client\.mjs blob differs/);
  assert.throws(() => validateJourneyV3MobileSourceForTest({ sourceSha, gitApi: (args) => args[0] === 'merge-base' ? { status: 0 } : args[0] === 'log' ? { status: 0, stdout: Buffer.from(`${sourceSha}\n`) } : args[1].endsWith('generate-journey-v3-client.mjs') ? { status: 0, stdout: generatorBytes } : { status: 0, stdout: Buffer.from('wrong') }, generatorBytes, lockBytes }), /lock.*blob differs/);
  assert.throws(() => validateJourneyV3NodeRuntimeForTest(23), /Node 24 is required/);
  assert.equal(validateJourneyV3NodeRuntimeForTest(24), undefined);
  const receipt = { schemaVersion: 2, generator: { ...contract.generator, sourceSha256: 'b'.repeat(64) }, mobileRepository: { repository: contract.mobileRepository, generationSourceCommitSha: sourceSha }, runtime: contract.runtime, command: contract.command, configSha256: contract.configSha256, lockSha256: 'c'.repeat(64), producer: {}, artifact: {}, payload: {}, publicationReceiptSha256: 'd'.repeat(64), resources: [], supportedFeatures: [], files: [], treeSha256: 'e'.repeat(64) };
  assert.deepEqual(contract.command.arguments, ['--contract-root', '<staged-contract-root>', '--lock', 'contracts/mobile/journey-v3-client.lock.json', '--output-root', '<absent-output-root>', '--receipt', '<output-root>/journey_v3_generation_receipt.json', '--mobile-source-sha', '<generation-source-commit>']);
  assert.deepEqual(selectJourneyV3GenerationReceiptForDrift(Buffer.from(JSON.stringify(receipt))), receipt);
  for (const mutate of [(value) => { value.command = { ...value.command, script: 'other.mjs' }; }, (value) => { value.runtime = { node: { ...value.runtime.node, majorVersion: 23 } }; }, (value) => { value.configSha256 = 'f'.repeat(64); }]) { const tampered = structuredClone(receipt); mutate(tampered); assert.throws(() => selectJourneyV3GenerationReceiptForDrift(Buffer.from(JSON.stringify(tampered))), /unsupported v2 generator identity/); }
});

test('generates and verifies one deterministic exact receipt-last Journey V3 tree', () => {
  const root = mkdtempSync(join(tmpdir(), 'journey-v3-drift-'));
  try {
    const contractRoot = stage(root);
    const first = join(root, 'first');
    const second = join(root, 'second');
    generate(contractRoot, first);
    generate(contractRoot, second);
    assert.deepEqual(treeBytes(first), treeBytes(second));
    const result = verifyJourneyV3ClientDriftForTest({ contractRoot, lockPath, generatedRoot: first });
    assert.equal(result.receipt.schemaVersion, 1);
    assert.equal(result.receipt.generator.id, 'easysubway-mobile-journey-v3-client');
    assert.deepEqual(result.receipt.generator.formatter, { command: 'dart format', sdkVersion: '3.12.0' });
    assert.equal(result.receipt.files.length, 5);
    assert.deepEqual(result.receipt.supportedFeatures, ['array', 'boolean', 'closed-object', 'enum', 'integer-bounds', 'json-post', 'local-ref', 'nullable', 'openapi-3.0.3', 'request-response-security', 'strict-yaml-subset', 'string-constraints', 'tagged-one-of']);
    const treeIdentity = result.receipt.files.map(({ path, sha256: digest }) => `${path}\0${digest}\n`).join('');
    assert.equal(result.receipt.treeSha256, sha256(treeIdentity));
    assert.equal(result.receipt.generator.sourceSha256, sha256(readFileSync(generator)));
    assert.equal(existsSync(join(first, receiptName)), true);
  } finally { rmSync(root, { recursive: true, force: true }); }
});

test('fails closed on missing, extra, changed, incomplete, and symlink generated trees', () => {
  const root = mkdtempSync(join(tmpdir(), 'journey-v3-drift-'));
  try {
    const contractRoot = stage(root);
    const baseline = join(root, 'baseline');
    generate(contractRoot, baseline);
    const verify = (generatedRoot) => verifyJourneyV3ClientDriftForTest({ contractRoot, lockPath, generatedRoot });

    const missing = copyTree(baseline, join(root, 'missing'));
    unlinkSync(join(missing, 'journey_v3_models.dart'));
    assert.throws(() => verify(missing), /generated file set/);

    const extra = copyTree(baseline, join(root, 'extra'));
    writeFileSync(join(extra, 'unexpected.dart'), 'unexpected\n');
    assert.throws(() => verify(extra), /generated file set/);

    const changed = copyTree(baseline, join(root, 'changed'));
    writeFileSync(join(changed, 'journey_v3_error.dart'), 'changed\n');
    assert.throws(() => verify(changed), /differs from regenerated bytes/);

    const incomplete = copyTree(baseline, join(root, 'incomplete'));
    unlinkSync(join(incomplete, receiptName));
    assert.throws(() => verify(incomplete), /generated file set/);

    const leafSymlink = copyTree(baseline, join(root, 'leaf-symlink'));
    unlinkSync(join(leafSymlink, 'journey_v3_models.dart'));
    symlinkSync('journey_v3_enums.dart', join(leafSymlink, 'journey_v3_models.dart'));
    assert.throws(() => verify(leafSymlink), /regular non-symlink/);

    const rootSymlink = join(root, 'root-symlink');
    symlinkSync(baseline, rootSymlink, 'dir');
    assert.throws(() => verify(rootSymlink), /real non-symlink directory/);
  } finally { rmSync(root, { recursive: true, force: true }); }
});

test('generator never replaces an existing or wrongly addressed output', () => {
  const root = mkdtempSync(join(tmpdir(), 'journey-v3-drift-'));
  try {
    const contractRoot = stage(root);
    const outputRoot = join(root, 'generated');
    generate(contractRoot, outputRoot);
    const before = treeBytes(outputRoot);
    assert.throws(() => generate(contractRoot, outputRoot), /output root must be absent/);
    assert.deepEqual(treeBytes(outputRoot), before);

    const incomplete = join(root, 'incomplete-output');
    mkdirSync(incomplete);
    writeFileSync(join(incomplete, 'journey_v3_models.dart'), 'preserve\n');
    assert.throws(() => generate(contractRoot, incomplete), /output root must be absent/);
    assert.equal(readFileSync(join(incomplete, 'journey_v3_models.dart'), 'utf8'), 'preserve\n');

    const wrongRoot = join(root, 'wrong-receipt');
    assert.throws(() => generate(contractRoot, wrongRoot, join(root, receiptName)), /receipt must be the exact output-root generation receipt/);
    assert.equal(existsSync(wrongRoot), false);

    const realParent = join(root, 'real-parent');
    const symlinkParent = join(root, 'symlink-parent');
    mkdirSync(realParent);
    symlinkSync(realParent, symlinkParent, 'dir');
    assert.throws(() => generate(contractRoot, join(symlinkParent, 'generated')), /output parent must be a real non-symlink directory/);
    assert.equal(readdirSync(realParent).length, 0);

    const formatterUnavailable = join(root, 'formatter-unavailable');
    assert.throws(
      () => execFileSync(process.execPath, [generator, '--contract-root', contractRoot, '--lock', lockPath, '--output-root', formatterUnavailable, '--receipt', join(formatterUnavailable, receiptName)], { encoding: 'utf8', stdio: 'pipe', env: { ...process.env, PATH: '/nonexistent' } }),
      /Dart formatter is required/,
    );
    assert.equal(existsSync(formatterUnavailable), false);
  } finally { rmSync(root, { recursive: true, force: true }); }
});

test('input changes before publish or before receipt leave no generated output', () => {
  const root = mkdtempSync(join(tmpdir(), 'journey-v3-drift-'));
  try {
    const beforePublishContract = stage(join(root, 'before-publish'));
    const beforePublishResource = join(beforePublishContract, 'contracts/api/journey-v3.openapi.yaml');
    const mutatingDart = join(root, 'mutating-dart.mjs');
    writeFileSync(mutatingDart, `#!/usr/bin/env node\nimport { appendFileSync } from 'node:fs';\nif (process.argv[2] === '--version') { process.stderr.write('Dart SDK version: 3.12.0 (stable) test\\n'); process.exit(0); }\nif (process.argv[2] === 'format') { appendFileSync(${JSON.stringify(beforePublishResource)}, '\\n'); process.exit(0); }\nprocess.exit(2);\n`);
    chmodSync(mutatingDart, 0o700);
    const beforePublishOutput = join(root, 'before-publish-output');
    assert.throws(
      () => generateJourneyV3ClientForTest({ contractRoot: beforePublishContract, lockPath, outputRoot: beforePublishOutput, receiptPath: join(beforePublishOutput, receiptName), dartExecutable: mutatingDart }),
      /changed during generation/,
    );
    assert.equal(existsSync(beforePublishOutput), false);

    const beforeReceiptContract = stage(join(root, 'before-receipt'));
    const beforeReceiptResource = join(beforeReceiptContract, 'contracts/api/journey-v3.openapi.yaml');
    const beforeReceiptOutput = join(root, 'before-receipt-output');
    assert.throws(
      () => generateJourneyV3ClientForTest({
        contractRoot: beforeReceiptContract,
        lockPath,
        outputRoot: beforeReceiptOutput,
        receiptPath: join(beforeReceiptOutput, receiptName),
        beforeReceiptForTest: () => {
          assert.deepEqual(readdirSync(beforeReceiptOutput).sort(), ['journey_v3_contract.dart', 'journey_v3_enums.dart', 'journey_v3_error.dart', 'journey_v3_models.dart', 'journey_v3_validation.dart']);
          assert.equal(existsSync(join(beforeReceiptOutput, receiptName)), false);
          writeFileSync(beforeReceiptResource, `${readFileSync(beforeReceiptResource, 'utf8')}\n`);
        },
      }),
      /changed during generation/,
    );
    assert.equal(existsSync(beforeReceiptOutput), false);
  } finally { rmSync(root, { recursive: true, force: true }); }
});

test('production verifier CLI accepts only the exact generated tree', () => {
  const root = mkdtempSync(join(tmpdir(), 'journey-v3-drift-'));
  try {
    const contractRoot = stage(root);
    const generatedRoot = join(root, 'generated');
    generate(contractRoot, generatedRoot);
    execFileSync(process.execPath, [verifier, '--contract-root', contractRoot, '--lock', lockPath, '--generated-root', generatedRoot], { encoding: 'utf8', stdio: 'pipe' });
  } finally { rmSync(root, { recursive: true, force: true }); }
});

test('Mobile CI pulls the locked OCI payload before stage, generation, drift, and Dart checks', () => {
  const workflow = readFileSync(ciWorkflow, 'utf8');
  const setupOras = workflow.indexOf('      - name: Set up ORAS\n');
  const pull = workflow.indexOf('      - name: Pull locked Journey V3 contract bundle\n');
  const stageContract = workflow.indexOf('      - name: Stage locked Journey V3 contract\n');
  const generateAndVerify = workflow.indexOf('      - name: Generate and verify Journey V3 client\n');
  const setupFlutter = workflow.indexOf('      - name: Set up Flutter\n');
  const focusedChecks = workflow.indexOf('      - name: Run Journey V3 generator checks\n');
  const installFlutter = workflow.indexOf('      - name: Install Flutter dependencies\n');
  assert.ok(setupOras >= 0 && setupOras < pull && pull < stageContract && stageContract < setupFlutter);
  assert.ok(setupFlutter < generateAndVerify && generateAndVerify < focusedChecks && focusedChecks < installFlutter);

  const journeySteps = workflow.slice(setupOras, focusedChecks);
  assert.match(journeySteps, /uses: oras-project\/setup-oras@1d808f7d7f6995cc68b7bf507bfe5c5446e1dc9d/);
  assert.match(journeySteps, /version: 1\.3\.3/);
  assert.match(journeySteps, /oras pull "\$\{journey_contract_subject\}" --output "\$JOURNEY_PULL_ROOT"/);
  assert.match(journeySteps, /node tools\/mobile\/stage-journey-v3-contract\.mjs/);
  assert.match(journeySteps, /node tools\/mobile\/generate-journey-v3-client\.mjs/);
  assert.equal((journeySteps.match(/node tools\/mobile\/verify-journey-v3-client-drift\.mjs/g) ?? []).length, 2);
  assert.match(journeySteps, /--generated-root apps\/mobile\/lib\/generated\/journey_v3/);
  assert.doesNotMatch(journeySteps, /continue-on-error|\|\| true/);

  const checks = workflow.slice(focusedChecks, installFlutter);
  assert.match(checks, /tools\/mobile\/stage-journey-v3-contract\.test\.mjs/);
  assert.match(checks, /tools\/mobile\/generate-journey-v3-client\.test\.mjs/);
  assert.match(checks, /tools\/mobile\/verify-journey-v3-client-drift\.test\.mjs/);
});
