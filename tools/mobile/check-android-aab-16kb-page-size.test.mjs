import assert from "node:assert/strict";
import { mkdtemp, readFile, writeFile } from "node:fs/promises";
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
  const bundleConfig = path.join(fixture, "bundle-config.txt");
  const evidence = path.join(fixture, "evidence");
  await writeFile(aab, "fixture");
  await writeFile(bundleConfig, '{"compression": {}}\n');

  await assert.rejects(
    execFileAsync(gate, ["--aab", aab, "--bundle-config", bundleConfig, "--artifact-dir", evidence]),
    (error) => error.code === 1,
  );
  assert.match(await readFile(path.join(evidence, "summary.txt"), "utf8"), /missing_PAGE_ALIGNMENT_16K_native_library_alignment/);
});

test("pins AGP-loaded bundletool and orders config inspection before hashing", async () => {
  const gradle = await readFile(gradleBuild, "utf8");
  assert.match(gradle, /BundleToolVersion\.getCurrentVersion\(\)\.toString\(\) == "1\.18\.3"/);
  assert.match(gradle, /DumpCommand\.builder\(\)[\s\S]*?setDumpTarget\(DumpCommand\.DumpTarget\.CONFIG\)[\s\S]*?\.execute\(\)/);
  assert.match(gradle, /packaging\s*\{\s*jniLibs\s*\{\s*useLegacyPackaging\s*=\s*false\s*}\s*}/);

  for (const workflow of [".github/workflows/ci.yml", ".github/workflows/release-artifacts.yml"]) {
    const text = await readFile(path.join(repositoryRoot, workflow), "utf8");
    const build = text.indexOf("flutter build appbundle --release");
    const configTask = text.indexOf("dumpReleaseBundleConfig", build);
    const gateInvocation = text.indexOf("check-android-aab-16kb-page-size.sh", build);
    const hash = text.indexOf("hash-android-bundle-payload.mjs", build);
    assert.ok(build >= 0, `${workflow} builds a release AAB`);
    assert.ok(configTask > build, `${workflow} generates the bundle config after building the AAB`);
    assert.ok(gateInvocation > configTask, `${workflow} runs the gate after generating the config`);
    assert.ok(hash > gateInvocation, `${workflow} accepts the AAB hash after the gate`);
    assert.ok(text.indexOf('-Pandroid16kbAab="$PWD/build/app/outputs/bundle/release/app-release.aab"', configTask) > configTask, `${workflow} passes the AAB to Gradle as an absolute path`);
    assert.ok(text.indexOf("--bundle-config \"$bundle_config\"", configTask) > configTask, `${workflow} passes generated config to the gate`);
  }
});
