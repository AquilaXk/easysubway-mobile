import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { existsSync, mkdtempSync, readFileSync, writeFileSync } from 'node:fs';
import { readFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';
import {
  canonicalPatchDigest,
  verifyAutomergeReviewClosure,
} from './verify-automerge-review-closure.mjs';

const workflowUrl = new URL(
  '../../.github/workflows/automerge-queue.yml',
  import.meta.url,
);

// review gate jq 식 추출·실행 헬퍼. 기존 review-state-filter 테스트와 #406 claude[bot] 테스트가 함께 쓴다 (D7).
const reviewGateProgram = (workflow) => {
  const program = workflow.match(
    /# frozen-discovery-review-filter-begin\n\s+if ! jq -e --arg head "\$\{head\}" --argjson commits "\$\{commits\}" --argjson comments "\$\{comments\}" --argjson verified_claude_commits "\$\{verified_claude_commits\}" '\n([\s\S]*?)\n\s+' <<<"\$\{reviews\}" >\/dev\/null; then/,
  )?.[1];
  assert.ok(program, 'review state jq program must stay testable');
  return program;
};
// jq -e 결과를 그대로 돌려준다: status 0=인정, 1=거부, 그 밖은 jq 오류.
const runReviewGateProgram = (program, reviews, { head, commits, comments, verifiedClaudeCommits = [] }) =>
  spawnSync(
    'jq',
    [
      '-e',
      '--arg', 'head', head,
      '--argjson', 'commits', JSON.stringify(commits),
      '--argjson', 'comments', JSON.stringify(comments),
      '--argjson', 'verified_claude_commits', JSON.stringify(verifiedClaudeCommits),
      program,
    ],
    { input: JSON.stringify([reviews]), encoding: 'utf8' },
  );
// 게이트의 claude[bot] Review 검증 함수(verified_claude_review_commits) 본문.
const claudeVerificationHelper = (workflow) => {
  const helper = workflow.match(
    /\n {10}# claude-review-verification-begin\n([\s\S]*?)\n {10}# claude-review-verification-end\n/,
  )?.[1];
  assert.ok(helper, 'claude[bot] review verification helper must stay executable');
  return helper.replace(/^ {10}/gm, '');
};
// run·compare 응답 fixture. 배열이면 API 응답 모양으로 감싸고, { raw }면 그 값을 그대로 응답한다.
const claudeRunsResponse = (value) =>
  Array.isArray(value) ? { total_count: value.length, workflow_runs: value } : value.raw;
const claudeCompareResponse = (value) => (Array.isArray(value) ? { files: value } : value.raw);
// verified_claude_review_commits를 게이트와 같은 `if !` + 명령 치환 문맥(set -e가 꺼지는 곳)에서 실행한다.
// fixture가 없는 commit의 run·compare 조회는 gh 실패다.
const runClaudeVerification = (workflow, { reviews, commits, base, runsByCommit = {}, compareFilesByCommit = {} }) => {
  const dir = mkdtempSync(join(tmpdir(), 'automerge-claude-verify-'));
  const log = join(dir, 'gh.log');
  writeFileSync(log, '');
  writeFileSync(join(dir, 'reviews.json'), JSON.stringify(reviews));
  writeFileSync(join(dir, 'commits.json'), JSON.stringify(commits));
  for (const [sha, value] of Object.entries(runsByCommit)) {
    writeFileSync(join(dir, `runs-${sha}.json`), JSON.stringify(claudeRunsResponse(value)));
  }
  for (const [sha, value] of Object.entries(compareFilesByCommit)) {
    writeFileSync(join(dir, `compare-${sha}.json`), JSON.stringify(claudeCompareResponse(value)));
  }
  const script = [
    'set -euo pipefail',
    `FIX=${JSON.stringify(dir)}`,
    `GH_LOG=${JSON.stringify(log)}`,
    'gh() {',
    '  printf "%s\\n" "gh $*" >> "$GH_LOG"',
    '  local all="$*" sha',
    '  case "$all" in',
    '    *"actions/workflows/claude-code-review.yml/runs?head_sha="*) sha="${all#*head_sha=}"; sha="${sha%%&*}"; [[ -f "$FIX/runs-$sha.json" ]] || return 1; cat "$FIX/runs-$sha.json" ;;',
    '    *"/compare/"*) sha="${all#*...}"; sha="${sha%%\\?*}"; [[ -f "$FIX/compare-$sha.json" ]] || return 1; cat "$FIX/compare-$sha.json" ;;',
    '    *) return 99 ;;',
    '  esac',
    '}',
    'repo=o/r',
    'pr=91',
    `base=${JSON.stringify(base)}`,
    'reviews="$(cat "$FIX/reviews.json")"',
    'commits="$(cat "$FIX/commits.json")"',
    claudeVerificationHelper(workflow),
    'if ! verified_claude_commits="$(verified_claude_review_commits)"; then',
    '  echo SKIPPED',
    '  exit 3',
    'fi',
    'printf "%s\\n" "${verified_claude_commits}"',
  ].join('\n');
  const result = spawnSync('bash', ['-c', script], { encoding: 'utf8' });
  const calls = readFileSync(log, 'utf8').split('\n').filter(Boolean);
  return {
    status: result.status,
    stderr: result.stderr,
    verified: result.status === 0 ? JSON.parse(result.stdout) : null,
    runCalls: calls.filter((call) => call.includes('/runs?')).length,
    compareCalls: calls.filter((call) => call.includes('/compare/')).length,
  };
};

test('automerge coordinator fails closed around the native merge queue', async () => {
  const workflow = await readFile(workflowUrl, 'utf8');

  for (const contract of [
    'pull_request_target:',
    'types: [labeled]',
    'workflow_run:',
    'workflow_dispatch:',
    'pull_request_review:',
    'permissions: {}',
    'actions: read',
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
    '# claude-review-verification-begin',
    'verified_claude_review_commits() {',
    'if ! verified_claude_commits="$(verified_claude_review_commits)"; then',
    '--json baseRefName,baseRefOid,headRefOid',
    'base="$(jq -r \'.baseRefOid\' <<<"${info}")"',
    'repos/${repo}/actions/workflows/claude-code-review.yml/runs?head_sha=${sha}&status=success&per_page=20',
    'repos/${repo}/compare/${base}...${sha}?per_page=1',
    '# exact-head-marker-producer-begin',
    'data_page_limit=3',
    'overflow_probe_page=$((data_page_limit + 1))',
    'marker_pattern=',
    'test($marker_pattern)',
    'canonical_actions_marker',
    '/collaborators/${sender}/permission',
    'admin" or . == "maintain" or . == "write"',
    'if ! reviews="$(bounded_pr_reviews)"; then',
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
  assert.match(markerProducer, /sender=.*\.sender\.login/);
  assert.match(markerProducer, /permission=.*collaborators\/\$\{sender\}\/permission/);
  const commentReader = workflow.match(/          bounded_issue_comments\(\) \{\n([\s\S]*?)\n          \}/)?.[1];
  assert.ok(commentReader, 'bounded comment reader must stay executable');
  const runProducer = (comments) => {
    const dir = mkdtempSync(join(tmpdir(), 'automerge-producer-'));
    const event = join(dir, 'event.json');
    const log = join(dir, 'gh.log');
    writeFileSync(event, JSON.stringify({
      pull_request: { number: 91, head: { sha: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' } },
      sender: { login: 'writer' },
    }));
    const script = [
      'set -euo pipefail',
      `GH_LOG=${JSON.stringify(log)}`,
      `EVENT_COMMENTS=${JSON.stringify(JSON.stringify(comments))}`,
      ': > "$GH_LOG"',
      'gh() {',
      '  printf "%s\\n" "gh $*" >> "$GH_LOG"',
      '  case "$*" in',
      '    *collaborators/*/permission*) printf "%s\\n" \'{"permission":"write"}\' ;;',
      '    *issues/*/comments?*) printf "%s\\n" "$EVENT_COMMENTS" ;;',
      '  esac',
      '}',
      'repo=o/r',
      'data_page_limit=3',
      'page_size=100',
      'overflow_probe_page=$((data_page_limit + 1))',
      `GITHUB_EVENT_PATH=${JSON.stringify(event)}`,
      'GITHUB_EVENT_NAME=pull_request_target',
      ['bounded_issue_comments() {', commentReader.replace(/^ {12}/gm, ''), '}'].join('\n'),
      markerProducer.replace(/^ {10}/gm, ''),
    ].join('\n');
    const result = spawnSync('bash', ['-c', script], { encoding: 'utf8' });
    return { status: result.status, calls: readFileSync(log, 'utf8') };
  };
  const duplicateProducer = runProducer([canonicalTuple(7, oldMarker), canonicalTuple(8, oldMarker)]);
  assert.equal(duplicateProducer.status, 1, 'multiple canonical markers must fail the producer');
  assert.doesNotMatch(duplicateProducer.calls, /--method (POST|PATCH)/, 'multiple canonical markers must not mutate');
  const commitReader = workflow.match(/          bounded_pr_commits\(\) \{\n([\s\S]*?)\n          \}/)?.[1];
  assert.ok(commitReader, 'bounded commit reader must stay executable');
  const runCommitReader = (pages) => {
    const dir = mkdtempSync(join(tmpdir(), 'automerge-commits-'));
    pages.forEach((page, index) => writeFileSync(join(dir, `${index + 1}.json`), JSON.stringify(page)));
    const script = [
      'set -euo pipefail',
      `FIX=${JSON.stringify(dir)}`,
      'gh() { case "$*" in *page=1) cat "$FIX/1.json" ;; *page=2) cat "$FIX/2.json" ;; *page=3) cat "$FIX/3.json" ;; *page=4) cat "$FIX/4.json" ;; esac; }',
      'repo=o/r', 'pr=91', 'data_page_limit=3', 'page_size=100', 'overflow_probe_page=4',
      ['bounded_pr_commits() {', commitReader.replace(/^ {12}/gm, ''), '}'].join('\n'),
      'bounded_pr_commits >/dev/null',
    ].join('\n');
    return spawnSync('bash', ['-c', script], { encoding: 'utf8' }).status;
  };
  const validCommit = { sha: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' };
  const fullPage = Array.from({ length: 100 }, () => validCommit);
  assert.equal(runCommitReader([fullPage, fullPage, fullPage, []]), 0, '300 commits plus an empty overflow probe must pass');
  assert.notEqual(runCommitReader([fullPage, fullPage, fullPage, [validCommit]]), 0, 'nonempty overflow probe must fail closed');
  assert.notEqual(runCommitReader([[{ sha: 'bad' }]]), 0, 'malformed commit sha must fail closed');

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

  const reviewProgram = reviewGateProgram(workflow);

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
  ) => runReviewGateProgram(reviewProgram, reviews, { head, commits, comments }).status;

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
  assert.equal(
    runReviewFilter([
      review(1, 'COMMENTED', '2026-08-01T00:00:00Z', '**Actionable comments posted: 0**\n<!-- Review source: Aquila fallback; canonical visible structure: PR #1926 Review 4676157515 -->'),
    ]),
    0,
    'Aquila fallback review must satisfy frozen discovery filter',
  );
  assert.equal(
    runReviewFilter([
      review(1, 'COMMENTED', '2026-08-01T00:00:00Z', '**Actionable comments posted: 0**\n<!-- Review source: Aquila Universal Review; engine: aquila-review -->'),
    ]),
    0,
    'Aquila Universal Review must satisfy frozen discovery filter',
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
      const head = pr.head ?? `head${pr.number}`;
      writeFileSync(
        join(dir, `pr-${pr.number}.json`),
        JSON.stringify({
          state: pr.state ?? 'OPEN',
          isDraft: false,
          baseRefName: 'main',
          baseRefOid: 'f'.repeat(40),
          labels: [{ name: 'automerge' }],
          headRefName: `feature-${pr.number}`,
          headRefOid: head,
          headRepository: { nameWithOwner: 'o/r' },
          mergeStateStatus: pr.mergeStateStatus,
        }),
      );
      writeFileSync(
        join(dir, `reviews-${pr.number}.json`),
        JSON.stringify(pr.reviews ?? (pr.reviewed === false ? [] : trustedReview(head)[0])),
      );
      writeFileSync(join(dir, `commits-${pr.number}.json`), JSON.stringify((pr.commits ?? [head]).map((sha) => ({ sha }))));
      writeFileSync(join(dir, `comments-${pr.number}.json`), JSON.stringify(pr.comments ?? []));
      for (const [sha, value] of Object.entries(pr.claudeRuns ?? {})) {
        writeFileSync(join(dir, `claude-runs-${sha}.json`), JSON.stringify(claudeRunsResponse(value)));
      }
      for (const [sha, value] of Object.entries(pr.claudeCompare ?? {})) {
        writeFileSync(join(dir, `claude-compare-${sha}.json`), JSON.stringify(claudeCompareResponse(value)));
      }
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
      '    *"actions/workflows/claude-code-review.yml/runs?head_sha="*) h="${all#*head_sha=}"; h="${h%%&*}"; [[ -f "$FIX/claude-runs-$h.json" ]] || return 1; cat "$FIX/claude-runs-$h.json" ;;',
      '    *"/compare/"*) h="${all#*...}"; h="${h%%\\?*}"; [[ -f "$FIX/claude-compare-$h.json" ]] || return 1; cat "$FIX/claude-compare-$h.json" ;;',
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
      claudeVerificationHelper(workflow),
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
  // #406 D1: 큐 루프는 claude[bot] Review 검증 결과를 게이트에 넘기고, 검증 조회 실패 후보는 건너뛴다.
  const claudeQueuePr = (number, overrides = {}) => {
    const claudeHead = String(number).repeat(40);
    return {
      number,
      head: claudeHead,
      mergeStateStatus: 'CLEAN',
      reviews: [
        {
          id: 1,
          state: 'COMMENTED',
          submitted_at: '2026-08-01T00:00:00Z',
          commit_id: claudeHead,
          author_association: 'NONE',
          body: '🔴 0 · 🟡 0 · 🟣 0\n변경 범위를 검토했고 finding이 없습니다.',
          user: { login: 'claude[bot]', id: 209825114, type: 'Bot' },
        },
      ],
      comments: [
        {
          id: 1,
          body: `<!-- Automerge frozen discovery authorization: ${claudeHead} -->`,
          user: { login: 'github-actions[bot]', id: 41898282, type: 'Bot' },
        },
      ],
      claudeRuns: { [claudeHead]: [{ id: 1, head_sha: claudeHead, conclusion: 'success' }] },
      claudeCompare: { [claudeHead]: [{ filename: 'apps/mobile/lib/main.dart' }] },
      ...overrides,
    };
  };
  assert.equal(runQueue([claudeQueuePr(1)]).mergedPr, 1, '검증된 current-head claude[bot] Review와 exact marker가 있으면 병합한다');
  const failedClaudeRun = runQueue([
    claudeQueuePr(1, { claudeRuns: { ['1'.repeat(40)]: [{ id: 1, head_sha: '1'.repeat(40), conclusion: 'failure' }] } }),
    claudeQueuePr(2),
  ]);
  assert.equal(failedClaudeRun.mergedPr, 2, '리뷰 commit의 claude-code-review.yml run이 success가 아니면 건너뛴다');
  assert.match(failedClaudeRun.stdout, /PR #1: no trusted review on the current head/);
  assert.equal(
    runQueue([
      claudeQueuePr(1, { claudeCompare: { ['1'.repeat(40)]: [{ filename: '.github/workflows/claude-code-review.yml' }] } }),
      claudeQueuePr(2),
    ]).mergedPr,
    2,
    '리뷰 commit 시점 PR diff가 claude-code-review.yml을 바꿨으면 건너뛴다',
  );
  const unreadableClaudeRun = runQueue([claudeQueuePr(1, { claudeRuns: {} }), claudeQueuePr(2)]);
  assert.equal(unreadableClaudeRun.mergedPr, 2, 'run 조회 실패 후보는 건너뛴다');
  assert.match(unreadableClaudeRun.stdout, /PR #1: claude\[bot\] review verification read failed; skipping\./);

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

// #406: Claude Code 공식 /code-review(claude-code-review.yml)가 게시하는 claude[bot] Review를
// CodeRabbit과 같은 frozen discovery 자리에서 인정하는 계약. workflow의 검증 함수와 jq 식을 그대로 실행한다.
// D1: claude[bot] COMMENTED Review는 (a) 본문 첫 줄 개수 줄, (b) 리뷰 commit에서 claude-code-review.yml run success,
// (c) 리뷰 commit 시점 PR diff(compare base...commit)에 그 workflow 변경 없음을 모두 만족할 때만 discovery다.
const CLAUDE_BOT = { login: 'claude[bot]', id: 209825114, type: 'Bot' };
const CLAUDE_WORKFLOW = '.github/workflows/claude-code-review.yml';
const claudeGateHead = 'c'.repeat(40);
const claudeGatePreviousHead = 'd'.repeat(40);
const claudeGateBase = 'f'.repeat(40);
const claudeGateHeadMarker = {
  body: `<!-- Automerge frozen discovery authorization: ${claudeGateHead} -->`,
  user: { login: 'github-actions[bot]', id: 41898282, type: 'Bot' },
};
const claudeGateAt = (id) => `2026-09-29T00:00:${String(id).padStart(2, '0')}Z`;
const claudeReview = (id, overrides = {}) => ({
  id,
  state: 'COMMENTED',
  submitted_at: claudeGateAt(id),
  commit_id: claudeGatePreviousHead,
  author_association: 'NONE',
  body: '🔴 0 · 🟡 0 · 🟣 0\n변경 범위를 검토했고 finding이 없습니다.',
  user: CLAUDE_BOT,
  ...overrides,
});
const memberReview = (id, state, overrides = {}) => ({
  id,
  state,
  submitted_at: claudeGateAt(id),
  commit_id: claudeGateHead,
  author_association: 'MEMBER',
  body: '',
  user: { login: 'reviewer', id: 2, type: 'User' },
  ...overrides,
});
const claudeRun = (sha, conclusion = 'success') => ({ id: 7, head_sha: sha, conclusion });
// 기본 fixture: 두 PR commit 모두 claude-code-review.yml run success, 리뷰 commit 시점 PR diff에 workflow 변경 없음.
const claudeGateFixture = (overrides = {}) => ({
  commits: [{ sha: claudeGatePreviousHead }, { sha: claudeGateHead }],
  comments: [claudeGateHeadMarker],
  base: claudeGateBase,
  runsByCommit: {
    [claudeGatePreviousHead]: [claudeRun(claudeGatePreviousHead)],
    [claudeGateHead]: [claudeRun(claudeGateHead)],
  },
  compareFilesByCommit: {
    [claudeGatePreviousHead]: [{ filename: 'apps/mobile/lib/route.dart' }],
    [claudeGateHead]: [{ filename: 'apps/mobile/lib/route.dart' }],
  },
  ...overrides,
});
const withoutKey = (object, key) => Object.fromEntries(Object.entries(object).filter(([entry]) => entry !== key));
// 큐 루프 한 후보의 review 판정: 검증 함수(조회 실패 = 후보 skip) → review gate jq.
const loadFrozenDiscoveryGate = () => {
  const workflow = readFileSync(workflowUrl, 'utf8');
  const program = reviewGateProgram(workflow);
  return (reviews, overrides = {}) => {
    const fixture = claudeGateFixture(overrides);
    const verification = runClaudeVerification(workflow, { reviews, ...fixture });
    if (verification.status === 3) return 'rejected';
    assert.equal(verification.status, 0, `claude review verification failed: ${verification.stderr}`);
    const result = runReviewGateProgram(program, reviews, {
      head: claudeGateHead,
      commits: fixture.commits,
      comments: fixture.comments,
      verifiedClaudeCommits: verification.verified,
    });
    // jq -e: 0=true(인정), 1=false(거부). 그 밖의 종료 코드는 jq 오류라 "거부"로 세지 않는다.
    if (result.status === 0) return 'accepted';
    if (result.status === 1) return 'rejected';
    throw new Error(`review gate jq failed with status ${result.status}: ${result.stderr}`);
  };
};

test('frozen discovery gate는 검증된 고정 신원 claude[bot] COMMENTED Review를 CodeRabbit 자리에서 인정한다 (#406)', () => {
  const gate = loadFrozenDiscoveryGate();
  assert.equal(gate([claudeReview(1)]), 'accepted', 'PR commit set의 이전 head Review + exact current-head marker');
  assert.equal(
    gate([claudeReview(1, { commit_id: claudeGateHead })]),
    'accepted',
    'current head Review + exact current-head marker',
  );
  assert.equal(
    gate([claudeReview(1), memberReview(2, 'COMMENTED')]),
    'accepted',
    '후속 신뢰된 사람의 빈 COMMENTED가 claude[bot] discovery를 지우지 않는다',
  );
});

test('frozen discovery gate는 claude[bot] 이름만 같거나 신원이 어긋난 Review를 거부한다 (#406)', () => {
  const gate = loadFrozenDiscoveryGate();
  for (const [overrides, reason] of [
    [{ user: { ...CLAUDE_BOT, id: 999 } }, 'login만 같고 user.id가 다르면 거부한다'],
    [{ user: { ...CLAUDE_BOT, type: 'User' } }, 'user.type이 Bot이 아니면 거부한다'],
    [{ user: { login: 'claude', id: 209825114, type: 'Bot' } }, 'id가 같아도 login이 다르면 거부한다'],
    [{ user: { login: 'claude-bot[bot]', id: 55, type: 'Bot' } }, '유사한 봇 login은 거부한다'],
    [{ user: null }, 'user가 없으면 거부한다'],
    [{ author_association: 'CONTRIBUTOR' }, 'author_association이 NONE이 아니면 거부한다'],
    [
      { author_association: 'COLLABORATOR', user: { login: 'claude', id: 77, type: 'User' } },
      '신뢰된 사람이 claude를 흉내 낸 마커 없는 COMMENTED는 discovery가 아니다',
    ],
  ]) {
    assert.equal(gate([claudeReview(1, overrides)]), 'rejected', reason);
  }
});

test('frozen discovery gate는 claude[bot] Review에도 PR commit set과 exact current-head marker를 요구한다 (#406)', () => {
  const gate = loadFrozenDiscoveryGate();
  assert.equal(
    gate([claudeReview(1, { commit_id: 'e'.repeat(40) })]),
    'rejected',
    'PR commit set에 없는 commit의 Review는 거부한다',
  );
  assert.equal(gate([claudeReview(1)], { comments: [] }), 'rejected', 'exact-head marker가 없으면 거부한다');
  assert.equal(
    gate([claudeReview(1)], {
      comments: [{ ...claudeGateHeadMarker, body: claudeGateHeadMarker.body.replace(claudeGateHead, 'b'.repeat(40)) }],
    }),
    'rejected',
    '다른 head를 가리키는 marker는 거부한다',
  );
  assert.equal(
    gate([claudeReview(1)], { commits: [{ sha: claudeGatePreviousHead }] }),
    'rejected',
    'current head가 PR commit set에 없으면 거부한다',
  );
});

test('frozen discovery gate는 claude[bot]을 COMMENTED로만 인정하고 active change request는 막는다 (#406)', () => {
  const gate = loadFrozenDiscoveryGate();
  assert.equal(
    gate([claudeReview(1, { state: 'APPROVED', commit_id: claudeGateHead })], { comments: [] }),
    'rejected',
    'claude[bot] APPROVED는 current head여도 native 승인 경로로 인정하지 않는다',
  );
  assert.equal(
    gate([claudeReview(1, { state: 'APPROVED' })]),
    'rejected',
    'claude[bot] APPROVED는 marker가 있어도 frozen discovery가 아니다',
  );
  assert.equal(
    gate([memberReview(1, 'APPROVED'), claudeReview(2, { state: 'CHANGES_REQUESTED' })]),
    'rejected',
    'claude[bot]의 active change request는 신뢰된 사람 승인이 있어도 병합을 막는다',
  );
  assert.equal(
    gate([claudeReview(1), claudeReview(2, { state: 'CHANGES_REQUESTED' })]),
    'rejected',
    'claude[bot] 자신의 이후 change request가 discovery를 무효화한다',
  );
  assert.equal(
    gate([claudeReview(1), memberReview(2, 'CHANGES_REQUESTED')]),
    'rejected',
    'claude[bot] discovery 뒤 신뢰된 사람의 change request는 병합을 막는다',
  );
});

test('frozen discovery gate는 본문 첫 줄 개수 줄이 없는 claude[bot] Review를 discovery로 보지 않는다 (#406 D1 a)', () => {
  const gate = loadFrozenDiscoveryGate();
  for (const [body, reason] of [
    ['', '빈 본문(inline 답글 wrapper) claude[bot] Review만 있다'],
    [null, '본문 없음'],
    ['요약만 있고 개수 줄 없음', '개수 줄 없음'],
    ['요약\n🔴 0 · 🟡 0 · 🟣 0', '개수 줄이 첫 줄이 아니다'],
    ['🔴 0 · 🟡 0 · 🟣 0\r\n요약', '개수 줄 뒤에 CR이 붙었다'],
    ['🔴 0 · 🟡 0\n요약', '🟣 개수가 빠졌다'],
  ]) {
    assert.equal(gate([claudeReview(1, { body })]), 'rejected', reason);
    assert.equal(gate([claudeReview(1, { body, commit_id: claudeGateHead })]), 'rejected', `${reason} (current head)`);
  }
  assert.equal(gate([claudeReview(1, { body: '🔴 0 · 🟡 0 · 🟣 0' })]), 'accepted', '개수 줄만 있는 본문');
  assert.equal(
    gate([claudeReview(1, { body: '' }), claudeReview(2, { commit_id: claudeGateHead })]),
    'accepted',
    '빈 본문 wrapper가 섞여도 개수 줄 Review로 인정한다',
  );
});

test('frozen discovery gate는 리뷰 commit의 claude-code-review.yml run이 success가 아니면 거부한다 (#406 D1 b)', () => {
  const gate = loadFrozenDiscoveryGate();
  const base = claudeGateFixture();
  for (const [runs, reason] of [
    [[claudeRun(claudeGatePreviousHead, 'failure')], '검증 step 실패로 run이 failure만 있다'],
    [[claudeRun(claudeGatePreviousHead, 'cancelled')], 'run이 cancelled만 있다'],
    [[], '리뷰 commit의 run이 없다'],
    [[claudeRun(claudeGateHead)], 'success run의 head_sha가 리뷰 commit이 아니다'],
  ]) {
    assert.equal(
      gate([claudeReview(1)], { runsByCommit: { ...base.runsByCommit, [claudeGatePreviousHead]: runs } }),
      'rejected',
      reason,
    );
  }
  assert.equal(
    gate([claudeReview(1)], { runsByCommit: withoutKey(base.runsByCommit, claudeGatePreviousHead) }),
    'rejected',
    'run 조회 실패는 후보 skip이다',
  );
  assert.equal(
    gate([claudeReview(1)], { runsByCommit: { ...base.runsByCommit, [claudeGatePreviousHead]: { raw: { message: 'Not Found' } } } }),
    'rejected',
    'run 응답 형식 오류는 후보 skip이다',
  );
  assert.equal(
    gate([claudeReview(1), claudeReview(2, { commit_id: claudeGateHead })], {
      runsByCommit: { ...base.runsByCommit, [claudeGatePreviousHead]: [claudeRun(claudeGatePreviousHead, 'failure')] },
    }),
    'accepted',
    '검증 실패한 이전 Review가 있어도 검증된 current-head Review가 있으면 인정한다',
  );
});

test('frozen discovery gate는 리뷰 commit 시점 PR diff가 claude-code-review.yml을 바꿨으면 거부한다 (#406 D1 c)', () => {
  const gate = loadFrozenDiscoveryGate();
  const base = claudeGateFixture();
  const touchedEverywhere = {
    [claudeGatePreviousHead]: [{ filename: CLAUDE_WORKFLOW }],
    [claudeGateHead]: [{ filename: 'apps/mobile/lib/route.dart' }, { filename: CLAUDE_WORKFLOW }],
  };
  assert.equal(
    gate([claudeReview(1, { commit_id: claudeGateHead })], { compareFilesByCommit: touchedEverywhere }),
    'rejected',
    'PR이 workflow 파일을 바꿨다',
  );
  assert.equal(
    gate([claudeReview(1)], {
      compareFilesByCommit: {
        ...base.compareFilesByCommit,
        [claudeGatePreviousHead]: [{ filename: '.github/workflows/renamed.yml', previous_filename: CLAUDE_WORKFLOW }],
      },
    }),
    'rejected',
    'PR이 workflow 파일 이름을 바꿨다',
  );
  // 중간 commit에서 workflow를 바꿔 리뷰를 받고 다음 commit에서 되돌려도, 리뷰 commit 시점 diff로 판정한다.
  const touched = { ...base.compareFilesByCommit, [claudeGatePreviousHead]: [{ filename: CLAUDE_WORKFLOW }] };
  assert.equal(
    gate([claudeReview(1)], { compareFilesByCommit: touched }),
    'rejected',
    '중간 commit에서 바꿨다가 되돌린 PR의 그 commit Review는 거부한다',
  );
  assert.equal(
    gate([claudeReview(1, { commit_id: claudeGateHead })], { compareFilesByCommit: touched }),
    'accepted',
    '되돌린 뒤 commit에서 base workflow로 받은 Review는 인정한다',
  );
  const truncated = Array.from({ length: 300 }, (_, index) => ({ filename: `apps/mobile/lib/f${index}.dart` }));
  for (const [compare, reason] of [
    [truncated, 'compare files가 300개 상한에 닿아 끝까지 볼 수 없다'],
    [{ raw: { message: 'diff too large' } }, 'compare 응답에 files가 없다'],
  ]) {
    assert.equal(
      gate([claudeReview(1)], { compareFilesByCommit: { ...base.compareFilesByCommit, [claudeGatePreviousHead]: compare } }),
      'rejected',
      reason,
    );
  }
  assert.equal(
    gate([claudeReview(1)], { compareFilesByCommit: withoutKey(base.compareFilesByCommit, claudeGatePreviousHead) }),
    'rejected',
    'compare 조회 실패는 후보 skip이다',
  );
  assert.equal(gate([claudeReview(1)], { base: 'null' }), 'rejected', 'PR base SHA를 모르면 판정하지 않는다');
});

test('claude[bot] Review 검증 조회는 claude[bot] 후보가 있을 때만 서로 다른 리뷰 commit마다 run·compare 1회씩이다 (#406 D1)', () => {
  const workflow = readFileSync(workflowUrl, 'utf8');
  const verify = (reviews, overrides = {}) => runClaudeVerification(workflow, { reviews, ...claudeGateFixture(overrides) });
  for (const [reviews, reason] of [
    [[memberReview(1, 'APPROVED')], 'claude[bot] Review가 없다'],
    [[claudeReview(1, { body: '' })], '개수 줄 없는 claude[bot] Review뿐이다'],
    [[claudeReview(1, { commit_id: 'e'.repeat(40) })], 'PR commit 밖 Review뿐이다'],
    [[claudeReview(1, { state: 'CHANGES_REQUESTED' })], 'COMMENTED가 아니다'],
  ]) {
    const result = verify(reviews);
    assert.deepEqual(
      { status: result.status, verified: result.verified, runCalls: result.runCalls, compareCalls: result.compareCalls },
      { status: 0, verified: [], runCalls: 0, compareCalls: 0 },
      reason,
    );
  }
  const twoCommits = verify([claudeReview(1), claudeReview(2), claudeReview(3, { commit_id: claudeGateHead })]);
  assert.deepEqual(
    { status: twoCommits.status, verified: twoCommits.verified, runCalls: twoCommits.runCalls, compareCalls: twoCommits.compareCalls },
    { status: 0, verified: [claudeGateHead, claudeGatePreviousHead], runCalls: 2, compareCalls: 2 },
  );
  const failedRun = verify([claudeReview(1)], {
    runsByCommit: { [claudeGatePreviousHead]: [claudeRun(claudeGatePreviousHead, 'failure')] },
  });
  assert.deepEqual({ runCalls: failedRun.runCalls, compareCalls: failedRun.compareCalls }, { runCalls: 1, compareCalls: 0 }, 'run success가 없으면 compare를 조회하지 않는다');
});

test('claude[bot] 검증은 기존 CodeRabbit·Aquila·Codex·사람 판정을 바꾸지 않는다 (#406)', () => {
  const gate = loadFrozenDiscoveryGate();
  const noClaudeData = { runsByCommit: {}, compareFilesByCommit: {} };
  const codeRabbit = claudeReview(1, { body: '', user: { login: 'coderabbitai[bot]', id: 136622811, type: 'Bot' } });
  assert.equal(gate([codeRabbit], noClaudeData), 'accepted', 'CodeRabbit COMMENTED는 개수 줄·run 없이 그대로 인정한다');
  assert.equal(gate([memberReview(1, 'APPROVED')], { ...noClaudeData, comments: [] }), 'accepted', '사람 current-head APPROVED');
  assert.equal(gate([memberReview(1, 'CHANGES_REQUESTED'), codeRabbit]), 'rejected', '사람 change request는 계속 막는다');
  const aquila = memberReview(1, 'COMMENTED', {
    commit_id: claudeGatePreviousHead,
    body: '**Actionable comments posted: 0**\n<!-- Review source: Aquila Universal Review; engine: aquila-review -->',
  });
  assert.equal(gate([aquila], noClaudeData), 'accepted', 'Aquila Universal Review');
  // 검증 조회 실패는 후보 전체 skip이다(fail-closed). 사람 승인이 있어도 병합하지 않는다.
  assert.equal(
    gate([memberReview(1, 'APPROVED'), claudeReview(2)], { ...noClaudeData, comments: [] }),
    'rejected',
    'claude[bot] 후보의 run을 조회할 수 없으면 사람 승인 후보도 이번 실행에서 건너뛴다',
  );
});

test('verifyAutomergeReviewClosure enforces 1-discovery Review contract (Mobile #277)', () => {
  const currentHead = '1'.repeat(40);
  const previousHead = '2'.repeat(40);
  const rebasedCommitSha = '3'.repeat(40);

  const trustedHumanReview = (id, state, commitId, body = '', overrides = {}) => ({
    id,
    state,
    commit_id: commitId,
    author_association: 'OWNER',
    submitted_at: '2026-08-01T00:00:00Z',
    body,
    user: { login: 'owner', id: 1, type: 'User' },
    ...overrides,
  });

  const canonicalCodexBody = (findings = 0) =>
    `**Actionable comments posted: ${findings}**\n<!-- Review source: Codex CLI fallback; canonical visible structure: PR #1926 Review 4676157515 -->`;

  const canonicalMarker = (headSha = currentHead) => ({
    body: `<!-- Automerge frozen discovery authorization: ${headSha} -->`,
    user: { login: 'github-actions[bot]', id: 41898282, type: 'Bot' },
  });

  const validPatch = 'diff --git a/apps/mobile/lib/route.dart b/apps/mobile/lib/route.dart\n+void main() {}\n';

  // 1. current-head trusted APPROVED 통과
  assert.equal(
    verifyAutomergeReviewClosure({
      head: currentHead,
      reviews: [trustedHumanReview(1, 'APPROVED', currentHead)],
      comments: [],
    }).ok,
    true,
  );

  // 2. rebase-equivalent reviewed prefix + inline finding path 수정 + selected test 수정 + exact marker 통과
  const rebasePrefixPatch = 'diff --git a/apps/mobile/lib/route.dart b/apps/mobile/lib/route.dart\n+void oldRoute() {}\n';
  const closureFindingPatch = 'diff --git a/apps/mobile/lib/route.dart b/apps/mobile/lib/route.dart\n+void fixedRoute() {}\n';
  const closureTestPatch = 'diff --git a/apps/mobile/test/route_test.dart b/apps/mobile/test/route_test.dart\n+test();\n';

  assert.equal(
    verifyAutomergeReviewClosure({
      head: currentHead,
      reviews: [trustedHumanReview(1, 'COMMENTED', previousHead, canonicalCodexBody(1))],
      comments: [canonicalMarker(currentHead)],
      reviewThreads: {
        pageInfo: { hasNextPage: false },
        nodes: [{ isResolved: true, path: 'apps/mobile/lib/route.dart' }],
      },
      reviewedCommits: [{ sha: previousHead, patch: rebasePrefixPatch }],
      currentCommits: [
        { sha: rebasedCommitSha, patch: rebasePrefixPatch },
        { sha: currentHead, patch: closureFindingPatch },
      ],
      closureFiles: [
        { filename: 'apps/mobile/lib/route.dart', status: 'modified' },
        { filename: 'apps/mobile/test/route_test.dart', status: 'modified' },
      ],
      selectedTestPaths: ['apps/mobile/test/route_test.dart'],
    }).ok,
    true,
  );

  // 3. previous-head live APPROVED의 rebase-only 통과
  assert.equal(
    verifyAutomergeReviewClosure({
      head: currentHead,
      reviews: [trustedHumanReview(1, 'APPROVED', previousHead)],
      comments: [canonicalMarker(currentHead)],
      reviewedCommits: [{ sha: previousHead, patch: validPatch }],
      currentCommits: [{ sha: currentHead, patch: validPatch }],
      closureFiles: [],
    }).ok,
    true,
  );

  // 4. unrelated Review, patch tamper/누락/재정렬/squash 차단
  // 누락 (squash되어 commit 수가 줄어듦)
  assert.throws(
    () =>
      verifyAutomergeReviewClosure({
        head: currentHead,
        reviews: [trustedHumanReview(1, 'APPROVED', previousHead)],
        comments: [canonicalMarker(currentHead)],
        reviewedCommits: [
          { sha: 'a'.repeat(40), patch: validPatch },
          { sha: previousHead, patch: validPatch },
        ],
        currentCommits: [{ sha: currentHead, patch: validPatch }],
        closureFiles: [],
      }),
    /current commit series is shorter/,
  );

  // Patch tamper (내용 변경)
  assert.throws(
    () =>
      verifyAutomergeReviewClosure({
        head: currentHead,
        reviews: [trustedHumanReview(1, 'APPROVED', previousHead)],
        comments: [canonicalMarker(currentHead)],
        reviewedCommits: [{ sha: previousHead, patch: validPatch }],
        currentCommits: [{ sha: currentHead, patch: validPatch + '+tampered\n' }],
        closureFiles: [],
      }),
    /commit series mismatch/,
  );

  // Merge commit 차단
  assert.throws(
    () =>
      verifyAutomergeReviewClosure({
        head: currentHead,
        reviews: [trustedHumanReview(1, 'APPROVED', previousHead)],
        comments: [canonicalMarker(currentHead)],
        reviewedCommits: [{ sha: previousHead, patch: validPatch }],
        currentCommits: [{ sha: currentHead, patch: validPatch, parents: ['1', '2'] }],
        closureFiles: [],
      }),
    /merge commit detected/,
  );

  // Empty commit 차단
  assert.throws(
    () =>
      verifyAutomergeReviewClosure({
        head: currentHead,
        reviews: [trustedHumanReview(1, 'APPROVED', previousHead)],
        comments: [canonicalMarker(currentHead)],
        reviewedCommits: [{ sha: previousHead, patch: validPatch }],
        currentCommits: [{ sha: currentHead, patch: '' }],
        closureFiles: [],
      }),
    /empty commit detected/,
  );

  // 5. selected 밖 production/test path와 add/delete/rename/binary/submodule 차단
  const baseClosureSetup = {
    head: currentHead,
    reviews: [trustedHumanReview(1, 'COMMENTED', previousHead, canonicalCodexBody(1))],
    comments: [canonicalMarker(currentHead)],
    reviewThreads: {
      pageInfo: { hasNextPage: false },
      nodes: [{ isResolved: true, path: 'apps/mobile/lib/route.dart' }],
    },
    reviewedCommits: [{ sha: previousHead, patch: validPatch }],
    currentCommits: [{ sha: previousHead, patch: validPatch }, { sha: currentHead, patch: validPatch }],
    selectedTestPaths: ['apps/mobile/test/route_test.dart'],
  };

  // selected 밖 production path
  assert.throws(
    () =>
      verifyAutomergeReviewClosure({
        ...baseClosureSetup,
        closureFiles: [{ filename: 'apps/mobile/lib/other.dart', status: 'modified' }],
      }),
    /production path outside original inline finding paths/,
  );

  // selected 밖 test path
  assert.throws(
    () =>
      verifyAutomergeReviewClosure({
        ...baseClosureSetup,
        closureFiles: [
          { filename: 'apps/mobile/lib/route.dart', status: 'modified' },
          { filename: 'apps/mobile/test/unselected_test.dart', status: 'modified' },
        ],
      }),
    /test path outside review-selected test paths/,
  );

  // add/delete/rename status 차단
  for (const status of ['added', 'deleted', 'renamed']) {
    assert.throws(
      () =>
        verifyAutomergeReviewClosure({
          ...baseClosureSetup,
          closureFiles: [{ filename: 'apps/mobile/lib/route.dart', status }],
        }),
      new RegExp(`forbidden file status '${status}'`),
    );
  }

  // binary 차단
  assert.throws(
    () =>
      verifyAutomergeReviewClosure({
        ...baseClosureSetup,
        closureFiles: [{ filename: 'apps/mobile/lib/route.dart', status: 'modified', isBinary: true }],
      }),
    /binary changes forbidden/,
  );

  // submodule 차단
  assert.throws(
    () =>
      verifyAutomergeReviewClosure({
        ...baseClosureSetup,
        closureFiles: [{ filename: 'apps/mobile/lib/route.dart', status: 'modified', isSubmodule: true }],
      }),
    /submodule changes forbidden/,
  );

  // mode change 차단
  assert.throws(
    () =>
      verifyAutomergeReviewClosure({
        ...baseClosureSetup,
        closureFiles: [{ filename: 'apps/mobile/lib/route.dart', status: 'modified', modeChanged: true }],
      }),
    /mode changes forbidden/,
  );

  // workflow / dependency 파일 변경 차단
  for (const protectedFile of ['.github/workflows/ci.yml', 'package.json', 'pubspec.yaml']) {
    assert.throws(
      () =>
        verifyAutomergeReviewClosure({
          ...baseClosureSetup,
          closureFiles: [{ filename: protectedFile, status: 'modified' }],
        }),
      /protected workflow or dependency file modified/,
    );
  }

  // 6. finding 0 + closure delta 차단
  assert.throws(
    () =>
      verifyAutomergeReviewClosure({
        head: currentHead,
        reviews: [trustedHumanReview(1, 'COMMENTED', previousHead, canonicalCodexBody(0))],
        comments: [canonicalMarker(currentHead)],
        reviewedCommits: [{ sha: previousHead, patch: validPatch }],
        currentCommits: [{ sha: previousHead, patch: validPatch }, { sha: currentHead, patch: validPatch }],
        closureFiles: [{ filename: 'apps/mobile/lib/route.dart', status: 'modified' }],
      }),
    /finding 0 requires diff 0/,
  );

  // 7. Review 0, 임의 COMMENTED, malformed canonical body, wrong actor 차단
  // Review 0
  assert.throws(
    () =>
      verifyAutomergeReviewClosure({
        head: currentHead,
        reviews: [],
        comments: [canonicalMarker(currentHead)],
      }),
    /no trusted reviews found/,
  );

  // 임의 COMMENTED
  assert.throws(
    () =>
      verifyAutomergeReviewClosure({
        head: currentHead,
        reviews: [
          {
            id: 1,
            state: 'COMMENTED',
            commit_id: previousHead,
            author_association: 'NONE',
            body: 'random comment',
            user: { login: 'stranger', id: 999, type: 'User' },
          },
        ],
        comments: [canonicalMarker(currentHead)],
      }),
    /no trusted reviews found/,
  );

  // malformed canonical body
  assert.throws(
    () =>
      verifyAutomergeReviewClosure({
        head: currentHead,
        reviews: [trustedHumanReview(1, 'COMMENTED', previousHead, 'Not a canonical codex body')],
        comments: [canonicalMarker(currentHead)],
        reviewedCommits: [{ sha: previousHead, patch: validPatch }],
        currentCommits: [{ sha: currentHead, patch: validPatch }],
      }),
    /no eligible previous-head discovery review found/,
  );

  // wrong actor for CodeRabbit
  assert.throws(
    () =>
      verifyAutomergeReviewClosure({
        head: currentHead,
        reviews: [
          {
            id: 1,
            state: 'COMMENTED',
            commit_id: previousHead,
            author_association: 'NONE',
            body: 'CodeRabbit review',
            user: { login: 'impostor[bot]', id: 136622811, type: 'Bot' },
          },
        ],
        comments: [canonicalMarker(currentHead)],
      }),
    /no trusted reviews found/,
  );

  // 8. active CHANGES_REQUESTED, unresolved/paginated thread 차단
  // active CHANGES_REQUESTED
  assert.throws(
    () =>
      verifyAutomergeReviewClosure({
        head: currentHead,
        reviews: [
          trustedHumanReview(1, 'APPROVED', currentHead),
          trustedHumanReview(2, 'CHANGES_REQUESTED', previousHead, '', {
            user: { login: 'reviewer-two', id: 2, type: 'User' },
          }),
        ],
        comments: [],
      }),
    /active CHANGES_REQUESTED remains/,
  );

  // unresolved review thread
  assert.throws(
    () =>
      verifyAutomergeReviewClosure({
        head: currentHead,
        reviews: [trustedHumanReview(1, 'APPROVED', currentHead)],
        comments: [],
        reviewThreads: {
          pageInfo: { hasNextPage: false },
          nodes: [{ isResolved: false, path: 'apps/mobile/lib/route.dart' }],
        },
      }),
    /unresolved review thread/,
  );

  // paginated review thread
  assert.throws(
    () =>
      verifyAutomergeReviewClosure({
        head: currentHead,
        reviews: [trustedHumanReview(1, 'APPROVED', currentHead)],
        comments: [],
        reviewThreads: {
          pageInfo: { hasNextPage: true },
          nodes: [{ isResolved: true, path: 'apps/mobile/lib/route.dart' }],
        },
      }),
    /paginated review threads not allowed/,
  );

  // 9. stale/wrong/multiple marker 차단
  // stale marker
  assert.throws(
    () =>
      verifyAutomergeReviewClosure({
        head: currentHead,
        reviews: [trustedHumanReview(1, 'APPROVED', previousHead)],
        comments: [canonicalMarker(previousHead)],
        reviewedCommits: [{ sha: previousHead, patch: validPatch }],
        currentCommits: [{ sha: currentHead, patch: validPatch }],
      }),
    /stale or wrong marker/,
  );

  // multiple markers
  assert.throws(
    () =>
      verifyAutomergeReviewClosure({
        head: currentHead,
        reviews: [trustedHumanReview(1, 'APPROVED', previousHead)],
        comments: [canonicalMarker(currentHead), canonicalMarker(previousHead)],
        reviewedCommits: [{ sha: previousHead, patch: validPatch }],
        currentCommits: [{ sha: currentHead, patch: validPatch }],
      }),
    /multiple canonical markers found/,
  );

  // missing marker
  assert.throws(
    () =>
      verifyAutomergeReviewClosure({
        head: currentHead,
        reviews: [trustedHumanReview(1, 'APPROVED', previousHead)],
        comments: [],
        reviewedCommits: [{ sha: previousHead, patch: validPatch }],
        currentCommits: [{ sha: currentHead, patch: validPatch }],
      }),
    /missing automerge frozen discovery authorization marker/,
  );

  // 10. missing/pending/failing required context 차단
  const required = [{ context: 'Mobile CI', integration_id: null }];

  // missing
  assert.throws(
    () =>
      verifyAutomergeReviewClosure({
        head: currentHead,
        reviews: [trustedHumanReview(1, 'APPROVED', currentHead)],
        requiredContexts: required,
        checks: [],
        statuses: [],
      }),
    /missing required context/,
  );

  // pending
  assert.throws(
    () =>
      verifyAutomergeReviewClosure({
        head: currentHead,
        reviews: [trustedHumanReview(1, 'APPROVED', currentHead)],
        requiredContexts: required,
        checks: [{ name: 'Mobile CI', conclusion: null, started_at: '2026-08-01T00:00:00Z' }],
      }),
    /required check 'Mobile CI' is not successful/,
  );

  // failing
  assert.throws(
    () =>
      verifyAutomergeReviewClosure({
        head: currentHead,
        reviews: [trustedHumanReview(1, 'APPROVED', currentHead)],
        requiredContexts: required,
        checks: [{ name: 'Mobile CI', conclusion: 'failure', started_at: '2026-08-01T00:00:00Z' }],
      }),
    /required check 'Mobile CI' is not successful/,
  );
});

// #406: verifyAutomergeReviewClosure 미러도 workflow 게이트(검증 함수 + jq)와 같은 claude[bot] 판정을 한다.
// 이전 head에 inline finding 1건을 남긴 Review → current head에서 그 path만 고친 closure를 기본 입력으로 쓴다.
// 게이트 fixture(claudeGateFixture)의 run·compare 자료를 미러 입력으로 그대로 옮긴다({ raw }는 형식 오류 응답).
const mirrorData = (byCommit) =>
  Object.fromEntries(Object.entries(byCommit).map(([sha, value]) => [sha, Array.isArray(value) ? value : value.raw]));
const claudeMirrorClosure = (reviews, overrides = {}, { closureFiles = [{ filename: 'apps/mobile/lib/route.dart', status: 'modified' }] } = {}) => {
  const fixture = claudeGateFixture(overrides);
  return verifyAutomergeReviewClosure({
    head: claudeGateHead,
    reviews,
    comments: fixture.comments,
    reviewThreads: {
      pageInfo: { hasNextPage: false },
      nodes: [{ isResolved: true, path: 'apps/mobile/lib/route.dart' }],
    },
    currentCommits: fixture.commits.map(({ sha }) => ({
      sha,
      patch: `diff --git a/apps/mobile/lib/route.dart b/apps/mobile/lib/route.dart\n+void route${sha.slice(0, 1)}() {}\n`,
    })),
    closureFiles,
    claudeWorkflowRuns: mirrorData(fixture.runsByCommit),
    claudeReviewDiffFiles: mirrorData(fixture.compareFilesByCommit),
  });
};
// verifier가 판정으로 던진 Error만 거부로 센다. 프로그래밍 오류는 그대로 올려 가짜 거부를 막는다.
const claudeMirrorVerdict = (reviews, overrides = {}, mirrorOptions = {}) => {
  try {
    claudeMirrorClosure(reviews, overrides, mirrorOptions);
  } catch (error) {
    if (error instanceof TypeError || error instanceof ReferenceError) throw error;
    return 'rejected';
  }
  return 'accepted';
};

test('verifyAutomergeReviewClosure 미러는 검증된 고정 신원 claude[bot] COMMENTED Review를 CodeRabbit 자리에서 인정한다 (#406)', () => {
  const result = claudeMirrorClosure([claudeReview(1)]);
  assert.deepEqual(
    { ok: result.ok, type: result.type, discoveryReviewId: result.discoveryReviewId },
    { ok: true, type: 'reused-discovery-review', discoveryReviewId: 1 },
  );
  const currentHead = claudeMirrorClosure([claudeReview(1, { commit_id: claudeGateHead })], {}, { closureFiles: [] });
  assert.deepEqual(
    { ok: currentHead.ok, discoveryReviewId: currentHead.discoveryReviewId },
    { ok: true, discoveryReviewId: 1 },
    'finding 0건 기본 경로인 current-head claude[bot] Review도 인정한다 (#407 F5)',
  );
});

test('verifyAutomergeReviewClosure 미러의 claude[bot] 판정은 workflow 게이트와 같다 (#406 D1, #407 F5)', () => {
  const gate = loadFrozenDiscoveryGate();
  const base = claudeGateFixture();
  const atCurrentHead = { closureFiles: [] };
  const truncated = Array.from({ length: 300 }, (_, index) => ({ filename: `apps/mobile/lib/f${index}.dart` }));
  for (const [reviews, overrides, mirrorOptions, expected, reason] of [
    [[claudeReview(1)], {}, {}, 'accepted', '검증된 이전 head Review'],
    [[claudeReview(1, { commit_id: claudeGateHead })], {}, atCurrentHead, 'accepted', '검증된 current-head Review (#407 F5)'],
    [
      [claudeReview(1), claudeReview(2, { commit_id: claudeGateHead })],
      { runsByCommit: { ...base.runsByCommit, [claudeGatePreviousHead]: [claudeRun(claudeGatePreviousHead, 'failure')] } },
      atCurrentHead,
      'accepted',
      '검증 실패한 이전 Review + 검증된 current-head Review',
    ],
    [[claudeReview(1, { body: '' })], {}, {}, 'rejected', '빈 본문 claude[bot] Review만 있다'],
    [[claudeReview(1, { body: '', commit_id: claudeGateHead })], {}, atCurrentHead, 'rejected', '빈 본문 current-head Review만 있다'],
    [[claudeReview(1, { body: '요약만 있고 개수 줄 없음' })], {}, {}, 'rejected', '개수 줄 없음'],
    [[claudeReview(1, { body: '요약\n🔴 0 · 🟡 0 · 🟣 0' })], {}, {}, 'rejected', '개수 줄이 첫 줄이 아니다'],
    [[claudeReview(1, { body: '🔴 0 · 🟡 0 · 🟣 0\r\n요약' })], {}, {}, 'rejected', '개수 줄 뒤 CR'],
    [
      [claudeReview(1)],
      { runsByCommit: { ...base.runsByCommit, [claudeGatePreviousHead]: [claudeRun(claudeGatePreviousHead, 'failure')] } },
      {},
      'rejected',
      'run이 failure만 있다',
    ],
    [[claudeReview(1)], { runsByCommit: { ...base.runsByCommit, [claudeGatePreviousHead]: [] } }, {}, 'rejected', 'run이 없다'],
    [
      [claudeReview(1)],
      { runsByCommit: { ...base.runsByCommit, [claudeGatePreviousHead]: [claudeRun(claudeGateHead)] } },
      {},
      'rejected',
      'success run의 head_sha가 리뷰 commit이 아니다',
    ],
    [[claudeReview(1)], { runsByCommit: withoutKey(base.runsByCommit, claudeGatePreviousHead) }, {}, 'rejected', 'run 조회 불가'],
    [
      [claudeReview(1)],
      { runsByCommit: { ...base.runsByCommit, [claudeGatePreviousHead]: { raw: { message: 'Not Found' } } } },
      {},
      'rejected',
      'run 응답 형식 오류',
    ],
    [
      [claudeReview(1)],
      { compareFilesByCommit: { ...base.compareFilesByCommit, [claudeGatePreviousHead]: [{ filename: CLAUDE_WORKFLOW }] } },
      {},
      'rejected',
      '리뷰 commit 시점 PR diff가 workflow를 바꿨다(되돌린 경우 포함)',
    ],
    [
      [claudeReview(1)],
      {
        compareFilesByCommit: {
          ...base.compareFilesByCommit,
          [claudeGatePreviousHead]: [{ filename: '.github/workflows/renamed.yml', previous_filename: CLAUDE_WORKFLOW }],
        },
      },
      {},
      'rejected',
      '리뷰 commit 시점 PR diff가 workflow 이름을 바꿨다',
    ],
    [
      [claudeReview(1)],
      { compareFilesByCommit: { ...base.compareFilesByCommit, [claudeGatePreviousHead]: truncated } },
      {},
      'rejected',
      'compare files 300개 상한',
    ],
    [
      [claudeReview(1)],
      { compareFilesByCommit: withoutKey(base.compareFilesByCommit, claudeGatePreviousHead) },
      {},
      'rejected',
      'compare 조회 불가',
    ],
    [[claudeReview(1, { commit_id: 'e'.repeat(40) })], {}, {}, 'rejected', 'PR commit 밖 Review'],
    [
      [memberReview(1, 'APPROVED'), claudeReview(2)],
      { comments: [], runsByCommit: {}, compareFilesByCommit: {} },
      {},
      'rejected',
      '사람 current-head 승인이 있어도 claude[bot] 후보 검증 조회가 안 되면 건너뛴다',
    ],
    [
      [memberReview(1, 'APPROVED'), claudeReview(2, { body: '' })],
      { comments: [], runsByCommit: {}, compareFilesByCommit: {} },
      {},
      'accepted',
      '개수 줄 없는 claude[bot] Review는 후보가 아니라 사람 승인 경로에 영향이 없다',
    ],
  ]) {
    assert.deepEqual(
      [gate(reviews, overrides), claudeMirrorVerdict(reviews, overrides, mirrorOptions)],
      [expected, expected],
      reason,
    );
  }
});

test('verifyAutomergeReviewClosure 미러의 claude[bot] 신원 판정은 workflow jq 게이트와 같다 (#406)', () => {
  const gate = loadFrozenDiscoveryGate();
  assert.deepEqual(
    [gate([claudeReview(1)]), claudeMirrorVerdict([claudeReview(1)])],
    ['accepted', 'accepted'],
    '고정 신원은 workflow와 미러가 모두 인정한다',
  );
  for (const [overrides, reason] of [
    [{ user: { ...CLAUDE_BOT, id: 999 } }, 'login만 같고 user.id가 다름'],
    [{ user: { ...CLAUDE_BOT, type: 'User' } }, 'user.type이 Bot이 아님'],
    [{ user: { login: 'claude', id: 209825114, type: 'Bot' } }, 'id가 같아도 login이 다름'],
    [{ user: { login: 'claude-bot[bot]', id: 55, type: 'Bot' } }, '유사한 봇 login'],
    [{ user: null }, 'user 없음'],
    [{ author_association: 'CONTRIBUTOR' }, 'author_association이 NONE이 아님'],
    [
      { author_association: 'COLLABORATOR', user: { login: 'claude', id: 77, type: 'User' } },
      '신뢰된 사람이 claude를 흉내 낸 마커 없는 COMMENTED',
    ],
  ]) {
    assert.deepEqual(
      [gate([claudeReview(1, overrides)]), claudeMirrorVerdict([claudeReview(1, overrides)])],
      ['rejected', 'rejected'],
      reason,
    );
  }
});

test('verifyAutomergeReviewClosure 미러는 claude[bot]을 COMMENTED로만 인정하고 active change request는 막는다 (#406)', () => {
  assert.throws(
    () => claudeMirrorClosure([claudeReview(1, { state: 'APPROVED', commit_id: claudeGateHead })], { comments: [] }),
    /missing automerge frozen discovery authorization marker/,
    'claude[bot] APPROVED는 current head여도 current-head-approved 경로가 아니다',
  );
  assert.throws(
    () => claudeMirrorClosure([claudeReview(1, { state: 'APPROVED' })]),
    /no eligible previous-head discovery review found/,
    'claude[bot] APPROVED는 marker가 있어도 frozen discovery가 아니다',
  );
  assert.throws(
    () => claudeMirrorClosure([memberReview(1, 'APPROVED'), claudeReview(2, { state: 'CHANGES_REQUESTED' })]),
    /active CHANGES_REQUESTED remains from claude\[bot\]/,
    'claude[bot]의 active change request는 신뢰된 사람 승인이 있어도 막는다',
  );
  assert.throws(
    () => claudeMirrorClosure([claudeReview(1), claudeReview(2, { state: 'CHANGES_REQUESTED' })]),
    /active CHANGES_REQUESTED remains from claude\[bot\]/,
    'claude[bot] 자신의 이후 change request가 discovery를 무효화한다',
  );
});

test('verifyAutomergeReviewClosure 미러는 claude[bot] Review에도 PR commit과 exact current-head marker를 요구한다 (#406)', () => {
  assert.throws(
    () => claudeMirrorClosure([claudeReview(1, { commit_id: 'e'.repeat(40) })]),
    /no eligible previous-head discovery review found/,
    'PR commit에 없는 commit의 Review는 검증 후보가 아니라 거부한다',
  );
  assert.throws(
    () => claudeMirrorClosure([claudeReview(1)], { comments: [] }),
    /missing automerge frozen discovery authorization marker/,
    'exact-head marker가 없으면 거부한다',
  );
  assert.throws(
    () =>
      claudeMirrorClosure([claudeReview(1)], {
        comments: [{ ...claudeGateHeadMarker, body: claudeGateHeadMarker.body.replace(claudeGateHead, 'b'.repeat(40)) }],
      }),
    /stale or wrong marker/,
    '다른 head를 가리키는 marker는 거부한다',
  );
});
