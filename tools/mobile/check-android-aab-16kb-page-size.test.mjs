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

test("fails closed for missing 16KB alignment and ambiguous thin-JAR dependencies", async () => {
  const fixture = await mkdtemp(path.join(tmpdir(), "android-16kb-aab-gate-"));
  const aab = path.join(fixture, "app.aab");
  const gradleCache = path.join(fixture, "gradle", "caches", "modules-2", "files-2.1");
  const bundletool = path.join(fixture, "bundletool-1.18.3.jar");
  const manifestRoot = path.join(fixture, "manifest");
  const java = path.join(fixture, "java");
  const evidence = path.join(fixture, "evidence");
  await writeFile(aab, "fixture");
  await mkdir(path.join(manifestRoot, "META-INF"), { recursive: true });
  await writeFile(
    path.join(manifestRoot, "META-INF", "MANIFEST.MF"),
    "Manifest-Version: 1.0\r\nClass-Path: dependency-one.jar \r\n dependency-two.jar\r\n\r\n",
  );
  await execFileAsync("zip", ["-q", "-r", bundletool, "META-INF"], { cwd: manifestRoot });
  for (const dependency of ["dependency-one.jar", "dependency-two.jar"]) {
    const dependencyPath = path.join(gradleCache, "fixture", dependency);
    await mkdir(path.dirname(dependencyPath), { recursive: true });
    await writeFile(dependencyPath, "fixture");
  }
  await writeFile(
    java,
    '#!/usr/bin/env bash\n[[ "$1" == -cp && "$3" == com.android.tools.build.bundletool.BundleToolMain && "$4" == dump && "$5" == config && "$2" == *dependency-one.jar* && "$2" == *dependency-two.jar* ]] || exit 2\nprintf "%s\\n" "{\\"compression\\": {}}"\n',
  );
  await chmod(java, 0o755);

  await assert.rejects(
    execFileAsync(
      gate,
      ["--aab", aab, "--artifact-dir", evidence, "--bundletool", bundletool],
      { env: { ...process.env, GRADLE_USER_HOME: path.join(fixture, "gradle"), PATH: `${fixture}:${process.env.PATH}` } },
    ),
    (error) => error.code === 1,
  );
  assert.match(await readFile(path.join(evidence, "summary.txt"), "utf8"), /missing_PAGE_ALIGNMENT_16K_native_library_alignment/);

  const duplicateDependency = path.join(gradleCache, "duplicate", "dependency-one.jar");
  await mkdir(path.dirname(duplicateDependency), { recursive: true });
  await writeFile(duplicateDependency, "fixture");
  await assert.rejects(
    execFileAsync(
      gate,
      ["--aab", aab, "--artifact-dir", evidence, "--bundletool", bundletool],
      { env: { ...process.env, GRADLE_USER_HOME: path.join(fixture, "gradle"), PATH: `${fixture}:${process.env.PATH}` } },
    ),
    (error) => error.code === 2 && /dependency is ambiguous: dependency-one\.jar/.test(error.stderr),
  );
});

test("runs the 16KB AAB gate before accepting the artifact hash", async () => {
  for (const workflow of [".github/workflows/ci.yml", ".github/workflows/release-artifacts.yml"]) {
    const text = await readFile(path.join(repositoryRoot, workflow), "utf8");
    const build = text.indexOf("flutter build appbundle --release");
    const gateInvocation = text.indexOf("check-android-aab-16kb-page-size.sh", build);
    const hash = text.indexOf("hash-android-bundle-payload.mjs", build);
    assert.ok(build >= 0, `${workflow} builds a release AAB`);
    assert.ok(gateInvocation > build, `${workflow} runs the 16KB gate after the AAB build`);
    assert.ok(gateInvocation < hash, `${workflow} runs the 16KB gate before accepting the AAB hash`);
    assert.equal(text.indexOf("command -v bundletool", build), -1, `${workflow} does not allow a PATH bundletool`);
    assert.ok(text.indexOf("bundletool/1.18.3") > build, `${workflow} selects only AGP 9.0.1's bundletool 1.18.3 artifact`);
  }
});
