import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { existsSync, mkdtempSync, readFileSync, writeFileSync } from 'node:fs';
import { readFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';

const workflowUrl = new URL(
  '../../.github/workflows/automerge-queue.yml',
  import.meta.url,
);
const ciWorkflowUrl = new URL('../../.github/workflows/ci.yml', import.meta.url);

test('automerge coordinator fails closed around the native merge queue', async () => {
  const workflow = await readFile(workflowUrl, 'utf8');
  const ciWorkflow = await readFile(ciWorkflowUrl, 'utf8');

  for (const contract of [
    'pull_request_target:',
    'workflow_run:',
    'workflow_dispatch:',
    'schedule:',
    'permissions: {}',
    'actions: write',
    'checks: read',
    'statuses: read',
    'contents: write',
    'pull-requests: write',
    '/rules/branches/main',
    'required_status_checks',
    'integration_id',
    '/commits/${head}/statuses?per_page=100',
    '($statuses | flatten) as $status_records',
    '($trusted | map(select(.commit_id == $head))) as $current',
    'any($current[];',
    'author_association == "OWNER"',
    '. == "APPROVED"',
    'reduce .[] as $review',
    'del(.[$review.user.login])',
    '.submitted_at',
    'reviewThreads(first: 100)',
    'hasNextPage',
    'mergeStateStatus',
    '# merge-state-dispatch-begin',
    'CLEAN | HAS_HOOKS | UNSTABLE)',
    '# queue-loop-begin',
    '# candidate-window-begin',
    'window=20',
    '(GITHUB_RUN_NUMBER * window) % total',
    '[sort_by(.createdAt)[].number]',
    'gh pr merge --squash --auto',
    '--match-head-commit "${head}"',
    '--limit 1000',
    '/update-branch',
    'headRepository',
    '[[ "${head_repo}" != "${repo}" ]]',
    'gh workflow run ci.yml',
  ]) {
    assert.ok(workflow.includes(contract), `missing contract: ${contract}`);
  }

  assert.doesNotMatch(workflow, /--admin|gh pr merge.+--merge|gh pr merge.+--rebase/);
  assert.doesNotMatch(workflow, /LABELED_PR/);
  assert.ok(ciWorkflow.includes('  workflow_dispatch:'));

  // run은 YAML block scalar라 본문 줄이 블록 들여쓰기 아래로 내려가면 워크플로 전체가
  // 파싱되지 않는다. 이 테스트는 파일을 텍스트로 읽어 셸을 뽑으므로 그 파손을 그냥
  // 지나치고, CI에는 actionlint가 없다. 들여쓰기 불변식을 여기서 직접 고정한다.
  const runBlockAt = workflow.indexOf('        run: |\n');
  assert.ok(runBlockAt > 0, 'coordinate step run block must stay findable');
  for (const line of workflow.slice(runBlockAt).split('\n').slice(1)) {
    if (line.trim() === '') continue;
    assert.ok(
      line.startsWith('          '),
      `run block line escapes the YAML block scalar: ${line.slice(0, 48)}`,
    );
  }

  // classic commit status는 check-runs와 동일하게 전 페이지를 모아야 한다.
  const statusRequest = workflow.match(/statuses="\$\(gh api ([\s\S]*?)"\)"/)?.[1];
  assert.ok(statusRequest, 'classic status request must stay testable');
  for (const flag of ['--paginate', '--slurp', '/commits/${head}/statuses?per_page=100']) {
    assert.ok(statusRequest.includes(flag), `status request missing: ${flag}`);
  }

  const reviewProgram = workflow.match(
    /# review-state-filter-begin\n\s+if ! jq -e --arg head "\$\{head\}" '\n([\s\S]*?)\n\s+' <<<"\$\{reviews\}" >\/dev\/null; then/,
  )?.[1];
  assert.ok(reviewProgram, 'review state jq program must stay testable');

  const fallbackBody =
    '**Actionable comments posted: 0**\n<!-- Review source: Codex CLI fallback; canonical visible structure: PR #1926 Review 4676157515 -->';
  const review = (id, state, submittedAt, body = '', overrides = {}) => ({
    id,
    state,
    submitted_at: submittedAt,
    commit_id: 'head',
    author_association: 'OWNER',
    body,
    user: { login: 'reviewer' },
    ...overrides,
  });
  const runReviewFilter = (reviews) =>
    spawnSync('jq', ['-e', '--arg', 'head', 'head', reviewProgram], {
      input: JSON.stringify([reviews]),
    }).status;

  assert.equal(
    runReviewFilter([
      review(1, 'CHANGES_REQUESTED', '2026-08-01T00:00:00Z'),
      review(2, 'APPROVED', '2026-08-01T00:01:00Z'),
    ]),
    0,
  );
  assert.notEqual(
    runReviewFilter([
      review(1, 'CHANGES_REQUESTED', '2026-08-01T00:00:00Z'),
      review(2, 'COMMENTED', '2026-08-01T00:01:00Z'),
    ]),
    0,
  );
  assert.notEqual(
    runReviewFilter([review(1, 'COMMENTED', '2026-08-01T00:00:00Z')]),
    0,
  );
  assert.equal(
    runReviewFilter([
      review(1, 'COMMENTED', '2026-08-01T00:00:00Z', fallbackBody),
    ]),
    0,
  );
  assert.notEqual(
    runReviewFilter([
      review(1, 'COMMENTED', '2026-08-01T00:00:00Z', '', {
        author_association: 'NONE',
      }),
    ]),
    0,
  );

  // 이전 head에 남은 CHANGES_REQUESTED는 head가 바뀌어도 게이트에서 사라지지 않는다.
  assert.notEqual(
    runReviewFilter([
      review(1, 'CHANGES_REQUESTED', '2026-08-01T00:00:00Z', '', {
        commit_id: 'previous-head',
        user: { login: 'reviewer-one' },
      }),
      review(2, 'APPROVED', '2026-08-01T00:01:00Z', '', {
        user: { login: 'reviewer-two' },
      }),
    ]),
    0,
  );
  // 폴백 리뷰가 current head에 있어도 다른 리뷰어의 이전 head change request는 여전히 막는다.
  assert.notEqual(
    runReviewFilter([
      review(1, 'CHANGES_REQUESTED', '2026-08-01T00:00:00Z', '', {
        commit_id: 'previous-head',
        user: { login: 'reviewer-one' },
      }),
      review(2, 'COMMENTED', '2026-08-01T00:01:00Z', fallbackBody, {
        user: { login: 'reviewer-two' },
      }),
    ]),
    0,
  );
  // 같은 리뷰어가 current head에서 승인하면 이전 change request는 해소된다.
  assert.equal(
    runReviewFilter([
      review(1, 'CHANGES_REQUESTED', '2026-08-01T00:00:00Z', '', {
        commit_id: 'previous-head',
      }),
      review(2, 'APPROVED', '2026-08-01T00:01:00Z'),
    ]),
    0,
  );
  // 긍정 리뷰는 여전히 current head를 요구한다.
  assert.notEqual(
    runReviewFilter([
      review(1, 'APPROVED', '2026-08-01T00:00:00Z', '', {
        commit_id: 'previous-head',
      }),
    ]),
    0,
  );
  assert.notEqual(
    runReviewFilter([
      review(1, 'COMMENTED', '2026-08-01T00:00:00Z', fallbackBody, {
        commit_id: 'previous-head',
      }),
    ]),
    0,
  );

  // dismiss된 change request는 더 이상 활성이 아니므로 큐를 막지 않는다.
  assert.equal(
    runReviewFilter([
      review(1, 'DISMISSED', '2026-08-01T00:00:00Z', '', {
        commit_id: 'previous-head',
        user: { login: 'reviewer-one' },
      }),
      review(2, 'APPROVED', '2026-08-01T00:01:00Z', '', {
        user: { login: 'reviewer-two' },
      }),
    ]),
    0,
  );
  // dismiss_stale_reviews로 무효화된 이전 head 승인도 큐를 막지 않는다.
  // 같은 리뷰어가 승인을 남긴 뒤 그 승인이 dismiss된 순서를 그대로 고정한다.
  assert.equal(
    runReviewFilter([
      review(1, 'APPROVED', '2026-08-01T00:00:00Z', '', {
        commit_id: 'previous-head',
        user: { login: 'reviewer-one' },
      }),
      review(2, 'DISMISSED', '2026-08-01T00:01:00Z', '', {
        commit_id: 'previous-head',
        user: { login: 'reviewer-one' },
      }),
      review(3, 'APPROVED', '2026-08-01T00:02:00Z', '', {
        user: { login: 'reviewer-two' },
      }),
    ]),
    0,
  );
  // dismissed가 섞여 있어도 다른 리뷰어의 활성 change request는 그대로 막는다.
  assert.notEqual(
    runReviewFilter([
      review(1, 'DISMISSED', '2026-08-01T00:00:00Z', '', {
        commit_id: 'previous-head',
        user: { login: 'reviewer-one' },
      }),
      review(2, 'CHANGES_REQUESTED', '2026-08-01T00:01:00Z', '', {
        commit_id: 'previous-head',
        user: { login: 'reviewer-two' },
      }),
      review(3, 'APPROVED', '2026-08-01T00:02:00Z', '', {
        user: { login: 'reviewer-three' },
      }),
    ]),
    0,
  );
  // dismiss 이후 같은 리뷰어가 다시 남긴 change request는 정상 반영된다.
  assert.notEqual(
    runReviewFilter([
      review(1, 'DISMISSED', '2026-08-01T00:00:00Z', '', {
        commit_id: 'previous-head',
        user: { login: 'reviewer-one' },
      }),
      review(2, 'CHANGES_REQUESTED', '2026-08-01T00:01:00Z', '', {
        commit_id: 'previous-head',
        user: { login: 'reviewer-one' },
      }),
      review(3, 'APPROVED', '2026-08-01T00:02:00Z', '', {
        user: { login: 'reviewer-two' },
      }),
    ]),
    0,
  );
  // dismissed 리뷰만 남으면 활성 리뷰가 없으므로 fail-closed로 막는다.
  assert.notEqual(
    runReviewFilter([
      review(1, 'DISMISSED', '2026-08-01T00:00:00Z', '', {
        commit_id: 'previous-head',
      }),
    ]),
    0,
  );

  const checkProgram = workflow.match(
    /# required-context-filter-begin\n\s+if ! jq -e [^']+'\n([\s\S]*?)\n\s+' <<<"\$\{checks\}" >\/dev\/null; then/,
  )?.[1];
  assert.ok(checkProgram, 'required context jq program must stay testable');
  // statusPages는 `gh api --paginate --slurp` 결과와 같은 페이지 배열이다.
  const runCheckFilter = (
    checkRuns,
    statusPages = [],
    requiredCheck = { context: 'Required CI', integration_id: null },
  ) =>
    spawnSync(
      'jq',
      [
        '-e',
        '--argjson',
        'required_check',
        JSON.stringify(requiredCheck),
        '--argjson',
        'statuses',
        JSON.stringify(statusPages),
        checkProgram,
      ],
      { input: JSON.stringify([{ check_runs: checkRuns }]) },
    ).status;
  assert.notEqual(
    runCheckFilter([
      { id: 1, name: 'Required CI', conclusion: 'success', started_at: '2026-08-01T00:00:00Z' },
      { id: 2, name: 'Required CI', conclusion: 'failure', started_at: '2026-08-01T00:01:00Z' },
    ]),
    0,
  );
  assert.equal(
    runCheckFilter([
      { id: 1, name: 'Required CI', conclusion: 'failure', started_at: '2026-08-01T00:00:00Z' },
      { id: 2, name: 'Required CI', conclusion: 'success', started_at: '2026-08-01T00:01:00Z' },
    ]),
    0,
  );
  assert.notEqual(
    runCheckFilter(
      [],
      [[
        { id: 1, context: 'Required CI', state: 'success', updated_at: '2026-08-01T00:00:00Z' },
        { id: 2, context: 'Required CI', state: 'failure', updated_at: '2026-08-01T00:01:00Z' },
      ]],
    ),
    0,
  );
  assert.equal(
    runCheckFilter(
      [],
      [[
        { id: 1, context: 'Required CI', state: 'failure', updated_at: '2026-08-01T00:00:00Z' },
        { id: 2, context: 'Required CI', state: 'success', updated_at: '2026-08-01T00:01:00Z' },
      ]],
    ),
    0,
  );
  // required context가 두 번째 status 페이지에 있어도 찾아낸다.
  assert.equal(
    runCheckFilter(
      [],
      [
        [{ id: 1, context: 'Other CI', state: 'success', updated_at: '2026-08-01T00:00:00Z' }],
        [{ id: 2, context: 'Required CI', state: 'success', updated_at: '2026-08-01T00:01:00Z' }],
      ],
    ),
    0,
  );
  // 뒤 페이지의 최신 실패가 앞 페이지의 성공을 덮는다.
  assert.notEqual(
    runCheckFilter(
      [],
      [
        [{ id: 1, context: 'Required CI', state: 'success', updated_at: '2026-08-01T00:00:00Z' }],
        [{ id: 2, context: 'Required CI', state: 'failure', updated_at: '2026-08-01T00:01:00Z' }],
      ],
    ),
    0,
  );
  assert.notEqual(
    runCheckFilter(
      [{ id: 1, name: 'Required CI', conclusion: 'success', started_at: '2026-08-01T00:00:00Z', app: { id: 7 } }],
      [[{ id: 2, context: 'Required CI', state: 'success', updated_at: '2026-08-01T00:01:00Z' }]],
      { context: 'Required CI', integration_id: 42 },
    ),
    0,
  );
  assert.equal(
    runCheckFilter(
      [{ id: 1, name: 'Required CI', conclusion: 'success', started_at: '2026-08-01T00:00:00Z', app: { id: 42 } }],
      [],
      { context: 'Required CI', integration_id: 42 },
    ),
    0,
  );

  // 게이트는 후보별로 수행되고, 실패하면 그 후보만 건너뛴다. 순서 계약은 유지한다.
  assert.ok(workflow.includes('set -euo pipefail'));
  const queueLoopAt = workflow.indexOf('# queue-loop-begin');
  const reviewGateAt = workflow.indexOf('# review-state-filter-end');
  const contextGateAt = workflow.indexOf('# required-context-filter-end');
  const dispatchAt = workflow.indexOf('# merge-state-dispatch-begin');
  assert.ok(
    queueLoopAt > 0 &&
      reviewGateAt > queueLoopAt &&
      contextGateAt > reviewGateAt &&
      dispatchAt > contextGateAt,
    'gates must run per candidate, before the merge dispatch',
  );

  // 후보 목록은 오래된 순이어야 한다(best-effort FIFO).
  const orderProgram = workflow.match(/--jq '(\[sort_by\(\.createdAt\)\[\]\.number\])'/)?.[1];
  assert.ok(orderProgram, 'candidate ordering must stay testable');
  const ordered = spawnSync('jq', ['-c', orderProgram], {
    input: JSON.stringify([
      { number: 9, createdAt: '2026-08-01T02:00:00Z' },
      { number: 3, createdAt: '2026-08-01T00:00:00Z' },
      { number: 7, createdAt: '2026-08-01T01:00:00Z' },
    ]),
    encoding: 'utf8',
  });
  assert.equal(ordered.stdout.trim(), '[3,7,9]');

  const dispatchBlock = workflow.match(
    /# merge-state-dispatch-begin\n([\s\S]*?)\n\s+# merge-state-dispatch-end/,
  )?.[1];
  assert.ok(dispatchBlock, 'merge state dispatch must stay testable');
  // gh 호출을 기록만 하는 스텁으로 대체해 상태별 분기 결과를 실측한다. 분기는 큐 루프
  // 안에 있으므로 `continue`가 유효하도록 1회 루프로 감싸고, 루프를 빠져나오면
  // SKIPPED를 남겨 "이 후보를 건너뛰었다"를 관측한다.
  const runDispatch = (mergeState, { headRepo = 'o/r', newHead = 'updated-head' } = {}) => {
    const log = join(mkdtempSync(join(tmpdir(), 'automerge-queue-')), 'gh.log');
    const script = [
      'set -euo pipefail',
      `GH_LOG=${JSON.stringify(log)}`,
      ': > "$GH_LOG"',
      'gh() {',
      `  printf '%s\\n' "gh $*" >> "$GH_LOG"`,
      '  case "$*" in',
      `    *"pr view"*headRefOid*) printf '%s\\n' ${JSON.stringify(newHead)} ;;`,
      '  esac',
      '}',
      'sleep() { :; }',
      'pr=44',
      'repo=o/r',
      'head=old-head',
      `head_repo=${JSON.stringify(headRepo)}`,
      'head_ref=feature',
      `merge_state=${JSON.stringify(mergeState)}`,
      'for _ in 1; do',
      dispatchBlock.replace(/^ {12}/gm, ''),
      'done',
      `printf 'SKIPPED\\n' >> "$GH_LOG"`,
    ].join('\n');
    const result = spawnSync('bash', ['-c', script], { encoding: 'utf8' });
    const calls = existsSync(log) ? readFileSync(log, 'utf8') : '';
    return {
      status: result.status,
      merged: calls.includes('gh pr merge'),
      updatedBranch: calls.includes('update-branch'),
      dispatchedCi: calls.includes('workflow run ci.yml'),
      skipped: calls.includes('SKIPPED'),
    };
  };

  // 병합 가능 상태. UNSTABLE은 "필수가 아닌 check가 green이 아님"일 뿐이고 required
  // context는 위에서 ruleset 기준으로 이미 검증했으므로 병합을 진행한다.
  for (const mergeState of ['CLEAN', 'HAS_HOOKS', 'UNSTABLE']) {
    assert.deepEqual(
      runDispatch(mergeState),
      { status: 0, merged: true, updatedBranch: false, dispatchedCi: false, skipped: false },
      `${mergeState} must proceed to merge`,
    );
  }
  // base 갱신이 필요한 상태는 update-branch 경로로 간다.
  assert.deepEqual(runDispatch('BEHIND'), {
    status: 0,
    merged: false,
    updatedBranch: true,
    dispatchedCi: true,
    skipped: false,
  });
  // update-branch는 비동기라 bounded wait 안에 head가 안 바뀔 수 있다. stale ref로 CI를
  // 쏘지도 말고 실패하지도 말고 다음 트리거에서 재시도한다. 판정을 bash 버전에 맡기지
  // 않으려면 명시적 분기여야 한다 — bare `[[ ]]`는 bash 5에서 조용히 job을 죽이고
  // bash 3.2에서는 그냥 통과한다.
  assert.deepEqual(runDispatch('BEHIND', { newHead: 'old-head' }), {
    status: 0,
    merged: false,
    updatedBranch: true,
    dispatchedCi: false,
    skipped: false,
  });
  // 병합할 수 없는 상태는 전부 "이 후보만 건너뛴다"로 수렴한다. 실행을 실패시키지도,
  // 라벨을 건드리지도 않는다. 뒤의 후보는 계속 평가된다.
  for (const mergeState of ['DIRTY', 'BLOCKED', 'UNKNOWN', 'SOME_NEW_STATE']) {
    assert.deepEqual(
      runDispatch(mergeState),
      { status: 0, merged: false, updatedBranch: false, dispatchedCi: false, skipped: true },
      `${mergeState} must skip to the next candidate`,
    );
  }
  // fork head에 base 저장소 CI를 dispatch하지 않는다. 거부하되 큐는 계속 진행한다.
  assert.deepEqual(runDispatch('BEHIND', { headRepo: 'fork/r' }), {
    status: 0,
    merged: false,
    updatedBranch: false,
    dispatchedCi: false,
    skipped: true,
  });

  // 큐 루프 전체를 돌려 "막힌 후보가 뒤의 후보를 굶기지 않는다"를 직접 실측한다.
  const queueLoop = workflow.match(/# queue-loop-begin\n([\s\S]*?)\n\s+# queue-loop-end/)?.[1];
  assert.ok(queueLoop, 'queue loop must stay testable');
  const trustedReview = (head) => [
    [
      {
        id: 1,
        state: 'APPROVED',
        submitted_at: '2026-08-01T00:00:00Z',
        commit_id: head,
        author_association: 'OWNER',
        body: '',
        user: { login: 'reviewer' },
      },
    ],
  ];
  const runQueue = (prs, runNumber = 0) => {
    const dir = mkdtempSync(join(tmpdir(), 'automerge-queue-loop-'));
    const log = join(dir, 'gh.log');
    for (const pr of prs) {
      const head = `head${pr.number}`;
      writeFileSync(
        join(dir, `pr-${pr.number}.json`),
        JSON.stringify({
          state: pr.state ?? 'OPEN',
          isDraft: false,
          baseRefName: 'main',
          labels: [{ name: 'automerge' }],
          headRefName: `feature-${pr.number}`,
          headRefOid: head,
          headRepository: { nameWithOwner: 'o/r' },
          mergeStateStatus: pr.mergeStateStatus,
        }),
      );
      writeFileSync(
        join(dir, `reviews-${pr.number}.json`),
        JSON.stringify(pr.reviewed === false ? [[]] : trustedReview(head)),
      );
      writeFileSync(
        join(dir, `threads-${pr.number}.json`),
        JSON.stringify({
          data: {
            repository: {
              pullRequest: {
                reviewThreads: {
                  nodes: pr.unresolvedThread ? [{ isResolved: false }] : [],
                  pageInfo: { hasNextPage: false },
                },
              },
            },
          },
        }),
      );
      writeFileSync(
        join(dir, `checks-${head}.json`),
        JSON.stringify([
          {
            check_runs: [
              {
                id: 1,
                name: 'Required CI',
                conclusion: pr.checkFailed ? 'failure' : 'success',
                started_at: '2026-08-01T00:00:00Z',
              },
            ],
          },
        ]),
      );
      writeFileSync(join(dir, `statuses-${head}.json`), JSON.stringify([[]]));
    }
    const script = [
      'set -euo pipefail',
      `GH_LOG=${JSON.stringify(log)}`,
      `FIX=${JSON.stringify(dir)}`,
      `GITHUB_RUN_NUMBER=${JSON.stringify(String(runNumber))}`,
      ': > "$GH_LOG"',
      'gh() {',
      `  printf '%s\\n' "gh $*" >> "$GH_LOG"`,
      '  local all="$*"',
      '  case "$all" in',
      `    "pr list"*) printf '%s\\n' ${JSON.stringify(JSON.stringify(prs.map((p) => p.number)))} ;;`,
      '    "pr view "*) set -- $all; cat "$FIX/pr-$3.json" ;;',
      '    *pulls/*/reviews*) n="${all#*pulls/}"; n="${n%%/reviews*}"; cat "$FIX/reviews-$n.json" ;;',
      '    *graphql*) n="${all#*number=}"; n="${n%% *}"; cat "$FIX/threads-$n.json" ;;',
      '    *check-runs*) h="${all#*commits/}"; h="${h%%/check-runs*}"; cat "$FIX/checks-$h.json" ;;',
      '    *statuses*) h="${all#*commits/}"; h="${h%%/statuses*}"; cat "$FIX/statuses-$h.json" ;;',
      '  esac',
      '}',
      'sleep() { :; }',
      'repo=o/r',
      'owner=o',
      'name=r',
      `required='[{"context":"Required CI","integration_id":null}]'`,
      'candidates="$(gh pr list)"',
      queueLoop.replace(/^ {10}/gm, ''),
    ].join('\n');
    const result = spawnSync('bash', ['-c', script], { encoding: 'utf8' });
    const calls = existsSync(log) ? readFileSync(log, 'utf8') : '';
    const merged = calls.match(/gh pr merge [^\n]*?(\d+) --repo/)?.[1];
    return {
      status: result.status,
      mergedPr: merged ? Number(merged) : null,
      evaluated: [...calls.matchAll(/gh pr view (\d+) --repo/g)].map((m) => Number(m[1])),
      stdout: result.stdout,
    };
  };

  // 큐 head가 BLOCKED이어도 뒤의 병합 가능한 후보가 처리된다. 이것이 이 설계의 핵심이다.
  assert.equal(
    runQueue([
      { number: 1, mergeStateStatus: 'BLOCKED' },
      { number: 2, mergeStateStatus: 'CLEAN' },
    ]).mergedPr,
    2,
  );
  // 충돌한 후보도 뒤를 막지 않는다.
  assert.equal(
    runQueue([
      { number: 1, mergeStateStatus: 'DIRTY' },
      { number: 2, mergeStateStatus: 'CLEAN' },
    ]).mergedPr,
    2,
  );
  // 게이트는 후보별로 그대로 강제된다 — 리뷰 없는 후보는 건너뛰고 병합되지 않는다.
  const reviewGateQueue = runQueue([
    { number: 1, mergeStateStatus: 'CLEAN', reviewed: false },
    { number: 2, mergeStateStatus: 'CLEAN' },
  ]);
  assert.equal(reviewGateQueue.mergedPr, 2);
  // 미해결 thread가 있는 후보도 건너뛴다.
  assert.equal(
    runQueue([
      { number: 1, mergeStateStatus: 'CLEAN', unresolvedThread: true },
      { number: 2, mergeStateStatus: 'CLEAN' },
    ]).mergedPr,
    2,
  );
  // required check가 실패한 후보도 건너뛴다.
  assert.equal(
    runQueue([
      { number: 1, mergeStateStatus: 'CLEAN', checkFailed: true },
      { number: 2, mergeStateStatus: 'CLEAN' },
    ]).mergedPr,
    2,
  );
  // 게이트를 통과한 가장 오래된 후보가 우선한다(best-effort FIFO).
  assert.equal(
    runQueue([
      { number: 1, mergeStateStatus: 'CLEAN' },
      { number: 2, mergeStateStatus: 'CLEAN' },
    ]).mergedPr,
    1,
  );
  // 아무 후보도 병합할 수 없으면 병합 없이 성공으로 끝난다. 라벨은 건드리지 않는다.
  const allBlocked = runQueue([
    { number: 1, mergeStateStatus: 'BLOCKED' },
    { number: 2, mergeStateStatus: 'DIRTY' },
  ]);
  assert.equal(allBlocked.status, 0);
  assert.equal(allBlocked.mergedPr, null);

  // 후보 창(window)은 job timeout 때문에 필요하지만, 창을 큐 앞쪽에 고정하면 창 밖의
  // 후보가 매 실행 제외되어 굶는다. 창 선택 jq를 직접 돌려 세 가지를 고정한다.
  //   ① 한 실행에서 고르는 후보는 window를 넘지 않는다(timeout 상한 유지).
  //   ② 고른 후보는 항상 오래된 순이다(창이 회전해도 FIFO 우선순위 유지).
  //   ③ 연속 ceil(total/window)회 안에 모든 후보가 최소 한 번 평가된다(굶주림 없음).
  const windowSize = 20;
  const windowProgram = workflow.match(
    /# candidate-window-begin\n\s+done < <\(jq -r --argjson window "\$\{window\}" --argjson offset "\$\{offset\}" '\n([\s\S]*?)\n\s+' <<<"\$\{candidates\}"\)/,
  )?.[1];
  assert.ok(windowProgram, 'candidate window jq program must stay testable');
  const pickWindow = (total, offset) => {
    const stdout = spawnSync(
      'jq',
      [
        '-r',
        '--argjson',
        'window',
        String(windowSize),
        '--argjson',
        'offset',
        String(offset),
        windowProgram,
      ],
      {
        input: JSON.stringify(Array.from({ length: total }, (_, index) => index)),
        encoding: 'utf8',
      },
    ).stdout.trim();
    return stdout === '' ? [] : stdout.split('\n').map(Number);
  };
  // 워크플로의 offset 계산과 같은 식이다. 창 안에 다 들어오면 회전하지 않는다.
  const windowOffset = (total, runNumber) =>
    total > windowSize ? (runNumber * windowSize) % total : 0;
  assert.deepEqual(pickWindow(0, 0), []);
  for (const total of [1, 20, 21, 45, 100]) {
    const runs = Math.ceil(total / windowSize);
    for (let start = 0; start < 8; start += 1) {
      const seen = new Set();
      for (let runNumber = start; runNumber < start + runs; runNumber += 1) {
        const slice = pickWindow(total, windowOffset(total, runNumber));
        assert.ok(slice.length <= windowSize, `window exceeded at total=${total}`);
        assert.deepEqual(
          slice,
          [...slice].sort((a, b) => a - b),
          `candidate window must stay oldest-first at total=${total}`,
        );
        for (const index of slice) seen.add(index);
      }
      assert.equal(
        seen.size,
        total,
        `every candidate must be evaluated within ${runs} runs at total=${total}`,
      );
    }
  }

  // 창보다 큰 큐에서 뒤쪽 후보만 병합 가능한 경우를 큐 루프로 직접 실측한다.
  const oversizedQueue = [];
  for (let number = 1; number <= windowSize; number += 1) {
    oversizedQueue.push({ number, mergeStateStatus: 'BLOCKED' });
  }
  oversizedQueue.push({ number: windowSize + 1, mergeStateStatus: 'CLEAN' });
  // 창이 큐 앞쪽에 고정되면(회전 전 실행) 21번째는 평가조차 되지 않는다.
  const firstPass = runQueue(oversizedQueue, 0);
  assert.equal(firstPass.status, 0);
  assert.ok(!firstPass.evaluated.includes(windowSize + 1));
  // 다음 실행에서 창이 밀려 21번째가 평가되고 병합된다. 어느 실행 번호에서 시작하든
  // 연속 두 실행(= ceil(21/20)) 안에 반드시 병합된다.
  for (let start = 0; start < 4; start += 1) {
    const window2 = [
      runQueue(oversizedQueue, start),
      runQueue(oversizedQueue, start + 1),
    ];
    assert.ok(
      window2.some((run) => run.mergedPr === windowSize + 1),
      `a ready candidate past the window must merge within two runs (start=${start})`,
    );
    for (const run of window2) assert.equal(run.status, 0);
  }

  // 창이 회전해도 평가한 후보 중 가장 오래된 병합 가능 후보가 이긴다.
  const rotatedFifoQueue = oversizedQueue.map((candidate, index) =>
    index === 0 ? { ...candidate, mergeStateStatus: 'CLEAN' } : candidate,
  );
  assert.equal(runQueue(rotatedFifoQueue, 1).mergedPr, 1);

  // 후보가 창 안에 다 들어오면 실행 번호와 무관하게 회전하지 않는다.
  assert.equal(
    runQueue(
      [
        { number: 1, mergeStateStatus: 'CLEAN' },
        { number: 2, mergeStateStatus: 'CLEAN' },
      ],
      7,
    ).mergedPr,
    1,
  );
});
