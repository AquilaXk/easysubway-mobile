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
    '/commits/${head}/status',
    '$statuses.statuses',
    'commit_id == $head',
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

  const review = (id, state, submittedAt) => ({
    id,
    state,
    submitted_at: submittedAt,
    commit_id: 'head',
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
});
