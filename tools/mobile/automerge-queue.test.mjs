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
test('automerge coordinator fails closed around the native merge queue', async () => {
  const workflow = await readFile(workflowUrl, 'utf8');

  for (const contract of [
    'pull_request_target:',
    'types: [labeled]',
    'workflow_run:',
    'workflow_dispatch:',
    'schedule:',
    'permissions: {}',
    'checks: read',
    'statuses: read',
    'contents: write',
    'pull-requests: write',
    '/rules/branches/main',
    'required_status_checks',
    'integration_id',
    '/commits/${head}/statuses?per_page=100',
    '($statuses | flatten) as $status_records',
    'any(.[]; .sha == $head)',
    '# frozen-discovery-review-filter-begin',
    '# exact-head-marker-producer-begin',
    'data_page_limit=3',
    'overflow_probe_page=$((data_page_limit + 1))',
    'marker_pattern=',
    'test($marker_pattern)',
    'canonical_actions_marker',
    'bounded_pr_reviews()',
    'github-actions[bot]',
    '41898282',
    '$has_exact_marker',
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
    '# candidate-offset-begin',
    'window=20',
    'offset="$(( RANDOM % total ))"',
    '[sort_by(.createdAt)[].number]',
    'gh pr merge --squash --auto',
    '--match-head-commit "${head}"',
    'gh pr merge "${pr}" --repo "${repo}" --disable-auto',
    'fail_closed_pr()',
    'gh pr comment "${pr}"',
    'gh pr edit "${pr}" --repo "${repo}" --remove-label automerge',
    'Actions run: ${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}',
    '--limit 1000',
  ]) {
    assert.ok(workflow.includes(contract), `missing contract: ${contract}`);
  }

  assert.doesNotMatch(workflow, /--admin|gh pr merge.+--merge|gh pr merge.+--rebase/);
  assert.doesNotMatch(workflow, /actions: write/);
  assert.doesNotMatch(workflow, /update-branch|gh workflow run ci\.yml/);
  assert.doesNotMatch(workflow, /LABELED_PR/);

  const markerProducer = workflow.match(
    /# exact-head-marker-producer-begin\n([\s\S]*?)\n\s+# exact-head-marker-producer-end/,
  )?.[1];
  assert.ok(markerProducer, 'exact-head marker producer must stay testable');
  assert.match(markerProducer, /marker_pattern='\^<!-- Automerge frozen discovery authorization: \[0-9a-f\]\{40\} -->\$'/);
  assert.match(markerProducer, /marker_count.*-eq 0[\s\S]*?--method POST/);
  assert.match(markerProducer, /marker_count.*-eq 1[\s\S]*?--method PATCH/);
  assert.doesNotMatch(markerProducer, /\.body == \$marker/);
  // relabel 후 head가 바뀌어도 old canonical marker 하나는 PATCH 대상이고 POST가 아니다.
  const canonicalMarkerIds = markerProducer.match(
    /marker_ids="\$\(jq -cer --arg marker_pattern "\$\{marker_pattern\}" '\n([\s\S]*?)\n\s+' <<<"\$\{comments\}"\)"/,
  )?.[1];
  assert.ok(canonicalMarkerIds, 'canonical marker selector must stay testable');
  const oldMarker = '<!-- Automerge frozen discovery authorization: bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb -->';
  const canonicalTuple = (id, body) => ({
    id,
    body,
    user: { login: 'github-actions[bot]', id: 41898282, type: 'Bot' },
  });
  const markerIds = (comments) =>
    spawnSync('jq', ['-c', '--arg', 'marker_pattern', '^<!-- Automerge frozen discovery authorization: [0-9a-f]{40} -->$', canonicalMarkerIds], {
      input: JSON.stringify(comments),
      encoding: 'utf8',
    }).stdout.trim();
  assert.equal(markerIds([canonicalTuple(7, oldMarker)]), '[7]', 'relabel must PATCH the one old marker');
  assert.equal(markerIds([canonicalTuple(7, oldMarker), canonicalTuple(8, oldMarker)]), '[7,8]', 'multiple old/current canonical markers must mutate zero');

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
    /# frozen-discovery-review-filter-begin\n\s+if ! jq -e --arg head "\$\{head\}" --argjson commits "\$\{commits\}" --argjson comments "\$\{comments\}" '\n([\s\S]*?)\n\s+' <<<"\$\{reviews\}" >\/dev\/null; then/,
  )?.[1];
  assert.ok(reviewProgram, 'review state jq program must stay testable');

  const fallbackBody =
    '**Actionable comments posted: 0**\n<!-- Review source: Codex CLI fallback; canonical visible structure: PR #1926 Review 4676157515 -->';
  const head = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  const review = (id, state, submittedAt, body = '', overrides = {}) => ({
    id,
    state,
    submitted_at: submittedAt,
    commit_id: head,
    author_association: 'OWNER',
    body,
    user: { login: 'reviewer' },
    ...overrides,
  });
  const marker = `<!-- Automerge frozen discovery authorization: ${head} -->`;
  const actionMarker = (body = marker, overrides = {}) => ({
    body,
    user: { login: 'github-actions[bot]', id: 41898282, type: 'Bot' },
    ...overrides,
  });
  const runReviewFilter = (
    reviews,
    commits = [{ sha: head }, { sha: 'previous-head' }],
    comments = [actionMarker()],
  ) =>
    spawnSync('jq', ['-e', '--arg', 'head', head, '--argjson', 'commits', JSON.stringify(commits), '--argjson', 'comments', JSON.stringify(comments), reviewProgram], {
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

  // native APPROVED는 exact current head만으로 인정되며 marker가 필요 없다.
  assert.equal(
    runReviewFilter([review(1, 'APPROVED', '2026-08-01T00:00:00Z')], [{ sha: head }], []),
    0,
  );
  // frozen discovery는 commit set의 prior review와 exact current-head Actions marker를 함께 요구한다.
  assert.equal(
    runReviewFilter([
      review(1, 'COMMENTED', '2026-08-01T00:00:00Z', fallbackBody, { commit_id: 'previous-head' }),
    ]),
    0,
  );
  assert.notEqual(
    runReviewFilter([
      review(1, 'COMMENTED', '2026-08-01T00:00:00Z', fallbackBody, { commit_id: 'previous-head' }),
    ], [{ sha: head }]),
    0,
  );
  for (const comments of [
    [],
    [actionMarker(marker.replace(head, 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'))],
    [actionMarker(marker, { user: { login: 'github-actions[bot]', id: 1, type: 'Bot' } })],
    [actionMarker(), actionMarker()],
    [actionMarker(marker.replace(head, 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb')), actionMarker()],
  ]) {
    assert.notEqual(
      runReviewFilter([
        review(1, 'COMMENTED', '2026-08-01T00:00:00Z', fallbackBody, { commit_id: 'previous-head' }),
      ], [{ sha: head }, { sha: 'previous-head' }], comments),
      0,
    );
  }

  const codeRabbitReview = (id, state, submittedAt, overrides = {}) =>
    review(id, state, submittedAt, '', {
      author_association: 'NONE',
      user: { login: 'coderabbitai[bot]', id: 136622811, type: 'Bot' },
      ...overrides,
    });
  // CodeRabbit의 REST identity 전체가 일치하는 current-head COMMENTED만 예외다.
  assert.equal(
    runReviewFilter([codeRabbitReview(1, 'COMMENTED', '2026-08-01T00:00:00Z')]),
    0,
  );
  for (const overrides of [
    { user: { login: 'coderabbitai[bot]', id: 136622811, type: 'User' } },
    { user: { login: 'other[bot]', id: 136622811, type: 'Bot' } },
    { user: { login: 'coderabbitai[bot]', id: 1, type: 'Bot' } },
    { user: null },
  ]) {
    assert.notEqual(
      runReviewFilter([codeRabbitReview(1, 'COMMENTED', '2026-08-01T00:00:00Z', overrides)]),
      0,
    );
  }
  assert.equal(
    runReviewFilter([
      codeRabbitReview(1, 'COMMENTED', '2026-08-01T00:00:00Z', {
        commit_id: 'previous-head',
      }),
    ]),
    0,
  );
  assert.notEqual(
    runReviewFilter([
      review(1, 'APPROVED', '2026-08-01T00:00:00Z'),
      codeRabbitReview(2, 'CHANGES_REQUESTED', '2026-08-01T00:01:00Z'),
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
  // native APPROVED는 current head를 요구하고, canonical frozen fallback만 commit set+marker로 재사용한다.
  assert.notEqual(
    runReviewFilter([
      review(1, 'APPROVED', '2026-08-01T00:00:00Z', '', {
        commit_id: 'previous-head',
      }),
    ]),
    0,
  );
  assert.equal(
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
  const failureHandler = workflow.match(/          fail_closed_pr\(\) \{\n([\s\S]*?)\n          \}/)?.[1];
  assert.ok(failureHandler, 'failed merge operations must fail closed');
  // gh 호출을 기록만 하는 스텁으로 대체해 상태별 분기 결과를 실측한다. 분기는 큐 루프
  // 안에 있으므로 `continue`가 유효하도록 1회 루프로 감싸고, 루프를 빠져나오면
  // SKIPPED를 남겨 "이 후보를 건너뛰었다"를 관측한다.
  const runDispatch = (
    mergeState,
    {
      mergeStatus = 0,
      commentStatus = 0,
      disableStatus = 0,
      labelStatus = 0,
      disableFirstFails = false,
      labelFirstFails = false,
      autoMergeConverges = true,
      labelConverges = true,
      autoMergeQueryStatus = 0,
      labelQueryStatus = 0,
    } = {},
  ) => {
    const log = join(mkdtempSync(join(tmpdir(), 'automerge-queue-')), 'gh.log');
    const script = [
      'set -euo pipefail',
      `GH_LOG=${JSON.stringify(log)}`,
      ': > "$GH_LOG"',
      'gh() {',
      `  printf '%s\\n' "gh $*" >> "$GH_LOG"`,
      '  case "$*" in',
      `    *"--disable-auto"*) disable_calls=$(( disable_calls + 1 )); if [[ ${JSON.stringify(disableFirstFails)} == true && "$disable_calls" == 1 ]]; then return 41; fi; return ${disableStatus} ;;`,
      `    *"pr comment"*) return ${commentStatus} ;;`,
      `    *"pr edit"*) label_calls=$(( label_calls + 1 )); if [[ ${JSON.stringify(labelFirstFails)} == true && "$label_calls" == 1 ]]; then return 43; fi; return ${labelStatus} ;;`,
      `    *"pr view"*"autoMergeRequest"*) if [[ ${autoMergeQueryStatus} != 0 ]]; then return ${autoMergeQueryStatus}; fi; if [[ ${JSON.stringify(autoMergeConverges)} == true && "$disable_calls" -ge ${disableFirstFails ? 2 : 1} ]]; then printf '%s\\n' true; else printf '%s\\n' false; fi ;;`,
      `    *"pr view"*"labels"*) if [[ ${labelQueryStatus} != 0 ]]; then return ${labelQueryStatus}; fi; if [[ ${JSON.stringify(labelConverges)} == true && "$label_calls" -ge ${labelFirstFails ? 2 : 1} ]]; then printf '%s\\n' true; else printf '%s\\n' false; fi ;;`,
      `    *"pr merge"*) return ${mergeStatus} ;;`,
      '  esac',
      '}',
      'disable_calls=0',
      'label_calls=0',
      'pr=44',
      'repo=o/r',
      'head=old-head',
      'GITHUB_RUN_ID=123',
      'GITHUB_SERVER_URL=https://github.example',
      'GITHUB_REPOSITORY=o/r',
      `merge_state=${JSON.stringify(mergeState)}`,
      ['fail_closed_pr() {', failureHandler.replace(/^ {10}/gm, ''), '}'].join('\n'),
      'for _ in 1; do',
      dispatchBlock.replace(/^ {12}/gm, ''),
      'done',
      `printf 'SKIPPED\\n' >> "$GH_LOG"`,
    ].join('\n');
    const result = spawnSync('bash', ['-c', script], { encoding: 'utf8' });
    const calls = existsSync(log) ? readFileSync(log, 'utf8') : '';
    return {
      status: result.status,
      merged: calls.includes('gh pr merge --squash --auto'),
      updatedBranch: calls.includes('update-branch'),
      dispatchedCi: calls.includes('workflow run ci.yml'),
      skipped: calls.includes('SKIPPED'),
      commented: calls.includes('gh pr comment'),
      autoMergeDisabled: calls.includes('gh pr merge 44 --repo o/r --disable-auto'),
      labelRemoved: calls.includes('gh pr edit 44 --repo o/r --remove-label automerge'),
      disableCalls: [...calls.matchAll(/--disable-auto/g)].length,
      labelCalls: [...calls.matchAll(/--remove-label automerge/g)].length,
      autoMergeQueries: [...calls.matchAll(/--json autoMergeRequest/g)].length,
      labelQueries: [...calls.matchAll(/--json labels/g)].length,
      output: result.stdout,
      calls,
    };
  };
  const withoutCalls = ({ calls, disableCalls, labelCalls, autoMergeQueries, labelQueries, output, ...result }) => result;

  // 병합 가능 상태. UNSTABLE은 "필수가 아닌 check가 green이 아님"일 뿐이고 required
  // context는 위에서 ruleset 기준으로 이미 검증했으므로 병합을 진행한다.
  for (const mergeState of ['CLEAN', 'HAS_HOOKS', 'UNSTABLE']) {
    assert.deepEqual(
      withoutCalls(runDispatch(mergeState)),
      { status: 0, merged: true, updatedBranch: false, dispatchedCi: false, skipped: false, commented: false, autoMergeDisabled: false, labelRemoved: false },
      `${mergeState} must proceed to merge`,
    );
  }
  // base 갱신은 PR 소유 worktree가 담당한다. coordinator는 경고 후 다음 후보를 평가한다.
  const behind = runDispatch('BEHIND');
  assert.deepEqual(withoutCalls(behind), {
    status: 0,
    merged: false,
    updatedBranch: false,
    dispatchedCi: false,
    skipped: true,
    commented: false,
    autoMergeDisabled: false,
    labelRemoved: false,
  });
  assert.match(behind.output, /owning SSD worktree must rebase and push/);
  // 병합할 수 없는 상태는 전부 "이 후보만 건너뛴다"로 수렴한다. 실행을 실패시키지도,
  // 라벨을 건드리지도 않는다. 뒤의 후보는 계속 평가된다.
  for (const mergeState of ['DIRTY', 'BLOCKED', 'UNKNOWN', 'SOME_NEW_STATE']) {
    assert.deepEqual(
      withoutCalls(runDispatch(mergeState)),
      { status: 0, merged: false, updatedBranch: false, dispatchedCi: false, skipped: true, commented: false, autoMergeDisabled: false, labelRemoved: false },
      `${mergeState} must skip to the next candidate`,
    );
  }
  for (const [mergeState, options, expected, status] of [
    ['CLEAN', { mergeStatus: 17 }, { merged: true, updatedBranch: false, autoMergeDisabled: true }, 17],
    ['CLEAN', { mergeStatus: 17, commentStatus: 31 }, { merged: true, updatedBranch: false, autoMergeDisabled: true }, 17],
    ['CLEAN', { mergeStatus: 17, disableStatus: 33 }, { merged: true, updatedBranch: false, autoMergeDisabled: true }, 17],
    ['CLEAN', { mergeStatus: 17, labelStatus: 37 }, { merged: true, updatedBranch: false, autoMergeDisabled: true }, 17],
    ['CLEAN', { mergeStatus: 17, commentStatus: 31, disableStatus: 33, labelStatus: 37 }, { merged: true, updatedBranch: false, autoMergeDisabled: true }, 17],
  ]) {
    const result = runDispatch(mergeState, options);
    assert.equal(result.status, status, 'original operation status must win');
    assert.deepEqual(
      { merged: result.merged, updatedBranch: result.updatedBranch, dispatchedCi: result.dispatchedCi, skipped: result.skipped, commented: result.commented, autoMergeDisabled: result.autoMergeDisabled, labelRemoved: result.labelRemoved },
      { ...expected, dispatchedCi: false, skipped: false, commented: true, labelRemoved: true },
    );
    assert.match(result.calls, new RegExp(`operation=merge reservation; merge_state=${mergeState}; status=${status}; Actions run: https://github\\.example/o/r/actions/runs/123`));
    const disableAt = result.calls.indexOf('gh pr merge 44 --repo o/r --disable-auto');
    const labelAt = result.calls.indexOf('gh pr edit 44 --repo o/r --remove-label automerge');
    const commentAt = result.calls.indexOf('gh pr comment 44 --repo o/r --body');
    assert.ok(disableAt < labelAt && labelAt < commentAt, 'cleanup must disable auto-merge, remove the label, then comment');
    assert.ok(result.disableCalls <= 2 && result.labelCalls <= 2, 'cleanup attempts must stay bounded at two');
  }

  const convergedOnSecondAttempt = runDispatch('CLEAN', {
    mergeStatus: 17,
    disableFirstFails: true,
    labelFirstFails: true,
  });
  assert.equal(convergedOnSecondAttempt.status, 17, 'cleanup retries must not replace the merge status');
  assert.deepEqual(
    { disableCalls: convergedOnSecondAttempt.disableCalls, autoMergeQueries: convergedOnSecondAttempt.autoMergeQueries, labelCalls: convergedOnSecondAttempt.labelCalls, labelQueries: convergedOnSecondAttempt.labelQueries },
    { disableCalls: 2, autoMergeQueries: 2, labelCalls: 2, labelQueries: 2 },
  );

  const notConverged = runDispatch('CLEAN', {
    mergeStatus: 17,
    autoMergeConverges: false,
    labelConverges: false,
  });
  assert.equal(notConverged.status, 17, 'unconverged cleanup must preserve the merge status');
  assert.deepEqual(
    { disableCalls: notConverged.disableCalls, labelCalls: notConverged.labelCalls },
    { disableCalls: 2, labelCalls: 2 },
  );
  assert.match(notConverged.output, /cleanup did not converge/);

  const queryFailed = runDispatch('CLEAN', {
    mergeStatus: 17,
    autoMergeQueryStatus: 51,
    labelQueryStatus: 53,
  });
  assert.equal(queryFailed.status, 17, 'cleanup query failures must preserve the merge status');
  assert.deepEqual(
    { disableCalls: queryFailed.disableCalls, labelCalls: queryFailed.labelCalls },
    { disableCalls: 2, labelCalls: 2 },
  );
  assert.match(queryFailed.output, /failed to confirm/);

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
  // runNumber는 실행 컨텍스트 주입값이다. 큐 루프 결과가 이 값에 좌우되지 않아야 한다.
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
        JSON.stringify(pr.reviewed === false ? [] : trustedReview(head)[0]),
      );
      writeFileSync(join(dir, `commits-${pr.number}.json`), JSON.stringify([{ sha: head }]));
      writeFileSync(join(dir, `comments-${pr.number}.json`), JSON.stringify([]));
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
      '    *pulls/*/commits*) n="${all#*pulls/}"; n="${n%%/commits*}"; cat "$FIX/commits-$n.json" ;;',
      '    *issues/*/comments*) n="${all#*issues/}"; n="${n%%/comments*}"; cat "$FIX/comments-$n.json" ;;',
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
      'bounded_pr_reviews() { gh api "repos/${repo}/pulls/${pr}/reviews?per_page=100&page=1"; }',
      'bounded_pr_commits() { gh api "repos/${repo}/pulls/${pr}/commits?per_page=100&page=1"; }',
      'bounded_issue_comments() { gh api "repos/${repo}/issues/${pr}/comments?per_page=100&page=1"; }',
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
  // 후보가 매 실행 제외되어 굶는다. 굶주림 제거는 두 성질의 곱으로 고정한다.
  //   ① 도달 가능성(결정적): 어떤 시작점에서든 선택 수는 window 이하이고 오래된 순이며,
  //      시작점 전체를 훑으면 모든 후보가 창에 들어온다.
  //   ② 시작점 분포(구조적): 시작점이 실행 컨텍스트를 읽지 않고 실행마다 새로 뽑히므로
  //      모든 시작점의 확률이 0보다 크고, 그 값이 실행 간격에 좌우되지 않는다.
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
  assert.deepEqual(pickWindow(0, 0), []);
  // 도달 가능성은 결정적으로 고정한다. 시작점이 어떤 값이든 선택 수는 window 이하이고
  // 오래된 순이며, 시작점 전체를 훑으면 모든 후보가 최소 한 번은 창에 들어온다.
  for (const total of [21, 40]) {
    const reachable = new Set();
    for (let offset = 0; offset < total; offset += 1) {
      const slice = pickWindow(total, offset);
      assert.ok(slice.length <= windowSize, `window exceeded at total=${total}`);
      assert.deepEqual(
        slice,
        [...slice].sort((a, b) => a - b),
        `candidate window must stay oldest-first at total=${total}`,
      );
      for (const index of slice) reachable.add(index);
    }
    assert.equal(
      reachable.size,
      total,
      `every candidate must be reachable from some offset at total=${total}`,
    );
  }

  // 시작점 산출. 커버리지 보장이 실행 간격에 의존하지 않으려면 시작점이 실행 컨텍스트
  // 값의 함수가 아니어야 한다. run number 기반 결정적 회전은 실제 coordinator 실행 사이의
  // 간격 d(라벨 이벤트 스킵·concurrency 폐기 때문에 1이 아니다)가 유효 보폭에 곱해져,
  // gcd(유효 보폭, total) > window인 조합에서 시작점이 고정된다. 실행 컨텍스트를 아예
  // 읽지 않는다는 것을 구조 계약으로 먼저 고정한다.
  const offsetBlock = workflow.match(
    /# candidate-offset-begin\n([\s\S]*?)\n\s+# candidate-offset-end/,
  )?.[1];
  assert.ok(offsetBlock, 'candidate offset block must stay testable');
  assert.doesNotMatch(
    offsetBlock,
    /GITHUB_RUN_NUMBER|GITHUB_RUN_ID|GITHUB_RUN_ATTEMPT|GITHUB_SHA/,
    'candidate offset must not depend on run context',
  );
  const drawOffset = (total, runNumber) => {
    const script = [
      'set -euo pipefail',
      `GITHUB_RUN_NUMBER=${JSON.stringify(String(runNumber))}`,
      `candidates=${JSON.stringify(
        JSON.stringify(Array.from({ length: total }, (_, index) => index)),
      )}`,
      offsetBlock.replace(/^ {10}/gm, ''),
      `printf '%s %s\\n' "$window" "$offset"`,
    ].join('\n');
    const result = spawnSync('bash', ['-c', script], { encoding: 'utf8' });
    assert.equal(result.status, 0, `offset block failed: ${result.stderr}`);
    const [drawnWindow, offset] = result.stdout.trim().split(' ').map(Number);
    assert.equal(drawnWindow, windowSize, 'window constant must stay in sync with the test');
    return offset;
  };
  // 창 안에 다 들어오면 회전하지 않는다. 빈 큐에서도 죽지 않는다.
  for (const total of [0, 1, 20]) {
    for (let attempt = 0; attempt < 4; attempt += 1) {
      assert.equal(drawOffset(total, attempt), 0, `must not rotate at total=${total}`);
    }
  }
  // total > window면 시작점이 실행마다 새로 뽑히고 범위 안에 있다. run number를 고정해
  // 두는 것은 최악의 앨리어싱 입력(간격 0)이며, 그래도 성질이 유지되어야 한다.
  const rotationTotal = 2 * windowSize;
  const drawn = [];
  for (let attempt = 0; attempt < 48; attempt += 1) {
    drawn.push(drawOffset(rotationTotal, 7));
  }
  for (const offset of drawn) {
    assert.ok(
      Number.isInteger(offset) && offset >= 0 && offset < rotationTotal,
      `offset out of range: ${offset}`,
    );
  }
  assert.ok(
    new Set(drawn).size > 1,
    'candidate offset must vary across executions even with a fixed run number',
  );
  // 뽑힌 시작점들의 창 합집합이 전 후보를 덮는다. 후보 하나가 한 실행에서 제외될 확률은
  // 1 - window/total = 1/2이므로 48회에서 누락 확률은 total * 2^-48 수준이다.
  const covered = new Set();
  for (const offset of drawn) {
    for (const index of pickWindow(rotationTotal, offset)) covered.add(index);
  }
  assert.equal(covered.size, rotationTotal, 'drawn offsets must cover the whole queue');

  // 리뷰가 지목한 정확한 시나리오를 큐 루프로 실측한다. total = 2 * window이고 실행 번호
  // 간격이 2로 일정한 시퀀스 — 결정적 회전에서는 시작점이 0에 고정돼 뒤쪽 절반이 영원히
  // 평가되지 않았다. 병합 가능한 후보는 큐 맨 뒤 1건뿐이다.
  // 하네스 비용을 줄이려고 미끼 후보는 첫 게이트(열린 라벨 PR 검사)에서 걸리게 둔다.
  // 스킵 사유별 계약은 위 시나리오들에서 이미 고정했고, 여기서 보는 것은 창 도달성이다.
  const aliasingQueue = [];
  for (let number = 1; number < rotationTotal; number += 1) {
    aliasingQueue.push({ number, mergeStateStatus: 'CLEAN', state: 'CLOSED' });
  }
  aliasingQueue.push({ number: rotationTotal, mergeStateStatus: 'CLEAN' });
  let lateMergeRun = null;
  const attempts = 24;
  for (let attempt = 0; attempt < attempts && lateMergeRun === null; attempt += 1) {
    // 간격 2의 비연속 run number. 시작점이 이 값을 읽지 않으므로 결과에 영향이 없다.
    const run = runQueue(aliasingQueue, 100 + attempt * 2);
    assert.equal(run.status, 0);
    if (run.mergedPr === rotationTotal) lateMergeRun = attempt;
  }
  assert.notEqual(
    lateMergeRun,
    null,
    `the only mergeable candidate sits past the window and must still merge within ${attempts} runs`,
  );

  // 후보가 창 안에 다 들어오면 실행 번호와 무관하게 오래된 후보가 먼저 병합된다.
  for (const runNumber of [0, 7, 40]) {
    assert.equal(
      runQueue(
        [
          { number: 1, mergeStateStatus: 'CLEAN' },
          { number: 2, mergeStateStatus: 'CLEAN' },
        ],
        runNumber,
      ).mergedPr,
      1,
    );
  }
});
