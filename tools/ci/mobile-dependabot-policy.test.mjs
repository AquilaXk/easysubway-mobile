import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const dependabot = readFileSync(
  new URL("../../.github/dependabot.yml", import.meta.url),
  "utf8",
);
const workflow = readFileSync(
  new URL("../../.github/workflows/ci.yml", import.meta.url),
  "utf8",
);
const pubspec = readFileSync(
  new URL("../../apps/mobile/pubspec.yaml", import.meta.url),
  "utf8",
);

function indentedBlock(source, header) {
  const lines = source.split("\n");
  const start = lines.indexOf(header);
  assert.notEqual(start, -1, `missing YAML block: ${header.trim()}`);

  const indent = header.search(/\S/u);
  let end = lines.length;
  for (let index = start + 1; index < lines.length; index += 1) {
    const line = lines[index];
    const trimmed = line.trim();
    if (trimmed === "" || trimmed.startsWith("#")) {
      continue;
    }
    if (line.search(/\S/u) <= indent) {
      end = index;
      break;
    }
  }
  return lines.slice(start, end).join("\n");
}

function assertLines(block, expectedLines) {
  for (const line of expectedLines) {
    assert.ok(block.includes(line), `missing policy line: ${line.trim()}`);
  }
}

test("pub version updates separate codegen and Workmanager compatibility lanes", () => {
  const pubUpdate = indentedBlock(dependabot, '  - package-ecosystem: "pub"');
  const codegen = indentedBlock(pubUpdate, "      pub-codegen:");
  const workmanager = indentedBlock(pubUpdate, "      pub-workmanager:");
  const general = indentedBlock(pubUpdate, "      pub-minor-patch:");

  assert.ok(
    pubUpdate.indexOf("      pub-codegen:") <
      pubUpdate.indexOf("      pub-minor-patch:"),
  );
  assert.ok(
    pubUpdate.indexOf("      pub-workmanager:") <
      pubUpdate.indexOf("      pub-minor-patch:"),
  );
  assert.match(pubUpdate, /^    open-pull-requests-limit: 5$/mu);

  assertLines(codegen, [
    "        applies-to: version-updates",
    '          - "build_runner"',
    '          - "drift_dev"',
    '          - "meta"',
    '          - "minor"',
    '          - "patch"',
  ]);
  assertLines(workmanager, [
    "        applies-to: version-updates",
    '          - "workmanager*"',
    '          - "major"',
    '          - "minor"',
    '          - "patch"',
  ]);
  assertLines(general, [
    "        applies-to: version-updates",
    '          - "*"',
    "        exclude-patterns:",
    '          - "build_runner"',
    '          - "drift_dev"',
    '          - "meta"',
    '          - "workmanager*"',
  ]);
});

test("known incompatible releases are ignored narrowly instead of hiding update classes", () => {
  const pubUpdate = indentedBlock(dependabot, '  - package-ecosystem: "pub"');
  const ignored = indentedBlock(pubUpdate, "    ignore:");

  assert.equal((ignored.match(/^      - dependency-name:/gmu) ?? []).length, 4);
  assert.doesNotMatch(ignored, /dependency-name: "\*"/u);
  assert.doesNotMatch(ignored, /update-types:/u);
  assertLines(ignored, [
    '      - dependency-name: "build_runner"\n        versions:\n          - "2.16.0"',
    '      - dependency-name: "meta"\n        versions:\n          - "1.19.0"',
    '      - dependency-name: "workmanager_android"\n        versions:\n          - "0.9.3"',
    '      - dependency-name: "workmanager_platform_interface"\n        versions:\n          - "0.9.4"',
  ]);
});

test("current Flutter and native compatibility pins stay exact and CI-owned", () => {
  assert.match(pubspec, /^  meta: 1\.18\.0$/mu);
  assert.match(pubspec, /^  workmanager_android: 0\.9\.0\+2$/mu);
  assert.match(pubspec, /^  workmanager_platform_interface: 0\.9\.1\+1$/mu);
  assert.match(pubspec, /^  build_runner: 2\.15\.1$/mu);
  assert.match(workflow, /^            tools\/ci\/mobile-dependabot-policy\.test\.mjs \\$/mu);
});
