import assert from "node:assert/strict";
import { execFileSync, spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

import {
  HEAVY_LANES,
  decideScope,
  isSkipEligiblePath,
} from "./mobile-ci-scope.mjs";

const scriptPath = fileURLToPath(new URL("./mobile-ci-scope.mjs", import.meta.url));

// 경로 → 무거운 lane(host tests·Android 빌드) 실행 여부 계약. 실행 대상 밖으로 증명된 경로만
// 건너뛸 수 있고, 그 외 경로가 하나라도 섞이면 전체 실행이다.
const SKIP_ELIGIBLE = [
  ".github/workflows/automerge-queue.yml",
  ".github/workflows/mobile-golden.yml",
  ".github/workflows/release-artifacts.yml",
  ".github/dependabot.yml",
  ".github/pull_request_template.md",
  ".github/PULL_REQUEST_TEMPLATE/full.md",
  ".github/ISSUE_TEMPLATE/bug.yml",
  "README.md",
  "README.ko.md",
  "tools/mobile/automerge-queue.test.mjs",
  "tools/ci/mobile-ci-scope.test.mjs",
  "tools/release/hash-android-bundle-payload.test.mjs",
];

const RUN_REQUIRED = [
  // CI 자신과 판정기 자신
  ".github/workflows/ci.yml",
  "tools/ci/mobile-ci-scope.mjs",
  // 앱·네이티브·의존성
  "apps/mobile/lib/main.dart",
  "apps/mobile/test/widget_test.dart",
  "apps/mobile/android/app/build.gradle.kts",
  "apps/mobile/pubspec.yaml",
  "apps/mobile/pubspec.lock",
  "apps/mobile/analysis_options.yaml",
  "apps/mobile/assets/datapacks/index.json",
  // 계약 입력과 테스트가 런타임에 읽는 저장소 파일
  "contracts/mobile/crashlytics-secret-injection.json",
  "contracts/mobile/journey-v3-client.lock.json",
  "tools/design/easysubway-color-system.json",
  // 무거운 lane이 실행하는 도구와 fixture
  "tools/ci/mobile-host-test-parity.mjs",
  "tools/ci/mobile-coverage-baseline.json",
  "tools/mobile/check-android-aab-16kb-page-size.sh",
  "tools/release/hash-android-bundle-payload.mjs",
  "tools/mobile/fixtures/journey-v3-contract-v2/sample.test.mjs",
  // 툴체인 핀과 루트 설정
  ".fvmrc",
  ".tool-versions",
  ".nvmrc",
  "package.json",
  ".gitattributes",
  ".gitignore",
  // 분류되지 않은 경로와 비정규 경로
  ".github/CODEOWNERS",
  ".github/workflows/nested/x.yml",
  ".github/workflows/ci.yml.bak",
  "docs/notes.md",
  "README.md/extra",
  "./README.md",
  "/README.md",
  "tools/../README.md",
  "tools/ci\\x.test.mjs",
  "",
];

test("실행 대상 밖으로 증명된 경로만 skip 가능하다", () => {
  for (const changed of SKIP_ELIGIBLE) {
    assert.equal(isSkipEligiblePath(changed), true, changed);
  }
  for (const changed of RUN_REQUIRED) {
    assert.equal(isSkipEligiblePath(changed), false, JSON.stringify(changed));
  }
});

test("pull_request에서 skip 가능 경로만 바뀌면 무거운 lane을 건너뛴다", () => {
  const decision = decideScope({
    event: "pull_request",
    changedPaths: [".github/workflows/automerge-queue.yml", "tools/mobile/automerge-queue.test.mjs", "README.md"],
  });
  assert.deepEqual(decision, {
    runHeavyLanes: false,
    reason: "SKIP_ELIGIBLE_PATHS_ONLY",
    blockingPaths: [],
  });
});

test("실행 필요 경로가 하나라도 섞이면 전체 실행이다", () => {
  for (const blocking of RUN_REQUIRED.filter((value) => value !== "")) {
    const decision = decideScope({ event: "pull_request", changedPaths: ["README.md", blocking] });
    assert.equal(decision.runHeavyLanes, true, blocking);
    assert.equal(decision.reason, "RUN_REQUIRED_PATH", blocking);
    assert.deepEqual(decision.blockingPaths, [blocking]);
  }
});

test("main push·dispatch·빈 diff는 항상 전체 실행이다", () => {
  for (const event of ["push", "workflow_dispatch", "merge_group", "pull_request_target", ""]) {
    const decision = decideScope({ event, changedPaths: ["README.md"] });
    assert.deepEqual(decision, { runHeavyLanes: true, reason: "EVENT_NOT_PULL_REQUEST", blockingPaths: [] }, event);
  }
  assert.deepEqual(decideScope({ event: "pull_request", changedPaths: [] }), {
    runHeavyLanes: true,
    reason: "EMPTY_DIFF",
    blockingPaths: [],
  });
});

test("건너뛰는 lane 목록은 무거운 lane 셋으로 닫혀 있다", () => {
  assert.deepEqual(HEAVY_LANES, ["Mobile host tests", "Android debug APK", "Android release AAB"]);
});

test("판정기는 trusted base에서 단독 실행되도록 node 내장 모듈만 import한다", () => {
  const source = readFileSync(scriptPath, "utf8");
  const specifiers = [...source.matchAll(/^\s*import\s[^;]*?from\s+["']([^"']+)["']/gmu)].map((match) => match[1]);
  assert.ok(specifiers.length > 0);
  for (const specifier of specifiers) {
    assert.match(specifier, /^node:/u, specifier);
  }
  assert.doesNotMatch(source, /\bimport\s*\(/u);
});

function git(cwd, args) {
  return execFileSync("git", args, { cwd, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] }).trim();
}

function fixtureRepository() {
  const root = mkdtempSync(path.join(os.tmpdir(), "mobile-ci-scope-"));
  git(root, ["init", "--quiet", "--initial-branch=main"]);
  git(root, ["config", "user.email", "ci-scope@example.invalid"]);
  git(root, ["config", "user.name", "CI scope fixture"]);
  git(root, ["config", "commit.gpgsign", "false"]);
  mkdirSync(path.join(root, "apps/mobile/lib"), { recursive: true });
  writeFileSync(path.join(root, "apps/mobile/lib/main.dart"), "void main() {}\n");
  writeFileSync(path.join(root, "README.md"), "base\n");
  git(root, ["add", "--", "apps/mobile/lib/main.dart", "README.md"]);
  git(root, ["commit", "--quiet", "-m", "base"]);
  return { root, base: git(root, ["rev-parse", "HEAD"]) };
}

function commitChange(root, relativePath, content) {
  mkdirSync(path.dirname(path.join(root, relativePath)), { recursive: true });
  writeFileSync(path.join(root, relativePath), content);
  git(root, ["add", "--", relativePath]);
  git(root, ["commit", "--quiet", "-m", `change ${relativePath}`]);
  return git(root, ["rev-parse", "HEAD"]);
}

function runDecide(root, args) {
  const output = path.join(root, ".scope-output");
  const summary = path.join(root, ".scope-summary");
  writeFileSync(output, "");
  writeFileSync(summary, "");
  const result = spawnSync(process.execPath, [scriptPath, "decide", ...args], {
    cwd: root,
    encoding: "utf8",
    env: { ...process.env, GITHUB_OUTPUT: output, GITHUB_STEP_SUMMARY: summary },
  });
  return { ...result, output: readFileSync(output, "utf8"), summary: readFileSync(summary, "utf8") };
}

test("CLI는 base와 tested tree diff로 판정하고 출력·요약에 건너뛴 lane을 기록한다", () => {
  const { root, base } = fixtureRepository();
  try {
    const docsOnly = commitChange(root, "README.ko.md", "문서\n");
    const skipped = runDecide(root, ["--event", "pull_request", "--base-sha", base, "--tested-sha", docsOnly]);
    assert.equal(skipped.status, 0, skipped.stderr);
    assert.equal(skipped.output, "run-heavy-lanes=false\nreason=SKIP_ELIGIBLE_PATHS_ONLY\n");
    assert.match(skipped.summary, /README\.ko\.md/u);
    for (const lane of HEAVY_LANES) {
      assert.match(skipped.summary, new RegExp(`${lane} — 건너뜀`, "u"));
    }

    const appChange = commitChange(root, "apps/mobile/lib/main.dart", "void main() { print(1); }\n");
    const full = runDecide(root, ["--event", "pull_request", "--base-sha", base, "--tested-sha", appChange]);
    assert.equal(full.status, 0, full.stderr);
    assert.equal(full.output, "run-heavy-lanes=true\nreason=RUN_REQUIRED_PATH\n");
    assert.match(full.summary, /apps\/mobile\/lib\/main\.dart/u);
    assert.doesNotMatch(full.summary, /건너뜀/u);

    const unchanged = runDecide(root, ["--event", "pull_request", "--base-sha", base, "--tested-sha", base]);
    assert.equal(unchanged.status, 0, unchanged.stderr);
    assert.equal(unchanged.output, "run-heavy-lanes=true\nreason=EMPTY_DIFF\n");
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test("CLI는 rename을 양쪽 경로로 보고 실행 필요 경로를 놓치지 않는다", () => {
  const { root, base } = fixtureRepository();
  try {
    git(root, ["mv", "apps/mobile/lib/main.dart", "README.ko.md"]);
    git(root, ["commit", "--quiet", "-m", "rename"]);
    const renamed = git(root, ["rev-parse", "HEAD"]);
    const result = runDecide(root, ["--event", "pull_request", "--base-sha", base, "--tested-sha", renamed]);
    assert.equal(result.status, 0, result.stderr);
    assert.equal(result.output, "run-heavy-lanes=true\nreason=RUN_REQUIRED_PATH\n");
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test("CLI는 잘못된 인자·SHA·출력 환경을 fail-closed로 거부한다", () => {
  const { root, base } = fixtureRepository();
  try {
    const missingSha = "0".repeat(40);
    for (const args of [
      [],
      ["decide"],
      ["decide", "--event", "pull_request", "--base-sha", base],
      ["decide", "--event", "pull_request", "--base-sha", "HEAD", "--tested-sha", base],
      ["decide", "--event", "pull_request", "--base-sha", base, "--tested-sha", missingSha],
      ["decide", "--event", "pull_request", "--base-sha", base, "--tested-sha", base, "--tested-sha", base],
      ["decide", "--event", "pull_request", "--base-sha", base, "--tested-sha", base, "--unknown", "x"],
      ["other", "--event", "pull_request", "--base-sha", base, "--tested-sha", base],
    ]) {
      const result = spawnSync(process.execPath, [scriptPath, ...args], {
        cwd: root,
        encoding: "utf8",
        env: { ...process.env, GITHUB_OUTPUT: path.join(root, ".o"), GITHUB_STEP_SUMMARY: path.join(root, ".s") },
      });
      assert.notEqual(result.status, 0, JSON.stringify(args));
    }
    const noOutputEnv = { ...process.env };
    delete noOutputEnv.GITHUB_OUTPUT;
    const result = spawnSync(process.execPath, [scriptPath, "decide", "--event", "pull_request", "--base-sha", base, "--tested-sha", base], {
      cwd: root,
      encoding: "utf8",
      env: { ...noOutputEnv, GITHUB_STEP_SUMMARY: path.join(root, ".s") },
    });
    assert.notEqual(result.status, 0);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});
