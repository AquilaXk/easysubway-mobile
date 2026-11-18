import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import test from 'node:test';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const repoRoot = resolve(__dirname, '../..');

export function validateFlutterSdkPin(root = repoRoot) {
  const pinPath = resolve(root, '.fvmrc');
  if (!existsSync(pinPath)) {
    throw new Error('Missing .fvmrc pin file');
  }
  const raw = readFileSync(pinPath, 'utf8');
  let config;
  try {
    config = JSON.parse(raw);
  } catch {
    throw new Error(`Malformed JSON in .fvmrc: ${raw}`);
  }
  const pinContent = config?.flutter;
  if (typeof pinContent !== 'string' || !/^\d+\.\d+\.\d+$/.test(pinContent)) {
    throw new Error(`Malformed Flutter version in .fvmrc: ${pinContent}`);
  }
  if (pinContent !== '3.44.0') {
    throw new Error(`Expected Flutter version 3.44.0, got ${pinContent}`);
  }

  // Verify consumers
  const workflows = [
    '.github/workflows/ci.yml',
    '.github/workflows/release-artifacts.yml',
  ];

  for (const wf of workflows) {
    const wfPath = resolve(root, wf);
    const content = readFileSync(wfPath, 'utf8');

    if (!content.includes('flutter-version-file: .fvmrc')) {
      throw new Error(`${wf} does not consume flutter-version-file: .fvmrc`);
    }
    if (content.includes('flutter-version: "3.44.0"')) {
      throw new Error(`${wf} still contains hardcoded flutter-version: "3.44.0"`);
    }
  }

  return pinContent;
}

test('validateFlutterSdkPin validates canonical .fvmrc pin and workflow consumers', () => {
  const version = validateFlutterSdkPin();
  assert.equal(version, '3.44.0');
});

test('validateFlutterSdkPin fails closed on missing pin or malformed pin', () => {
  assert.throws(() => validateFlutterSdkPin('/tmp/nonexistent-dir'), /Missing \.fvmrc pin file/);
});
