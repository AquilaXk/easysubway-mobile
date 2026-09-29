#!/usr/bin/env node
// Mobile CI 무거운 lane(host tests·Android 빌드) 실행 범위 판정기.
//
// CI는 PR head가 아니라 trusted base commit의 이 파일을 `git show`로 꺼내 단독 실행한다.
// 그래서 node 내장 모듈 외의 import를 두지 않는다(tools/ci/mobile-ci-scope.test.mjs가 고정).
//
// 판정은 보수적이다. pull_request에서 base tree와 tested(merge) tree 사이에 바뀐 경로가
// 모두 "무거운 lane이 읽지 않는다고 증명된 경로"일 때만 건너뛴다. 그 외 이벤트, 빈 diff,
// 분류되지 않은 경로가 하나라도 있으면 전체 실행이다.
import { execFileSync } from "node:child_process";
import { appendFileSync, realpathSync } from "node:fs";
import { fileURLToPath } from "node:url";

export const HEAVY_LANES = Object.freeze(["Mobile host tests", "Android build"]);

// Flutter host test·analyze 대상이 아닌 다른 workflow, 저장소 메타데이터, 루트 README,
// Node 계약 테스트 파일. 앱 코드·테스트·네이티브 빌드와 무거운 lane 도구가 이 경로를 읽지
// 않는다는 정적 불변식은 tools/ci/mobile-ci-parallel-lanes.test.mjs가 검사한다.
const SKIP_ELIGIBLE_EXACT = new Set([
  ".github/dependabot.yml",
  ".github/pull_request_template.md",
  "README.md",
  "README.ko.md",
]);
const SKIP_ELIGIBLE_PREFIXES = [".github/PULL_REQUEST_TEMPLATE/", ".github/ISSUE_TEMPLATE/"];
const OTHER_WORKFLOW = /^\.github\/workflows\/[A-Za-z0-9_.-]+\.ya?ml$/u;
const NODE_CONTRACT_TEST = /^tools\/(?:[A-Za-z0-9_.-]+\/)*[A-Za-z0-9_.-]+\.test\.mjs$/u;
const SAFE_SEGMENT = /^[A-Za-z0-9_.-]+$/u;
const SHA = /^[0-9a-f]{40}$/u;

function isNormalizedRelativePath(value) {
  if (typeof value !== "string" || value === "") return false;
  const segments = value.split("/");
  return segments.every((segment) => SAFE_SEGMENT.test(segment) && segment !== "." && segment !== "..");
}

export function isSkipEligiblePath(value) {
  if (!isNormalizedRelativePath(value)) return false;
  if (value === ".github/workflows/ci.yml") return false;
  if (SKIP_ELIGIBLE_EXACT.has(value)) return true;
  if (SKIP_ELIGIBLE_PREFIXES.some((prefix) => value.startsWith(prefix))) return true;
  if (OTHER_WORKFLOW.test(value)) return true;
  if (NODE_CONTRACT_TEST.test(value)) return !value.split("/").includes("fixtures");
  return false;
}

export function decideScope({ event, changedPaths }) {
  if (event !== "pull_request") {
    return { runHeavyLanes: true, reason: "EVENT_NOT_PULL_REQUEST", blockingPaths: [] };
  }
  if (changedPaths.length === 0) {
    return { runHeavyLanes: true, reason: "EMPTY_DIFF", blockingPaths: [] };
  }
  const blockingPaths = changedPaths.filter((changed) => !isSkipEligiblePath(changed));
  if (blockingPaths.length > 0) {
    return { runHeavyLanes: true, reason: "RUN_REQUIRED_PATH", blockingPaths };
  }
  return { runHeavyLanes: false, reason: "SKIP_ELIGIBLE_PATHS_ONLY", blockingPaths: [] };
}

class UsageError extends Error {}

function parseArguments(argv) {
  const [command, ...rest] = argv;
  if (command !== "decide") throw new UsageError("usage: mobile-ci-scope.mjs decide --event <name> --base-sha <sha> --tested-sha <sha>");
  const allowed = new Set(["--event", "--base-sha", "--tested-sha"]);
  const values = new Map();
  for (let index = 0; index < rest.length; index += 2) {
    const flag = rest[index];
    const value = rest[index + 1];
    if (!allowed.has(flag)) throw new UsageError(`unknown argument: ${flag}`);
    if (values.has(flag)) throw new UsageError(`duplicate argument: ${flag}`);
    if (value === undefined) throw new UsageError(`missing value: ${flag}`);
    values.set(flag, value);
  }
  for (const flag of allowed) {
    if (!values.has(flag)) throw new UsageError(`missing argument: ${flag}`);
  }
  const options = { event: values.get("--event"), baseSha: values.get("--base-sha"), testedSha: values.get("--tested-sha") };
  if (!SHA.test(options.baseSha) || !SHA.test(options.testedSha)) throw new UsageError("base and tested SHA must be 40 lowercase hex characters");
  return options;
}

function git(args) {
  return execFileSync("git", args, { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"], maxBuffer: 64 * 1024 * 1024 });
}

function changedPathsBetween(baseSha, testedSha) {
  git(["cat-file", "-e", `${baseSha}^{commit}`]);
  git(["cat-file", "-e", `${testedSha}^{commit}`]);
  const output = git(["-c", "core.quotepath=false", "diff", "--name-only", "-z", "--no-renames", "--no-ext-diff", baseSha, testedSha, "--"]);
  return output.split("\0").filter((entry) => entry !== "");
}

function renderSummary(decision, changedPaths) {
  const lines = [
    "### Mobile CI 실행 범위",
    "",
    `- 판정: ${decision.runHeavyLanes ? "전체 실행" : "무거운 lane 건너뜀"} (\`${decision.reason}\`)`,
    `- 바뀐 경로 ${changedPaths.length}개`,
  ];
  for (const changed of changedPaths) {
    lines.push(`  - \`${changed}\` — ${isSkipEligiblePath(changed) ? "skip 가능" : "실행 필요"}`);
  }
  if (!decision.runHeavyLanes) {
    lines.push("", "#### 건너뛴 lane");
    for (const lane of HEAVY_LANES) lines.push(`- ${lane} — 건너뜀`);
  }
  return `${lines.join("\n")}\n`;
}

export function runCli(argv, environment = process.env) {
  const options = parseArguments(argv);
  const outputPath = environment.GITHUB_OUTPUT;
  const summaryPath = environment.GITHUB_STEP_SUMMARY;
  if (!outputPath || !summaryPath) throw new UsageError("GITHUB_OUTPUT and GITHUB_STEP_SUMMARY are required");
  const changedPaths = options.event === "pull_request" ? changedPathsBetween(options.baseSha, options.testedSha) : [];
  const decision = decideScope({ event: options.event, changedPaths });
  appendFileSync(summaryPath, renderSummary(decision, changedPaths));
  appendFileSync(outputPath, `run-heavy-lanes=${decision.runHeavyLanes}\nreason=${decision.reason}\n`);
  return decision;
}

// 임시 디렉터리가 symlink(macOS /var -> /private/var)여도 직접 실행을 놓치지 않도록 실경로로 비교한다.
if (process.argv[1] && realpathSync(process.argv[1]) === realpathSync(fileURLToPath(import.meta.url))) {
  try {
    runCli(process.argv.slice(2));
  } catch (error) {
    console.error(`mobile-ci-scope: ${error.message}`);
    process.exit(error instanceof UsageError ? 2 : 1);
  }
}
