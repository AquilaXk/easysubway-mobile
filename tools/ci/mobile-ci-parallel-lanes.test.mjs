import assert from "node:assert/strict";
import { execFileSync, spawnSync } from "node:child_process";
import { copyFileSync, existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync } from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

const repositoryRoot = fileURLToPath(new URL("../..", import.meta.url));
const workflowPath = path.join(repositoryRoot, ".github/workflows/ci.yml");
const workflow = readFileSync(workflowPath, "utf8");

function jobBlock(id) {
  const lines = workflow.split("\n");
  const jobsStart = lines.indexOf("jobs:");
  assert.notEqual(jobsStart, -1, "jobs: section is missing");
  const start = lines.indexOf(`  ${id}:`, jobsStart);
  assert.notEqual(start, -1, `job ${id} is missing`);
  let end = lines.length;
  for (let index = start + 1; index < lines.length; index += 1) {
    // 다음 job 키나 다음 job 앞 주석(2칸 들여쓰기)에서 끝난다. job 내부는 4칸 이상이다.
    if (/^ {2}\S/u.test(lines[index])) {
      end = index;
      break;
    }
  }
  return lines.slice(start, end).join("\n");
}

function jobIds() {
  const lines = workflow.split("\n");
  const jobsStart = lines.indexOf("jobs:");
  return lines.slice(jobsStart + 1).filter((line) => /^ {2}[A-Za-z0-9_-]+:\s*$/u.test(line)).map((line) => line.trim().slice(0, -1));
}

function stepNames(job) {
  return [...job.matchAll(/^ {6}- name: (.+)$/gmu)].map((match) => match[1]);
}

function stepBlock(job, name) {
  const header = `      - name: ${name}`;
  const start = job.indexOf(`${header}\n`);
  assert.notEqual(start, -1, `step ${name} is missing`);
  const next = job.indexOf("\n      - name: ", start + header.length);
  return job.slice(start, next === -1 ? undefined : next);
}

function runScript(step) {
  const lines = step.split("\n");
  const start = lines.indexOf("        run: |");
  assert.notEqual(start, -1, "run: | block is missing");
  const body = [];
  for (const line of lines.slice(start + 1)) {
    if (line.trim() !== "" && !line.startsWith("          ")) break;
    body.push(line.slice(10));
  }
  return `${body.join("\n").trimEnd()}\n`;
}

const MOBILE_CONTRACT_STEPS = [
  "Checkout",
  "Set up Node",
  "Check documentation fragment preflight sync",
  "Set up ORAS",
  "Pull locked Journey V3 contract bundle",
  "Stage locked Journey V3 contract",
  "Set up Flutter",
  "Generate and verify Journey V3 client",
  "Stage trusted mobile root import ratchet",
  "Analyze mobile root import ratchet",
  "Upload mobile root import ratchet evidence",
  "Enforce mobile root import ratchet verdict",
  "Fetch exact generic mobile consumer bundle",
  "Stage exact generic mobile consumer bundle",
  "Verify residual consumer snapshots",
  "Run owned Node checks",
  "Run Journey V3 generator checks",
  "Install Flutter dependencies",
  "Check format",
  "Analyze",
];

const MOBILE_HOST_TEST_STEPS = [
  "Checkout",
  "Set up Node",
  "Set up Flutter",
  "Install Flutter dependencies",
  "Discover host tests",
  "Test",
  "Verify host test execution parity",
  "Filter mobile coverage",
  "Analyze mobile coverage ratchet",
  "Upload mobile coverage ratchet evidence",
  "Enforce mobile coverage ratchet verdict",
];

const ANDROID_DEBUG_STEPS = ["Checkout", "Set up Java", "Set up Flutter", "Install Flutter dependencies", "Build debug APK"];
const ANDROID_RELEASE_STEPS = [
  "Checkout",
  "Set up Java",
  "Set up Flutter",
  "Install Flutter dependencies",
  "Create ephemeral preflight key",
  "Build no-upload release AAB",
];

// 개선 전 단일 Mobile CI job과 Android CI job이 실행하던 검증 단계. 설정 단계(Checkout 등)를
// 제외한 각 검증 단계는 분할 뒤에도 정확히 한 lane에서 한 번 실행돼야 한다.
const SETUP_STEPS = new Set(["Checkout", "Set up Node", "Set up Java", "Set up Flutter", "Install Flutter dependencies"]);
const ORIGINAL_GATE_STEPS = [
  ...MOBILE_CONTRACT_STEPS,
  ...MOBILE_HOST_TEST_STEPS,
  ...ANDROID_DEBUG_STEPS,
  ...ANDROID_RELEASE_STEPS,
].filter((name) => !SETUP_STEPS.has(name));

test("workflow 이름과 required check 이름을 유지하고 집계 job이 그 이름을 소유한다", () => {
  assert.equal(workflow.split("\n")[0], "name: CI");
  const coordinator = readFileSync(path.join(repositoryRoot, ".github/workflows/automerge-queue.yml"), "utf8");
  assert.match(coordinator, /^ {2}workflow_run:\n {4}workflows: \[CI\]\n {4}types: \[completed\]$/mu);

  assert.deepEqual(jobIds(), [
    "scope",
    "mobile-contracts",
    "mobile-host-tests",
    "mobile",
    "android-debug-apk",
    "android-release-aab",
    "android",
    "dependency-vulnerability-scan",
  ]);
  const names = [...workflow.matchAll(/^ {4}name: (.+)$/gmu)].map((match) => match[1]);
  assert.deepEqual(names, [
    "CI scope",
    "Mobile contracts",
    "Mobile host tests",
    "Mobile CI",
    "Android debug APK",
    "Android release AAB",
    "Android CI",
    "Dependency Vulnerability Scan",
  ]);
  assert.match(jobBlock("mobile"), /^ {4}name: Mobile CI$/mu);
  assert.match(jobBlock("android"), /^ {4}name: Android CI$/mu);
});

test("PR 실행만 PR 번호 그룹으로 취소하고 main push·dispatch는 run마다 고유 그룹이다", () => {
  const concurrency = [
    "concurrency:",
    "  group: ci-${{ github.event_name == 'pull_request' && format('pr-{0}', github.event.pull_request.number) || github.run_id }}",
    "  cancel-in-progress: ${{ github.event_name == 'pull_request' }}",
  ].join("\n");
  assert.equal(workflow.includes(`\n${concurrency}\n`), true);
  assert.equal(workflow.match(/^concurrency:/gmu)?.length, 1);
  assert.doesNotMatch(workflow, /cancel-in-progress: true/u);
});

test("검증 단계는 분할 뒤에도 각각 정확히 한 lane에서 한 번 실행된다", () => {
  assert.deepEqual(stepNames(jobBlock("mobile-contracts")), MOBILE_CONTRACT_STEPS);
  assert.deepEqual(stepNames(jobBlock("mobile-host-tests")), MOBILE_HOST_TEST_STEPS);
  assert.deepEqual(stepNames(jobBlock("android-debug-apk")), ANDROID_DEBUG_STEPS);
  assert.deepEqual(stepNames(jobBlock("android-release-aab")), ANDROID_RELEASE_STEPS);
  const allSteps = [...workflow.matchAll(/^ {6}- name: (.+)$/gmu)].map((match) => match[1]);
  for (const gate of ORIGINAL_GATE_STEPS) {
    assert.equal(allSteps.filter((name) => name === gate).length, 1, gate);
  }
  assert.doesNotMatch(workflow, /continue-on-error/u);
});

test("무거운 lane만 scope 판정에 묶이고 계약 lane은 항상 실행된다", () => {
  const heavyCondition = "    if: ${{ needs.scope.outputs.run-heavy-lanes == 'true' }}";
  for (const id of ["mobile-host-tests", "android-debug-apk", "android-release-aab"]) {
    const job = jobBlock(id);
    assert.match(job, /^ {4}needs: scope$/mu, id);
    assert.equal(job.split("\n").filter((line) => line.startsWith("    if:")).join("\n"), heavyCondition, id);
  }
  const contracts = jobBlock("mobile-contracts");
  assert.doesNotMatch(contracts, /^ {4}(needs|if):/mu);
  const scope = jobBlock("scope");
  assert.doesNotMatch(scope, /^ {4}(needs|if):/mu);
  assert.match(scope, /^ {6}run-heavy-lanes: \$\{\{ steps\.decide\.outputs\.run-heavy-lanes \}\}$/mu);
  assert.match(scope, /^ {6}reason: \$\{\{ steps\.decide\.outputs\.reason \}\}$/mu);
});

test("집계 job은 취소된 run에서도 실행돼 모든 lane 결과를 모은다", () => {
  const mobile = jobBlock("mobile");
  assert.match(mobile, /^ {4}needs: \[scope, mobile-contracts, mobile-host-tests\]$/mu);
  assert.match(mobile, /^ {4}if: \$\{\{ always\(\) \}\}$/mu);
  const android = jobBlock("android");
  assert.match(android, /^ {4}needs: \[scope, android-debug-apk, android-release-aab\]$/mu);
  assert.match(android, /^ {4}if: \$\{\{ always\(\) \}\}$/mu);
  for (const job of [mobile, android]) {
    assert.doesNotMatch(job, /uses: actions\/checkout/u);
    assert.match(job, /^ {4}permissions: \{\}$/mu);
  }
});

function runAggregate(jobId, stepName, environment) {
  const script = runScript(stepBlock(jobBlock(jobId), stepName));
  const dir = mkdtempSync(path.join(os.tmpdir(), "mobile-ci-aggregate-"));
  try {
    const summary = path.join(dir, "summary.md");
    writeFileSync(summary, "");
    const result = spawnSync("bash", ["-c", script], {
      encoding: "utf8",
      env: { PATH: process.env.PATH, GITHUB_STEP_SUMMARY: summary, ...environment },
    });
    return { status: result.status, stderr: result.stderr, summary: readFileSync(summary, "utf8") };
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

const AGGREGATES = [
  {
    job: "mobile",
    step: "Require every Mobile CI lane",
    always: ["CONTRACTS_RESULT"],
    heavy: ["HOST_TESTS_RESULT"],
    skippedLabels: ["Mobile host tests"],
  },
  {
    job: "android",
    step: "Require every Android CI lane",
    always: [],
    heavy: ["DEBUG_APK_RESULT", "RELEASE_AAB_RESULT"],
    skippedLabels: ["Android debug APK", "Android release AAB"],
  },
];

for (const aggregate of AGGREGATES) {
  const allResults = (value) => Object.fromEntries([...aggregate.always, ...aggregate.heavy].map((key) => [key, value]));
  const base = { EVENT_NAME: "pull_request", SCOPE_RESULT: "success", RUN_HEAVY_LANES: "true", SCOPE_REASON: "RUN_REQUIRED_PATH" };

  test(`${aggregate.job} 집계: 실행 판정이면 모든 lane success만 통과한다`, () => {
    const passed = runAggregate(aggregate.job, aggregate.step, { ...base, ...allResults("success") });
    assert.equal(passed.status, 0, passed.stderr);
    assert.doesNotMatch(passed.summary, /건너뜀/u);
    for (const key of [...aggregate.always, ...aggregate.heavy]) {
      for (const bad of ["failure", "cancelled", "skipped", ""]) {
        const result = runAggregate(aggregate.job, aggregate.step, { ...base, ...allResults("success"), [key]: bad });
        assert.notEqual(result.status, 0, `${key}=${bad}`);
      }
    }
  });

  test(`${aggregate.job} 집계: skip 판정이면 무거운 lane은 skipped여야 하고 요약에 기록된다`, () => {
    const skipBase = { ...base, RUN_HEAVY_LANES: "false", SCOPE_REASON: "SKIP_ELIGIBLE_PATHS_ONLY" };
    const heavySkipped = Object.fromEntries(aggregate.heavy.map((key) => [key, "skipped"]));
    const alwaysSuccess = Object.fromEntries(aggregate.always.map((key) => [key, "success"]));
    const passed = runAggregate(aggregate.job, aggregate.step, { ...skipBase, ...alwaysSuccess, ...heavySkipped });
    assert.equal(passed.status, 0, passed.stderr);
    for (const label of aggregate.skippedLabels) {
      assert.match(passed.summary, new RegExp(`${label}: 건너뜀 \\(SKIP_ELIGIBLE_PATHS_ONLY\\)`, "u"));
    }
    for (const key of aggregate.heavy) {
      for (const bad of ["success", "failure", "cancelled", ""]) {
        const result = runAggregate(aggregate.job, aggregate.step, { ...skipBase, ...alwaysSuccess, ...heavySkipped, [key]: bad });
        assert.notEqual(result.status, 0, `${key}=${bad}`);
      }
    }
    for (const key of aggregate.always) {
      for (const bad of ["skipped", "failure", "cancelled", ""]) {
        const result = runAggregate(aggregate.job, aggregate.step, { ...skipBase, ...alwaysSuccess, ...heavySkipped, [key]: bad });
        assert.notEqual(result.status, 0, `${key}=${bad}`);
      }
    }
    for (const event of ["push", "workflow_dispatch", ""]) {
      const result = runAggregate(aggregate.job, aggregate.step, { ...skipBase, ...alwaysSuccess, ...heavySkipped, EVENT_NAME: event });
      assert.notEqual(result.status, 0, `skip on ${event}`);
    }
  });

  test(`${aggregate.job} 집계: scope 실패·누락·비정상 판정은 실패다`, () => {
    for (const scopeResult of ["failure", "cancelled", "skipped", ""]) {
      const result = runAggregate(aggregate.job, aggregate.step, { ...base, ...allResults("success"), SCOPE_RESULT: scopeResult });
      assert.notEqual(result.status, 0, scopeResult);
    }
    for (const decision of ["", "TRUE", "yes", "false\ntrue"]) {
      const result = runAggregate(aggregate.job, aggregate.step, { ...base, ...allResults("success"), RUN_HEAVY_LANES: decision });
      assert.notEqual(result.status, 0, JSON.stringify(decision));
    }
  });
}

test("host test lane은 러너 코어 수만큼 병렬로 전체 host test와 coverage를 실행한다", () => {
  const job = jobBlock("mobile-host-tests");
  assert.equal(
    stepBlock(job, "Test"),
    [
      "      - name: Test",
      "        working-directory: apps/mobile",
      "        run: >-",
      "          flutter test --coverage",
      "          --concurrency \"$(nproc)\"",
      "          --file-reporter \"json:${RUNNER_TEMP}/mobile-host-test-events.json\"",
    ].join("\n"),
  );
  assert.match(job, /^ {10}fetch-depth: 0$/mu);
  assert.match(job, /^ {6}contents: read\n {6}issues: read$/mu);
  assert.match(stepBlock(job, "Discover host tests"), /mobile-host-test-parity\.mjs discover/u);
  assert.match(stepBlock(job, "Verify host test execution parity"), /mobile-host-test-parity\.mjs verify/u);
});

test("Android lane은 개선 전과 같은 debug APK·release AAB 검증 명령을 병렬로 실행한다", () => {
  const debug = jobBlock("android-debug-apk");
  assert.equal(
    stepBlock(debug, "Build debug APK"),
    ["      - name: Build debug APK", "        working-directory: apps/mobile", "        run: flutter build apk --debug", ""].join("\n"),
  );
  const release = jobBlock("android-release-aab");
  assert.equal(
    stepBlock(release, "Build no-upload release AAB"),
    [
      "      - name: Build no-upload release AAB",
      "        working-directory: apps/mobile",
      "        env:",
      "          EASYSUBWAY_ANDROID_KEYSTORE_PATH: ${{ runner.temp }}/mobile-preflight.p12",
      "          EASYSUBWAY_ANDROID_STORE_PASSWORD: mobile-preflight",
      "          EASYSUBWAY_ANDROID_KEY_ALIAS: mobile-preflight",
      "          EASYSUBWAY_ANDROID_KEY_PASSWORD: mobile-preflight",
      "        run: |",
      "          defines=(",
      "            --dart-define=EASYSUBWAY_API_BASE_URL=https://easysubway-api.aquilaxk.site",
      "            --dart-define=EASYSUBWAY_KAKAO_MAP_NATIVE_APP_KEY=ci-preflight",
      "          )",
      "          ../../tools/mobile/validate-release-dart-defines.sh \"${defines[@]}\"",
      "          flutter build appbundle --release \"${defines[@]}\"",
      "          ../../tools/mobile/check-android-aab-16kb-page-size.sh \\",
      "            --aab build/app/outputs/bundle/release/app-release.aab \\",
      "            --android-project android \\",
      "            --artifact-dir \"$RUNNER_TEMP/android-16kb-aab-evidence\"",
      "          node ../../tools/release/hash-android-bundle-payload.mjs \\",
      "            --aab build/app/outputs/bundle/release/app-release.aab",
      "",
    ].join("\n"),
  );
  assert.match(stepBlock(release, "Create ephemeral preflight key"), /keytool -genkeypair -storetype PKCS12/u);
});

test("Gradle·Flutter SDK·pub 캐시가 Flutter를 쓰는 모든 lane에 걸려 있다", () => {
  for (const id of ["mobile-contracts", "mobile-host-tests", "android-debug-apk", "android-release-aab"]) {
    const flutter = stepBlock(jobBlock(id), "Set up Flutter");
    assert.match(flutter, /^ {10}flutter-version-file: \.fvmrc\n {10}cache: true$/mu, id);
  }
  for (const id of ["android-debug-apk", "android-release-aab"]) {
    assert.match(stepBlock(jobBlock(id), "Set up Java"), /^ {10}java-version: "21"\n {10}cache: gradle$/mu, id);
  }
});

test("Mobile contracts lane은 scope 판정기 계약 테스트를 한 번씩 실행한다", () => {
  const nodeChecks = stepBlock(jobBlock("mobile-contracts"), "Run owned Node checks");
  for (const file of ["tools/ci/mobile-ci-scope.test.mjs", "tools/ci/mobile-ci-parallel-lanes.test.mjs"]) {
    assert.equal(nodeChecks.split(`            ${file} \\\n`).length - 1, 1, file);
    assert.equal(workflow.split(file).length - 1, 1, file);
  }
});

function gitIn(cwd, args) {
  return execFileSync("git", args, { cwd, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] }).trim();
}

function scopeFixture({ withTrustedScope }) {
  const root = mkdtempSync(path.join(os.tmpdir(), "mobile-ci-scope-step-"));
  gitIn(root, ["init", "--quiet", "--initial-branch=main"]);
  gitIn(root, ["config", "user.email", "ci-scope@example.invalid"]);
  gitIn(root, ["config", "user.name", "CI scope fixture"]);
  gitIn(root, ["config", "commit.gpgsign", "false"]);
  mkdirSync(path.join(root, "apps/mobile/lib"), { recursive: true });
  writeFileSync(path.join(root, "apps/mobile/lib/main.dart"), "void main() {}\n");
  writeFileSync(path.join(root, "README.md"), "base\n");
  const tracked = ["apps/mobile/lib/main.dart", "README.md"];
  if (withTrustedScope) {
    mkdirSync(path.join(root, "tools/ci"), { recursive: true });
    copyFileSync(path.join(repositoryRoot, "tools/ci/mobile-ci-scope.mjs"), path.join(root, "tools/ci/mobile-ci-scope.mjs"));
    tracked.push("tools/ci/mobile-ci-scope.mjs");
  }
  gitIn(root, ["add", "--", ...tracked]);
  gitIn(root, ["commit", "--quiet", "-m", "base"]);
  return { root, base: gitIn(root, ["rev-parse", "HEAD"]) };
}

function commitIn(root, relativePath, content) {
  mkdirSync(path.dirname(path.join(root, relativePath)), { recursive: true });
  writeFileSync(path.join(root, relativePath), content);
  gitIn(root, ["add", "--", relativePath]);
  gitIn(root, ["commit", "--quiet", "-m", `change ${relativePath}`]);
  return gitIn(root, ["rev-parse", "HEAD"]);
}

function runScopeStep(root, environment) {
  const script = runScript(stepBlock(jobBlock("scope"), "Decide heavy lane scope"));
  const output = path.join(root, ".git", "scope-output");
  const summary = path.join(root, ".git", "scope-summary");
  writeFileSync(output, "");
  writeFileSync(summary, "");
  const trustedRoot = path.join(root, ".git", "scope-trusted");
  const result = spawnSync("bash", ["-c", script], {
    cwd: root,
    encoding: "utf8",
    env: { PATH: process.env.PATH, HOME: process.env.HOME, GITHUB_OUTPUT: output, GITHUB_STEP_SUMMARY: summary, SCOPE_TRUSTED_ROOT: trustedRoot, ...environment },
  });
  return { status: result.status, stderr: result.stderr, output: readFileSync(output, "utf8"), summary: readFileSync(summary, "utf8"), trustedRoot };
}

test("scope step: PR이 아닌 이벤트는 git 판정 없이 전체 실행이다", () => {
  const { root } = scopeFixture({ withTrustedScope: true });
  try {
    for (const event of ["push", "workflow_dispatch"]) {
      const result = runScopeStep(root, { SCOPE_EVENT: event, SCOPE_BASE_SHA: "not-a-sha", SCOPE_TESTED_SHA: "not-a-sha" });
      assert.equal(result.status, 0, result.stderr);
      assert.equal(result.output, "run-heavy-lanes=true\nreason=EVENT_NOT_PULL_REQUEST\n");
      assert.match(result.summary, /전체 lane을 실행한다/u);
    }
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test("scope step: base에 판정기가 없으면 전체 실행이다", () => {
  const { root, base } = scopeFixture({ withTrustedScope: false });
  try {
    const tested = commitIn(root, "README.md", "changed\n");
    const result = runScopeStep(root, { SCOPE_EVENT: "pull_request", SCOPE_BASE_SHA: base, SCOPE_TESTED_SHA: tested });
    assert.equal(result.status, 0, result.stderr);
    assert.equal(result.output, "run-heavy-lanes=true\nreason=TRUSTED_SCOPE_ABSENT_IN_BASE\n");
    assert.equal(existsSync(result.trustedRoot), false);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test("scope step: base의 판정기로 판정하므로 PR이 판정기를 바꿔도 결과를 바꾸지 못한다", () => {
  const { root, base } = scopeFixture({ withTrustedScope: true });
  try {
    const docsOnly = commitIn(root, "README.md", "changed\n");
    const skipped = runScopeStep(root, { SCOPE_EVENT: "pull_request", SCOPE_BASE_SHA: base, SCOPE_TESTED_SHA: docsOnly });
    assert.equal(skipped.status, 0, skipped.stderr);
    assert.equal(skipped.output, "run-heavy-lanes=false\nreason=SKIP_ELIGIBLE_PATHS_ONLY\n");
    assert.equal(readdirSync(skipped.trustedRoot).join(","), "mobile-ci-scope.mjs");

    commitIn(root, "tools/ci/mobile-ci-scope.mjs", "import { appendFileSync } from \"node:fs\";\nappendFileSync(process.env.GITHUB_OUTPUT, \"run-heavy-lanes=false\\nreason=SKIP_ELIGIBLE_PATHS_ONLY\\n\");\n");
    const tampered = commitIn(root, "apps/mobile/lib/main.dart", "void main() { print(1); }\n");
    rmSync(skipped.trustedRoot, { recursive: true, force: true });
    const full = runScopeStep(root, { SCOPE_EVENT: "pull_request", SCOPE_BASE_SHA: base, SCOPE_TESTED_SHA: tampered });
    assert.equal(full.status, 0, full.stderr);
    assert.equal(full.output, "run-heavy-lanes=true\nreason=RUN_REQUIRED_PATH\n");
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test("scope step: base 판정기가 판정을 내지 않으면 실패다", () => {
  const { root } = scopeFixture({ withTrustedScope: false });
  try {
    const silentBase = commitIn(root, "tools/ci/mobile-ci-scope.mjs", "// 판정을 쓰지 않는 판정기\n");
    const tested = commitIn(root, "README.md", "changed\n");
    const result = runScopeStep(root, { SCOPE_EVENT: "pull_request", SCOPE_BASE_SHA: silentBase, SCOPE_TESTED_SHA: tested });
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /produced no decision/u);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test("scope step: 비정상 SHA와 존재하지 않는 commit은 실패다", () => {
  const { root, base } = scopeFixture({ withTrustedScope: true });
  try {
    for (const [baseSha, testedSha] of [["HEAD", base], [base, "main"], [base, "f".repeat(40)], ["", base]]) {
      const result = runScopeStep(root, { SCOPE_EVENT: "pull_request", SCOPE_BASE_SHA: baseSha, SCOPE_TESTED_SHA: testedSha });
      assert.notEqual(result.status, 0, `${baseSha} ${testedSha}`);
      assert.equal(result.output, "");
    }
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

// skip 가능 경로가 정말 실행 대상 밖인지에 대한 정적 불변식. 앱 코드·테스트·네이티브 빌드와
// 무거운 lane이 실행하는 도구가 이 경로를 읽기 시작하면 skip 판정이 안전하지 않으므로 실패한다.
const SKIP_ELIGIBLE_REFERENCE = /\.github\/|README|\.test\.mjs/u;

function trackedFiles(prefix) {
  return execFileSync("git", ["ls-files", "-z", "--", prefix], { cwd: repositoryRoot, encoding: "utf8" }).split("\0").filter(Boolean);
}

function isCommentLine(line) {
  return /^\s*(\/\/|#|\*|\/\*|<!--)/u.test(line);
}

test("앱 코드·테스트·네이티브 빌드 입력은 skip 가능 경로를 참조하지 않는다", () => {
  const scanned = trackedFiles("apps/mobile").filter((file) => /\.(dart|gradle|kts|kt|java|properties|yaml|xml)$/u.test(file) && !file.startsWith("apps/mobile/ios/"));
  assert.ok(scanned.length > 100, `scanned ${scanned.length}`);
  const offenders = [];
  for (const file of scanned) {
    readFileSync(path.join(repositoryRoot, file), "utf8").split("\n").forEach((line, index) => {
      if (!isCommentLine(line) && SKIP_ELIGIBLE_REFERENCE.test(line)) offenders.push(`${file}:${index + 1}`);
    });
  }
  assert.deepEqual(offenders, []);
});

test("무거운 lane이 실행하는 도구와 그 의존 파일은 skip 가능 경로를 참조하지 않는다", () => {
  const heavyRuns = ["mobile-host-tests", "android-debug-apk", "android-release-aab"].map(jobBlock).join("\n");
  const queue = [...heavyRuns.matchAll(/(?:\.\.\/\.\.\/)?(tools\/[A-Za-z0-9_./-]+\.(?:mjs|sh))/gu)].map((match) => match[1]);
  assert.ok(queue.length >= 5, queue.join(","));
  const seen = new Set();
  while (queue.length > 0) {
    const file = queue.shift();
    if (seen.has(file)) continue;
    seen.add(file);
    const source = readFileSync(path.join(repositoryRoot, file), "utf8");
    assert.doesNotMatch(source, SKIP_ELIGIBLE_REFERENCE, file);
    for (const match of source.matchAll(/from\s+["'](\.{1,2}\/[^"']+)["']/gu)) {
      queue.push(path.posix.normalize(path.posix.join(path.posix.dirname(file), match[1])));
    }
    for (const match of source.matchAll(/\$SCRIPT_DIR\/([A-Za-z0-9_.-]+\.(?:mjs|sh))/gu)) {
      queue.push(path.posix.join(path.posix.dirname(file), match[1]));
    }
  }
  assert.ok(seen.has("tools/mobile/check-elf-load-alignment.mjs"));
  assert.ok(seen.has("tools/ci/filter-mobile-lcov.mjs"));
});
