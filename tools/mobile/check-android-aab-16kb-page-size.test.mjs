import assert from "node:assert/strict";
import { chmod, mkdtemp, readFile, writeFile } from "node:fs/promises";
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

test("rejects an AAB whose bundle config lacks 16KB alignment", async () => {
  const fixture = await mkdtemp(path.join(tmpdir(), "android-16kb-aab-gate-"));
  const aab = path.join(fixture, "app.aab");
  const bundletool = path.join(fixture, "bundletool.jar");
  const java = path.join(fixture, "java");
  const evidence = path.join(fixture, "evidence");
  await writeFile(aab, "fixture");
  await writeFile(bundletool, "fixture");
  await writeFile(
    java,
    '#!/usr/bin/env bash\n[[ "$1" == -jar && "$3" == dump && "$4" == config ]] || exit 2\nprintf "%s\\n" "{\\"compression\\": {}}"\n',
  );
  await chmod(java, 0o755);

  await assert.rejects(
    execFileAsync(
      gate,
      ["--aab", aab, "--artifact-dir", evidence, "--bundletool", bundletool],
      { env: { ...process.env, PATH: `${fixture}:${process.env.PATH}` } },
    ),
    (error) => error.code === 1,
  );
  assert.match(await readFile(path.join(evidence, "summary.txt"), "utf8"), /missing_PAGE_ALIGNMENT_16K_native_library_alignment/);
});

test("runs the 16KB AAB gate before accepting the artifact hash", async () => {
  for (const workflow of [".github/workflows/ci.yml", ".github/workflows/release-artifacts.yml"]) {
    const text = await readFile(path.join(repositoryRoot, workflow), "utf8");
    const build = text.indexOf("flutter build appbundle --release");
    const gateInvocation = text.indexOf("check-android-aab-16kb-page-size.sh");
    const hash = text.indexOf("hash-android-bundle-payload.mjs");
    assert.ok(build >= 0, `${workflow} builds a release AAB`);
    assert.ok(gateInvocation > build, `${workflow} runs the 16KB gate after the AAB build`);
    assert.ok(gateInvocation < hash, `${workflow} runs the 16KB gate before accepting the AAB hash`);
    assert.ok(text.indexOf('java -jar "$candidate" version') > build, `${workflow} probes a runnable bundletool JAR`);
  }
});
