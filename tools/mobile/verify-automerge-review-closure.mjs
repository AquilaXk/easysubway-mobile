import { createHash } from 'node:crypto';

export const TRUSTED_ROLES = new Set(['OWNER', 'MEMBER', 'COLLABORATOR']);
export const CODERABBIT_LOGIN = 'coderabbitai[bot]';
export const CODERABBIT_ID = 136622811;
export const ACTIONS_BOT_LOGIN = 'github-actions[bot]';
export const ACTIONS_BOT_ID = 41898282;
export const MARKER_PATTERN = /^<!-- Automerge frozen discovery authorization: [0-9a-f]{40} -->$/;

const FENCED_MD_CODE_RE =
  /^ {0,3}(`{3,})[^`\n]*\n[\s\S]*?(?:^ {0,3}\1`*[ \t]*$|(?![\s\S]))|^ {0,3}(~{3,})[^\n]*\n[\s\S]*?(?:^ {0,3}\2~*[ \t]*$|(?![\s\S]))/gm;
const INLINE_MD_CODE_RE = /(?<!`)(`+)(?!`)(?:(?!\n[ \t]*\n)[\s\S])*?(?<!`)\1(?!`)/g;
const PSTACK_MARKER_SCAN_RE = /<!--\s*pstack-interrogate/g;

/**
 * Calculates a canonical whitespace-preserving patch digest.
 * Strips git index blob object ID headers (which naturally change across rebases)
 * while strictly preserving all unified diff whitespace and chunk content.
 */
export function canonicalPatchDigest(patch) {
  if (typeof patch !== 'string') {
    throw new Error('patch must be a string');
  }
  const normalized = patch
    .split('\n')
    .filter((line) => !line.startsWith('index '))
    .join('\n');
  return createHash('sha256').update(normalized, 'utf8').digest('hex');
}

export function isTrustedHuman(review) {
  return (
    TRUSTED_ROLES.has(review?.author_association) &&
    review?.user !== null &&
    typeof review?.user === 'object' &&
    typeof review.user.login === 'string' &&
    review.user.login.length > 0 &&
    review.user.type === 'User'
  );
}

export function isCodeRabbit(review) {
  return (
    review?.author_association === 'NONE' &&
    review?.user !== null &&
    typeof review?.user === 'object' &&
    review.user.login === CODERABBIT_LOGIN &&
    review.user.id === CODERABBIT_ID &&
    review.user.type === 'Bot'
  );
}

export function stripMarkdownCode(text) {
  if (typeof text !== 'string' || text.length === 0) {
    return '';
  }
  return text
    .replace(/\r\n?/g, '\n')
    .replace(FENCED_MD_CODE_RE, ' ')
    .replace(INLINE_MD_CODE_RE, ' ');
}

export function hasPstackInterrogateMarker(review) {
  const clean = stripMarkdownCode(review?.body);
  return (clean.match(PSTACK_MARKER_SCAN_RE) ?? []).length > 0;
}

export function isCanonicalPstackInterrogate(review, head) {
  if (typeof head !== 'string' || !/^[0-9a-f]{40}$/.test(head)) {
    return false;
  }
  if (!isTrustedHuman(review) || review?.state !== 'COMMENTED' || review?.commit_id !== head) {
    return false;
  }
  const clean = stripMarkdownCode(review?.body);
  if ((clean.match(PSTACK_MARKER_SCAN_RE) ?? []).length !== 1) {
    return false;
  }
  const standaloneRe = new RegExp(`^<!-- pstack-interrogate head=${head} act-on=0 -->[ \\t]*$`, 'm');
  return standaloneRe.test(clean);
}

export function isCanonicalMarker(comment) {
  return (
    comment?.user !== null &&
    typeof comment?.user === 'object' &&
    comment.user.login === ACTIONS_BOT_LOGIN &&
    comment.user.id === ACTIONS_BOT_ID &&
    comment.user.type === 'Bot' &&
    typeof comment?.body === 'string' &&
    MARKER_PATTERN.test(comment.body)
  );
}

export function isExactMarker(comment, head) {
  return (
    isCanonicalMarker(comment) &&
    comment.body === `<!-- Automerge frozen discovery authorization: ${head} -->`
  );
}

function parseReviewTimestamp(value) {
  if (!value || typeof value !== 'string') return 0;
  const parsed = Date.parse(value);
  return Number.isFinite(parsed) ? parsed : 0;
}

function posClears(recordedPos, pos) {
  return (pos >= 0 && pos >= recordedPos) || (pos < 0 && recordedPos < 0);
}

function clearPriorActOn(pstack, pos) {
  if (pstack && pstack.kind === 'ACT_ON' && !pstack.current && posClears(pstack.pos, pos)) {
    return null;
  }
  return pstack;
}

export function getActiveReviewStates(reviews, head = null, commitShas = null) {
  const sorted = [...reviews].sort((a, b) => {
    const timeDiff = parseReviewTimestamp(a.submitted_at) - parseReviewTimestamp(b.submitted_at);
    return timeDiff !== 0 ? timeDiff : (a.id || 0) - (b.id || 0);
  });

  const hasCommitList = Array.isArray(commitShas) && commitShas.length > 0;
  const internal = {};
  for (const review of sorted) {
    if (!isTrustedHuman(review) && !isCodeRabbit(review)) {
      continue;
    }
    const login = review.user.login;
    const cur = internal[login] ?? { formal: null, formalPos: -1, pstack: null };
    const pos = hasCommitList
      ? commitShas.indexOf(review.commit_id)
      : head !== null && review.commit_id === head
        ? 1
        : 0;
    const isCurHead = head !== null && review.commit_id === head && pos >= 0;

    if (review.state === 'DISMISSED') {
      if (cur.pstack && cur.pstack.kind === 'ACT_ON') {
        internal[login] = { formal: null, formalPos: -1, pstack: cur.pstack };
      } else {
        delete internal[login];
      }
    } else if (review.state === 'CHANGES_REQUESTED') {
      if (isTrustedHuman(review)) {
        internal[login] = {
          formal: 'CHANGES_REQUESTED',
          formalPos: cur.formal === 'CHANGES_REQUESTED' ? Math.max(cur.formalPos, pos) : pos,
          pstack: cur.pstack?.kind === 'OK' ? null : cur.pstack,
        };
      } else {
        internal[login] = {
          formal: 'UNTRUSTED_CHANGES_REQUESTED',
          formalPos: cur.formal === 'UNTRUSTED_CHANGES_REQUESTED' ? Math.max(cur.formalPos, pos) : pos,
          pstack: cur.pstack,
        };
      }
    } else if (review.state === 'APPROVED') {
      if (isTrustedHuman(review) && pos >= 0) {
        if (isCurHead) {
          internal[login] = { formal: 'APPROVED', formalPos: pos, pstack: null };
        } else if (cur.formal === 'CHANGES_REQUESTED' && !posClears(cur.formalPos, pos)) {
          internal[login] = {
            formal: 'CHANGES_REQUESTED',
            formalPos: cur.formalPos,
            pstack: clearPriorActOn(cur.pstack, pos),
          };
        } else {
          internal[login] = {
            formal: head === null ? 'APPROVED' : 'APPROVED_PRIOR',
            formalPos: pos,
            pstack: clearPriorActOn(cur.pstack, pos),
          };
        }
      } else if (isTrustedHuman(review) && pos < 0) {
        internal[login] = {
          formal: cur.formal === 'CHANGES_REQUESTED' && posClears(cur.formalPos, pos) ? 'COMMENTED' : (cur.formal ?? 'COMMENTED'),
          formalPos: cur.formal === 'CHANGES_REQUESTED' && posClears(cur.formalPos, pos) ? -1 : cur.formalPos,
          pstack: clearPriorActOn(cur.pstack, pos),
        };
      } else if (isCodeRabbit(review) && posClears(cur.formalPos, pos)) {
        internal[login] = {
          formal: cur.formal === 'UNTRUSTED_CHANGES_REQUESTED' ? 'COMMENTED' : (cur.formal ?? 'COMMENTED'),
          formalPos: cur.formal === 'UNTRUSTED_CHANGES_REQUESTED' ? -1 : cur.formalPos,
          pstack: cur.pstack,
        };
      } else {
        internal[login] = { formal: cur.formal ?? 'COMMENTED', formalPos: cur.formalPos, pstack: cur.pstack };
      }
    } else if (review.state === 'COMMENTED') {
      if (isTrustedHuman(review) && hasPstackInterrogateMarker(review)) {
        const targetHead = head ?? review.commit_id;
        if (head === null ? isCanonicalPstackInterrogate(review, targetHead) : isCurHead && isCanonicalPstackInterrogate(review, head)) {
          internal[login] = {
            formal: cur.formal === null || cur.formal === 'CHANGES_REQUESTED' ? 'COMMENTED' : cur.formal,
            formalPos: cur.formal === 'CHANGES_REQUESTED' ? -1 : cur.formalPos,
            pstack: head === null ? null : { kind: 'OK' },
          };
        } else if (head !== null && isCanonicalPstackInterrogate(review, review.commit_id)) {
          internal[login] = {
            formal: cur.formal === 'CHANGES_REQUESTED' && pos < 0 && cur.formalPos < 0 ? 'COMMENTED' : (cur.formal ?? 'COMMENTED'),
            formalPos: cur.formal === 'CHANGES_REQUESTED' && pos < 0 && cur.formalPos < 0 ? -1 : cur.formalPos,
            pstack: clearPriorActOn(cur.pstack, pos),
          };
        } else if (isCurHead) {
          internal[login] = {
            formal: cur.formal === 'APPROVED' ? 'APPROVED_PRIOR' : (cur.formal ?? 'COMMENTED'),
            formalPos: cur.formalPos,
            pstack: { kind: 'ACT_ON', pos, current: true },
          };
        } else {
          internal[login] = {
            formal: cur.formal ?? 'COMMENTED',
            formalPos: cur.formalPos,
            pstack:
              cur.pstack?.kind === 'ACT_ON'
                ? { kind: 'ACT_ON', pos: Math.max(pos, cur.pstack.pos), current: cur.pstack.current }
                : { kind: 'ACT_ON', pos, current: false },
          };
        }
      } else {
        internal[login] = { formal: cur.formal ?? 'COMMENTED', formalPos: cur.formalPos, pstack: cur.pstack };
      }
    } else {
      internal[login] = { formal: review.state, formalPos: cur.formalPos, pstack: cur.pstack };
    }
  }

  const states = {};
  for (const [login, { formal, pstack }] of Object.entries(internal)) {
    if (formal === 'CHANGES_REQUESTED' || formal === 'UNTRUSTED_CHANGES_REQUESTED') {
      states[login] = formal;
    } else if (pstack?.kind === 'ACT_ON') {
      states[login] = pstack.current ? 'ACT_ON_CURRENT' : (head === null ? 'ACT_ON' : 'ACT_ON_PRIOR');
    } else if (formal === 'APPROVED') {
      states[login] = 'APPROVED';
    } else if (pstack?.kind === 'OK') {
      states[login] = 'PSTACK_OK';
    } else if (formal !== null) {
      states[login] = formal;
    }
  }
  return states;
}

export function extractFindings(reviewThreads = []) {
  const inlinePaths = new Set();
  let count = 0;
  for (const thread of reviewThreads) {
    if (thread.path) {
      inlinePaths.add(thread.path);
      count += 1;
    }
  }
  return { findingCount: count, inlineFindingPaths: inlinePaths };
}

export function verifyCommitSeries(reviewedCommits, currentCommits) {
  if (!Array.isArray(reviewedCommits) || reviewedCommits.length === 0) {
    throw new Error('reviewed commit series must be a non-empty array');
  }
  if (!Array.isArray(currentCommits) || currentCommits.length === 0) {
    throw new Error('current commit series must be a non-empty array');
  }

  for (const commit of [...reviewedCommits, ...currentCommits]) {
    if (commit.parents && commit.parents.length > 1) {
      throw new Error(`merge commit detected: ${commit.sha}`);
    }
    if (commit.isMerge) {
      throw new Error(`merge commit detected: ${commit.sha}`);
    }
    if (commit.isEmpty || (typeof commit.patch === 'string' && commit.patch.trim() === '')) {
      throw new Error(`empty commit detected: ${commit.sha}`);
    }
  }

  if (currentCommits.length < reviewedCommits.length) {
    throw new Error('current commit series is shorter than reviewed commit series (missing or squashed commits)');
  }

  const N = reviewedCommits.length;
  const prefix = currentCommits.slice(0, N);

  const isDirectAncestry = prefix.every((c, i) => c.sha === reviewedCommits[i].sha);
  if (isDirectAncestry) {
    return { mode: 'direct-ancestry', closureCommits: currentCommits.slice(N) };
  }

  const isDigestMatch = prefix.every((c, i) => {
    const cDigest = c.patchDigest ?? (c.patch ? canonicalPatchDigest(c.patch) : null);
    const rDigest = reviewedCommits[i].patchDigest ?? (reviewedCommits[i].patch ? canonicalPatchDigest(reviewedCommits[i].patch) : null);
    if (!cDigest || !rDigest) {
      throw new Error(`missing patch evidence for commit comparison at index ${i}`);
    }
    return cDigest === rDigest;
  });

  if (!isDigestMatch) {
    throw new Error('commit series mismatch: reviewed commits were tampered, reordered, squashed, or altered');
  }

  return { mode: 'rebase-canonical-digest', closureCommits: currentCommits.slice(N) };
}

export function verifyClosureDelta({
  findingCount,
  inlineFindingPaths = new Set(),
  selectedTestPaths = new Set(),
  closureFiles = [],
  closureCommits = [],
}) {
  if (findingCount === 0) {
    if (closureFiles.length > 0) {
      throw new Error(`finding 0 requires diff 0, but found ${closureFiles.length} modified files in closure`);
    }
    if (closureCommits.length > 0) {
      const hasNonEmptyCommit = closureCommits.some(
        (c) => (c.patch && c.patch.trim() !== '') || (c.files && c.files.length > 0),
      );
      if (hasNonEmptyCommit) {
        throw new Error('finding 0 requires diff 0, but closure commits contain non-empty changes');
      }
    }
    return;
  }

  const forbiddenPatterns = [
    /^\.github\/workflows\//,
    /^package\.json$/,
    /^package-lock\.json$/,
    /^pubspec\.yaml$/,
    /^pubspec\.lock$/,
  ];

  for (const file of closureFiles) {
    if (file.status && file.status !== 'modified' && file.status !== 'change') {
      throw new Error(`forbidden file status '${file.status}' on path: ${file.filename}`);
    }
    if (file.isBinary) {
      throw new Error(`binary changes forbidden in closure: ${file.filename}`);
    }
    if (file.isSubmodule) {
      throw new Error(`submodule changes forbidden in closure: ${file.filename}`);
    }
    if (file.modeChanged) {
      throw new Error(`mode changes forbidden in closure: ${file.filename}`);
    }
    if (forbiddenPatterns.some((p) => p.test(file.filename))) {
      throw new Error(`protected workflow or dependency file modified in closure: ${file.filename}`);
    }

    const isTest =
      file.filename.startsWith('apps/mobile/test/') ||
      file.filename.startsWith('apps/mobile/integration_test/') ||
      file.filename.endsWith('.test.mjs') ||
      file.filename.endsWith('_test.dart');

    if (isTest) {
      if (!selectedTestPaths.has(file.filename)) {
        throw new Error(`test path outside review-selected test paths: ${file.filename}`);
      }
    } else {
      if (!inlineFindingPaths.has(file.filename)) {
        throw new Error(`production path outside original inline finding paths: ${file.filename}`);
      }
    }
  }
}

export function verifyReviewThreads(reviewThreads) {
  if (!reviewThreads) return;
  const pageInfo = reviewThreads.pageInfo;
  if (pageInfo?.hasNextPage) {
    throw new Error('paginated review threads not allowed (incomplete thread view)');
  }
  const nodes = reviewThreads.nodes ?? (Array.isArray(reviewThreads) ? reviewThreads : []);
  for (const node of nodes) {
    if (!node.isResolved) {
      throw new Error(`unresolved review thread on path ${node.path ?? 'unknown'}`);
    }
  }
}

export function verifyRequiredContexts(requiredContexts, checks = [], statuses = []) {
  if (!Array.isArray(requiredContexts) || requiredContexts.length === 0) return;

  const flattenedChecks = checks.flatMap((c) => (c.check_runs ? c.check_runs : c));
  const flattenedStatuses = statuses.flat();

  for (const required of requiredContexts) {
    const matchingRuns = flattenedChecks.filter(
      (r) =>
        r.name === required.context &&
        (required.integration_id == null || r.app?.id === required.integration_id),
    );
    const matchingStatuses = flattenedStatuses.filter((s) => s.context === required.context);

    if (matchingRuns.length === 0 && matchingStatuses.length === 0) {
      throw new Error(`missing required context: ${required.context}`);
    }

    if (matchingRuns.length > 0) {
      const latest = [...matchingRuns]
        .sort((a, b) => {
          const timeDiff = new Date(a.started_at || 0).getTime() - new Date(b.started_at || 0).getTime();
          return timeDiff !== 0 ? timeDiff : (a.id || 0) - (b.id || 0);
        })
        .at(-1);

      if (latest.conclusion !== 'success') {
        throw new Error(`required check '${required.context}' is not successful (conclusion: ${latest.conclusion})`);
      }
    } else {
      const latest = [...matchingStatuses]
        .sort((a, b) => {
          const timeDiff =
            new Date(a.updated_at || a.created_at || 0).getTime() -
            new Date(b.updated_at || b.created_at || 0).getTime();
          return timeDiff !== 0 ? timeDiff : (a.id || 0) - (b.id || 0);
        })
        .at(-1);

      if (latest.state !== 'success') {
        throw new Error(`required status '${required.context}' is not successful (state: ${latest.state})`);
      }
    }
  }
}

export function verifyAutomergeReviewClosure({
  head,
  reviews = [],
  comments = [],
  reviewThreads = { nodes: [], pageInfo: { hasNextPage: false } },
  currentCommits = [],
  reviewedCommits = null,
  closureFiles = [],
  selectedTestPaths = [],
  requiredContexts = [],
  checks = [],
  statuses = [],
}) {
  if (!head || typeof head !== 'string' || !/^[0-9a-f]{40}$/.test(head)) {
    throw new Error(`invalid head commit SHA: ${head}`);
  }

  const trustedReviews = reviews.filter((r) => isTrustedHuman(r) || isCodeRabbit(r));
  if (trustedReviews.length === 0) {
    throw new Error('no trusted reviews found on pull request');
  }

  const commitShas =
    currentCommits.length > 0
      ? [...(reviewedCommits?.map((c) => c.sha) ?? []), ...currentCommits.map((c) => c.sha)]
      : null;
  const activeStates = getActiveReviewStates(reviews, head, commitShas);
  const activeEntries = Object.entries(activeStates);
  if (activeEntries.length === 0) {
    throw new Error('no active trusted reviews remain on pull request');
  }

  const currentHeadApproved = reviews.some(
    (r) =>
      isTrustedHuman(r) &&
      r.state === 'APPROVED' &&
      r.commit_id === head &&
      activeStates[r.user.login] === 'APPROVED',
  );
  const currentHeadPstackInterrogate = reviews.some(
    (r) =>
      isCanonicalPstackInterrogate(r, head) &&
      (activeStates[r.user.login] === 'PSTACK_OK' || activeStates[r.user.login] === 'APPROVED'),
  );
  const hasCurrentHumanPass = currentHeadApproved || currentHeadPstackInterrogate;

  for (const [reviewer, state] of activeEntries) {
    if (state === 'CHANGES_REQUESTED') {
      throw new Error(`active CHANGES_REQUESTED remains from ${reviewer}`);
    }
    if (state === 'ACT_ON_CURRENT' || (state === 'ACT_ON_PRIOR' && !hasCurrentHumanPass)) {
      throw new Error(`blocking review state '${state}' remains from ${reviewer}`);
    }
    if (
      state !== 'APPROVED' &&
      state !== 'APPROVED_PRIOR' &&
      state !== 'PSTACK_OK' &&
      state !== 'COMMENTED' &&
      state !== 'ACT_ON_PRIOR'
    ) {
      throw new Error(`blocking review state '${state}' remains from ${reviewer}`);
    }
  }

  if (hasCurrentHumanPass) {
    verifyReviewThreads(reviewThreads);
    verifyRequiredContexts(requiredContexts, checks, statuses);
    return {
      ok: true,
      type: currentHeadApproved ? 'current-head-approved' : 'current-head-pstack-interrogate',
    };
  }

  const canonicalMarkers = comments.filter(isCanonicalMarker);
  if (canonicalMarkers.length === 0) {
    throw new Error('missing automerge frozen discovery authorization marker');
  }
  if (canonicalMarkers.length > 1) {
    throw new Error(`multiple canonical markers found: ${canonicalMarkers.length}`);
  }
  if (!isExactMarker(canonicalMarkers[0], head)) {
    throw new Error(`stale or wrong marker for head ${head}: ${canonicalMarkers[0].body}`);
  }

  const eligibleReviews = reviews.filter((r) => {
    if (r.commit_id === head) return false;
    if (r.state === 'DISMISSED') return false;
    if (!Object.hasOwn(activeStates, r.user?.login)) return false;
    if (isTrustedHuman(r) && r.state === 'APPROVED') {
      return activeStates[r.user.login] === 'APPROVED_PRIOR' || activeStates[r.user.login] === 'APPROVED';
    }
    if (isCodeRabbit(r) && r.state === 'COMMENTED') {
      return activeStates[r.user.login] === 'COMMENTED';
    }
    return false;
  });

  if (eligibleReviews.length === 0) {
    throw new Error('no eligible previous-head discovery review found');
  }

  const discoveryReview = [...eligibleReviews]
    .sort((a, b) => {
      const timeDiff = parseReviewTimestamp(a.submitted_at) - parseReviewTimestamp(b.submitted_at);
      return timeDiff !== 0 ? timeDiff : (a.id || 0) - (b.id || 0);
    })
    .at(-1);

  const effectiveReviewed =
    reviewedCommits ??
    (() => {
      const idx = currentCommits.findIndex((c) => c.sha === discoveryReview.commit_id);
      if (idx >= 0) return currentCommits.slice(0, idx + 1);
      throw new Error(`reviewed head ${discoveryReview.commit_id} not found in current commit ancestry`);
    })();

  const { closureCommits } = verifyCommitSeries(effectiveReviewed, currentCommits);

  const threadsArray = reviewThreads?.nodes ?? (Array.isArray(reviewThreads) ? reviewThreads : []);
  const { findingCount, inlineFindingPaths } = extractFindings(threadsArray);

  verifyClosureDelta({
    findingCount,
    inlineFindingPaths,
    selectedTestPaths: new Set(selectedTestPaths),
    closureFiles,
    closureCommits,
  });

  verifyReviewThreads(reviewThreads);
  verifyRequiredContexts(requiredContexts, checks, statuses);

  return { ok: true, type: 'reused-discovery-review', discoveryReviewId: discoveryReview.id };
}
