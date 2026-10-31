import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { existsSync, mkdtempSync, readFileSync, writeFileSync } from 'node:fs';
import { readFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';
import {
  canonicalPatchDigest,
  hasPstackInterrogateMarker,
  isCanonicalPstackInterrogate,
  isTrustedHuman,
  stripMarkdownCode,
  verifyAutomergeReviewClosure,
} from './verify-automerge-review-closure.mjs';

const workflowUrl = new URL(
  '../../.github/workflows/automerge-queue.yml',
  import.meta.url,
);
const closureModuleUrl = new URL(
  './verify-automerge-review-closure.mjs',
  import.meta.url,
);
const prTemplateUrls = [
  new URL('../../.github/PULL_REQUEST_TEMPLATE/full.md', import.meta.url),
  new URL('../../.github/PULL_REQUEST_TEMPLATE/short.md', import.meta.url),
  new URL('../../.github/pull_request_template.md', import.meta.url),
];
const MARKER_SYNC_RE =
  /# authorization-marker-sync-begin\n([\s\S]*?)\n\s+# authorization-marker-sync-end/;
const extractReviewJqDefs = (workflow) => {
  const match = workflow.match(/(^ +review_jq_defs="\$\(cat <<'JQ'\n([\s\S]*?)\n +JQ\n +\)"$)/m);
  assert.ok(match, 'shared review jq definitions must stay testable');
  return { block: match[1], body: match[2] };
};
const AQUILA_UNIVERSAL_MARKER = '<!-- Review source: Aquila Universal Review; engine: aquila-review -->';
const AQUILA_FALLBACK_MARKER =
  '<!-- Review source: Aquila fallback; canonical visible structure: PR #1926 Review 4676157515 -->';
const CODEX_LEGACY_MARKER =
  '<!-- Review source: Codex CLI fallback; canonical visible structure: PR #1926 Review 4676157515 -->';

test('automerge coordinator fails closed around the native merge queue', async () => {
  const workflow = await readFile(workflowUrl, 'utf8');

  for (const contract of [
    'pull_request_target:',
    'types: [labeled]',
    'workflow_run:',
    'workflow_dispatch:',
    'pull_request_review:',
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
    'any(.[]; . == $head)',
    '# frozen-discovery-review-filter-begin',
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
    '.author_association == "OWNER"',
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
    '# candidate-window-end',
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
    'strip_markdown_code',
    'has_pstack_interrogate_marker',
    'is_valid_pstack_interrogate_on($head)',
    '<!-- pstack-interrogate head=',
  ]) {
    assert.ok(workflow.includes(contract), `missing contract: ${contract}`);
  }

  assert.doesNotMatch(workflow, /--admin|gh pr merge.+--merge|gh pr merge.+--rebase/);
  assert.doesNotMatch(workflow, /Aquila Universal Review|Aquila fallback|is_aquila_fallback|Codex CLI fallback/);
  assert.doesNotMatch(workflow, /exact_actions_marker|\$commit_set\b/);
  assert.doesNotMatch(workflow, /actions: write/);
  assert.doesNotMatch(workflow, /gh workflow run ci\.yml/);
  // base 갱신 요청은 병합 분기의 BEHIND 한 곳에서만, 게이트를 통과한 현재 head를 고정해 PAT로 보낸다.
  const updateBranchCalls = workflow.split('\n').filter((line) => /\bgh api\b.*update-branch/.test(line));
  assert.equal(updateBranchCalls.length, 1, 'base update must be requested from exactly one place');
  assert.ok(
    updateBranchCalls[0].includes('GH_TOKEN="${MERGE_GH_TOKEN}" gh api --method PUT "repos/${repo}/pulls/${pr}/update-branch"'),
    'base update must be a PAT PUT on the candidate PR',
  );
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
  const markerIds = (comments) => {
    const res = spawnSync(
      'jq',
      ['-cer', '--arg', 'marker_pattern', '^<!-- Automerge frozen discovery authorization: [0-9a-f]{40} -->$', canonicalMarkerIds],
      {
        input: JSON.stringify(comments),
        encoding: 'utf8',
      },
    );
    assert.equal(res.status, 0, res.stderr);
    return res.stdout.trim();
  };
  assert.equal(markerIds([canonicalTuple(7, oldMarker)]), '[7]', 'relabel must PATCH the one old marker');
  assert.equal(
    markerIds([canonicalTuple(7, oldMarker), { id: 9, body: null, user: null }]),
    '[7]',
    'null comment fields must not crash canonical marker selector',
  );
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
  const runBlockAt = workflow.indexOf('        run: |\n', workflow.indexOf('\n  coordinate:\n'));
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

  const { body: reviewJqDefs } = extractReviewJqDefs(workflow);
  const reviewFilterBody = workflow.match(
    /# frozen-discovery-review-filter-begin\n\s+if ! jq -e --arg head "\$\{head\}" --argjson commit_shas "\$\{commit_shas\}" --argjson comments "\$\{comments_slim\}" \\\n\s+"\$\{review_jq_defs\}"'\n([\s\S]*?)\n\s+' <<<"\$\{reviews\}" >\/dev\/null; then/,
  )?.[1];
  assert.ok(reviewFilterBody, 'review state jq program must stay testable');
  const reviewProgram = `${reviewJqDefs}\n${reviewFilterBody}`;

  const head = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  const previousHeadSha = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
  const pstackInterrogateBody = (sha = head, actOn = 0) =>
    `## Summary\nAll clean.\n<!-- pstack-interrogate head=${sha} act-on=${actOn} -->`;
  const review = (id, state, submittedAt, body = '', overrides = {}) => ({
    id,
    state,
    submitted_at: submittedAt,
    commit_id: head,
    author_association: 'OWNER',
    body,
    user: { login: 'reviewer', type: 'User' },
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
    commits = [{ sha: head }, { sha: 'previous-head' }, { sha: previousHeadSha }],
    comments = [actionMarker()],
  ) => {
    const commitShas = Array.isArray(commits) && commits.length > 0 && typeof commits[0] === 'object' && commits[0] !== null
      ? commits.map((c) => c.sha)
      : commits;
    return spawnSync('jq', ['-e', '--arg', 'head', head, '--argjson', 'commit_shas', JSON.stringify(commitShas), '--argjson', 'comments', JSON.stringify(comments), reviewProgram], {
      input: JSON.stringify([reviews]),
    }).status;
  };

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
    'plain COMMENTED review without marker must be rejected',
  );
  for (const role of ['OWNER', 'MEMBER', 'COLLABORATOR']) {
    assert.equal(
      runReviewFilter(
        [review(1, 'COMMENTED', '2026-08-01T00:00:00Z', pstackInterrogateBody(head, 0), { author_association: role })],
        [{ sha: head }],
        [],
      ),
      0,
      `pstack-interrogate act-on=0 from ${role} on current head must pass`,
    );
  }
  assert.equal(
    runReviewFilter([
      review(1, 'COMMENTED', '2026-08-01T00:00:00Z', '', { commit_id: previousHeadSha }),
      review(2, 'COMMENTED', '2026-08-01T00:01:00Z', `<!-- pstack-interrogate head=${head} act-on=0 -->`),
    ], [{ sha: head }, { sha: previousHeadSha }], []),
    0,
    'earlier non-matching review must not short-circuit or crash pstack-interrogate evaluation',
  );
  for (const actOn of [1, 2, 12]) {
    assert.notEqual(
      runReviewFilter([
        review(1, 'COMMENTED', '2026-08-01T00:00:00Z', pstackInterrogateBody(head, actOn)),
      ]),
      0,
      `pstack-interrogate act-on=${actOn} must be rejected`,
    );
  }
  assert.notEqual(
    runReviewFilter([
      review(1, 'COMMENTED', '2026-08-01T00:00:00Z', pstackInterrogateBody(previousHeadSha, 0), { commit_id: head }),
    ]),
    0,
    'pstack-interrogate marker head mismatching review commit_id must be rejected',
  );
  assert.notEqual(
    runReviewFilter([
      review(1, 'COMMENTED', '2026-08-01T00:00:00Z', pstackInterrogateBody(head, 0), { commit_id: previousHeadSha }),
    ]),
    0,
    'pstack-interrogate review commit_id mismatching current head must be rejected',
  );
  assert.notEqual(
    runReviewFilter([
      review(1, 'COMMENTED', '2026-08-01T00:00:00Z', pstackInterrogateBody(previousHeadSha, 0), { commit_id: previousHeadSha }),
    ]),
    0,
    'pstack-interrogate review on previous head must be rejected even with exact Actions marker',
  );
  for (const multiBody of [
    `${pstackInterrogateBody(head, 1)}\n${pstackInterrogateBody(head, 0)}`,
    `${pstackInterrogateBody(head, 0)}\n${pstackInterrogateBody(head, 0)}`,
    `<!-- pstack-interrogate head=${head} act-on=0 extra=1 -->`,
  ]) {
    assert.notEqual(
      runReviewFilter([review(1, 'COMMENTED', '2026-08-01T00:00:00Z', multiBody)]),
      0,
      'multiple or malformed pstack-interrogate markers must be rejected',
    );
  }
  for (const [name, legacyMarker] of [
    ['Aquila fallback', AQUILA_FALLBACK_MARKER],
    ['Aquila Universal Review', AQUILA_UNIVERSAL_MARKER],
    ['Codex CLI fallback', CODEX_LEGACY_MARKER],
  ]) {
    assert.notEqual(
      runReviewFilter([
        review(1, 'COMMENTED', '2026-08-01T00:00:00Z', `**Actionable comments posted: 0**\n${legacyMarker}`),
      ]),
      0,
      `retired ${name} marker on current head must be rejected`,
    );
    assert.notEqual(
      runReviewFilter([
        review(1, 'COMMENTED', '2026-08-01T00:00:00Z', `**Actionable comments posted: 0**\n${legacyMarker}`, { commit_id: previousHeadSha }),
      ]),
      0,
      `retired ${name} marker on previous head must be rejected`,
    );
  }
  assert.notEqual(
    runReviewFilter([
      review(1, 'COMMENTED', '2026-08-01T00:00:00Z', '**Actionable comments posted: 0**'),
    ]),
    0,
    'a review without any recognized marker must not satisfy review filter',
  );
  for (const untrustedRole of ['NONE', 'CONTRIBUTOR']) {
    assert.notEqual(
      runReviewFilter([
        review(1, 'COMMENTED', '2026-08-01T00:00:00Z', pstackInterrogateBody(head, 0), {
          author_association: untrustedRole,
        }),
      ]),
      0,
      `untrusted ${untrustedRole} pstack-interrogate review must be rejected`,
    );
    assert.notEqual(
      runReviewFilter([
        review(1, 'COMMENTED', '2026-08-01T00:00:00Z', 'plain note'),
        review(2, 'COMMENTED', '2026-08-01T00:01:00Z', pstackInterrogateBody(head, 0), {
          author_association: untrustedRole,
          user: { login: 'outsider', type: 'User' },
        }),
      ]),
      0,
      `untrusted ${untrustedRole} pstack-interrogate alongside trusted note must be rejected`,
    );
  }

  assert.equal(
    runReviewFilter([review(1, 'APPROVED', '2026-08-01T00:00:00Z')], [{ sha: head }], []),
    0,
  );

  const codeRabbitReview = (id, state, submittedAt, overrides = {}) =>
    review(id, state, submittedAt, '', {
      author_association: 'NONE',
      user: { login: 'coderabbitai[bot]', id: 136622811, type: 'Bot' },
      ...overrides,
    });

  assert.equal(
    runReviewFilter([
      codeRabbitReview(1, 'COMMENTED', '2026-08-01T00:00:00Z', { commit_id: 'previous-head' }),
    ]),
    0,
  );
  assert.notEqual(
    runReviewFilter([
      codeRabbitReview(1, 'COMMENTED', '2026-08-01T00:00:00Z', { commit_id: 'previous-head' }),
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
        codeRabbitReview(1, 'COMMENTED', '2026-08-01T00:00:00Z', { commit_id: 'previous-head' }),
      ], [{ sha: head }, { sha: 'previous-head' }], comments),
      0,
    );
  }

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

  assert.notEqual(
    runReviewFilter([
      review(1, 'CHANGES_REQUESTED', '2026-08-01T00:00:00Z', '', {
        commit_id: 'previous-head',
        user: { login: 'reviewer-one', type: 'User' },
      }),
      review(2, 'APPROVED', '2026-08-01T00:01:00Z', '', {
        user: { login: 'reviewer-two', type: 'User' },
      }),
    ]),
    0,
  );
  assert.notEqual(
    runReviewFilter([
      review(1, 'CHANGES_REQUESTED', '2026-08-01T00:00:00Z', '', {
        commit_id: 'previous-head',
        user: { login: 'reviewer-one', type: 'User' },
      }),
      review(2, 'COMMENTED', '2026-08-01T00:01:00Z', pstackInterrogateBody(head, 0), {
        user: { login: 'reviewer-two', type: 'User' },
      }),
    ]),
    0,
  );
  assert.equal(
    runReviewFilter([
      review(1, 'CHANGES_REQUESTED', '2026-08-01T00:00:00Z', '', {
        commit_id: 'previous-head',
      }),
      review(2, 'APPROVED', '2026-08-01T00:01:00Z'),
    ]),
    0,
  );
  const outOfPrSha = 'e'.repeat(40);
  assert.equal(
    runReviewFilter([
      review(1, 'CHANGES_REQUESTED', '2026-08-01T00:00:00Z', '', {
        commit_id: outOfPrSha,
        user: { login: 'reviewer-one', type: 'User' },
      }),
      review(2, 'APPROVED', '2026-08-01T00:01:00Z', '', {
        commit_id: outOfPrSha,
        user: { login: 'reviewer-one', type: 'User' },
      }),
      review(3, 'COMMENTED', '2026-08-01T00:02:00Z', pstackInterrogateBody(head, 0), {
        user: { login: 'reviewer-two', type: 'User' },
      }),
    ]),
    0,
    'pre-rebase cleared CHANGES_REQUESTED must not block current head',
  );
  assert.notEqual(
    runReviewFilter([
      review(1, 'CHANGES_REQUESTED', '2026-08-01T00:00:00Z', '', {
        commit_id: 'previous-head',
        user: { login: 'reviewer-one', type: 'User' },
      }),
      review(2, 'APPROVED', '2026-08-01T00:01:00Z', '', {
        commit_id: outOfPrSha,
        user: { login: 'reviewer-one', type: 'User' },
      }),
      review(3, 'COMMENTED', '2026-08-01T00:02:00Z', pstackInterrogateBody(head, 0), {
        user: { login: 'reviewer-two', type: 'User' },
      }),
    ]),
    0,
    'out-of-PR APPROVED must not clear an in-PR CHANGES_REQUESTED',
  );
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
      codeRabbitReview(1, 'COMMENTED', '2026-08-01T00:00:00Z', {
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
        user: { login: 'reviewer-one', type: 'User' },
      }),
      review(2, 'APPROVED', '2026-08-01T00:01:00Z', '', {
        user: { login: 'reviewer-two', type: 'User' },
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
        user: { login: 'reviewer-one', type: 'User' },
      }),
      review(2, 'DISMISSED', '2026-08-01T00:01:00Z', '', {
        commit_id: 'previous-head',
        user: { login: 'reviewer-one', type: 'User' },
      }),
      review(3, 'APPROVED', '2026-08-01T00:02:00Z', '', {
        user: { login: 'reviewer-two', type: 'User' },
      }),
    ]),
    0,
  );
  // dismissed가 섞여 있어도 다른 리뷰어의 활성 change request는 그대로 막는다.
  assert.notEqual(
    runReviewFilter([
      review(1, 'DISMISSED', '2026-08-01T00:00:00Z', '', {
        commit_id: 'previous-head',
        user: { login: 'reviewer-one', type: 'User' },
      }),
      review(2, 'CHANGES_REQUESTED', '2026-08-01T00:01:00Z', '', {
        commit_id: 'previous-head',
        user: { login: 'reviewer-two', type: 'User' },
      }),
      review(3, 'APPROVED', '2026-08-01T00:02:00Z', '', {
        user: { login: 'reviewer-three', type: 'User' },
      }),
    ]),
    0,
  );
  // dismiss 이후 같은 리뷰어가 다시 남긴 change request는 정상 반영된다.
  assert.notEqual(
    runReviewFilter([
      review(1, 'DISMISSED', '2026-08-01T00:00:00Z', '', {
        commit_id: 'previous-head',
        user: { login: 'reviewer-one', type: 'User' },
      }),
      review(2, 'CHANGES_REQUESTED', '2026-08-01T00:01:00Z', '', {
        commit_id: 'previous-head',
        user: { login: 'reviewer-one', type: 'User' },
      }),
      review(3, 'APPROVED', '2026-08-01T00:02:00Z', '', {
        user: { login: 'reviewer-two', type: 'User' },
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

  assert.equal(
    runReviewFilter([
      codeRabbitReview(1, 'COMMENTED', '2026-08-01T00:00:00Z', { commit_id: previousHeadSha }),
      review(2, 'COMMENTED', '2026-08-01T00:01:00Z', pstackInterrogateBody(head, 1)),
    ]),
    1,
    'CodeRabbit frozen discovery must not bypass an active pstack-interrogate act-on>0 review',
  );
  assert.equal(
    runReviewFilter([
      review(1, 'COMMENTED', '2026-08-01T00:00:00Z', pstackInterrogateBody(head, 0)),
      review(2, 'COMMENTED', '2026-08-01T00:01:00Z', pstackInterrogateBody(head, 1)),
    ]),
    1,
    'later pstack-interrogate act-on>0 by same reviewer on same head must supersede earlier act-on=0',
  );
  assert.equal(
    runReviewFilter([
      review(1, 'COMMENTED', '2026-08-01T00:00:00Z', pstackInterrogateBody(head, 0)),
      review(2, 'COMMENTED', '2026-08-01T00:00:00Z', pstackInterrogateBody(head, 1)),
    ]),
    1,
    'same-timestamp pstack-interrogate act-on>0 with higher id must supersede earlier act-on=0',
  );
  assert.equal(
    runReviewFilter([
      review(1, 'COMMENTED', '2026-08-01T00:00:00Z', pstackInterrogateBody(head, 0), {
        user: { login: 'reviewer-one', type: 'User' },
      }),
      review(2, 'COMMENTED', '2026-08-01T00:01:00Z', pstackInterrogateBody(head, 2), {
        user: { login: 'reviewer-two', type: 'User' },
      }),
    ]),
    1,
    'later pstack-interrogate act-on>0 by another trusted reviewer on same head must block',
  );
  assert.equal(
    runReviewFilter(
      [
        review(1, 'CHANGES_REQUESTED', '2026-08-01T00:00:00Z', 'fix needed', {
          commit_id: previousHeadSha,
        }),
        review(2, 'COMMENTED', '2026-08-01T00:01:00Z', pstackInterrogateBody(head, 0)),
      ],
      [{ sha: head }, { sha: previousHeadSha }],
      [],
    ),
    0,
    'canonical pstack-interrogate act-on=0 on current head must clear prior CHANGES_REQUESTED by same reviewer',
  );
  assert.equal(
    runReviewFilter(
      [
        review(1, 'COMMENTED', '2026-08-01T00:00:00Z', pstackInterrogateBody(previousHeadSha, 3), {
          commit_id: previousHeadSha,
        }),
        review(2, 'COMMENTED', '2026-08-01T00:01:00Z', pstackInterrogateBody(head, 0)),
      ],
      [{ sha: head }, { sha: previousHeadSha }],
      [],
    ),
    0,
    'canonical pstack-interrogate act-on=0 on current head must clear prior ACT_ON by same reviewer',
  );
  assert.equal(
    runReviewFilter(
      [
        review(1, 'COMMENTED', '2026-08-01T00:00:00Z', pstackInterrogateBody(previousHeadSha, 0), {
          commit_id: previousHeadSha,
          user: { login: 'reviewer-one', type: 'User' },
        }),
        review(2, 'COMMENTED', '2026-08-01T00:01:00Z', pstackInterrogateBody(head, 0), {
          user: { login: 'reviewer-two', type: 'User' },
        }),
      ],
      [{ sha: head }, { sha: previousHeadSha }],
      [],
    ),
    0,
    'clean act-on=0 on previous head must not block a different reviewer act-on=0 on current head',
  );
  assert.equal(
    runReviewFilter(
      [
        review(
          1,
          'COMMENTED',
          '2026-08-01T00:00:00Z',
          [
            `Inline \`<!-- pstack-interrogate head=${previousHeadSha} act-on=2 -->\` and double \`\` \`<!-- pstack-interrogate head=${head} act-on=3 -->\` \`\`.`,
            '```html',
            `<!-- pstack-interrogate head=${head} act-on=1 -->`,
            '```',
            '~~~markdown',
            `<!-- pstack-interrogate head=${head} act-on=4 -->`,
            '~~~',
            pstackInterrogateBody(head, 0),
          ].join('\n'),
        ),
      ],
      [{ sha: head }],
      [],
    ),
    0,
    'Markdown fenced and inline code examples must not invalidate a real pstack-interrogate act-on=0 marker',
  );
  assert.equal(
    runReviewFilter(
      [
        review(
          1,
          'COMMENTED',
          '2026-08-01T00:00:00Z',
          [
            '```html',
            `<!-- pstack-interrogate head=${head} act-on=0 -->`,
            '```',
            `Inline \`<!-- pstack-interrogate head=${head} act-on=0 -->\` only.`,
          ].join('\n'),
        ),
      ],
      [{ sha: head }],
      [],
    ),
    1,
    'marker inside Markdown code only must not be accepted as a real pstack-interrogate marker',
  );
  for (const [label, malformedBody] of [
    [
      'marker between double-backtick inline spans',
      `\`\`a \` b\`\` <!-- pstack-interrogate head=${head} act-on=1 --> \`\`c \` d\`\` <!-- pstack-interrogate head=${head} act-on=0 -->`,
    ],
    ['extra leading space after <!--', `<!--  pstack-interrogate head=${head} act-on=0 -->`],
    ['multiline comment', `<!--\npstack-interrogate\nhead=${head} act-on=0\n-->`],
    [
      'internal > decoy before canonical marker',
      `<!-- pstack-interrogate a>b -->\n<!-- pstack-interrogate head=${head} act-on=0 -->`,
    ],
    ['unclosed marker prefix alone', `<!-- pstack-interrogate head=${head} act-on=0`],
    [
      'unclosed marker prefix before canonical marker',
      `<!-- pstack-interrogate broken\n<!-- pstack-interrogate head=${head} act-on=0 -->`,
    ],
    ['blockquote marker only', `> <!-- pstack-interrogate head=${head} act-on=0 -->`],
    ['indented code block marker only', `Summary\n\n    <!-- pstack-interrogate head=${head} act-on=0 -->`],
    ['mid-line marker with leading text', `prefix <!-- pstack-interrogate head=${head} act-on=0 -->`],
    ['unclosed fenced code block wrapping marker', `\`\`\`\n<!-- pstack-interrogate head=${head} act-on=0 -->`],
  ]) {
    assert.equal(
      runReviewFilter([review(1, 'COMMENTED', '2026-08-01T00:00:00Z', malformedBody)], [{ sha: head }], []),
      1,
      `${label} must fail closed with jq exit 1`,
    );
  }
  for (const [label, dismissedResurrection] of [
    [
      'dismissed pstack-interrogate followed by same reviewer plain comment',
      [
        review(1, 'COMMENTED', '2026-08-01T00:00:00Z', pstackInterrogateBody(head, 0)),
        review(2, 'DISMISSED', '2026-08-01T00:01:00Z', ''),
        review(3, 'COMMENTED', '2026-08-01T00:02:00Z', 'plain note'),
      ],
    ],
    [
      'dismissed APPROVED followed by same reviewer plain comment',
      [
        review(1, 'APPROVED', '2026-08-01T00:00:00Z', ''),
        review(2, 'DISMISSED', '2026-08-01T00:01:00Z', ''),
        review(3, 'COMMENTED', '2026-08-01T00:02:00Z', 'plain note'),
      ],
    ],
  ]) {
    assert.equal(
      runReviewFilter(dismissedResurrection, [{ sha: head }], []),
      1,
      `${label} must not resurrect dismissed review`,
    );
  }
  assert.equal(
    runReviewFilter(
      [
        review(1, 'COMMENTED', '2026-08-01T00:00:00Z', pstackInterrogateBody('c'.repeat(40), 2), {
          commit_id: 'c'.repeat(40),
          user: { login: 'reviewer-one', type: 'User' },
        }),
        review(2, 'COMMENTED', '2026-08-01T00:01:00Z', pstackInterrogateBody(previousHeadSha, 0), {
          commit_id: previousHeadSha,
          user: { login: 'reviewer-one', type: 'User' },
        }),
        codeRabbitReview(3, 'COMMENTED', '2026-08-01T00:02:00Z', { commit_id: previousHeadSha }),
      ],
      [{ sha: 'c'.repeat(40) }, { sha: previousHeadSha }, { sha: head }],
      [actionMarker()],
    ),
    0,
    'later prior-commit act-on=0 by same reviewer must clear earlier ACT_ON_PRIOR to COMMENTED',
  );
  for (const [label, badOverrides] of [
    ['MEMBER with user: null', { author_association: 'MEMBER', user: null }],
    ['OWNER with empty login', { author_association: 'OWNER', user: { login: '', type: 'User' } }],
    ['COLLABORATOR with Bot user', { author_association: 'COLLABORATOR', user: { login: 'bot[bot]', type: 'Bot' } }],
    ['DISMISSED review carrying canonical marker', { state: 'DISMISSED' }],
    ['PENDING review carrying canonical marker', { state: 'PENDING', submitted_at: '' }],
  ]) {
    assert.equal(
      runReviewFilter(
        [review(1, 'COMMENTED', '2026-08-01T00:00:00Z', pstackInterrogateBody(head, 0), badOverrides)],
        [{ sha: head }],
        [],
      ),
      1,
      `${label} must fail closed with jq exit 1 and never crash`,
    );
  }
  assert.equal(
    runReviewFilter(
      [
        review(1, 'COMMENTED', '2026-08-01T00:00:00Z', pstackInterrogateBody(head, 0), {
          user: { login: 'reviewer-one', type: 'User' },
        }),
        review(2, 'DISMISSED', '2026-08-01T00:01:00Z', '', {
          user: { login: 'reviewer-one', type: 'User' },
        }),
        review(3, 'COMMENTED', '2026-08-01T00:02:00Z', 'plain note', {
          user: { login: 'reviewer-two', type: 'User' },
        }),
      ],
      [{ sha: head }],
      [],
    ),
    1,
    'dismissed pstack-interrogate review must not pass via another reviewer plain note',
  );
  assert.equal(
    runReviewFilter(
      [codeRabbitReview(1, 'COMMENTED', '2026-08-01T00:00:00Z', { commit_id: previousHeadSha })],
      [{ sha: head }, { sha: previousHeadSha }],
      [{ user: null, body: null }, actionMarker()],
    ),
    0,
    'null user/body comments permitted by bounded_issue_comments must not crash canonical_actions_marker',
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
  const defaultDispatchHead = '0'.repeat(40);
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
      hasPat = false,
      updateStatus = 0,
      recordStatus = 0,
      baseUpdateRecords = [],
      headSha = defaultDispatchHead,
      reviews = [codeRabbitReview(1, 'COMMENTED', '2026-08-01T00:00:00Z', { commit_id: headSha })],
      commitShas = [headSha],
      comments = [
        {
          id: 1,
          body: `<!-- Automerge frozen discovery authorization: ${headSha} -->`,
          user: { login: 'github-actions[bot]', id: 41898282, type: 'Bot' },
        },
      ],
    } = {},
  ) => {
    const log = join(mkdtempSync(join(tmpdir(), 'automerge-queue-')), 'gh.log');
    const markerSync = workflow.match(MARKER_SYNC_RE)?.[1];
    assert.ok(markerSync, 'authorization marker sync must stay testable');
    const { block: reviewJqDefs } = extractReviewJqDefs(workflow);
    const script = [
      'set -euo pipefail',
      `GH_LOG=${JSON.stringify(log)}`,
      ': > "$GH_LOG"',
      `HAS_AUTOMERGE_PAT=${hasPat}`,
      'GH_TOKEN=github-token',
      `base_update_records=${JSON.stringify(JSON.stringify(baseUpdateRecords))}`,
      `reviews=${JSON.stringify(JSON.stringify(reviews))}`,
      `commit_shas=${JSON.stringify(JSON.stringify(commitShas))}`,
      `comments=${JSON.stringify(JSON.stringify(comments))}`,
      'gh() {',
      `  printf '%s\\n' "gh $*" >> "$GH_LOG"`,
      '  case "$*" in',
      `    "api --method PUT "*update-branch*) printf 'UPDATE_BRANCH_TOKEN=%s\\n' "$GH_TOKEN" >> "$GH_LOG"; return ${updateStatus} ;;`,
      `    "api --method "*"requested: "*) printf 'RECORD_TOKEN=%s\\n' "$GH_TOKEN" >> "$GH_LOG"; return ${recordStatus} ;;`,
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
      `head=${JSON.stringify(headSha)}`,
      'GITHUB_RUN_ID=123',
      'GITHUB_SERVER_URL=https://github.example',
      'GITHUB_REPOSITORY=o/r',
      'MERGE_GH_TOKEN=merge-token',
      `merge_state=${JSON.stringify(mergeState)}`,
      ['fail_closed_pr() {', failureHandler.replace(/^ {10}/gm, ''), '}'].join('\n'),
      markerSync.replace(/^ {10}/gm, ''),
      reviewJqDefs.replace(/^ {10}/gm, ''),
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
  // PAT가 있으면 게이트를 통과한 BEHIND 후보의 base를 현재 head 고정으로 갱신하고, 수락된 요청만
  // github.token 기록으로 남긴 뒤 그 실행을 끝낸다.
  const recordLine = `gh api --method POST repos/o/r/issues/44/comments -f body=<!-- Automerge base update requested: ${defaultDispatchHead} -->`;
  const behindWithPat = runDispatch('BEHIND', { hasPat: true });
  assert.equal(behindWithPat.status, 0);
  assert.equal(behindWithPat.merged, false);
  assert.equal(behindWithPat.skipped, false, 'base update must end the run');
  assert.equal(behindWithPat.labelRemoved, false);
  assert.deepEqual(
    behindWithPat.calls.split('\n').filter((line) => line.includes('update-branch')),
    [`gh api --method PUT repos/o/r/pulls/44/update-branch -f expected_head_sha=${defaultDispatchHead}`],
  );
  assert.match(behindWithPat.calls, /^UPDATE_BRANCH_TOKEN=merge-token$/m);
  assert.ok(behindWithPat.calls.includes(recordLine), 'an accepted base update must be recorded');
  assert.ok(behindWithPat.calls.indexOf('update-branch') < behindWithPat.calls.indexOf(recordLine));
  assert.match(behindWithPat.calls, /^RECORD_TOKEN=github-token$/m);
  const behindRecorded = runDispatch('BEHIND', { hasPat: true, baseUpdateRecords: [{ id: 7, head: 'a'.repeat(40) }] });
  assert.ok(behindRecorded.calls.includes(`gh api --method PATCH repos/o/r/issues/comments/7 -f body=<!-- Automerge base update requested: ${defaultDispatchHead} -->`));
  assert.doesNotMatch(behindRecorded.calls, /--method POST/);
  const behindAmbiguous = runDispatch('BEHIND', { hasPat: true, baseUpdateRecords: [{ id: 7, head: 'a'.repeat(40) }, { id: 8, head: 'b'.repeat(40) }] });
  assert.equal(behindAmbiguous.status, 0);
  assert.equal(behindAmbiguous.skipped, false);
  assert.doesNotMatch(behindAmbiguous.calls, /requested: /, 'ambiguous records must not be touched');
  assert.match(behindAmbiguous.output, /::warning::/);
  const behindRecordFailed = runDispatch('BEHIND', { hasPat: true, recordStatus: 49 });
  assert.equal(behindRecordFailed.status, 0, 'a record failure must not fail the run after the accepted update');
  assert.equal(behindRecordFailed.skipped, false);
  assert.match(behindRecordFailed.output, /::warning::/);
  const behindUpdateFailed = runDispatch('BEHIND', { hasPat: true, updateStatus: 42 });
  assert.equal(behindUpdateFailed.status, 0, 'a failed base update must skip only this candidate');
  assert.equal(behindUpdateFailed.skipped, true);
  assert.equal(behindUpdateFailed.merged, false);
  assert.equal(behindUpdateFailed.labelRemoved, false);
  assert.doesNotMatch(behindUpdateFailed.calls, /requested: /, 'a failed base update must not be recorded');
  assert.match(behindUpdateFailed.output, /::warning::/);
  for (const [label, options] of [
    [
      'pstack-interrogate review without frozen discovery',
      {
        hasPat: true,
        reviews: [
          review(1, 'COMMENTED', '2026-08-01T00:00:00Z', pstackInterrogateBody(defaultDispatchHead, 0), {
            commit_id: defaultDispatchHead,
          }),
        ],
      },
    ],
    ['frozen discovery without canonical marker', { hasPat: true, comments: [] }],
    [
      'unresolved ACT_ON_PRIOR masked on current head by second reviewer pstack-interrogate',
      {
        hasPat: true,
        commitShas: ['b'.repeat(40), defaultDispatchHead],
        reviews: [
          codeRabbitReview(1, 'COMMENTED', '2026-08-01T00:00:00Z', { commit_id: 'b'.repeat(40) }),
          review(2, 'COMMENTED', '2026-08-01T00:01:00Z', pstackInterrogateBody('b'.repeat(40), 2), {
            commit_id: 'b'.repeat(40),
            user: { login: 'reviewer-one', type: 'User' },
          }),
          review(3, 'COMMENTED', '2026-08-01T00:02:00Z', pstackInterrogateBody(defaultDispatchHead, 0), {
            commit_id: defaultDispatchHead,
            user: { login: 'reviewer-two', type: 'User' },
          }),
        ],
      },
    ],
    [
      'prior CHANGES_REQUESTED cleared only by current-head pstack-interrogate',
      {
        hasPat: true,
        commitShas: ['b'.repeat(40), defaultDispatchHead],
        reviews: [
          codeRabbitReview(1, 'COMMENTED', '2026-08-01T00:00:00Z', { commit_id: 'b'.repeat(40) }),
          review(2, 'CHANGES_REQUESTED', '2026-08-01T00:01:00Z', 'fix needed', {
            commit_id: 'b'.repeat(40),
          }),
          review(3, 'COMMENTED', '2026-08-01T00:02:00Z', pstackInterrogateBody(defaultDispatchHead, 0), {
            commit_id: defaultDispatchHead,
          }),
        ],
      },
    ],
  ]) {
    const nonTransferable = runDispatch('BEHIND', options);
    assert.deepEqual(
      withoutCalls(nonTransferable),
      {
        status: 0,
        merged: false,
        updatedBranch: false,
        dispatchedCi: false,
        skipped: true,
        commented: false,
        autoMergeDisabled: false,
        labelRemoved: false,
      },
      `${label} must skip BEHIND without calling update-branch`,
    );
    assert.doesNotMatch(nonTransferable.calls, /requested: /);
    assert.match(nonTransferable.output, /without a transferable frozen discovery review/);
  }
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
        user: { login: 'reviewer', type: 'User' },
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
      'MERGE_GH_TOKEN=merge-token',
      'HAS_AUTOMERGE_PAT=false',
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
    /# candidate-window-begin\n\s+done < <\(jq -r --argjson window "\$\{window\}" --argjson offset "\$\{offset\}" '\n([\s\S]*?)\n\s+' <<<"\$\{candidates\}"\)\n\s+# candidate-window-end/,
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

  const pstackInterrogateBody = (headSha = currentHead, actOn = 0) =>
    `## Summary\nAll clean.\n<!-- pstack-interrogate head=${headSha} act-on=${actOn} -->`;

  const codeRabbitDiscoveryReview = (id, commitId, body = 'CodeRabbit review', overrides = {}) => ({
    id,
    state: 'COMMENTED',
    commit_id: commitId,
    author_association: 'NONE',
    submitted_at: '2026-08-01T00:00:00Z',
    body,
    user: { login: 'coderabbitai[bot]', id: 136622811, type: 'Bot' },
    ...overrides,
  });

  const canonicalMarker = (headSha = currentHead) => ({
    body: `<!-- Automerge frozen discovery authorization: ${headSha} -->`,
    user: { login: 'github-actions[bot]', id: 41898282, type: 'Bot' },
  });

  const validPatch = 'diff --git a/apps/mobile/lib/route.dart b/apps/mobile/lib/route.dart\n+void main() {}\n';

  assert.equal(
    verifyAutomergeReviewClosure({
      head: currentHead,
      reviews: [trustedHumanReview(1, 'APPROVED', currentHead)],
      comments: [],
    }).ok,
    true,
  );
  for (const role of ['OWNER', 'MEMBER', 'COLLABORATOR']) {
    const res = verifyAutomergeReviewClosure({
      head: currentHead,
      reviews: [
        trustedHumanReview(1, 'COMMENTED', currentHead, pstackInterrogateBody(currentHead, 0), {
          author_association: role,
        }),
      ],
      comments: [],
    });
    assert.equal(res.ok, true);
    assert.equal(res.type, 'current-head-pstack-interrogate');
  }

  const rebasePrefixPatch = 'diff --git a/apps/mobile/lib/route.dart b/apps/mobile/lib/route.dart\n+void oldRoute() {}\n';
  const closureFindingPatch = 'diff --git a/apps/mobile/lib/route.dart b/apps/mobile/lib/route.dart\n+void fixedRoute() {}\n';

  assert.equal(
    verifyAutomergeReviewClosure({
      head: currentHead,
      reviews: [codeRabbitDiscoveryReview(1, previousHead)],
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

  const baseClosureSetup = {
    head: currentHead,
    reviews: [codeRabbitDiscoveryReview(1, previousHead)],
    comments: [canonicalMarker(currentHead)],
    reviewThreads: {
      pageInfo: { hasNextPage: false },
      nodes: [{ isResolved: true, path: 'apps/mobile/lib/route.dart' }],
    },
    reviewedCommits: [{ sha: previousHead, patch: validPatch }],
    currentCommits: [{ sha: previousHead, patch: validPatch }, { sha: currentHead, patch: validPatch }],
    selectedTestPaths: ['apps/mobile/test/route_test.dart'],
  };

  assert.throws(
    () =>
      verifyAutomergeReviewClosure({
        ...baseClosureSetup,
        closureFiles: [{ filename: 'apps/mobile/lib/other.dart', status: 'modified' }],
      }),
    /production path outside original inline finding paths/,
  );

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

  assert.throws(
    () =>
      verifyAutomergeReviewClosure({
        ...baseClosureSetup,
        closureFiles: [{ filename: 'apps/mobile/lib/route.dart', status: 'modified', isBinary: true }],
      }),
    /binary changes forbidden/,
  );

  assert.throws(
    () =>
      verifyAutomergeReviewClosure({
        ...baseClosureSetup,
        closureFiles: [{ filename: 'apps/mobile/lib/route.dart', status: 'modified', isSubmodule: true }],
      }),
    /submodule changes forbidden/,
  );

  assert.throws(
    () =>
      verifyAutomergeReviewClosure({
        ...baseClosureSetup,
        closureFiles: [{ filename: 'apps/mobile/lib/route.dart', status: 'modified', modeChanged: true }],
      }),
    /mode changes forbidden/,
  );

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

  assert.throws(
    () =>
      verifyAutomergeReviewClosure({
        head: currentHead,
        reviews: [codeRabbitDiscoveryReview(1, previousHead)],
        comments: [canonicalMarker(currentHead)],
        reviewedCommits: [{ sha: previousHead, patch: validPatch }],
        currentCommits: [{ sha: previousHead, patch: validPatch }, { sha: currentHead, patch: validPatch }],
        closureFiles: [{ filename: 'apps/mobile/lib/route.dart', status: 'modified' }],
      }),
    /finding 0 requires diff 0/,
  );

  assert.throws(
    () =>
      verifyAutomergeReviewClosure({
        head: currentHead,
        reviews: [],
        comments: [canonicalMarker(currentHead)],
      }),
    /no trusted reviews found/,
  );

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

  assert.throws(
    () =>
      verifyAutomergeReviewClosure({
        head: currentHead,
        reviews: [trustedHumanReview(1, 'COMMENTED', currentHead, 'Not a canonical review body')],
        comments: [canonicalMarker(currentHead)],
        reviewedCommits: [{ sha: previousHead, patch: validPatch }],
        currentCommits: [{ sha: currentHead, patch: validPatch }],
      }),
    /no eligible previous-head discovery review found/,
  );

  const closureOnHead = (commitId, body) => () =>
    verifyAutomergeReviewClosure({
      head: currentHead,
      reviews: [trustedHumanReview(1, 'COMMENTED', commitId, body)],
      comments: [canonicalMarker(currentHead)],
      reviewedCommits: [{ sha: previousHead, patch: validPatch }],
      currentCommits: [{ sha: currentHead, patch: validPatch }],
      closureFiles: [],
    });

  for (const actOn of [1, 2, 12]) {
    assert.throws(
      closureOnHead(currentHead, pstackInterrogateBody(currentHead, actOn)),
      /blocking review state 'ACT_ON_CURRENT'/,
      `act-on=${actOn} must be rejected`,
    );
  }
  assert.throws(
    closureOnHead(currentHead, pstackInterrogateBody(previousHead, 0)),
    /blocking review state 'ACT_ON_CURRENT'/,
    'marker head != review commit_id must be rejected',
  );
  assert.throws(
    closureOnHead(previousHead, pstackInterrogateBody(currentHead, 0)),
    /blocking review state 'ACT_ON_PRIOR'/,
    'review commit_id != currentHead must be rejected even if marker names currentHead',
  );
  assert.throws(
    closureOnHead(previousHead, pstackInterrogateBody(previousHead, 0)),
    /no eligible previous-head discovery review found/,
    'previous-head pstack-interrogate review must not be reused as frozen discovery',
  );
  for (const body of [
    `${pstackInterrogateBody(currentHead, 1)}\n${pstackInterrogateBody(currentHead, 0)}`,
    `${pstackInterrogateBody(currentHead, 0)}\n${pstackInterrogateBody(currentHead, 0)}`,
    `<!-- pstack-interrogate head=${currentHead} act-on=0 extra=1 -->`,
  ]) {
    assert.throws(
      closureOnHead(currentHead, body),
      /blocking review state 'ACT_ON_CURRENT'/,
      body,
    );
  }
  for (const legacyMarker of [AQUILA_FALLBACK_MARKER, AQUILA_UNIVERSAL_MARKER, CODEX_LEGACY_MARKER]) {
    for (const commitId of [currentHead, previousHead]) {
      assert.throws(
        closureOnHead(commitId, `**Actionable comments posted: 0**\n${legacyMarker}`),
        /no eligible previous-head discovery review found/,
        legacyMarker,
      );
    }
  }
  for (const commitId of [currentHead, previousHead]) {
    assert.throws(
      closureOnHead(commitId, '**Actionable comments posted: 0**'),
      /no eligible previous-head discovery review found/,
      'missing pstack-interrogate marker must be rejected',
    );
  }

  const untrustedCanonical = trustedHumanReview(
    2,
    'COMMENTED',
    currentHead,
    pstackInterrogateBody(currentHead, 0),
    {
      author_association: 'NONE',
      user: { login: 'outsider', id: 2, type: 'User' },
    },
  );
  assert.throws(
    () =>
      verifyAutomergeReviewClosure({
        head: currentHead,
        reviews: [trustedHumanReview(1, 'COMMENTED', previousHead, 'plain note'), untrustedCanonical],
        comments: [canonicalMarker(currentHead)],
        reviewedCommits: [{ sha: previousHead, patch: validPatch }],
        currentCommits: [{ sha: currentHead, patch: validPatch }],
        closureFiles: [],
      }),
    /no eligible previous-head discovery review found/,
  );

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

  for (const currentHeadReview of [
    trustedHumanReview(1, 'APPROVED', currentHead),
    trustedHumanReview(1, 'COMMENTED', currentHead, pstackInterrogateBody(currentHead, 0)),
  ]) {
    assert.throws(
      () =>
        verifyAutomergeReviewClosure({
          head: currentHead,
          reviews: [
            currentHeadReview,
            trustedHumanReview(2, 'CHANGES_REQUESTED', previousHead, '', {
              user: { login: 'reviewer-two', id: 2, type: 'User' },
            }),
          ],
          comments: [],
        }),
      /active CHANGES_REQUESTED remains/,
    );

    assert.throws(
      () =>
        verifyAutomergeReviewClosure({
          head: currentHead,
          reviews: [currentHeadReview],
          comments: [],
          reviewThreads: {
            pageInfo: { hasNextPage: false },
            nodes: [{ isResolved: false, path: 'apps/mobile/lib/route.dart' }],
          },
        }),
      /unresolved review thread/,
    );

    assert.throws(
      () =>
        verifyAutomergeReviewClosure({
          head: currentHead,
          reviews: [currentHeadReview],
          comments: [],
          reviewThreads: {
            pageInfo: { hasNextPage: true },
            nodes: [{ isResolved: true, path: 'apps/mobile/lib/route.dart' }],
          },
        }),
      /paginated review threads not allowed/,
    );
  }

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

  const required = [{ context: 'Mobile CI', integration_id: null }];

  for (const currentHeadReview of [
    trustedHumanReview(1, 'APPROVED', currentHead),
    trustedHumanReview(1, 'COMMENTED', currentHead, pstackInterrogateBody(currentHead, 0)),
  ]) {
    assert.throws(
      () =>
        verifyAutomergeReviewClosure({
          head: currentHead,
          reviews: [currentHeadReview],
          requiredContexts: required,
          checks: [],
          statuses: [],
        }),
      /missing required context/,
    );

    assert.throws(
      () =>
        verifyAutomergeReviewClosure({
          head: currentHead,
          reviews: [currentHeadReview],
          requiredContexts: required,
          checks: [{ name: 'Mobile CI', conclusion: null, started_at: '2026-08-01T00:00:00Z' }],
        }),
      /required check 'Mobile CI' is not successful/,
    );

    assert.throws(
      () =>
        verifyAutomergeReviewClosure({
          head: currentHead,
          reviews: [currentHeadReview],
          requiredContexts: required,
          checks: [{ name: 'Mobile CI', conclusion: 'failure', started_at: '2026-08-01T00:00:00Z' }],
        }),
      /required check 'Mobile CI' is not successful/,
    );
  }
});

test('병합 예약과 update-branch만 AUTOMERGE_PAT 병합 토큰을 쓰고 나머지는 github.token을 유지한다', async () => {
  const workflow = await readFile(workflowUrl, 'utf8');
  assert.ok(
    workflow.includes(
      "MERGE_GH_TOKEN: ${{ secrets.AUTOMERGE_PAT != '' && secrets.AUTOMERGE_PAT || github.token }}",
    ),
  );
  assert.ok(workflow.includes("HAS_AUTOMERGE_PAT: ${{ secrets.AUTOMERGE_PAT != '' }}"));
  assert.ok(workflow.includes('GH_TOKEN: ${{ github.token }}'));
  assert.match(workflow, /if \[ "\$\{HAS_AUTOMERGE_PAT\}" != "true" \]; then/);
  assert.match(workflow, /::warning::AUTOMERGE_PAT/);

  const prefix = 'GH_TOKEN="${MERGE_GH_TOKEN}" ';
  const lines = workflow.split('\n');
  const mergeLines = lines.filter((line) => /\bgh pr merge --squash\b/.test(line));
  const updateLines = lines.filter(
    (line) => /update-branch/.test(line) && /\bgh (api|pr)\b/.test(line),
  );
  assert.ok(mergeLines.length >= 1, 'merge call not found');
  for (const line of [...mergeLines, ...updateLines]) {
    assert.ok(
      line.includes(prefix + 'gh '),
      'merge/update-branch call must use MERGE_GH_TOKEN: ' + line.trim(),
    );
  }

  // 병합 토큰은 병합·update-branch 호출 외에는 어디에도 쓰지 않는다.
  const prefixed = lines.filter((line) => line.includes(prefix));
  assert.equal(prefixed.length, mergeLines.length + updateLines.length);

  const others = lines.filter(
    (l) => /gh api --method (POST|PATCH)/.test(l) || /--disable-auto/.test(l) || /gh workflow run/.test(l),
  );
  for (const line of others) {
    assert.ok(!line.includes('MERGE_GH_TOKEN'), 'must keep github.token: ' + line.trim());
  }
});

test('bounded_pr_reviews: 2페이지에서 gh 호출 실패 시 return 1로 종료되고 fail-closed된다', async () => {
  const workflow = await readFile(workflowUrl, 'utf8');
  const reviewReader = workflow.match(/          bounded_pr_reviews\(\) \{\n([\s\S]*?)\n          \}/)?.[1];
  assert.ok(reviewReader, 'bounded_pr_reviews must exist');

  const stubGh = `
    case "$*" in
      *page=1*)
        node -e 'console.log(JSON.stringify(Array.from({length: 100}, (_, i) => ({id: i+1, state: "APPROVED", commit_id: "c", submitted_at: "2026-01-01T00:00:00Z", author_association: "MEMBER", body: "b", user: {login: "u"}}))))'
        ;;
      *page=2*)
        return 1
        ;;
      *)
        echo "[]"
        ;;
    esac
  `;

  const script = [
    'set -euo pipefail',
    'repo=o/r',
    'pr=123',
    'data_page_limit=3',
    'page_size=100',
    'overflow_probe_page=$((data_page_limit + 1))',
    'gh() {',
    stubGh,
    '}',
    'bounded_pr_reviews() {',
    reviewReader.replace(/^ {10,12}/gm, ''),
    '}',
    'if ! out="$(bounded_pr_reviews)"; then',
    '  echo "FAILED"',
    'else',
    '  echo "OK"',
    'fi',
  ].join('\n');

  const result = spawnSync('bash', ['-c', script], { encoding: 'utf8' });
  assert.equal(result.stdout.trim(), 'FAILED');
});

test('bounded_pr_reviews: 중간 페이지 파싱 실패 시 return 1로 종료되고 fail-closed된다', async () => {
  const workflow = await readFile(workflowUrl, 'utf8');
  const reviewReader = workflow.match(/          bounded_pr_reviews\(\) \{\n([\s\S]*?)\n          \}/)?.[1];
  assert.ok(reviewReader, 'bounded_pr_reviews must exist');

  const stubGh = `
    case "$*" in
      *page=1*)
        # submitted_at 누락으로 jq 스키마 검증 실패
        echo '[{"id": 1, "state": "APPROVED"}]'
        ;;
      *)
        echo "[]"
        ;;
    esac
  `;

  const script = [
    'set -euo pipefail',
    'repo=o/r',
    'pr=123',
    'data_page_limit=3',
    'page_size=100',
    'overflow_probe_page=$((data_page_limit + 1))',
    'gh() {',
    stubGh,
    '}',
    'bounded_pr_reviews() {',
    reviewReader.replace(/^ {10,12}/gm, ''),
    '}',
    'if ! out="$(bounded_pr_reviews)"; then',
    '  echo "FAILED"',
    'else',
    '  echo "OK"',
    'fi',
  ].join('\n');

  const result = spawnSync('bash', ['-c', script], { encoding: 'utf8' });
  assert.equal(result.stdout.trim(), 'FAILED');
});

test('bounded_pr_commits: overflow probe에 잔여 데이터가 있으면 return 1로 종료되고 fail-closed된다', async () => {
  const workflow = await readFile(workflowUrl, 'utf8');
  const commitReader = workflow.match(/          bounded_pr_commits\(\) \{\n([\s\S]*?)\n          \}/)?.[1];
  assert.ok(commitReader, 'bounded_pr_commits must exist');

  const stubGh = `
    case "$*" in
      *page=[123]*)
        node -e 'console.log(JSON.stringify(Array.from({length: 100}, () => ({sha: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}))))'
        ;;
      *page=4*)
        echo '[{"sha": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}]'
        ;;
      *)
        echo "[]"
        ;;
    esac
  `;

  const script = [
    'set -euo pipefail',
    'repo=o/r',
    'pr=123',
    'data_page_limit=3',
    'page_size=100',
    'overflow_probe_page=$((data_page_limit + 1))',
    'gh() {',
    stubGh,
    '}',
    'bounded_pr_commits() {',
    commitReader.replace(/^ {10,12}/gm, ''),
    '}',
    'if ! out="$(bounded_pr_commits)"; then',
    '  echo "FAILED"',
    'else',
    '  echo "OK"',
    'fi',
  ].join('\n');

  const result = spawnSync('bash', ['-c', script], { encoding: 'utf8' });
  assert.equal(result.stdout.trim(), 'FAILED');
});

test('판정 jq 인자로 commits는 SHA 배열로, comments는 필수 필드로 축소되어 전달된다', async () => {
  const workflow = await readFile(workflowUrl, 'utf8');

  assert.match(
    workflow,
    /commit_shas="\$\(jq -c 'map\(\.sha\)' <<<"\$\{commits\}"\)"/,
    'commits must be projected to SHA array before passing to judgment jq',
  );
  assert.ok(
    workflow.includes('--argjson commit_shas "${commit_shas}"'),
    'must pass --argjson commit_shas to judgment jq',
  );
  assert.ok(
    !workflow.includes('--argjson commits "${commits}"'),
    'must not pass full commits object to judgment jq',
  );

  assert.match(
    workflow,
    /comments_slim="\$\(jq -c 'map\(\{user: \{login: \.user\.login, id: \.user\.id, type: \.user\.type\}, body\}\)' <<<"\$\{comments\}"\)"|comments_slim="\$\(jq -c 'map\(\{user, body\}\)' <<<"\$\{comments\}"\)"/,
    'comments must be projected to slim form before passing to judgment jq',
  );
  assert.ok(
    workflow.includes('--argjson comments "${comments_slim}"') || workflow.includes('--argjson comments_slim "${comments_slim}"'),
    'must pass slimmed comments to judgment jq',
  );
});


// 조회 함수 하나를 stub gh로 실행한다. stubGh는 `case "$*" in ... esac` 본문이다.
async function runBoundedReader(name, stubGh) {
  const workflow = await readFile(workflowUrl, 'utf8');
  const body = workflow.match(new RegExp(`          ${name}\\(\\) \\{\\n([\\s\\S]*?)\\n          \\}`))?.[1];
  assert.ok(body, `${name} must exist`);
  const script = [
    'set -euo pipefail',
    'repo=o/r',
    'pr=123',
    'data_page_limit=3',
    'page_size=100',
    'overflow_probe_page=$((data_page_limit + 1))',
    'gh() {',
    stubGh,
    '}',
    `${name}() {`,
    body.replace(/^ {10,12}/gm, ''),
    '}',
    `if ! out="$(${name})"; then`,
    '  echo "FAILED"',
    'else',
    '  echo "OK"',
    '  printf "%s\\n" "${out}"',
    'fi',
  ].join('\n');
  const result = spawnSync('bash', ['-c', script], { encoding: 'utf8' });
  const [status, ...rest] = result.stdout.trim().split('\n');
  return { status, output: rest.join('\n') };
}

const readerPages = {
  bounded_issue_comments: [
    { id: 1, body: 'first', user: { login: 'a' } },
    { id: 2, body: null, user: null },
  ],
  bounded_pr_commits: [
    { sha: '1111111111111111111111111111111111111111' },
    { sha: '2222222222222222222222222222222222222222' },
  ],
  bounded_pr_reviews: [
    {
      id: 7,
      state: 'COMMENTED',
      commit_id: '1111111111111111111111111111111111111111',
      submitted_at: '2026-09-29T00:00:00Z',
      author_association: 'OWNER',
      body: 'review',
      user: { login: 'a' },
    },
  ],
};

for (const [name, page] of Object.entries(readerPages)) {
  test(`${name}: 짧은 1페이지는 성공하고 그 페이지를 그대로 반환한다`, async () => {
    const pageJson = JSON.stringify(page);
    const result = await runBoundedReader(name, `
      case "$*" in
        *page=1*) printf '%s\\n' '${pageJson}' ;;
        *) echo "unexpected page: $*" >&2; return 1 ;;
      esac
    `);
    assert.equal(result.status, 'OK');
    assert.deepEqual(JSON.parse(result.output), page);
  });
}

test('bounded_issue_comments: 스키마 불일치 페이지는 실패한다', async () => {
  const result = await runBoundedReader('bounded_issue_comments', `
    case "$*" in
      *page=1*) echo '[{"id": "not-a-number", "body": "x", "user": null}]' ;;
      *) echo "[]" ;;
    esac
  `);
  assert.equal(result.status, 'FAILED');
});

test('bounded_issue_comments: gh 호출 실패는 출력이 정상이어도 실패로 전파된다', async () => {
  // 다음 스키마 검사가 대신 잡지 못하도록 유효한 빈 배열을 출력한 뒤 비정상 종료한다.
  const result = await runBoundedReader('bounded_issue_comments', `
    echo "[]"
    return 1
  `);
  assert.equal(result.status, 'FAILED');
});

test('bounded_issue_comments: overflow probe에 잔여 코멘트가 있으면 실패한다', async () => {
  const result = await runBoundedReader('bounded_issue_comments', `
    case "$*" in
      *page=[123]*) node -e 'console.log(JSON.stringify(Array.from({length: 100}, (_, i) => ({id: i + 1, body: "b", user: null}))))' ;;
      *page=4*) echo '[{"id": 999, "body": "late", "user": null}]' ;;
      *) echo "[]" ;;
    esac
  `);
  assert.equal(result.status, 'FAILED');
});

const markerFor = (head) => `<!-- Automerge frozen discovery authorization: ${head} -->`;
const recordFor = (head) => `<!-- Automerge base update requested: ${head} -->`;
const actionsBotUser = { login: 'github-actions[bot]', id: 41898282, type: 'Bot' };
const pstackMarkerFor = (head, actOn = 0) => `<!-- pstack-interrogate head=${head} act-on=${actOn} -->`;
const discoveryReview = (commitId, overrides = {}) => ({
  id: 5,
  state: 'COMMENTED',
  submitted_at: '2026-09-29T00:00:00Z',
  commit_id: commitId,
  author_association: 'NONE',
  body: '',
  user: { login: 'coderabbitai[bot]', id: 136622811, type: 'Bot' },
  ...overrides,
});
const pstackReview = (commitId, markerHead = commitId, actOn = 0, overrides = {}) => ({
  id: 6,
  state: 'COMMENTED',
  submitted_at: '2026-09-29T00:00:00Z',
  commit_id: commitId,
  author_association: 'OWNER',
  body: `## Summary\nAll clean.\n${pstackMarkerFor(markerHead, actOn)}`,
  user: { login: 'reviewer', type: 'User' },
  ...overrides,
});
const committedAt = (sha, date) => ({ sha, commit: { committer: { date } } });
const labeledAt = (date, name = 'automerge') => ({ event: 'labeled', label: { name }, created_at: date });

// 워크플로의 marker 동기화 블록을 그대로 꺼내 stub gh로 실행한다. stub은 `--jq` 인자를 실제 jq로
// 적용하고, 호출마다 GH_TOKEN을 남겨 토큰 경계를 관측한다.
const runMarkerSync = (
  workflow,
  { head, comments = [], reviews = [], commits = [], headCommit = null, compare = null, events = null, mutation = 'ok' },
) => {
  const block = workflow.match(MARKER_SYNC_RE)?.[1];
  assert.ok(block, 'authorization marker sync must stay testable');
  const dir = mkdtempSync(join(tmpdir(), 'automerge-marker-sync-'));
  const log = join(dir, 'gh.log');
  const fixture = (name, payload) =>
    writeFileSync(join(dir, name), payload === '__FAIL__' ? payload : JSON.stringify(payload));
  if (headCommit !== null) fixture('head-commit.json', headCommit);
  if (compare !== null) fixture('compare.json', compare);
  for (const [index, page] of (events ?? []).entries()) fixture(`events-${index + 1}.json`, page);
  const result = spawnSync('bash', ['-c', [
    'set -euo pipefail',
    `GH_LOG=${JSON.stringify(log)}`,
    `FIX=${JSON.stringify(dir)}`,
    'repo=o/r',
    'pr=85',
    `head=${JSON.stringify(head)}`,
    'GH_TOKEN=github-token',
    'MERGE_GH_TOKEN=merge-token',
    `mutation=${JSON.stringify(mutation)}`,
    `comments=${JSON.stringify(JSON.stringify(comments))}`,
    `commits=${JSON.stringify(JSON.stringify(commits))}`,
    `commit_shas=${JSON.stringify(JSON.stringify(commits.map((commit) => commit.sha)))}`,
    `reviews=${JSON.stringify(JSON.stringify(reviews))}`,
    ': > "$GH_LOG"',
    'gh() {',
    '  printf "TOKEN=%s gh %s\\n" "$GH_TOKEN" "$*" >> "$GH_LOG"',
    '  local all="$*" filter="" previous="" argument payload=""',
    '  for argument in "$@"; do [[ "$previous" == --jq ]] && filter="$argument"; previous="$argument"; done',
    '  case "$all" in',
    '    "api --method PATCH repos/o/r/issues/comments/"*|"api --method POST repos/o/r/issues/"*"/comments "*)',
    '      [[ "$mutation" == fail ]] && return 1',
    '      local id=77; [[ "$all" == *"issues/comments/"* ]] && { id="${all#*issues/comments/}"; id="${id%% *}"; }',
    '      if [[ "$mutation" == foreign ]]; then',
    '        jq -nc --argjson id "$id" \'{id: $id, body: "other", user: {login: "github-actions[bot]", id: 41898282, type: "Bot"}}\'',
    '        return 0',
    '      fi',
    '      jq -nc --argjson id "$id" --arg body "${all#*body=}" \'{id: $id, body: $body, user: {login: "github-actions[bot]", id: 41898282, type: "Bot"}}\' ;;',
    '    "api repos/o/r/commits/"*) payload="$(cat "$FIX/head-commit.json")" ;;',
    '    "api repos/o/r/compare/"*) payload="$(cat "$FIX/compare.json")" ;;',
    '    "api repos/o/r/issues/85/events?per_page=100&page="*) page="${all##*page=}"; [[ -f "$FIX/events-$page.json" ]] || return 1; payload="$(cat "$FIX/events-$page.json")" ;;',
    '    *) printf "unstubbed gh call: %s\\n" "$all" >&2; return 1 ;;',
    '  esac',
    '  if [[ -n "$payload" ]]; then',
    '    [[ "$payload" == __FAIL__ ]] && return 1',
    '    if [[ -n "$filter" ]]; then jq -r "$filter" <<<"$payload"; else printf "%s\\n" "$payload"; fi',
    '  fi',
    '}',
    block.replace(/^ {10}/gm, ''),
    'sync_authorization_marker',
    'printf "SYNC_RETURNED\\n"',
    'printf "%s\\n" "$comments"',
  ].join('\n')], { encoding: 'utf8' });
  const calls = existsSync(log) ? readFileSync(log, 'utf8') : '';
  const lines = (result.stdout ?? '').trim().split('\n');
  const after = lines.at(-1)?.startsWith('[') ? JSON.parse(lines.at(-1)) : null;
  const canonical = (after ?? []).filter(
    (comment) =>
      comment.user?.login === actionsBotUser.login &&
      comment.user?.id === actionsBotUser.id &&
      comment.user?.type === actionsBotUser.type &&
      /^<!-- Automerge frozen discovery authorization: [0-9a-f]{40} -->$/.test(comment.body ?? ''),
  );
  return {
    status: result.status,
    stdout: result.stdout ?? '',
    stderr: result.stderr ?? '',
    calls,
    mutations: calls.split('\n').filter((line) => / --method (PATCH|POST) /.test(line)),
    // mobile 게이트는 canonical marker가 정확히 1개이고 그것이 exact여야 인정한다.
    authorized: canonical.length === 1 && canonical[0].body === markerFor(head),
  };
};

test('marker 재발행은 코디네이터 기록이 있는 base 갱신 병합 커밋에만 적용된다', async () => {
  const workflow = await readFile(workflowUrl, 'utf8');
  const previous = 'b'.repeat(40);
  const head = 'c'.repeat(40);
  const mainParent = 'd'.repeat(40);
  const other = 'e'.repeat(40);
  const markerComment = { id: 99, body: markerFor(previous), user: actionsBotUser };
  const record = { id: 100, body: recordFor(previous), user: actionsBotUser };
  const base = {
    head,
    comments: [markerComment, record],
    reviews: [discoveryReview(previous)],
    commits: [{ sha: previous }, { sha: head }],
    headCommit: { sha: head, parents: [{ sha: previous }, { sha: mainParent }] },
    compare: { status: 'ahead' },
  };

  for (const status of ['ahead', 'identical']) {
    const reissued = runMarkerSync(workflow, { ...base, compare: { status } });
    assert.equal(reissued.status, 0, reissued.stderr);
    assert.deepEqual(
      reissued.mutations,
      [`TOKEN=github-token gh api --method PATCH repos/o/r/issues/comments/99 -f body=${markerFor(head)}`],
    );
    assert.match(reissued.calls, new RegExp(`gh api repos/o/r/compare/${mainParent}\\.\\.\\.main `));
    assert.equal(reissued.authorized, true, 'the patched marker must replace the old one so the strict gate sees exactly one');
  }

  for (const [label, options] of [
    ['first parent differs from the marker head', { headCommit: { sha: head, parents: [{ sha: other }, { sha: mainParent }] } }],
    ['single-parent session push', { headCommit: { sha: head, parents: [{ sha: previous }] } }],
    ['octopus merge', { headCommit: { sha: head, parents: [{ sha: previous }, { sha: mainParent }, { sha: other }] } }],
    ['malformed parent', { headCommit: { sha: head, parents: [{ sha: previous }, { sha: 'not-a-sha' }] } }],
    ['second parent behind main', { compare: { status: 'behind' } }],
    ['second parent diverged from main', { compare: { status: 'diverged' } }],
    ['commit lookup failure', { headCommit: '__FAIL__' }],
    ['compare lookup failure', { compare: '__FAIL__' }],
  ]) {
    const kept = runMarkerSync(workflow, { ...base, ...options });
    assert.equal(kept.status, 0, `${label}: ${kept.stderr}`);
    assert.match(kept.stdout, /SYNC_RETURNED/);
    assert.deepEqual(kept.mutations, [], `${label} must not reissue`);
    assert.equal(kept.authorized, false);
  }

  // 코디네이터 기록이 없거나 어긋나면 조회 전에 걸러진다(세션이 만든 병합 커밋).
  for (const [label, comments] of [
    ['no base-update record', [markerComment]],
    ['record for another head', [markerComment, { ...record, body: recordFor(other) }]],
    ['forged record author', [markerComment, { ...record, user: { ...actionsBotUser, id: 1 } }]],
    ['duplicated records', [markerComment, record, { ...record, id: 101 }]],
  ]) {
    const kept = runMarkerSync(workflow, { ...base, comments });
    assert.equal(kept.status, 0, `${label}: ${kept.stderr}`);
    assert.equal(kept.calls, '', `${label} must not reissue or look up anything`);
    assert.equal(kept.authorized, false);
  }

  const current = runMarkerSync(workflow, { ...base, comments: [{ ...markerComment, body: markerFor(head) }] });
  assert.equal(current.calls, '', 'an exact-head marker needs no API call');
  assert.equal(current.authorized, true);

  const duplicated = runMarkerSync(workflow, {
    ...base,
    comments: [markerComment, { ...markerComment, id: 98, body: markerFor(other) }, record],
  });
  assert.equal(duplicated.calls, '', 'ambiguous markers must not be touched');
  assert.equal(duplicated.authorized, false);

  for (const mutation of ['fail', 'foreign']) {
    const failed = runMarkerSync(workflow, { ...base, mutation });
    assert.equal(failed.status, 0, `${mutation}: ${failed.stderr}`);
    assert.equal(failed.mutations.length, 1, `${mutation} must not retry`);
    assert.equal(failed.authorized, false);
    assert.match(failed.stdout, /::warning::PR #85: authorization marker/);
    assert.doesNotMatch(failed.stdout, /now covers/);
  }
});

test('marker 복구는 marker가 없고 게이트 정의의 discovery가 있으며 라벨 시점 이전 head일 때만 게시한다', async () => {
  const workflow = await readFile(workflowUrl, 'utf8');
  const previous = 'b'.repeat(40);
  const head = 'c'.repeat(40);
  const outside = 'f'.repeat(40);
  const base = {
    head,
    comments: [],
    reviews: [discoveryReview(previous)],
    commits: [committedAt(previous, '2026-09-29T00:00:00Z'), committedAt(head, '2026-09-29T01:00:00Z')],
    events: [[labeledAt('2026-09-29T02:00:00Z')]],
  };
  const posted = [`TOKEN=github-token gh api --method POST repos/o/r/issues/85/comments -f body=${markerFor(head)}`];
  const hundred = (event) => Array.from({ length: 100 }, () => event);

  for (const [label, options] of [
    ['CodeRabbit discovery on an earlier PR commit', {}],
    ['CodeRabbit discovery on current head', { reviews: [discoveryReview(head)] }],
    ['spoofed marker is not canonical', { comments: [{ id: 7, body: markerFor(previous), user: { ...actionsBotUser, id: 1 } }] }],
    ['head committed at the label time', { events: [[labeledAt('2026-09-29T01:00:00Z')]] }],
    ['relabel after the head', { events: [[labeledAt('2026-09-28T00:00:00Z'), labeledAt('2026-09-29T02:00:00Z')]] }],
    ['force push before the label', { events: [[{ event: 'head_ref_force_pushed', created_at: '2026-09-29T01:30:00Z' }, labeledAt('2026-09-29T02:00:00Z')]] }],
    ['a full first page followed by an empty page', { events: [hundred(labeledAt('2026-09-29T02:00:00Z')), []] }],
  ]) {
    const recovered = runMarkerSync(workflow, { ...base, ...options });
    assert.equal(recovered.status, 0, `${label}: ${recovered.stderr}`);
    assert.deepEqual(recovered.mutations, posted, `${label} must recover the labeled head`);
    assert.equal(recovered.authorized, true, `${label} must authorize the current head in this run`);
  }

  for (const [label, options] of [
    ['no review', { reviews: [] }],
    ['approval only', { reviews: [pstackReview(head, head, 0, { state: 'APPROVED', body: '' })] }],
    ['non-canonical comment review', { reviews: [pstackReview(head, head, 0, { body: 'looks fine' })] }],
    ['pstack-interrogate review on current head', { reviews: [pstackReview(head, head, 0)] }],
    ['pstack-interrogate act-on>0', { reviews: [pstackReview(head, head, 1)] }],
    ['pstack-interrogate on previous head', { reviews: [pstackReview(previous, previous, 0)] }],
    ['pstack-interrogate marker head mismatch', { reviews: [pstackReview(head, previous, 0)] }],
    ['retired Aquila marker', { reviews: [pstackReview(head, head, 0, { body: `**Actionable comments posted: 0**\n${AQUILA_UNIVERSAL_MARKER}` })] }],
    ['discovery outside the PR commit set', { reviews: [discoveryReview(outside)] }],
    ['pstack-interrogate head outside the PR commit set', { reviews: [pstackReview(outside, outside, 0)], head: outside }],
    ['untrusted pstack-interrogate author', { reviews: [pstackReview(head, head, 0, { author_association: 'NONE' })] }],
    ['CodeRabbit impersonation', { reviews: [discoveryReview(head, { user: { login: 'coderabbitai[bot]', id: 1, type: 'Bot' } })] }],
  ]) {
    const kept = runMarkerSync(workflow, { ...base, ...options });
    assert.equal(kept.status, 0, `${label}: ${kept.stderr}`);
    assert.equal(kept.calls, '', `${label} must not read events or post a marker`);
    assert.equal(kept.authorized, false);
  }

  for (const [label, options] of [
    ['head committed after the latest automerge label', { commits: [committedAt(previous, '2026-09-29T00:00:00Z'), committedAt(head, '2026-09-29T03:00:00Z')] }],
    ['events lookup failure', { events: ['__FAIL__'] }],
    ['no events at all', { events: [[]] }],
    ['only other label events', { events: [[labeledAt('2026-09-29T02:00:00Z', 'ready')]] }],
    ['force push after the label', { events: [[labeledAt('2026-09-29T02:00:00Z'), { event: 'head_ref_force_pushed', created_at: '2026-09-29T02:30:00Z' }]] }],
    ['unparseable label time', { events: [[labeledAt('yesterday')]] }],
    ['head without a committer date', { commits: [committedAt(previous, '2026-09-29T00:00:00Z'), { sha: head }] }],
    ['event history beyond the bounded read', { events: [hundred(labeledAt('2026-09-29T02:00:00Z')), [labeledAt('2026-09-29T02:00:00Z')]] }],
  ]) {
    const kept = runMarkerSync(workflow, { ...base, ...options });
    assert.equal(kept.status, 0, `${label}: ${kept.stderr}`);
    assert.match(kept.stdout, /SYNC_RETURNED/);
    assert.deepEqual(kept.mutations, [], `${label} must not recover a marker`);
    assert.equal(kept.authorized, false);
  }

  const failed = runMarkerSync(workflow, { ...base, mutation: 'fail' });
  assert.equal(failed.mutations.length, 1);
  assert.equal(failed.authorized, false, 'a failed recovery must not authorize the head');
});

test('marker 동기화의 discovery 판정은 리뷰 게이트와 같은 정의를 쓰고 github.token만 쓴다', async () => {
  const workflow = await readFile(workflowUrl, 'utf8');
  const sync = workflow.match(MARKER_SYNC_RE)?.[1];
  assert.ok(sync, 'authorization marker sync must stay testable');
  const { body: reviewJqDefs } = extractReviewJqDefs(workflow);
  const gateBody = workflow.match(/# frozen-discovery-review-filter-begin\n([\s\S]*?)\n\s+# review-state-filter-end/)?.[1];
  assert.ok(gateBody, 'review gate must stay testable');
  const gate = `${reviewJqDefs}\n${gateBody}`;
  const normalize = (text) => text.replace(/\s+/g, ' ').trim();
  for (const name of ['is_coderabbit', 'is_frozen_discovery']) {
    const definition = (source) => source.match(new RegExp(`def ${name}:[\\s\\S]*?;\\n`))?.[0];
    assert.ok(definition(gate), `gate must define ${name}`);
    assert.equal(normalize(definition(sync) ?? ''), normalize(definition(gate)), `marker sync ${name} must match the review gate`);
  }
  assert.doesNotMatch(
    sync,
    /is_trusted_human|pstack-interrogate/,
    'marker sync must only recover frozen discovery reviews and not duplicate pstack-interrogate logic',
  );
  assert.ok(
    normalize(sync).includes(
      normalize('any($frozen[]; ((.commit_id) as $review_head | $commit_shas | index($review_head) != null))'),
    ),
    'recovery must use the gate frozen discovery commit-set clause',
  );
  assert.doesNotMatch(sync, /MERGE_GH_TOKEN/);
  const loop = workflow.slice(workflow.indexOf('while IFS= read -r pr; do'));
  const syncAt = loop.indexOf('\n            sync_authorization_marker\n');
  assert.ok(syncAt > loop.indexOf('if ! comments="$(bounded_issue_comments)"; then'), 'sync must follow the comment read');
  assert.ok(syncAt < loop.indexOf('comments_slim="$('), 'sync must precede the slim projection and the gate');
});

// 큐 루프 전체를 돌리는 하네스. PR별 head·comments·reviews·commits·events·commit·compare 픽스처를 받는다.
const runSyncQueue = (queueLoop, prs, { hasPat = false } = {}) => {
  const dir = mkdtempSync(join(tmpdir(), 'automerge-sync-queue-'));
  const log = join(dir, 'gh.log');
  for (const pr of prs) {
    const head = pr.head;
    writeFileSync(join(dir, `pr-${pr.number}.json`), JSON.stringify({
      state: 'OPEN', isDraft: false, baseRefName: 'main', labels: [{ name: 'automerge' }],
      headRefOid: head, mergeStateStatus: pr.mergeStateStatus,
    }));
    writeFileSync(join(dir, `reviews-${pr.number}.json`), JSON.stringify(pr.reviews));
    writeFileSync(join(dir, `commits-${pr.number}.json`), JSON.stringify(pr.commits));
    writeFileSync(join(dir, `comments-${pr.number}.json`), JSON.stringify(pr.comments));
    for (const [page, events] of (pr.events ?? []).entries()) {
      writeFileSync(join(dir, `events-${pr.number}-${page + 1}.json`), JSON.stringify(events));
    }
    if (pr.headParents) {
      writeFileSync(join(dir, `commit-${head}.json`), JSON.stringify({ sha: head, parents: pr.headParents.map((sha) => ({ sha })) }));
    }
    for (const [baseSha, status] of Object.entries(pr.compare ?? {})) {
      writeFileSync(join(dir, `compare-${baseSha}.json`), JSON.stringify({ status }));
    }
    writeFileSync(join(dir, `threads-${pr.number}.json`), JSON.stringify({
      data: { repository: { pullRequest: { reviewThreads: { nodes: [], pageInfo: { hasNextPage: false } } } } },
    }));
    writeFileSync(join(dir, `checks-${head}.json`), JSON.stringify([
      { check_runs: [{ id: 1, name: 'Required CI', conclusion: 'success', started_at: '2026-08-01T00:00:00Z' }] },
    ]));
    writeFileSync(join(dir, `statuses-${head}.json`), JSON.stringify([[]]));
  }
  const script = [
    'set -euo pipefail',
    `GH_LOG=${JSON.stringify(log)}`,
    `FIX=${JSON.stringify(dir)}`,
    ': > "$GH_LOG"',
    'gh() {',
    `  printf '%s\\n' "gh $*" >> "$GH_LOG"`,
    '  local all="$*"',
    '  case "$all" in',
    `    "pr list"*) printf '%s\\n' ${JSON.stringify(JSON.stringify(prs.map((p) => p.number)))} ;;`,
    `    "api --method PUT repos/o/r/pulls/"*"/update-branch "*) printf 'TOKEN=%s\\n' "$GH_TOKEN" >> "$GH_LOG"; printf '%s\\n' '{"message":"Updating pull request branch."}' ;;`,
    `    "api --method PATCH repos/o/r/issues/comments/"*|"api --method POST repos/o/r/issues/"*"/comments "*) printf 'TOKEN=%s\\n' "$GH_TOKEN" >> "$GH_LOG"; id=77; [[ "$all" == *"issues/comments/"* ]] && { id="\${all#*issues/comments/}"; id="\${id%% *}"; }; jq -nc --argjson id "$id" --arg body "\${all#*body=}" '{id: $id, body: $body, user: {login: "github-actions[bot]", id: 41898282, type: "Bot"}}' ;;`,
    '    "api repos/o/r/commits/"*) h="${all#api repos/o/r/commits/}"; [[ -f "$FIX/commit-$h.json" ]] || return 1; cat "$FIX/commit-$h.json" ;;',
    '    "api repos/o/r/compare/"*) b="${all#api repos/o/r/compare/}"; b="${b%%...*}"; [[ -f "$FIX/compare-$b.json" ]] || return 1; jq -r .status "$FIX/compare-$b.json" ;;',
    '    *issues/*/events*) n="${all#*issues/}"; n="${n%%/events*}"; page="${all##*page=}"; [[ -f "$FIX/events-$n-$page.json" ]] || return 1; cat "$FIX/events-$n-$page.json" ;;',
    '    "pr view "*) set -- $all; cat "$FIX/pr-$3.json" ;;',
    '    *pulls/*/reviews*) n="${all#*pulls/}"; n="${n%%/reviews*}"; cat "$FIX/reviews-$n.json" ;;',
    '    *pulls/*/commits*) n="${all#*pulls/}"; n="${n%%/commits*}"; cat "$FIX/commits-$n.json" ;;',
    '    *issues/*/comments*) n="${all#*issues/}"; n="${n%%/comments*}"; cat "$FIX/comments-$n.json" ;;',
    '    *graphql*) n="${all#*number=}"; n="${n%% *}"; cat "$FIX/threads-$n.json" ;;',
    '    *check-runs*) h="${all#*commits/}"; h="${h%%/check-runs*}"; cat "$FIX/checks-$h.json" ;;',
    '    *statuses*) h="${all#*commits/}"; h="${h%%/statuses*}"; cat "$FIX/statuses-$h.json" ;;',
    '    "pr merge"*) ;;',
    `    *) printf 'unstubbed gh call: %s\\n' "$all" >&2; return 1 ;;`,
    '  esac',
    '}',
    'repo=o/r',
    'owner=o',
    'name=r',
    'GH_TOKEN=github-token',
    'MERGE_GH_TOKEN=merge-token',
    `HAS_AUTOMERGE_PAT=${hasPat}`,
    `required='[{"context":"Required CI","integration_id":null}]'`,
    'bounded_pr_reviews() { gh api "repos/${repo}/pulls/${pr}/reviews?per_page=100&page=1"; }',
    'bounded_pr_commits() { gh api "repos/${repo}/pulls/${pr}/commits?per_page=100&page=1"; }',
    'bounded_issue_comments() { gh api "repos/${repo}/issues/${pr}/comments?per_page=100&page=1"; }',
    'candidates="$(gh pr list)"',
    queueLoop.replace(/^ {10}/gm, ''),
  ].join('\n');
  const result = spawnSync('bash', ['-c', script], { encoding: 'utf8' });
  const calls = existsSync(log) ? readFileSync(log, 'utf8') : '';
  const merged = calls.match(/gh pr merge --squash --auto (\d+) --repo/)?.[1];
  return { status: result.status, mergedPr: merged ? Number(merged) : null, calls, stdout: result.stdout, stderr: result.stderr };
};

test('코디네이터 base 갱신 기록 뒤 다음 실행은 marker를 재발행해 병합하고, 세션 병합 커밋·라벨 이후 head는 승인하지 않는다', async () => {
  const workflow = await readFile(workflowUrl, 'utf8');
  const queueLoop = workflow.match(/# queue-loop-begin\n([\s\S]*?)\n\s+# queue-loop-end/)?.[1];
  assert.ok(queueLoop, 'queue loop must stay testable');
  const previous = 'b'.repeat(40);
  const head = 'c'.repeat(40);
  const mainParent = 'd'.repeat(40);
  const markerComment = { id: 99, body: markerFor(previous), user: actionsBotUser };

  // 1차 실행: 게이트를 통과한 BEHIND 후보(head P)를 PAT로 갱신하고 github.token으로 기록한다.
  const requested = runSyncQueue(queueLoop, [{
    number: 1, head: previous, mergeStateStatus: 'BEHIND',
    comments: [markerComment], reviews: [discoveryReview(previous)], commits: [{ sha: previous }],
  }], { hasPat: true });
  assert.equal(requested.status, 0, requested.stderr);
  assert.equal(requested.mergedPr, null);
  assert.match(requested.calls, new RegExp(`update-branch -f expected_head_sha=${previous}\\nTOKEN=merge-token\\n`));
  const recordBody = requested.calls.match(
    /gh api --method POST repos\/o\/r\/issues\/1\/comments -f body=(<!-- Automerge base update requested: [0-9a-f]{40} -->)\nTOKEN=github-token\n/,
  )?.[1];
  assert.equal(recordBody, recordFor(previous), 'the accepted base update must be recorded for head P');

  // 2차 실행: GitHub이 만든 병합 커밋 H(첫 부모 P)가 head다. 기록으로 marker를 재발행하고 병합한다.
  const candidate = {
    number: 1, head, mergeStateStatus: 'CLEAN',
    comments: [markerComment, { id: 100, body: recordBody, user: actionsBotUser }],
    reviews: [discoveryReview(previous)],
    commits: [{ sha: previous }, { sha: head }],
    headParents: [previous, mainParent],
    compare: { [mainParent]: 'ahead' },
  };
  const reissued = runSyncQueue(queueLoop, [candidate]);
  assert.equal(reissued.status, 0, reissued.stderr);
  assert.match(reissued.calls, new RegExp(`gh api --method PATCH repos/o/r/issues/comments/99 -f body=${markerFor(head)}\\nTOKEN=github-token\\n`));
  assert.equal(reissued.mergedPr, 1, 'the reissued marker must satisfy the unchanged review gate in the same run');

  const sessionMerge = runSyncQueue(queueLoop, [{ ...candidate, comments: [markerComment] }]);
  assert.equal(sessionMerge.status, 0, sessionMerge.stderr);
  assert.doesNotMatch(sessionMerge.calls, /--method (PATCH|POST)/);
  assert.equal(sessionMerge.mergedPr, null, 'a session-pushed merge commit must wait for a new label authorization');

  const recovery = {
    ...candidate,
    comments: [],
    headParents: undefined,
    compare: undefined,
    commits: [committedAt(previous, '2026-09-29T00:00:00Z'), committedAt(head, '2026-09-29T01:00:00Z')],
  };
  const pushedAfterLabel = runSyncQueue(queueLoop, [{ ...recovery, events: [[labeledAt('2026-09-29T00:30:00Z')]] }]);
  assert.equal(pushedAfterLabel.status, 0, pushedAfterLabel.stderr);
  assert.doesNotMatch(pushedAfterLabel.calls, /--method (PATCH|POST)/, 'a head pushed after the label must not be recovered');
  assert.equal(pushedAfterLabel.mergedPr, null);

  const recovered = runSyncQueue(queueLoop, [{ ...recovery, events: [[labeledAt('2026-09-29T02:00:00Z')]] }]);
  assert.equal(recovered.status, 0, recovered.stderr);
  assert.match(recovered.calls, new RegExp(`gh api --method POST repos/o/r/issues/1/comments -f body=${markerFor(head)}\\nTOKEN=github-token\\n`));
  assert.equal(recovered.mergedPr, 1, 'a recovered marker must satisfy the unchanged review gate in the same run');

  for (const [label, prComments] of [
    ['without authorization marker', []],
    ['with labeled exact-head marker', [{ id: 55, body: markerFor(head), user: actionsBotUser }]],
  ]) {
    const behindPstack = runSyncQueue(
      queueLoop,
      [
        {
          number: 1,
          head,
          mergeStateStatus: 'BEHIND',
          comments: prComments,
          reviews: [pstackReview(head, head, 0)],
          commits: [committedAt(head, '2026-09-29T01:00:00Z')],
          events: [[labeledAt('2026-09-29T02:00:00Z')]],
        },
        {
          number: 2,
          head: previous,
          mergeStateStatus: 'CLEAN',
          comments: [],
          reviews: [pstackReview(previous, previous, 0)],
          commits: [{ sha: previous }],
        },
      ],
      { hasPat: true },
    );
    assert.equal(behindPstack.status, 0, `${label}: ${behindPstack.stderr}`);
    assert.doesNotMatch(
      behindPstack.calls,
      /update-branch|--method (POST|PATCH)/,
      `pstack-interrogate BEHIND PR (${label}) must neither recover a marker nor request update-branch`,
    );
    assert.equal(
      behindPstack.mergedPr,
      2,
      `pstack-interrogate BEHIND PR (${label}) must be skipped so later ready PRs still merge`,
    );
  }
});

// #3036: 큐를 다시 깨울 이벤트가 오지 않는 공백을 schedule tick이 메운다. 한 run이 후보를 일시적 상태(대기 중 check)로
// 읽고 건너뛰면 그 상태가 풀려도 이 워크플로가 구독하는 이벤트는 나오지 않는다(backend 2026-10-22 #539·#542, 110분 정지).
// 빈 큐 tick은 checkout 없이 목록 조회 한 번으로 끝나야 한다.
const COORDINATE_IF =
  "if: ${{ !cancelled() && (github.event_name != 'schedule' || needs.queue-probe.outputs.labeled == 'true') && (github.event_name != 'pull_request_target' || github.event.label.name == 'automerge') }}";
const PROBE_JOB_RE = /\n {2}queue-probe:\n([\s\S]*?)\n {2}coordinate:\n/;
const COORDINATE_HEAD_RE = /\n {2}coordinate:(\n[\s\S]*?)\n {4}steps:\n/;

const scheduleMinutesOf = (workflow) => {
  const cron = workflow.match(/\n {2}schedule:\n {4}- cron: "([^"]+)"\n/)?.[1];
  assert.ok(cron, 'schedule cron trigger is missing');
  const [minute, ...rest] = cron.split(' ');
  assert.deepEqual(rest, ['*', '*', '*', '*'], 'the tick must fire every hour of every day');
  return minute.split(',').map(Number);
};

const runQueueProbe = (workflow, { listOutput = '0', listFails = false } = {}) => {
  const job = workflow.match(PROBE_JOB_RE)?.[1];
  assert.ok(job, 'queue-probe job must precede coordinate');
  const script = job.match(/\n {8}run: \|\n([\s\S]*)$/)?.[1];
  assert.ok(script, 'queue-probe must have one run block');
  for (const line of script.split('\n').filter((l) => l.trim() !== '')) {
    assert.ok(line.startsWith('          '), `probe run line escapes the YAML block scalar: ${line.slice(0, 48)}`);
  }
  const dir = mkdtempSync(join(tmpdir(), 'automerge-probe-'));
  const log = join(dir, 'gh.log');
  const output = join(dir, 'output');
  const result = spawnSync(
    'bash',
    [
      '-c',
      [
        `GH_LOG=${JSON.stringify(log)}`,
        `GITHUB_OUTPUT=${JSON.stringify(output)}`,
        'GITHUB_REPOSITORY=o/r',
        ': > "$GH_LOG"; : > "$GITHUB_OUTPUT"',
        'gh() {',
        '  printf "%s\\n" "gh $*" >> "$GH_LOG"',
        listFails ? '  return 1' : `  printf "%s\\n" ${JSON.stringify(listOutput)}`,
        '}',
        script.replace(/^ {10}/gm, ''),
      ].join('\n'),
    ],
    { encoding: 'utf8' },
  );
  return {
    status: result.status,
    output: readFileSync(output, 'utf8'),
    calls: readFileSync(log, 'utf8').split('\n').filter(Boolean),
  };
};

test('schedule tick이 이벤트 없이도 큐를 다시 판정하고 빈 큐에서는 목록 조회 한 번으로 끝난다', async () => {
  const workflow = await readFile(workflowUrl, 'utf8');

  const minutes = scheduleMinutesOf(workflow);
  assert.ok(minutes.every((m) => Number.isInteger(m) && m > 0 && m < 60), 'tick minutes must avoid the top of the hour');
  const sorted = [...minutes].sort((a, b) => a - b);
  const gaps = sorted.map((m, i) => (i + 1 < sorted.length ? sorted[i + 1] : sorted[0] + 60) - m);
  assert.ok(Math.max(...gaps) <= 15, `tick interval must stay within 15 minutes: ${gaps}`);

  const probe = workflow.match(PROBE_JOB_RE)?.[1] ?? '';
  assert.match(probe, /\n {4}if: github\.event_name == 'schedule'\n/);
  assert.match(probe, /\n {4}permissions:\n {6}pull-requests: read\n {4}outputs:/);
  assert.doesNotMatch(probe, /uses:/, 'the probe must not check out or call actions');

  const idle = runQueueProbe(workflow, { listOutput: '0' });
  assert.equal(idle.status, 0, idle.stderr);
  assert.equal(idle.output, 'labeled=false\n');
  assert.equal(idle.calls.length, 1);
  assert.match(idle.calls[0], /^gh pr list --repo o\/r --base main --state open --label automerge --draft=false --limit 1 /);

  assert.equal(runQueueProbe(workflow, { listOutput: '1' }).output, 'labeled=true\n');

  for (const broken of [{ listFails: true }, { listOutput: 'oops' }]) {
    const result = runQueueProbe(workflow, broken);
    assert.notEqual(result.status, 0, 'an unreadable queue must fail the probe, not report it empty');
    assert.equal(result.output, '');
  }
});

test('coordinate는 schedule에서 라벨 PR이 있을 때만 돌고 동시성 그룹은 coordinate job만 점유한다', async () => {
  const workflow = await readFile(workflowUrl, 'utf8');
  const head = workflow.match(COORDINATE_HEAD_RE)?.[1] ?? '';

  assert.match(head, /\n {4}needs: queue-probe\n/);
  // 이 if를 이벤트별로 평가해 볼 수 있는 평가기가 이 저장소에 없다. 첫 &&가 ||로 바뀌면 probe가 실패하거나 라벨 PR이 없다고 답해도
  // schedule tick이 coordinate를 띄우므로, 식 전체를 한 글자도 다르지 않게 고정한다.
  assert.equal(head.match(/\n {4}(if: .+)\n/)?.[1], COORDINATE_IF, 'coordinate if must match the pinned expression');
  // 빈 큐 tick이 그룹에 들어가면 대기 중인 라벨 run을 밀어낼 수 있다. 그룹은 coordinate job에만 둔다.
  assert.match(head, /\n {4}concurrency:\n {6}group: automerge-queue\n {6}cancel-in-progress: false\n/);
  assert.doesNotMatch(workflow, /^concurrency:/m);
});

test('모든 PR 템플릿이 현재 head의 pstack interrogate 단일 마커 계약을 안내하고 은퇴한 폴백 문구를 남기지 않는다', async () => {
  const expectedLine =
    '- [ ] 현재 head에 대한 `pstack` `interrogate` Review(`<!-- pstack-interrogate head=<40자 sha> act-on=0 -->`)를 단일 PR review로 게시했습니다.';
  for (const url of prTemplateUrls) {
    const content = await readFile(url, 'utf8');
    assert.ok(content.includes(expectedLine), `${url.pathname} must contain the pstack interrogate checklist item`);
    assert.doesNotMatch(
      content,
      /aquila-review|Codex|폴백 리뷰/i,
      `${url.pathname} must not reference retired fallback review wording`,
    );
  }

  const closureSource = await readFile(closureModuleUrl, 'utf8');
  assert.doesNotMatch(closureSource, /\breadFileSync\b/, 'verify-automerge-review-closure.mjs must not keep unused readFileSync import');
});

test('verifyAutomergeReviewClosure helpers enforce trusted human roles, code stripping, and chronological review states', () => {
  const head = 'a'.repeat(40);
  const prev = 'b'.repeat(40);
  const out = 'e'.repeat(40);
  const mkHuman = (id, state, commitId = head, body = '', overrides = {}) => ({
    id,
    state,
    commit_id: commitId,
    author_association: 'OWNER',
    submitted_at: `2026-10-31T00:0${id}:00Z`,
    body,
    user: { login: 'reviewer-one', id: 1, type: 'User' },
    ...overrides,
  });
  const mkBody = (sha = head, actOn = 0) => `### Intent\nCheck.\n\n<!-- pstack-interrogate head=${sha} act-on=${actOn} -->`;

  for (const role of ['OWNER', 'MEMBER', 'COLLABORATOR']) {
    assert.equal(isTrustedHuman(mkHuman(1, 'COMMENTED', head, '', { author_association: role })), true);
  }
  for (const overrides of [
    { user: null },
    { user: { login: '', type: 'User' } },
    { user: { login: 'bot[bot]', type: 'Bot' } },
    { author_association: 'CONTRIBUTOR' },
    { author_association: 'NONE' },
  ]) {
    assert.equal(isTrustedHuman(mkHuman(1, 'COMMENTED', head, '', overrides)), false);
  }

  const withCodeExamples = mkHuman(
    1,
    'COMMENTED',
    head,
    [
      `Inline \`<!-- pstack-interrogate head=${prev} act-on=2 -->\` example.`,
      '```html',
      `<!-- pstack-interrogate head=${head} act-on=1 -->`,
      '```',
      mkBody(head, 0),
    ].join('\n'),
  );
  assert.equal(hasPstackInterrogateMarker(withCodeExamples), true);
  assert.equal(isCanonicalPstackInterrogate(withCodeExamples, head), true);
  assert.equal(typeof stripMarkdownCode('```x\ny\n```'), 'string');

  const codeOnly = mkHuman(2, 'COMMENTED', head, `\`\`\`\n<!-- pstack-interrogate head=${head} act-on=0 -->\n\`\`\``);
  assert.equal(hasPstackInterrogateMarker(codeOnly), false);
  assert.equal(isCanonicalPstackInterrogate(codeOnly, head), false);

  assert.throws(
    () =>
      verifyAutomergeReviewClosure({
        head,
        reviews: [mkHuman(1, 'COMMENTED', head, mkBody(head, 0)), mkHuman(2, 'COMMENTED', head, mkBody(head, 1))],
        comments: [],
      }),
    /ACT_ON/,
  );
  assert.equal(
    verifyAutomergeReviewClosure({
      head,
      reviews: [mkHuman(1, 'CHANGES_REQUESTED', prev, 'fix'), mkHuman(2, 'COMMENTED', head, mkBody(head, 0))],
      comments: [],
    }).ok,
    true,
  );
  assert.throws(
    () =>
      verifyAutomergeReviewClosure({
        head,
        reviews: [
          mkHuman(1, 'CHANGES_REQUESTED', head, 'fix'),
          mkHuman(2, 'CHANGES_REQUESTED', prev, 'older commit cr'),
          mkHuman(3, 'APPROVED', prev, ''),
          mkHuman(4, 'COMMENTED', head, mkBody(head, 0), { user: { login: 'reviewer-two', id: 2, type: 'User' } }),
        ],
        currentCommits: [{ sha: prev, patch: '+x\n' }, { sha: head, patch: '+x\n' }],
      }),
    /active CHANGES_REQUESTED remains from reviewer-one/,
  );
  assert.equal(
    verifyAutomergeReviewClosure({
      head,
      reviews: [
        mkHuman(1, 'CHANGES_REQUESTED', out, 'pre-rebase cr'),
        mkHuman(2, 'COMMENTED', '6'.repeat(40), mkBody('6'.repeat(40), 0)),
        mkHuman(3, 'COMMENTED', head, mkBody(head, 0), { user: { login: 'reviewer-two', id: 2, type: 'User' } }),
      ],
      currentCommits: [{ sha: prev, patch: '+x\n' }, { sha: head, patch: '+x\n' }],
    }).ok,
    true,
  );
});

const validateJqAsBindings = (program) => {
  const openToClose = new Map();
  const closeToOpen = new Map();
  const stack = [];
  const chars = [...program];
  const masked = [];
  for (let index = 0; index < chars.length; index += 1) {
    const ch = chars[index];
    if (ch === '"') {
      masked.push(' ');
      index += 1;
      while (index < chars.length && chars[index] !== '"') {
        if (chars[index] === '\\' && index + 1 < chars.length) {
          masked.push(' ', ' ');
          index += 2;
          continue;
        }
        masked.push(' ');
        index += 1;
      }
      if (index >= chars.length) {
        return { ok: false, reason: 'unterminated string literal' };
      }
      masked.push(' ');
      continue;
    }
    if (ch === '#') {
      while (index < chars.length && chars[index] !== '\n') {
        masked.push(' ');
        index += 1;
      }
      if (index < chars.length) masked.push('\n');
      continue;
    }
    if (ch === '(') {
      stack.push(index);
    } else if (ch === ')') {
      const open = stack.pop();
      if (open === undefined) {
        return { ok: false, reason: `unmatched ')' at offset ${index}` };
      }
      openToClose.set(open, index);
      closeToOpen.set(index, open);
    }
    masked.push(ch);
  }
  if (stack.length > 0) {
    return { ok: false, reason: `unclosed '(' at offset ${stack.at(-1)}` };
  }

  const text = masked.join('');
  const prevNonSpace = (from) => {
    let cursor = from;
    while (cursor >= 0 && /\s/.test(text[cursor])) cursor -= 1;
    return cursor;
  };
  const nextNonSpace = (from) => {
    let cursor = from;
    while (cursor < text.length && /\s/.test(text[cursor])) cursor += 1;
    return cursor;
  };

  let nonReduceCount = 0;
  let reduceCount = 0;
  for (const match of text.matchAll(/\bas\s+\$([A-Za-z_][A-Za-z0-9_]*)/g)) {
    const asIndex = match.index;
    const varName = match[1];
    const varEnd = asIndex + match[0].length;
    const afterVar = nextNonSpace(varEnd);
    if (text[afterVar] === '(') {
      const enclosingOpen =
        [...openToClose.entries()]
          .filter(([open, close]) => open < asIndex && close > asIndex)
          .map(([open]) => open)
          .at(-1) ?? -1;
      if (!/\b(?:reduce|foreach)\b/.test(text.slice(enclosingOpen + 1, asIndex))) {
        return { ok: false, reason: `as $${varName} followed by '(' without reduce/foreach` };
      }
      reduceCount += 1;
      continue;
    }
    if (text[afterVar] !== '|') {
      return { ok: false, reason: `as $${varName} must be followed by '|'` };
    }
    const lhsClose = prevNonSpace(asIndex - 1);
    if (text[lhsClose] !== ')') {
      return { ok: false, reason: `as $${varName} LHS must be enclosed in (...)` };
    }
    const lhsOpen = closeToOpen.get(lhsClose);
    if (lhsOpen === undefined || text.slice(lhsOpen + 1, lhsClose).trim() === '') {
      return { ok: false, reason: `as $${varName} has empty LHS (...)` };
    }
    const outerOpen = prevNonSpace(lhsOpen - 1);
    if (text[outerOpen] !== '(') {
      return { ok: false, reason: `as $${varName} must have outer '(' immediately before LHS` };
    }
    const outerClose = openToClose.get(outerOpen);
    if (
      outerClose === undefined ||
      outerClose <= afterVar ||
      text.slice(afterVar + 1, outerClose).trim() === ''
    ) {
      return { ok: false, reason: `as $${varName} outer (...) must enclose a non-empty RHS body` };
    }
    nonReduceCount += 1;
  }
  return { ok: true, nonReduceCount, reduceCount };
};

test('automerge-queue.yml의 모든 비-reduce jq as 바인딩이 ((<lhs>) as $<var> | <body>) 형식을 지키고 jq 컴파일을 통과한다', async () => {
  assert.equal(validateJqAsBindings('((.[0]) as $x | $x)').ok, true);
  assert.equal(validateJqAsBindings('reduce .[] as $x ({}; .)').ok, true);
  for (const broken of [
    '.[0] as $x | $x',
    '($files | flatten) as $changed | ($changed | length == 1)',
    '(true and ($files | flatten) as $changed | $changed)',
    '((.[0]) as $x) | $x',
  ]) {
    assert.equal(validateJqAsBindings(broken).ok, false, broken);
  }

  const workflow = await readFile(workflowUrl, 'utf8');
  const commentStripped = workflow.replace(/^[ \t]*#.*$/gm, '');
  const totalWorkflowAsBindings = [
    ...commentStripped.matchAll(/\bas\s+\\?\$[A-Za-z_][A-Za-z0-9_]*/g),
  ].length;
  assert.ok(totalWorkflowAsBindings >= 20, 'workflow must contain jq as bindings');

  const { body: reviewJqDefs } = extractReviewJqDefs(workflow);
  let checkedNonReduce = 0;
  let checkedReduce = 0;
  const defsValidation = validateJqAsBindings(reviewJqDefs);
  assert.equal(defsValidation.ok, true, defsValidation.reason);
  checkedNonReduce += defsValidation.nonReduceCount;
  checkedReduce += defsValidation.reduceCount;

  const joinedWorkflow = workflow.replace(/\\\n[ \t]*/g, ' ');
  for (const match of joinedWorkflow.matchAll(
    /(?:--jq\s+|_query=|\bjq\b(?:[^\n']|'[^'\n]*')*?\s+)("\$\{review_jq_defs\}")?'([^']*)'/g,
  )) {
    const usesDefs = Boolean(match[1]);
    const program = match[2];
    const validation = validateJqAsBindings(program);
    assert.equal(
      validation.ok,
      true,
      `jq program violates ((...) as $var | ...) invariant (${validation.reason}):\n${program}`,
    );
    checkedNonReduce += validation.nonReduceCount;
    checkedReduce += validation.reduceCount;

    const fullProgram = usesDefs ? `${reviewJqDefs}\n${program}` : program;
    const args = [
      ...match[0].matchAll(/--(?:arg(?:json)?|slurpfile)\s+([A-Za-z_][A-Za-z0-9_]*)/g),
    ].map((argMatch) => argMatch[1]);
    const compileArgs = [
      '-n',
      ...args.flatMap((name) => ['--arg', name, '']),
      `if false then (${fullProgram}) else true end`,
    ];
    const compiled = spawnSync('jq', compileArgs, { encoding: 'utf8' });
    assert.equal(compiled.status, 0, `jq compile failed: ${compiled.stderr}\n${program}`);
  }
  assert.equal(
    checkedNonReduce + checkedReduce,
    totalWorkflowAsBindings,
    'every jq as binding in automerge-queue.yml must be covered by the structural check',
  );
});
