import assert from "node:assert/strict";
import { execFileSync, spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import test from "node:test";

// Claude Code 공식 /code-review를 PR discovery 리뷰로 실행하는 workflow 계약 (#406, hub #3006 이식).
const workflow = readFileSync(new URL("../../.github/workflows/claude-code-review.yml", import.meta.url), "utf8");
const gateWorkflow = readFileSync(new URL("../../.github/workflows/automerge-queue.yml", import.meta.url), "utf8");

// 들여쓰기 0칸 최상위 키(on:, permissions:, jobs: ...) 사이의 블록을 잘라낸다.
const topLevelBlock = (key) => {
  const match = workflow.match(new RegExp(`^${key}:[^\\n]*\\n((?:(?:[ \\t][^\\n]*)?\\n)*)`, "m"));
  assert.ok(match, `${key}: 최상위 블록이 필요하다`);
  return match[1].replace(/\n+$/, "\n");
};
// jobs 아래 들여쓰기 2칸 job 블록. 다음 job(2칸 키)이나 파일 끝에서 끝난다.
const jobBlock = (id) => {
  const start = workflow.indexOf(`\n  ${id}:\n`);
  assert.ok(start >= 0, `${id} job이 필요하다`);
  const rest = workflow.slice(start + 1);
  const end = rest.slice(1).search(/\n {2}\S/);
  return end === -1 ? rest : rest.slice(0, end + 1);
};
// step 블록은 다음 step·job·최상위 키(들여쓰기 8칸 미만의 다음 줄)에서 끝난다.
const stepBlock = (name) => {
  const start = workflow.indexOf(`      - name: ${name}\n`);
  assert.ok(start >= 0, `${name} step이 필요하다`);
  const end = workflow.slice(start + 1).search(/\n {0,7}\S/);
  return workflow.slice(start, end === -1 ? undefined : start + 1 + end);
};
const stepAt = (name) => workflow.indexOf(`      - name: ${name}\n`);
// `run: |` 본문을 들여쓰기를 걷어낸 bash 스크립트로 돌려준다.
const stepScript = (name) => {
  const run = stepBlock(name).match(/\n {8}run: \|\n((?: {10}[^\n]*\n|\n)*)/)?.[1];
  assert.ok(run, `${name} step에 run 블록이 필요하다`);
  return run.replace(/^ {10}/gm, "");
};

// gh 호출을 기록하고 인자에 match 조각이 든 첫 route의 응답을 돌려주는 stub.
// 같은 route의 두 번째 호출부터는 responses의 다음 항목(마지막 항목에서 멈춤)을 쓴다.
const GH_STUB = `
import { appendFileSync, existsSync, readFileSync, writeFileSync } from "node:fs";
const args = process.argv.slice(2).join(" ");
appendFileSync(process.env.GH_LOG, args + "\\n");
const routes = JSON.parse(readFileSync(process.env.GH_ROUTES, "utf8"));
const state = existsSync(process.env.GH_STATE) ? JSON.parse(readFileSync(process.env.GH_STATE, "utf8")) : {};
const index = routes.findIndex((route) => args.includes(route.match));
if (index === -1) {
  process.stderr.write("unrouted gh call: " + args + "\\n");
  process.exit(97);
}
const count = state[index] ?? 0;
state[index] = count + 1;
writeFileSync(process.env.GH_STATE, JSON.stringify(state));
const responses = routes[index].responses;
const response = responses[Math.min(count, responses.length - 1)];
if (response.status) process.exit(response.status);
process.stdout.write(typeof response.body === "string" ? response.body : JSON.stringify(response.body));
`;
// workflow step의 run 스크립트를 gh stub과 함께 그대로 실행한다.
const runStep = (name, { env = {}, routes = [], prelude = "", cwd } = {}) => {
  const dir = mkdtempSync(join(tmpdir(), "claude-review-step-"));
  const paths = {
    stub: join(dir, "gh-stub.mjs"),
    routes: join(dir, "routes.json"),
    log: join(dir, "gh.log"),
    state: join(dir, "gh-state.json"),
    output: join(dir, "github-output"),
  };
  writeFileSync(paths.stub, GH_STUB);
  writeFileSync(paths.routes, JSON.stringify(routes));
  writeFileSync(paths.log, "");
  writeFileSync(paths.output, "");
  const script = [`gh() { node ${JSON.stringify(paths.stub)} "$@"; }`, prelude, stepScript(name)].join("\n");
  const result = spawnSync("bash", ["-c", script], {
    cwd,
    encoding: "utf8",
    env: {
      ...process.env,
      GH_LOG: paths.log,
      GH_ROUTES: paths.routes,
      GH_STATE: paths.state,
      GITHUB_OUTPUT: paths.output,
      ...env,
    },
  });
  const outputs = Object.fromEntries(
    readFileSync(paths.output, "utf8")
      .split("\n")
      .filter((line) => line.includes("="))
      .map((line) => [line.slice(0, line.indexOf("=")), line.slice(line.indexOf("=") + 1)]),
  );
  const calls = readFileSync(paths.log, "utf8").split("\n").filter(Boolean);
  return { status: result.status, stdout: result.stdout, stderr: result.stderr, outputs, calls };
};

const HEAD = "a".repeat(40);
const OTHER = "b".repeat(40);
const BASE = "f".repeat(40);
const CLAUDE = { login: "claude[bot]", id: 209825114, type: "Bot" };
const claudeReview = (id, overrides = {}) => ({
  id,
  state: "COMMENTED",
  commit_id: HEAD,
  submitted_at: `2026-09-29T01:0${id % 10}:00Z`,
  author_association: "NONE",
  user: CLAUDE,
  body: "🔴 0 · 🟡 1 · 🟣 0\n요약",
  ...overrides,
});

test("트리거는 PR opened·reopened·synchronize·ready_for_review와 PR 번호 수동 재실행뿐이다", () => {
  // rebase(force-push) 뒤 사라진 discovery를 다시 만들 수 있도록 synchronize·reopened도 받는다 (#407 F3).
  const on = topLevelBlock("on");
  assert.match(on, /^ {2}pull_request:\n {4}types:\n {6}- opened\n {6}- reopened\n {6}- synchronize\n {6}- ready_for_review\n/m);
  assert.match(on, /^ {2}workflow_dispatch:\n {4}inputs:\n {6}pr_number:\n(?: {8}[^\n]*\n)* {8}required: true\n(?: {8}[^\n]*\n)* {8}type: number\n/m);
  assert.doesNotMatch(on, /labeled|pull_request_target|push:|schedule:|issue_comment|pull_request_review/);
});

test("target job이 리뷰 여부를 정하고 review job은 그 판정이 true일 때만 돈다", () => {
  const jobs = topLevelBlock("jobs");
  assert.deepEqual(
    [...jobs.matchAll(/^ {2}([a-z_-]+):\n/gm)].map((match) => match[1]),
    ["target", "review"],
    "job은 target → review 두 개다",
  );
  const target = jobBlock("target");
  assert.match(target, /^ {4}outputs:\n(?: {6}[^\n]*\n)* {6}should_review: \$\{\{ steps\.dedupe\.outputs\.should_review \}\}\n/m);
  assert.match(target, /^ {6}number: \$\{\{ steps\.pr\.outputs\.number \}\}\n/m);
  assert.match(target, /^ {6}head_sha: \$\{\{ steps\.pr\.outputs\.head_sha \}\}\n/m);
  const review = jobBlock("review");
  assert.match(review, /^ {4}needs: target\n/m);
  assert.match(review, /^ {4}if: needs\.target\.outputs\.should_review == 'true'\n/m);
  const steps = (block) => [...block.matchAll(/^ {6}- name: ([^\n]+)\n/gm)].map((match) => match[1]);
  assert.deepEqual(steps(target), ["Resolve pull request", "Check existing verified Claude review", "Wait for CI on pull request head"]);
  assert.deepEqual(steps(review), [
    "Checkout pull request head",
    "Restore base agent configuration",
    "Record existing reviews",
    "Run Claude Code review",
    "Verify Claude review object",
  ]);
});

test("Draft·fork PR과 봇이 실행 주체인 이벤트는 target job if로 건너뛰고 수동 재실행은 영향받지 않는다", () => {
  // 봇 판정은 PR 작성자가 아니라 이벤트 실행 주체(sender) 기준이다. action이 봇 actor를 거부하기 때문이다 (data#818 F2).
  const jobIf = jobBlock("target").match(/^ {4}if: (?:>-?\n)?([\s\S]*?)^ {4}runs-on:/m)?.[1];
  assert.ok(jobIf, "target job에 job-level if 조건이 필요하다");
  assert.equal(
    jobIf.replace(/\s+/g, " ").trim(),
    "(github.event_name == 'pull_request' && github.event.pull_request.draft == false && "
      + "github.event.pull_request.head.repo.full_name == github.repository && "
      + "github.event.sender.type != 'Bot') || github.event_name == 'workflow_dispatch'",
  );
  assert.doesNotMatch(workflow, /pull_request\.user\.type/);
  // skip된 job은 claude[bot] Review를 만들지 않으므로 게이트 통과가 아니다(automerge-queue.test.mjs의 marker·Review 없음 → 거부).
});

const prPayload = (overrides = {}) => ({
  state: "open",
  draft: false,
  head: { sha: HEAD, ref: "feature/review-406", repo: { full_name: "o/r" } },
  base: { sha: BASE },
  ...overrides,
});
const resolve = (pr, env = {}) =>
  runStep("Resolve pull request", {
    env: { REPO: "o/r", PR_NUMBER: "7", EVENT_NAME: "pull_request", RUN_HEAD_SHA: HEAD, ...env },
    routes: [{ match: "repos/o/r/pulls/7", responses: [{ body: pr }] }],
  });

test("Resolve는 open·non-draft·same-repo PR을 확인하고 head·base를 넘긴다", () => {
  const block = stepBlock("Resolve pull request");
  assert.match(block, /PR_NUMBER: \$\{\{ github\.event\.pull_request\.number \|\| inputs\.pr_number \}\}/);
  assert.doesNotMatch(block, /started_at/, "Review 식별에 시간 창을 쓰지 않는다 (D3)");

  const ok = resolve(prPayload());
  assert.equal(ok.status, 0, ok.stderr + ok.stdout);
  assert.deepEqual(ok.outputs, { number: "7", head_sha: HEAD, head_ref: "feature/review-406", base_sha: BASE });

  for (const [pr, reason] of [
    [prPayload({ state: "closed" }), "open 상태가 아니다"],
    [prPayload({ draft: true }), "Draft다"],
    [prPayload({ head: { sha: HEAD, ref: "x", repo: { full_name: "fork/r" } } }), "fork"],
  ]) {
    const result = resolve(pr);
    assert.equal(result.status, 1, reason);
    assert.match(result.stdout, new RegExp(reason));
    assert.deepEqual(result.outputs, {}, `${reason}: 출력 없이 실패한다`);
  }
});

test("Resolve는 실행 head가 PR head와 다르면 리뷰하지 않고 이벤트별 재실행 경로를 안내하며 실패한다", () => {
  // 게이트는 리뷰 commit == run head_sha인 run만 인정한다: pull_request는 이벤트 head, dispatch는 실행 ref head.
  assert.match(stepBlock("Resolve pull request"), /RUN_HEAD_SHA: \$\{\{ github\.event\.pull_request\.head\.sha \|\| github\.sha \}\}/);

  const moved = resolve(prPayload(), { RUN_HEAD_SHA: OTHER });
  assert.equal(moved.status, 1);
  assert.match(moved.stdout, /새 head의 synchronize 실행이 리뷰한다/);
  assert.deepEqual(moved.outputs, {});

  const dispatchedFromMain = resolve(prPayload(), { EVENT_NAME: "workflow_dispatch", RUN_HEAD_SHA: OTHER });
  assert.equal(dispatchedFromMain.status, 1);
  assert.match(
    dispatchedFromMain.stdout,
    /gh workflow run claude-code-review\.yml --ref feature\/review-406 -f pr_number=7/,
    "dispatch는 PR head 브랜치 ref로 재실행하라고 안내한다",
  );
  assert.deepEqual(dispatchedFromMain.outputs, {});

  const dispatchedFromHead = resolve(prPayload(), { EVENT_NAME: "workflow_dispatch", RUN_HEAD_SHA: HEAD });
  assert.equal(dispatchedFromHead.status, 0, "PR head 브랜치 ref로 실행한 dispatch는 통과한다");
});

// D8: synchronize·reopened의 skip 판정. 게이트(D1)와 같은 신원·개수 줄·run success·리뷰 commit 시점 diff 규칙을 쓴다.
const dedupeRoutes = ({ reviews = [], commits = [HEAD], runs = {}, compare = {} } = {}) => [
  { match: "pulls/7/reviews", responses: [{ body: [reviews] }] },
  { match: "pulls/7/commits", responses: [{ body: [commits.map((sha) => ({ sha }))] }] },
  ...Object.entries(runs).map(([sha, response]) => ({
    match: `actions/workflows/claude-code-review.yml/runs?head_sha=${sha}&status=success`,
    responses: [response],
  })),
  ...Object.entries(compare).map(([sha, response]) => ({ match: `compare/${BASE}...${sha}`, responses: [response] })),
];
const successRuns = (sha) => ({ body: { total_count: 1, workflow_runs: [{ id: 1, head_sha: sha, conclusion: "success" }] } });
const failedRuns = (sha) => ({ body: { total_count: 1, workflow_runs: [{ id: 1, head_sha: sha, conclusion: "failure" }] } });
const cleanCompare = { body: { files: [{ filename: "apps/mobile/lib/main.dart", status: "modified" }] } };
const verifiedFixture = {
  reviews: [claudeReview(1, { commit_id: OTHER })],
  commits: [OTHER, HEAD],
  runs: { [OTHER]: successRuns(OTHER) },
  compare: { [OTHER]: cleanCompare },
};
const dedupe = (action, fixture, event = "pull_request") =>
  runStep("Check existing verified Claude review", {
    env: { REPO: "o/r", PR_NUMBER: "7", BASE_SHA: BASE, EVENT_NAME: event, EVENT_ACTION: action },
    routes: dedupeRoutes(fixture),
  });

test("synchronize·reopened는 PR commit 안의 검증된 claude[bot] Review가 있으면 리뷰를 건너뛴다 (D8)", () => {
  for (const action of ["synchronize", "reopened"]) {
    const result = dedupe(action, verifiedFixture);
    assert.equal(result.status, 0, result.stderr + result.stdout);
    assert.equal(result.outputs.should_review, "false", `${action}: 검증된 discovery가 있으면 건너뛴다`);
  }
  for (const action of ["opened", "ready_for_review"]) {
    const result = dedupe(action, verifiedFixture);
    assert.equal(result.outputs.should_review, "true", `${action}는 항상 리뷰한다`);
    assert.deepEqual(result.calls, [], `${action}는 기존 Review를 조회하지 않는다`);
  }
  const dispatched = dedupe("", verifiedFixture, "workflow_dispatch");
  assert.equal(dispatched.outputs.should_review, "true", "수동 재실행은 항상 리뷰한다");
  assert.deepEqual(dispatched.calls, []);
});

test("synchronize는 rebase로 리뷰 commit이 빠졌거나 검증되지 않은 Review만 있으면 다시 리뷰한다 (D8)", () => {
  for (const [fixture, reason] of [
    [{ ...verifiedFixture, commits: [HEAD] }, "rebase로 리뷰 commit이 PR commit 목록에서 빠졌다"],
    [{ ...verifiedFixture, reviews: [claudeReview(1, { commit_id: OTHER, body: "" })] }, "빈 본문 wrapper만 있다"],
    [{ ...verifiedFixture, reviews: [claudeReview(1, { commit_id: OTHER, body: "요약만 있다" })] }, "개수 줄이 없다"],
    [{ ...verifiedFixture, reviews: [claudeReview(1, { commit_id: OTHER, user: { ...CLAUDE, id: 1 } })] }, "신원이 다르다"],
    [{ ...verifiedFixture, reviews: [claudeReview(1, { commit_id: OTHER, state: "APPROVED" })] }, "COMMENTED가 아니다"],
    [{ ...verifiedFixture, runs: { [OTHER]: failedRuns(OTHER) } }, "그 commit의 run이 success가 아니다(검증 step 실패)"],
    [{ ...verifiedFixture, runs: { [OTHER]: { body: { total_count: 0, workflow_runs: [] } } } }, "그 commit의 run이 없다"],
    [{ ...verifiedFixture, runs: { [OTHER]: successRuns(HEAD) } }, "success run의 head가 리뷰 commit이 아니다"],
    [
      { ...verifiedFixture, compare: { [OTHER]: { body: { files: [{ filename: ".github/workflows/claude-code-review.yml" }] } } } },
      "리뷰 commit 시점 PR diff가 이 workflow를 바꿨다",
    ],
  ]) {
    const result = dedupe("synchronize", fixture);
    assert.equal(result.status, 0, `${reason}: ${result.stderr}${result.stdout}`);
    assert.equal(result.outputs.should_review, "true", reason);
  }
  const noCandidate = dedupe("synchronize", { ...verifiedFixture, commits: [HEAD] });
  assert.ok(!noCandidate.calls.some((call) => call.includes("/runs?") || call.includes("/compare/")), "후보가 없으면 run·compare를 조회하지 않는다");
  const failedRun = dedupe("synchronize", { ...verifiedFixture, runs: { [OTHER]: failedRuns(OTHER) } });
  assert.ok(!failedRun.calls.some((call) => call.includes("/compare/")), "run success가 없으면 compare를 조회하지 않는다");
});

test("synchronize 판정은 조회 실패·변경 파일 300개 상한에서 추정하지 않고 실패한다 (D8)", () => {
  const truncated = Array.from({ length: 300 }, (_, index) => ({ filename: `f${index}.dart` }));
  for (const [fixture, reason] of [
    [{ ...verifiedFixture, runs: { [OTHER]: { status: 1 } } }, "run 조회 실패"],
    [{ ...verifiedFixture, runs: { [OTHER]: { body: { message: "Not Found" } } } }, "run 응답 형식 오류"],
    [{ ...verifiedFixture, compare: { [OTHER]: { status: 1 } } }, "compare 조회 실패"],
    [{ ...verifiedFixture, compare: { [OTHER]: { body: { files: truncated } } } }, "compare files 300개 상한"],
    [{ ...verifiedFixture, compare: { [OTHER]: { body: { message: "diff too large" } } } }, "compare files 없음"],
  ]) {
    const result = dedupe("synchronize", fixture);
    assert.notEqual(result.status, 0, reason);
    assert.equal(result.outputs.should_review, undefined, `${reason}: 판정을 내지 않는다`);
  }
});

test("synchronize 판정 후보 식은 automerge 게이트의 claude[bot] 후보 식과 같다 (D8)", () => {
  const candidateProgram = (text) =>
    text.match(/candidates="?\$\(jq -c --argjson commit_shas "\$\{commit_shas\}" '\n([\s\S]*?)\n\s*' <<<"\$\{reviews\}"\)/)?.[1];
  const dedupeProgram = candidateProgram(stepScript("Check existing verified Claude review"));
  const gateProgram = candidateProgram(gateWorkflow);
  assert.ok(dedupeProgram, "synchronize 판정 step의 후보 jq 식이 필요하다");
  assert.ok(gateProgram, "automerge 게이트의 claude[bot] 후보 jq 식이 필요하다");
  const normalize = (program) => program.replace(/\s+/g, " ").trim();
  assert.equal(normalize(dedupeProgram), normalize(gateProgram), "두 식은 문자 그대로 같아야 한다");
  for (const rule of [/\.user\.login == "claude\[bot\]"/, /\.user\.id == 209825114/, /\.user\.type == "Bot"/, /\.state == "COMMENTED"/]) {
    assert.match(dedupeProgram, rule);
  }
  const pick = (reviews, commitShas) =>
    JSON.parse(execFileSync("jq", ["-c", "--argjson", "commit_shas", JSON.stringify(commitShas), dedupeProgram], {
      input: JSON.stringify([reviews]),
      encoding: "utf8",
    }));
  assert.deepEqual(
    pick([claudeReview(1, { commit_id: OTHER }), claudeReview(2, { commit_id: OTHER }), claudeReview(3)], [OTHER, HEAD]),
    [HEAD, OTHER],
    "서로 다른 commit만 한 번씩 조회한다",
  );
  assert.deepEqual(pick([claudeReview(1, { body: "🔴 0 · 🟡 0 · 🟣 0\r\n요약" })], [HEAD]), [], "개수 줄 뒤 CR은 개수 줄이 아니다");
  assert.deepEqual(pick([claudeReview(1, { body: "요약\n🔴 0 · 🟡 0 · 🟣 0" })], [HEAD]), [], "개수 줄은 첫 줄이어야 한다");
  assert.deepEqual(pick([claudeReview(1, { body: null })], [HEAD]), [], "본문 없음");
});

// D4: 같은 head의 다른 pull_request workflow를 workflow별 최신 run으로 판정한다.
const ciRun = (overrides = {}) => ({
  id: 1,
  workflow_id: 11,
  run_number: 1,
  name: "CI",
  path: ".github/workflows/ci.yml",
  event: "pull_request",
  head_sha: HEAD,
  status: "completed",
  conclusion: "success",
  ...overrides,
});
const golden = (overrides = {}) =>
  ciRun({ id: 2, workflow_id: 12, name: "Mobile Golden", path: ".github/workflows/mobile-golden.yml", ...overrides });
const runsPage = (runs) => ({ body: [{ total_count: runs.length, workflow_runs: runs }] });
// date·sleep을 가짜 시계로 바꿔 대기 루프를 즉시 돌린다.
const FAKE_CLOCK = [
  "now=1000",
  "date() { printf '%s\\n' \"${now}\"; }",
  "sleep() { printf 'sleep %s\\n' \"$1\" >> \"${GH_LOG}\"; now=$(( now + $1 )); }",
].join("\n");
const waitForCi = (pages) =>
  runStep("Wait for CI on pull request head", {
    env: { REPO: "o/r", PR_NUMBER: "7", HEAD_SHA: HEAD, HEAD_REF: "feature/review-406" },
    routes: [{ match: `actions/runs?head_sha=${HEAD}`, responses: pages }],
    prelude: FAKE_CLOCK,
  });
const sleeps = (result) => result.calls.filter((call) => call.startsWith("sleep"));

test("CI 대기 step은 판정 뒤·리뷰 전에만 돌고 모든 pull_request workflow가 green일 때 끝난다 (D4)", () => {
  const block = stepBlock("Wait for CI on pull request head");
  assert.match(block, /^ {8}if: steps\.dedupe\.outputs\.should_review == 'true'\n/m);
  assert.ok(stepAt("Check existing verified Claude review") < stepAt("Wait for CI on pull request head"));
  assert.ok(stepAt("Wait for CI on pull request head") < stepAt("Run Claude Code review"));
  assert.match(block, /actions\/runs\?head_sha=\$\{HEAD_SHA\}&event=pull_request&per_page=100/);

  const pendingThenGreen = waitForCi([
    runsPage([ciRun({ status: "in_progress", conclusion: null }), golden()]),
    runsPage([ciRun(), golden()]),
  ]);
  assert.equal(pendingThenGreen.status, 0, pendingThenGreen.stderr + pendingThenGreen.stdout);
  assert.deepEqual(sleeps(pendingThenGreen), ["sleep 30"]);

  const ignored = waitForCi([
    runsPage([
      ciRun(),
      ciRun({ id: 3, workflow_id: 99, name: "Claude Code Review", path: ".github/workflows/claude-code-review.yml", status: "in_progress", conclusion: null }),
      ciRun({ id: 4, workflow_id: 98, name: "Automerge Queue", event: "pull_request_review", conclusion: "failure" }),
      ciRun({ id: 5, workflow_id: 97, name: "Docs", conclusion: "skipped" }),
      ciRun({ id: 6, workflow_id: 96, name: "Lint", conclusion: "neutral" }),
    ]),
  ]);
  assert.equal(ignored.status, 0, "이 workflow 자신·pull_request가 아닌 이벤트는 보지 않고 skipped·neutral은 green으로 본다");
  assert.deepEqual(sleeps(ignored), []);
});

test("CI 대기 step은 workflow별 최신 run만 보고 최신 run이 green이 아니면 --ref 재실행을 안내하며 실패한다 (D4)", () => {
  const superseded = waitForCi([
    runsPage([ciRun({ id: 1, run_number: 8541, conclusion: "cancelled" }), ciRun({ id: 2, run_number: 8542, conclusion: "success" })]),
  ]);
  assert.equal(superseded.status, 0, "concurrency로 대체된 이전 cancelled run은 무시한다");

  for (const conclusion of ["failure", "cancelled", "timed_out", "action_required", "startup_failure"]) {
    const result = waitForCi([runsPage([ciRun({ id: 1, run_number: 1 }), ciRun({ id: 2, run_number: 2, conclusion }), golden()])]);
    assert.equal(result.status, 1, `최신 run ${conclusion}`);
    assert.match(result.stdout, new RegExp(`CI\\(${conclusion}\\)`));
    assert.match(result.stdout, /gh workflow run claude-code-review\.yml --ref feature\/review-406 -f pr_number=7/);
    assert.deepEqual(sleeps(result), [], "green이 아닌 최신 run이 보이면 기다리지 않고 실패한다");
  }
  const olderFailureNewerPending = waitForCi([
    runsPage([ciRun({ id: 1, run_number: 1, conclusion: "failure" }), ciRun({ id: 2, run_number: 2, status: "queued", conclusion: null })]),
    runsPage([ciRun({ id: 1, run_number: 1, conclusion: "failure" }), ciRun({ id: 2, run_number: 2 })]),
  ]);
  assert.equal(olderFailureNewerPending.status, 0, "이전 실패 뒤 새 run이 green이면 통과한다");
});

test("CI 대기 step은 run이 없으면 최소 2분 기다리고 제한 시간을 넘기거나 조회에 실패하면 실패한다 (D4)", () => {
  const none = waitForCi([runsPage([])]);
  assert.equal(none.status, 0, none.stderr + none.stdout);
  assert.deepEqual(sleeps(none), ["sleep 30", "sleep 30", "sleep 30", "sleep 30"], "2분 동안 30초 간격으로 다시 본다");

  const stuck = waitForCi([runsPage([ciRun({ status: "in_progress", conclusion: null })])]);
  assert.equal(stuck.status, 1);
  assert.match(stuck.stdout, /1800초 안에 끝나지 않았다/);
  assert.match(stuck.stdout, /--ref feature\/review-406 -f pr_number=7/);

  const apiFailure = waitForCi([{ status: 1 }]);
  assert.notEqual(apiFailure.status, 0, "run 조회 실패는 대기 성공이 아니다");
});

test("인증은 CLAUDE_CODE_OAUTH_TOKEN만 쓰고 API 키·커스텀 github_token을 쓰지 않는다", () => {
  const review = stepBlock("Run Claude Code review");
  assert.match(review, /uses: anthropics\/claude-code-action@[0-9a-f]{40} # v1\.0\.\d+\n/, "40자 커밋 SHA 고정 + 버전 주석");
  assert.doesNotMatch(workflow, /claude-code-action@v\d/, "움직이는 tag 참조 금지");
  assert.match(review, /claude_code_oauth_token: \$\{\{ secrets\.CLAUDE_CODE_OAUTH_TOKEN \}\}/);
  assert.doesNotMatch(workflow, /anthropic_api_key|ANTHROPIC_API_KEY/);
  assert.doesNotMatch(review, /github_token:/, "커스텀 토큰은 claude[bot]이 아닌 신원으로 게시하게 만든다");
  assert.deepEqual([...new Set(workflow.match(/secrets\.[A-Z0-9_]+/g))], ["secrets.CLAUDE_CODE_OAUTH_TOKEN"]);
  assert.doesNotMatch(review, /track_progress: *["']?true/, "tag mode 전환 금지(agent mode prompt 유지)");
});

test("공식 /code-review를 high effort로 실행하고 ultra는 쓰지 않는다", () => {
  const review = stepBlock("Run Claude Code review");
  assert.match(review, /prompt: \/code-review high \$\{\{ needs\.target\.outputs\.number \}\}\n/);
  assert.doesNotMatch(workflow, /ultra/i);
});

test("Claude 도구 권한은 PR 조회, 작업 디렉터리 리뷰 JSON 편집, Review 목록 재확인, 단일 COMMENT Review 게시로 제한된다", () => {
  const review = stepBlock("Run Claude Code review");
  const allowed = review.match(/--allowedTools "([^"]+)"/)?.[1];
  assert.ok(allowed, "--allowedTools가 필요하다");
  assert.deepEqual(allowed.split(","), [
    "Bash(gh pr view *)",
    "Bash(gh pr diff *)",
    // Edit 규칙이 Write를 포함한 모든 파일 편집 도구에 적용되고 ./path는 현재 작업 디렉터리 기준이다 (D10, 공식 permissions 문서).
    "Edit(./claude-code-review.json)",
    // 게시 실패 뒤 재게시 전에 이미 게시됐는지 확인하는 GET (D5).
    "Bash(gh api --paginate repos/${{ github.repository }}/pulls/${{ needs.target.outputs.number }}/reviews)",
    "Bash(gh api repos/${{ github.repository }}/pulls/${{ needs.target.outputs.number }}/reviews --method POST --input claude-code-review.json)",
  ]);
  assert.doesNotMatch(allowed, /Write\(/, "Write 경로 규칙은 권한 판정에 쓰이지 않고 시작 경고만 낸다 (D10)");
  assert.doesNotMatch(allowed, /Edit\(\/claude-code-review\.json\)/, "/path는 settings source 기준이라 쓰지 않는다 (D10)");
  assert.match(review, /--append-system-prompt '/);
  assert.match(review, /"event": "COMMENT"/);
  assert.match(review, /"commit_id": "\$\{\{ needs\.target\.outputs\.head_sha \}\}"/);
  assert.match(review, /현재 작업 디렉터리의 \.\/claude-code-review\.json 파일/);
  assert.match(review, /🔴 Important/);
  assert.match(review, /🟡 Nit/);
  assert.match(review, /🟣 Pre-existing/);
  assert.match(review, /한국어/);
  assert.match(review, /작성자\(사람, 에이전트, 자동화\)나 변경 크기와 관계없이[^\n]*건너뛰지 않는다/, "PR 작성자·크기 기반 skip 금지");
  assert.doesNotMatch(review, /--approve|--request-changes|Bash\(gh \*\)|Bash\(gh:\*\)|Bash\(\*\)|Bash\(gh api \*\)|Bash\(git push/);
});

test("게시 명령이 실패하면 재게시 전에 이번 head의 claude[bot] Review가 이미 있는지 확인한다 (D5)", () => {
  const review = stepBlock("Run Claude Code review");
  const retry = review.match(/- 게시 명령이 실패하면([\s\S]*?)(?:\n {15}- |'\n)/)?.[1];
  assert.ok(retry, "게시 실패 절차 문단이 필요하다");
  assert.match(
    retry,
    /다시 게시하기 전에 파이프 없이 정확히 이 명령으로 Review 목록을 읽는다: gh api --paginate repos\/\$\{\{ github\.repository \}\}\/pulls\/\$\{\{ needs\.target\.outputs\.number \}\}\/reviews\n/,
  );
  assert.match(
    retry,
    /user\.login이 claude\[bot\]이고 commit_id가 \$\{\{ needs\.target\.outputs\.head_sha \}\}이며 body가 \.\/claude-code-review\.json의 body와 같은 Review가 이미 있으면[^\n]*다시 게시하지 않는다/,
  );
  assert.ok(retry.indexOf("Review 목록을 읽는다") < retry.indexOf("JSON을 고쳐 게시 명령을 다시 실행한다"), "확인이 재게시보다 먼저다");
});

test("리뷰 프롬프트는 mobile 레포 규칙으로 옮겨져 있다", () => {
  const review = stepBlock("Run Claude Code review");
  assert.match(review, /--append-system-prompt 'EasySubway mobile PR discovery 리뷰 규칙 \(Issue #406\)\./);
  for (const priority of [
    /Fallback 금지/,
    /stale 캐시/,
    /서버 공인 라우팅/,
    /클라이언트 쪽 경로 계산/,
    /접근성 회귀/,
    /스크린리더 라벨/,
    /큰 글자/,
    /48dp 터치 타깃/,
    /실패하는 테스트/,
    /continue-on-error/,
    /documentation-fragment\.json/,
    /내부 거버넌스 문구/,
    /시크릿/,
    /내부 절대경로/,
  ]) {
    assert.match(review, priority);
  }
  assert.doesNotMatch(review, /EasySubway hub|Issue #3006|Flyway/, "hub 전용 규칙(DB 마이그레이션 등)을 mobile 리뷰에 싣지 않는다");
});

test("최소 권한·PR별 concurrency·job별 timeout을 두고 실패를 성공으로 덮지 않는다", () => {
  assert.equal(topLevelBlock("permissions"), "  contents: read\n");
  const jobPermissions = (id) => jobBlock(id).match(/^ {4}permissions:\n((?: {6}[^\n]*\n)+)/m)?.[1];
  assert.equal(jobPermissions("target"), "      actions: read\n      contents: read\n      pull-requests: read\n");
  assert.equal(jobPermissions("review"), "      contents: read\n      pull-requests: read\n      id-token: write\n");
  assert.doesNotMatch(workflow, /write-all|contents: write|pull-requests: write|issues: write|actions: write/);
  assert.match(topLevelBlock("concurrency"), /group: claude-code-review-\$\{\{ github\.event\.pull_request\.number \|\| inputs\.pr_number \}\}\n/);
  const timeoutOf = (id) => Number(jobBlock(id).match(/^ {4}timeout-minutes: (\d+)\n/m)?.[1]);
  for (const id of ["target", "review"]) {
    assert.ok(timeoutOf(id) > 0 && timeoutOf(id) <= 60, `${id} timeout-minutes는 1~60이어야 한다: ${timeoutOf(id)}`);
  }
  // CI 대기 상한은 target job timeout보다 충분히 짧아야 job이 죽기 전에 명시 실패 메시지가 남는다.
  const maxWait = Number(stepScript("Wait for CI on pull request head").match(/max_wait_seconds=(\d+)/)?.[1]);
  assert.ok(maxWait > 0 && maxWait + 300 <= timeoutOf("target") * 60, `CI 대기 상한 ${maxWait}초`);
  assert.doesNotMatch(workflow, /^\s*continue-on-error\s*:/m);
  assert.doesNotMatch(workflow, /\|\| true|\|\| echo|\|\| exit 0/);
});

const verifyReview = ({ before = [], reviews = [], comments = [] } = {}) =>
  runStep("Verify Claude review object", {
    env: { REPO: "o/r", PR_NUMBER: "7", HEAD_SHA: HEAD, BEFORE_REVIEW_IDS: JSON.stringify(before) },
    routes: [
      { match: "pulls/7/reviews/", responses: [{ body: [comments] }] },
      { match: "pulls/7/reviews", responses: [{ body: [reviews] }] },
    ],
  });
const inline = (...prefixes) => prefixes.map((prefix, index) => ({ id: 100 + index, body: `${prefix} **finding ${index}**` }));

test("실행 전 Review id를 기록하고 검증 step은 그 차집합으로 이번 실행의 Review를 찾는다 (D3)", () => {
  // action 내부 단계가 전부 skipped여도 job이 pass로 끝나는 가짜 통과를 막는 별도 검증 step (easyconvert #238 실측).
  assert.ok(stepAt("Record existing reviews") < stepAt("Run Claude Code review"));
  assert.ok(stepAt("Run Claude Code review") < stepAt("Verify Claude review object"));
  const verify = stepBlock("Verify Claude review object");
  assert.doesNotMatch(verify, /^ {8}if:/m, "검증 step에는 step-level if를 두지 않는다");
  assert.match(verify, /BEFORE_REVIEW_IDS: \$\{\{ steps\.before\.outputs\.review_ids \}\}/);
  assert.doesNotMatch(verify, /since|submitted_at|started_at/, "시간 창으로 이번 실행의 Review를 고르지 않는다");
  assert.equal((verify.match(/\.user\.id == 209825114/g) ?? []).length, 1, "신원 필터는 한 번만 계산한다 (#407 F7)");

  const recorded = runStep("Record existing reviews", {
    env: { REPO: "o/r", PR_NUMBER: "7" },
    routes: [{ match: "pulls/7/reviews", responses: [{ body: [[{ id: 3 }, { id: 4 }], [{ id: 9 }]] }] }],
  });
  assert.equal(recorded.status, 0, recorded.stderr);
  assert.equal(recorded.outputs.review_ids, "[3,4,9]");

  const ok = verifyReview({
    before: [1],
    reviews: [claudeReview(1, { submitted_at: "2026-09-29T09:00:00Z" }), claudeReview(2)],
    comments: inline("🟡"),
  });
  assert.equal(ok.status, 0, ok.stderr + ok.stdout);
  assert.ok(ok.calls.includes("api --paginate --slurp repos/o/r/pulls/7/reviews/2/comments"), "새 Review의 inline 코멘트를 센다");

  for (const [fixture, reason] of [
    [{ before: [1], reviews: [claudeReview(1)] }, "새 Review가 없다(이전 실행 Review는 시각과 무관하게 세지 않는다)"],
    [{ before: [], reviews: [claudeReview(1), claudeReview(2)] }, "개수 줄 Review가 두 번 게시됐다"],
    [{ before: [], reviews: [claudeReview(1, { commit_id: OTHER })] }, "다른 head"],
    [{ before: [], reviews: [claudeReview(1, { state: "APPROVED" })] }, "APPROVE 게시"],
    [{ before: [], reviews: [claudeReview(1, { user: { ...CLAUDE, id: 1 } })] }, "위조 신원"],
    [{ before: [], reviews: [claudeReview(1, { body: "요약만 있고 개수 줄 없음" })] }, "개수 줄 없는 Review만 있다"],
    [{ before: [], reviews: [claudeReview(1, { body: "" })] }, "빈 본문 wrapper만 있다"],
  ]) {
    const result = verifyReview({ ...fixture, comments: inline("🟡") });
    assert.equal(result.status, 1, reason);
    assert.match(result.stdout, /정확히 하나 게시되지 않았다/, reason);
  }
  const withWrapper = verifyReview({ before: [], reviews: [claudeReview(1), claudeReview(2, { body: "" })], comments: inline("🟡") });
  assert.equal(withWrapper.status, 0, "새 빈 본문 thread 답글 wrapper는 개수에서 빠진다");
});

test("🔴·🟡는 심각도별 inline 코멘트 수로 대조하고 🟣 inline은 blocking 개수를 채우지 못한다 (D2)", () => {
  // 병합 차단은 미해결 inline thread에 의존하므로, 본문 개수보다 해당 심각도 inline이 적으면 thread gate 우회다 (#407 F4).
  const verify = stepBlock("Verify Claude review object");
  assert.match(verify, /gh api --paginate --slurp "repos\/\$\{REPO\}\/pulls\/\$\{PR_NUMBER\}\/reviews\/\$\{review_id\}\/comments"/);
  assert.match(verify, /if \[ "\$\{coverage\}" != "true" \]; then[\s\S]*?exit 1/);
  const coverage = (body, ...prefixes) => {
    const result = verifyReview({ before: [], reviews: [claudeReview(1, { body })], comments: inline(...prefixes) });
    if (result.status === 0) return "true";
    assert.equal(result.status, 1, result.stderr);
    assert.match(result.stdout, /inline 코멘트/, "개수 대조 실패여야 한다");
    return "false";
  };
  assert.equal(coverage("🔴 1 · 🟡 0 · 🟣 1\n요약", "🟣"), "false", "🟣 inline이 본문에만 둔 🔴를 가리지 못한다");
  assert.equal(coverage("🔴 1 · 🟡 0 · 🟣 0\n요약"), "false", "본문에만 둔 Important");
  assert.equal(coverage("🔴 1 · 🟡 0 · 🟣 0\n요약", "🟡"), "false", "🟡 inline이 🔴를 대신하지 못한다");
  assert.equal(coverage("🔴 0 · 🟡 1 · 🟣 0\n요약", "🔴"), "false", "🔴 inline이 🟡를 대신하지 못한다");
  assert.equal(coverage("🔴 1 · 🟡 0 · 🟣 0\n요약", "🔴"), "true", "Important 1건 inline");
  assert.equal(coverage("🔴 0 · 🟡 2 · 🟣 1\n요약", "🟡"), "false", "Nit 1건 누락");
  assert.equal(coverage("🔴 0 · 🟡 2 · 🟣 1\n요약", "🟡", "🟡"), "true", "Pre-existing은 본문 허용");
  assert.equal(coverage("🔴 1 · 🟡 1 · 🟣 0\n요약", "🔴", "🟡", "🟣"), "true", "🟣 inline이 섞여도 심각도별로 센다");
  assert.equal(coverage("🔴 0 · 🟡 0 · 🟣 0\nfinding 없음"), "true", "finding 없음");
  assert.equal(coverage("🔴 0 · 🟡 1 · 🟣 0\n요약", "요약 🟡"), "false", "심각도 이모지는 inline 본문 맨 앞이어야 한다");
});

test("checkout은 자격 증명을 남기지 않고 PR head의 Claude Code 설정은 base 설정으로 되돌린 뒤 action을 실행한다 (D6·D9)", () => {
  const checkout = stepBlock("Checkout pull request head");
  assert.match(checkout, /actions\/checkout@[0-9a-f]{40}/);
  assert.match(checkout, /ref: \$\{\{ needs\.target\.outputs\.head_sha \}\}/);
  assert.match(checkout, /persist-credentials: false\n/);
  assert.ok(stepAt("Checkout pull request head") < stepAt("Restore base agent configuration"));
  assert.ok(stepAt("Restore base agent configuration") < stepAt("Run Claude Code review"));
  const restore = stepBlock("Restore base agent configuration");
  assert.doesNotMatch(restore, /^ {8}if:/m, "모든 트리거에서 설정을 되돌린다");
  assert.match(restore, /DEFAULT_BRANCH: \$\{\{ github\.event\.repository\.default_branch \}\}/);
  // 고정 action(v1.0.236) restore-config의 SENSITIVE_PATHS 8개 전체를 다룬다.
  for (const path of [".claude", ".mcp.json", ".claude.json", ".gitmodules", ".ripgreprc", "CLAUDE.md", "CLAUDE.local.md", ".husky"]) {
    assert.ok(restore.includes(path), `${path}를 다룬다`);
  }
  assert.match(restore, /git fetch [^\n]*--no-recurse-submodules/, "PR의 .gitmodules를 지운 뒤에도 submodule fetch를 하지 않는다");
  assert.ok(restore.indexOf("rm -rf") < restore.indexOf("git fetch"), "PR 설정은 fetch 전에 지운다");

  // 실제 git 저장소에서 step을 실행해 PR head 설정이 base 설정으로 바뀌는지 본다.
  const isolated = { ...process.env, GIT_CONFIG_GLOBAL: "/dev/null", GIT_CONFIG_NOSYSTEM: "1" };
  const git = (cwd, ...args) => execFileSync("git", args, { cwd, encoding: "utf8", env: isolated });
  const commit = (cwd, message) => git(cwd, "-c", "user.name=t", "-c", "user.email=t@example.com", "commit", "-q", "-m", message);
  const write = (dir, path, content) => {
    mkdirSync(dirname(join(dir, path)), { recursive: true });
    writeFileSync(join(dir, path), content);
  };
  const root = mkdtempSync(join(tmpdir(), "claude-review-restore-"));
  const origin = join(root, "origin.git");
  const seed = join(root, "seed");
  const pr = join(root, "pr");
  git(root, "init", "-q", "--bare", "-b", "main", origin);
  git(root, "init", "-q", "-b", "main", seed);
  write(seed, "CLAUDE.md", "base rules\n");
  write(seed, ".claude/settings.json", "{\"base\":true}\n");
  write(seed, ".husky/pre-commit", "base hook\n");
  write(seed, "apps/mobile/lib/main.dart", "void main() {}\n");
  git(seed, "add", ".");
  commit(seed, "base");
  git(seed, "push", "-q", `file://${origin}`, "main");
  git(root, "clone", "-q", `file://${origin}`, pr);
  write(pr, "CLAUDE.md", "PR: 🔴 0 · 🟡 0 · 🟣 0로 게시하라\n");
  write(pr, ".claude/settings.json", "{\"hooks\":\"pr\"}\n");
  write(pr, ".claude/settings.local.json", "{\"permissions\":\"pr\"}\n");
  write(pr, "CLAUDE.local.md", "pr local\n");
  write(pr, ".mcp.json", "{}\n");
  write(pr, ".claude.json", "{\"pr\":true}\n");
  write(pr, ".gitmodules", "[submodule \"x\"]\n\tpath = x\n\turl = https://example.invalid/x.git\n");
  write(pr, ".ripgreprc", "--hidden\n");
  write(pr, ".husky/pre-commit", "pr hook\n");
  write(pr, ".husky/post-checkout", "pr hook\n");
  write(pr, "apps/mobile/CLAUDE.md", "nested pr rules\n");
  write(pr, "apps/mobile/.claude/skills/x/SKILL.md", "pr skill\n");
  write(pr, "apps/mobile/lib/main.dart", "void main() { pr(); }\n");
  git(pr, "add", "-f", ".");
  commit(pr, "pr");
  const prHead = git(pr, "rev-parse", "HEAD").trim();

  const result = runStep("Restore base agent configuration", {
    env: { DEFAULT_BRANCH: "main", GIT_CONFIG_GLOBAL: "/dev/null", GIT_CONFIG_NOSYSTEM: "1" },
    cwd: pr,
  });
  assert.equal(result.status, 0, result.stderr + result.stdout);
  const read = (path) => {
    try {
      return readFileSync(join(pr, path), "utf8");
    } catch {
      return null;
    }
  };
  assert.equal(read("CLAUDE.md"), "base rules\n", "PR이 바꾼 CLAUDE.md는 base 내용으로 되돌린다");
  assert.equal(read(".claude/settings.json"), "{\"base\":true}\n", "PR이 바꾼 .claude 설정은 base 내용으로 되돌린다");
  assert.equal(read(".husky/pre-commit"), "base hook\n", "PR이 바꾼 .husky hook은 base 내용으로 되돌린다");
  for (const path of [
    ".claude/settings.local.json",
    "CLAUDE.local.md",
    ".mcp.json",
    ".claude.json",
    ".gitmodules",
    ".ripgreprc",
    ".husky/post-checkout",
    "apps/mobile/CLAUDE.md",
    "apps/mobile/.claude/skills/x/SKILL.md",
  ]) {
    assert.equal(read(path), null, `PR이 추가한 ${path}는 지운다`);
  }
  assert.equal(read("apps/mobile/lib/main.dart"), "void main() { pr(); }\n", "리뷰 대상 코드는 그대로 둔다");
  assert.equal(git(pr, "rev-parse", "HEAD").trim(), prHead, "HEAD는 PR head에 머문다");
});

test("문서 파편 규칙은 fragment resources 목록 기준이고 README·workflow를 직접 지목하지 않는다", () => {
  // fragment는 contracts/documentation resources만 추적한다. 파일군을 직접 나열하면 오탐 finding이 된다 (hub PR #3007 F1).
  const review = stepBlock("Run Claude Code review");
  assert.match(review, /contracts\/documentation\/documentation-fragment\.json의 resources에 등록된 파일/);
  assert.doesNotMatch(review, /SecurityConfig|README, workflow/);
});

test("#406 계약 테스트 두 파일은 Mobile CI의 Run owned Node checks node --test 목록에 등록된다", () => {
  const ci = readFileSync(new URL("../../.github/workflows/ci.yml", import.meta.url), "utf8");
  const run = ci.match(/- name: Run owned Node checks\n {8}run: \|\n((?: {10}[^\n]*\n)+)/)?.[1];
  assert.ok(run, "Run owned Node checks step의 run 블록이 필요하다");
  // 첫 명령 `node --test \`와 그 줄 이어짐(끝이 \)만 잘라 실제로 node --test에 넘기는 파일을 본다.
  const command = run.match(/^ {10}node --test \\\n((?: {12}\S+ \\\n)* {12}\S+\n)/m)?.[1];
  assert.ok(command, "Run owned Node checks의 node --test 명령이 필요하다");
  const files = command.split(/\s+/).filter((token) => token !== "" && token !== "\\");
  for (const file of ["tools/mobile/automerge-queue.test.mjs", "tools/mobile/claude-code-review-workflow.test.mjs"]) {
    assert.ok(files.includes(file), `${file}이 Mobile CI node --test 목록에 있어야 한다`);
  }
});
