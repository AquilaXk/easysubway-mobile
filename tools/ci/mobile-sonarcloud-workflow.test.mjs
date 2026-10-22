import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";
import { jobBlock, runScript, stepBlock } from "./lib/workflow-blocks.mjs";

const read = (relative) => readFileSync(fileURLToPath(new URL(`../../${relative}`, import.meta.url)), "utf8");
const workflow = read(".github/workflows/ci.yml");
const coveragePolicy = JSON.parse(read("tools/ci/mobile-coverage-policy.json"));

const SONAR_PERMISSIONS = { contents: "read", "pull-requests": "read" };
const SAME_REPOSITORY = "AquilaXk/easysubway-mobile";

// job의 `if: >-` 접힌 스칼라를 한 줄 표현식으로 되돌린다.
function jobCondition(job) {
  const lines = job.split("\n");
  const start = lines.indexOf("    if: >-");
  assert.notEqual(start, -1, "job if: >- is missing");
  const body = [];
  for (const line of lines.slice(start + 1)) {
    if (!line.startsWith("      ")) break;
    body.push(line.trim());
  }
  const expression = body.join(" ").match(/^\$\{\{\s*(.*?)\s*\}\}$/u);
  assert.ok(expression, "job if must be a single ${{ }} expression");
  return expression[1];
}

// 이 workflow의 if 표현식이 쓰는 연산자만 JS로 옮겨 평가한다. 그 밖의 토큰은 거부한다.
const HOST_TESTS_RESULT = "needs.mobile-host-tests.result";
const SUPPORTED_TOKENS = /^(?:hostTestsResult|github\.(?:actor|event_name|repository|event\.pull_request\.head\.repo\.full_name)|'[^']*'|===|!==|&&|\|\||[()]|\s)+$/u;

function evaluateCondition(expression, { eventName, actor, headRepository, hostTestsResult }) {
  const js = expression.replaceAll("==", "===").replaceAll("!=", "!==").replaceAll(HOST_TESTS_RESULT, "hostTestsResult");
  assert.match(js, SUPPORTED_TOKENS, "unsupported token in job if expression");
  const github = {
    actor,
    event_name: eventName,
    repository: SAME_REPOSITORY,
    event: { pull_request: { head: { repo: { full_name: headRepository } } } },
  };
  return new Function("github", "hostTestsResult", `return (${js});`)(github, hostTestsResult);
}

// `permissions:` 아래 `key: value` 줄을 객체로 읽는다.
function jobPermissions(job) {
  const lines = job.split("\n");
  const start = lines.indexOf("    permissions:");
  assert.notEqual(start, -1, "job permissions are missing");
  const entries = [];
  for (const line of lines.slice(start + 1)) {
    const match = line.match(/^ {6}([\w-]+): (\S+)$/u);
    if (!match) break;
    entries.push([match[1], match[2]]);
  }
  return Object.fromEntries(entries);
}

// 최상위 `on:` 아래 2칸 들여쓰기 trigger 키를 읽는다.
function workflowTriggers() {
  const lines = workflow.split("\n");
  const start = lines.indexOf("on:");
  assert.notEqual(start, -1, "on: section is missing");
  const triggers = [];
  for (const line of lines.slice(start + 1)) {
    if (line !== "" && !line.startsWith(" ")) break;
    const match = line.match(/^ {2}([\w-]+):/u);
    if (match) triggers.push(match[1]);
  }
  return triggers;
}

function parseProperties(text) {
  const joined = text.replace(/\\\n\s*/gu, "");
  return Object.fromEntries(
    joined.split("\n").filter((line) => line && !line.startsWith("#")).map((line) => {
      const index = line.indexOf("=");
      return [line.slice(0, index), line.slice(index + 1)];
    }),
  );
}

const sonarJob = jobBlock(workflow, "sonarcloud");
const properties = parseProperties(read("sonar-project.properties"));

test("sonarcloud job은 host test lane의 필터링 lcov artifact를 받는다", () => {
  assert.match(sonarJob, /^ {4}needs: mobile-host-tests$/mu);
  const upload = jobBlock(workflow, "mobile-host-tests");
  assert.match(upload, /name: mobile-sonar-lcov\n\s+path: \$\{\{ runner\.temp \}\}\/mobile-coverage-normalized\.lcov/u);
  assert.match(sonarJob, /actions\/download-artifact@[0-9a-f]{40}/u);
  assert.match(sonarJob, /name: mobile-sonar-lcov/u);
});

test("scan action은 v6 이상 커밋 SHA로 고정되고 flutter pub get이 먼저 실행된다", () => {
  const match = sonarJob.match(/SonarSource\/sonarqube-scan-action@[0-9a-f]{40}\s+# v(\d+)\./u);
  assert.ok(match, "scan action must be pinned to a 40-hex SHA with a version comment");
  assert.ok(Number(match[1]) >= 6, "v3 이하는 Docker 안에서 돌아 Dart 의존성을 보지 못한다");
  const pubGet = sonarJob.indexOf("flutter pub get");
  const scan = sonarJob.indexOf("sonarqube-scan-action");
  assert.notEqual(pubGet, -1, "flutter pub get step is missing");
  assert.notEqual(scan, -1, "sonarqube-scan-action step is missing");
  assert.ok(pubGet < scan, "flutter pub get must run before the scan");
  assert.match(sonarJob, /SONAR_TOKEN: \$\{\{ secrets\.SONAR_TOKEN \}\}/u);
});

const CONDITION_CASES = [
  { name: "main push", eventName: "push", actor: "AquilaXk", headRepository: "", expected: true },
  { name: "같은 레포 PR", eventName: "pull_request", actor: "AquilaXk", headRepository: SAME_REPOSITORY, expected: true },
  { name: "fork PR", eventName: "pull_request", actor: "outside-contributor", headRepository: "outside-contributor/easysubway-mobile", expected: false },
  { name: "같은 레포 Dependabot PR", eventName: "pull_request", actor: "dependabot[bot]", headRepository: SAME_REPOSITORY, expected: false },
  { name: "Dependabot push", eventName: "push", actor: "dependabot[bot]", headRepository: "", expected: false },
  { name: "workflow_dispatch", eventName: "workflow_dispatch", actor: "AquilaXk", headRepository: "", expected: true },
];

for (const { name, expected, ...event } of CONDITION_CASES) {
  test(`sonarcloud job 조건: ${name}은 ${expected ? "실행" : "건너뜀"}`, () => {
    const condition = jobCondition(sonarJob);
    assert.equal(evaluateCondition(condition, { ...event, hostTestsResult: "success" }), expected);
    for (const hostTestsResult of ["failure", "cancelled", "skipped"]) {
      assert.equal(evaluateCondition(condition, { ...event, hostTestsResult }), false, `host tests ${hostTestsResult}`);
    }
  });
}

test("sonarcloud job은 읽기 권한만 갖고 secret을 받는 pull_request_target으로 돌지 않는다", () => {
  assert.deepEqual(jobPermissions(sonarJob), SONAR_PERMISSIONS);
  const triggers = workflowTriggers();
  assert.ok(triggers.includes("pull_request"), "pull_request trigger is missing");
  assert.ok(!triggers.includes("pull_request_target"), "pull_request_target would expose SONAR_TOKEN to fork code");
});

// map 단계와 verify 단계를 임시 작업 디렉터리에서 실제로 실행한다. RUNNER_TEMP가 다운로드된 artifact 위치다.
function runCoverageSteps(lcov) {
  const root = mkdtempSync(path.join(os.tmpdir(), "mobile-sonar-lcov-"));
  try {
    const artifactDirectory = path.join(root, "runner", "mobile-sonar-lcov");
    mkdirSync(artifactDirectory, { recursive: true });
    writeFileSync(path.join(artifactDirectory, "mobile-coverage-normalized.lcov"), lcov);
    const results = ["Map coverage paths to repository root", "Verify mapped coverage paths"].map((name) => {
      const script = runScript(stepBlock(sonarJob, name));
      return spawnSync("bash", ["-e", "-c", script], {
        cwd: root,
        env: { ...process.env, RUNNER_TEMP: path.join(root, "runner") },
        encoding: "utf8",
      });
    });
    const mapped = readFileSync(path.join(root, "apps/mobile/coverage/lcov.info"), "utf8");
    return { mapStatus: results[0].status, verify: results[1], mapped };
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
}

const RECORD_END = "end_of_record\n";

test("coverage 경로 매핑: lib/ 경로를 루트 기준으로 바꾸고 검증을 통과한다", () => {
  const { mapStatus, verify, mapped } = runCoverageSteps(`TN:\nSF:lib/a.dart\nDA:1,1\n${RECORD_END}SF:lib/b/c.dart\nDA:2,0\n${RECORD_END}`);
  assert.equal(mapStatus, 0);
  assert.equal(verify.status, 0, verify.stderr);
  assert.deepEqual(mapped.split("\n").filter((line) => line.startsWith("SF:")), ["SF:apps/mobile/lib/a.dart", "SF:apps/mobile/lib/b/c.dart"]);
});

test("coverage 경로 검증: 변환되지 않은 SF 줄이 하나라도 있으면 실패한다", () => {
  const { verify } = runCoverageSteps(`SF:lib/a.dart\n${RECORD_END}SF:packages/shared/b.dart\n${RECORD_END}`);
  assert.notEqual(verify.status, 0);
  assert.match(verify.stdout + verify.stderr, /packages\/shared\/b\.dart/u);
});

test("coverage 경로 검증: SF 줄이 0개이면 실패한다", () => {
  assert.notEqual(runCoverageSteps("").verify.status, 0);
  assert.notEqual(runCoverageSteps("TN:\n").verify.status, 0);
});

test("sonar-project.properties는 coverage ratchet 제외 목록과 같은 생성 코드만 소스에서 제외한다", () => {
  const excluded = properties["sonar.exclusions"].split(",").sort();
  assert.deepEqual(excluded, coveragePolicy.exclusions.map((entry) => entry.path).sort());
  assert.equal(properties["sonar.projectKey"], "AquilaXk_easysubway-mobile");
  assert.equal(properties["sonar.organization"], "aquilaxk");
  assert.equal(properties["sonar.sources"], "apps/mobile/lib");
  assert.equal(properties["sonar.tests"], "apps/mobile/test");
  assert.equal(properties["sonar.dart.lcov.reportPaths"], "apps/mobile/coverage/lcov.info");
});

test("sonar-project.properties는 테스트 폴더의 바이너리(골든·증거 이미지, 폰트)를 분석에서 뺀다", () => {
  assert.deepEqual(properties["sonar.test.exclusions"].split(",").sort(), ["**/*.png", "**/*.ttf"]);
});
