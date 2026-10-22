import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { fileURLToPath } from "node:url";

const read = (relative) => readFileSync(fileURLToPath(new URL(`../../${relative}`, import.meta.url)), "utf8");
const workflow = read(".github/workflows/ci.yml");
const coveragePolicy = JSON.parse(read("tools/ci/mobile-coverage-policy.json"));

function jobBlock(id) {
  const lines = workflow.split("\n");
  const start = lines.indexOf(`  ${id}:`, lines.indexOf("jobs:"));
  assert.notEqual(start, -1, `job ${id} is missing`);
  const end = lines.findIndex((line, index) => index > start && /^ {2}\S/u.test(line));
  return lines.slice(start, end === -1 ? undefined : end).join("\n");
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

const sonarJob = jobBlock("sonarcloud");
const properties = parseProperties(read("sonar-project.properties"));

test("sonarcloud job은 host test lane의 필터링 lcov artifact를 받는다", () => {
  assert.match(sonarJob, /^ {4}needs: mobile-host-tests$/mu);
  const upload = jobBlock("mobile-host-tests");
  assert.match(upload, /name: mobile-sonar-lcov\n\s+path: \$\{\{ runner\.temp \}\}\/mobile-coverage-normalized\.lcov/u);
  assert.match(sonarJob, /actions\/download-artifact@[0-9a-f]{40}/u);
  assert.match(sonarJob, /name: mobile-sonar-lcov/u);
  assert.match(sonarJob, /SF:lib\/#SF:apps\/mobile\/lib\//u);
});

test("scan action은 v6 이상 커밋 SHA로 고정되고 flutter pub get이 먼저 실행된다", () => {
  const match = sonarJob.match(/SonarSource\/sonarqube-scan-action@[0-9a-f]{40}\s+# v(\d+)\./u);
  assert.ok(match, "scan action must be pinned to a 40-hex SHA with a version comment");
  assert.ok(Number(match[1]) >= 6, "v3 이하는 Docker 안에서 돌아 Dart 의존성을 보지 못한다");
  assert.ok(sonarJob.indexOf("flutter pub get") < sonarJob.indexOf("sonarqube-scan-action"));
  assert.match(sonarJob, /SONAR_TOKEN: \$\{\{ secrets\.SONAR_TOKEN \}\}/u);
});

test("fork PR과 Dependabot PR은 secret이 없으므로 건너뛴다", () => {
  assert.match(sonarJob, /github\.event\.pull_request\.head\.repo\.full_name == github\.repository/u);
  assert.match(sonarJob, /github\.actor != 'dependabot\[bot\]'/u);
  assert.match(sonarJob, /needs\.mobile-host-tests\.result == 'success'/u);
});

test("sonar-project.properties는 coverage ratchet 제외 목록과 같은 생성 코드만 제외한다", () => {
  const excluded = properties["sonar.exclusions"].split(",").sort();
  assert.deepEqual(excluded, coveragePolicy.exclusions.map((entry) => entry.path).sort());
  assert.equal(properties["sonar.projectKey"], "AquilaXk_easysubway-mobile");
  assert.equal(properties["sonar.organization"], "aquilaxk");
  assert.equal(properties["sonar.sources"], "apps/mobile/lib");
  assert.equal(properties["sonar.tests"], "apps/mobile/test");
  assert.equal(properties["sonar.dart.lcov.reportPaths"], "apps/mobile/coverage/lcov.info");
});
