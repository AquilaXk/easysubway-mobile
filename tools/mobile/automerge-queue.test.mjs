import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { readFile } from 'node:fs/promises';
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
    '.submitted_at',
    'reviewThreads(first: 100)',
    'hasNextPage',
    'mergeStateStatus',
    'gh pr merge --squash --auto',
    '--match-head-commit "${head}"',
    '--limit 1000',
    '/update-branch',
    'headRepository',
    '[[ "${head_repo}" == "${repo}" ]]',
    'gh workflow run ci.yml',
  ]) {
    assert.ok(workflow.includes(contract), `missing contract: ${contract}`);
  }

  assert.doesNotMatch(workflow, /--admin|gh pr merge.+--merge|gh pr merge.+--rebase/);
  assert.doesNotMatch(workflow, /LABELED_PR/);
  assert.ok(ciWorkflow.includes('  workflow_dispatch:'));

  // classic commit status는 check-runs와 동일하게 전 페이지를 모아야 한다.
  const statusRequest = workflow.match(/statuses="\$\(gh api ([\s\S]*?)"\)"/)?.[1];
  assert.ok(statusRequest, 'classic status request must stay testable');
  for (const flag of ['--paginate', '--slurp', '/commits/${head}/statuses?per_page=100']) {
    assert.ok(statusRequest.includes(flag), `status request missing: ${flag}`);
  }

  const reviewProgram = workflow.match(
    /# review-state-filter-begin\n\s+jq -e --arg head "\$\{head\}" '\n([\s\S]*?)\n\s+' <<<"\$\{reviews\}" >\/dev\/null/,
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

  const checkProgram = workflow.match(
    /# required-context-filter-begin\n\s+jq -e [^']+'\n([\s\S]*?)\n\s+' <<<"\$\{checks\}" >\/dev\/null/,
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
});
