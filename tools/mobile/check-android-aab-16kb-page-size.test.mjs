import assert from "node:assert/strict";
import { chmod, mkdir, mkdtemp, readFile, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import test from "node:test";

const execFileAsync = promisify(execFile);
const here = path.dirname(fileURLToPath(import.meta.url));
const repositoryRoot = path.resolve(here, "../..");
const gate = path.join(here, "check-android-aab-16kb-page-size.sh");
const gradleBuild = path.join(repositoryRoot, "apps/mobile/android/app/build.gradle.kts");

test("rejects a generated bundle config without 16KB alignment", async () => {
  const fixture = await mkdtemp(path.join(tmpdir(), "android-16kb-aab-gate-"));
  const aab = path.join(fixture, "app.aab");
  const androidProject = path.join(fixture, "android");
  const gradlew = path.join(androidProject, "gradlew");
  const evidence = path.join(fixture, "evidence");
  await writeFile(aab, "fixture");
  await mkdir(androidProject, { recursive: true });
  await writeFile(
    gradlew,
    `#!/usr/bin/env bash
set -euo pipefail
[[ "$1" == "-p" && "$2" == "$(dirname "$0")" && "$3" == ":app:dumpAndroidBundleConfig" && "$4" == -Pandroid16kbAab=* && "$5" == -Pandroid16kbBundleConfig=* ]] || exit 2
aab="\${4#-Pandroid16kbAab=}"
output="\${5#-Pandroid16kbBundleConfig=}"
[[ "$aab" == "$(cd "$(dirname "$0")/.." && pwd -P)/app.aab" && "$output" == /* ]] || exit 2
mkdir -p "$(dirname "$output")"
printf '%s\\n' '{"compression": {}}' > "$output"
`,
  );
  await chmod(gradlew, 0o755);

  await assert.rejects(
    execFileAsync(gate, ["--aab", aab, "--android-project", androidProject, "--artifact-dir", evidence]),
    (error) => error.code === 1,
  );
  assert.match(await readFile(path.join(evidence, "summary.txt"), "utf8"), /missing_PAGE_ALIGNMENT_16K_native_library_alignment/);
  assert.equal(await readFile(path.join(evidence, "bundle-config.txt"), "utf8"), '{"compression": {}}\n');
});

test("pins AGP-loaded bundletool and orders config inspection before hashing", async () => {
  const gradle = await readFile(gradleBuild, "utf8");
  assert.match(gradle, /BundleToolVersion\.getCurrentVersion\(\)\.toString\(\) == "1\.18\.3"/);
  assert.match(gradle, /DumpCommand\.builder\(\)[\s\S]*?setDumpTarget\(DumpCommand\.DumpTarget\.CONFIG\)[\s\S]*?\.execute\(\)/);
  assert.match(gradle, /packaging\s*\{\s*jniLibs\s*\{\s*useLegacyPackaging\s*=\s*false\s*}\s*}/);

  for (const workflow of [".github/workflows/ci.yml", ".github/workflows/release-artifacts.yml"]) {
    const text = await readFile(path.join(repositoryRoot, workflow), "utf8");
    const build = text.indexOf("flutter build appbundle --release");
    const gateInvocation = text.indexOf("check-android-aab-16kb-page-size.sh", build);
    const hash = text.indexOf("hash-android-bundle-payload.mjs", build);
    assert.ok(build >= 0, `${workflow} builds a release AAB`);
    assert.ok(gateInvocation > build, `${workflow} runs the gate after building the AAB`);
    assert.ok(hash > gateInvocation, `${workflow} accepts the AAB hash after the gate`);
    assert.ok(text.indexOf("--android-project android", gateInvocation) > gateInvocation, `${workflow} binds config generation to the Android project inside the gate`);
    assert.equal(text.indexOf("dumpAndroidBundleConfig", build), -1, `${workflow} does not split config generation from the gate`);
  }
});
