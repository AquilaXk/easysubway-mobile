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
    '/commits/${head}/status',
    '$statuses.statuses',
    'commit_id == $head',
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

  const reviewProgram = workflow.match(
    /# review-state-filter-begin\n\s+jq -e --arg head "\$\{head\}" '\n([\s\S]*?)\n\s+' <<<"\$\{reviews\}" >\/dev\/null/,
  )?.[1];
  assert.ok(reviewProgram, 'review state jq program must stay testable');

  const review = (id, state, submittedAt, body = '') => ({
    id,
    state,
    submitted_at: submittedAt,
    commit_id: 'head',
    author_association: 'OWNER',
    body,
    user: { login: 'reviewer' },
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
      review(
        1,
        'COMMENTED',
        '2026-08-01T00:00:00Z',
        '**Actionable comments posted: 0**\n<!-- Review source: Codex CLI fallback; canonical visible structure: PR #1926 Review 4676157515 -->',
      ),
    ]),
    0,
  );
  assert.notEqual(
    runReviewFilter([
      {
        ...review(1, 'COMMENTED', '2026-08-01T00:00:00Z'),
        author_association: 'NONE',
      },
    ]),
    0,
  );

  const checkProgram = workflow.match(
    /# required-context-filter-begin\n\s+jq -e [^']+'\n([\s\S]*?)\n\s+' <<<"\$\{checks\}" >\/dev\/null/,
  )?.[1];
  assert.ok(checkProgram, 'required context jq program must stay testable');
  const runCheckFilter = (
    checkRuns,
    statuses = [],
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
        JSON.stringify({ statuses }),
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
      [
        { id: 1, context: 'Required CI', state: 'success', updated_at: '2026-08-01T00:00:00Z' },
        { id: 2, context: 'Required CI', state: 'failure', updated_at: '2026-08-01T00:01:00Z' },
      ],
    ),
    0,
  );
  assert.equal(
    runCheckFilter(
      [],
      [
        { id: 1, context: 'Required CI', state: 'failure', updated_at: '2026-08-01T00:00:00Z' },
        { id: 2, context: 'Required CI', state: 'success', updated_at: '2026-08-01T00:01:00Z' },
      ],
    ),
    0,
  );
  assert.notEqual(
    runCheckFilter(
      [{ id: 1, name: 'Required CI', conclusion: 'success', started_at: '2026-08-01T00:00:00Z', app: { id: 7 } }],
      [{ id: 2, context: 'Required CI', state: 'success', updated_at: '2026-08-01T00:01:00Z' }],
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
