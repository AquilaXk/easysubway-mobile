import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';

export const TRUSTED_ROLES = new Set(['OWNER', 'MEMBER', 'COLLABORATOR']);
export const CODERABBIT_LOGIN = 'coderabbitai[bot]';
export const CODERABBIT_ID = 136622811;
export const ACTIONS_BOT_LOGIN = 'github-actions[bot]';
export const ACTIONS_BOT_ID = 41898282;
export const MARKER_PATTERN = /^<!-- Automerge frozen discovery authorization: [0-9a-f]{40} -->$/;

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
  return TRUSTED_ROLES.has(review?.author_association);
}

export function isCodeRabbit(review) {
  return (
    review?.author_association === 'NONE' &&
    review?.user?.login === CODERABBIT_LOGIN &&
    review?.user?.id === CODERABBIT_ID &&
    review?.user?.type === 'Bot'
  );
}

export function isCanonicalCodexFallback(review) {
  const body = review?.body ?? '';
  return (
    isTrustedHuman(review) &&
    body.startsWith('**Actionable comments posted: ') &&
    body.includes('<!-- Review source: Codex CLI fallback; canonical visible structure:')
  );
}

export function isCanonicalMarker(comment) {
  return (
    comment?.user?.login === ACTIONS_BOT_LOGIN &&
    comment?.user?.id === ACTIONS_BOT_ID &&
    comment?.user?.type === 'Bot' &&
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

/**
 * Computes active review state per reviewer login across all trusted reviews.
 * Reviews are processed chronologically: DISMISSED resets state, CHANGES_REQUESTED
 * or APPROVED overwrites state, COMMENTED establishes a non-empty state.
 */
export function getActiveReviewStates(reviews) {
  const sorted = [...reviews].sort((a, b) => {
    const timeDiff = new Date(a.submitted_at || 0).getTime() - new Date(b.submitted_at || 0).getTime();
    return timeDiff !== 0 ? timeDiff : (a.id || 0) - (b.id || 0);
  });

  const states = {};
  for (const review of sorted) {
    if (!isTrustedHuman(review) && !isCodeRabbit(review)) {
      continue;
    }
    const login = review.user?.login;
    if (!login) continue;

    if (review.state === 'DISMISSED') {
      delete states[login];
    } else if (review.state === 'COMMENTED') {
      states[login] = states[login] ?? 'COMMENTED';
    } else {
      states[login] = review.state;
    }
  }
  return states;
}

export function extractFindings(discoveryReview, reviewThreads = []) {
  if (isCanonicalCodexFallback(discoveryReview)) {
    const match = (discoveryReview.body ?? '').match(/\*\*Actionable comments posted: (\d+)\*\*/);
    const findingCount = match ? parseInt(match[1], 10) : 0;
    const inlinePaths = new Set();
    for (const thread of reviewThreads) {
      if (thread.path) inlinePaths.add(thread.path);
    }
    return { findingCount, inlineFindingPaths: inlinePaths };
  }

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

  // 1. Fail closed if 0 trusted reviews exist
  const trustedReviews = reviews.filter((r) => isTrustedHuman(r) || isCodeRabbit(r));
  if (trustedReviews.length === 0) {
    throw new Error('no trusted reviews found on pull request');
  }

  // 2. Active CHANGES_REQUESTED check across all trusted reviews
  const activeStates = getActiveReviewStates(reviews);
  for (const [reviewer, state] of Object.entries(activeStates)) {
    if (state === 'CHANGES_REQUESTED') {
      throw new Error(`active CHANGES_REQUESTED remains from ${reviewer}`);
    }
  }

  // 3. Current-head trusted APPROVED path
  const currentHeadApproved = reviews.some(
    (r) => isTrustedHuman(r) && r.state === 'APPROVED' && r.commit_id === head,
  );

  if (currentHeadApproved) {
    verifyReviewThreads(reviewThreads);
    verifyRequiredContexts(requiredContexts, checks, statuses);
    return { ok: true, type: 'current-head-approved' };
  }

  // 4. Previous-head discovery review path
  // Exactly one canonical Actions marker matching current head
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

  // Find eligible discovery review
  const eligibleReviews = reviews.filter((r) => {
    if (r.commit_id === head) return false;
    if (r.state === 'DISMISSED') return false;
    if (isTrustedHuman(r) && r.state === 'APPROVED') return true;
    if (isCodeRabbit(r) && r.state === 'COMMENTED') return true;
    if (isCanonicalCodexFallback(r) && r.state === 'COMMENTED') return true;
    return false;
  });

  if (eligibleReviews.length === 0) {
    throw new Error('no eligible previous-head discovery review found');
  }

  // Pick the latest eligible review
  const discoveryReview = [...eligibleReviews]
    .sort((a, b) => {
      const timeDiff = new Date(a.submitted_at || 0).getTime() - new Date(b.submitted_at || 0).getTime();
      return timeDiff !== 0 ? timeDiff : (a.id || 0) - (b.id || 0);
    })
    .at(-1);

  // Determine reviewed commits prefix
  const effectiveReviewed =
    reviewedCommits ??
    (() => {
      const idx = currentCommits.findIndex((c) => c.sha === discoveryReview.commit_id);
      if (idx >= 0) return currentCommits.slice(0, idx + 1);
      throw new Error(`reviewed head ${discoveryReview.commit_id} not found in current commit ancestry`);
    })();

  // Verify commit series
  const { closureCommits } = verifyCommitSeries(effectiveReviewed, currentCommits);

  // Extract findings
  const threadsArray = reviewThreads?.nodes ?? (Array.isArray(reviewThreads) ? reviewThreads : []);
  const { findingCount, inlineFindingPaths } = extractFindings(discoveryReview, threadsArray);

  // Verify closure delta
  verifyClosureDelta({
    findingCount,
    inlineFindingPaths,
    selectedTestPaths: new Set(selectedTestPaths),
    closureFiles,
    closureCommits,
  });

  // Verify review threads
  verifyReviewThreads(reviewThreads);

  // Verify required contexts
  verifyRequiredContexts(requiredContexts, checks, statuses);

  return { ok: true, type: 'reused-discovery-review', discoveryReviewId: discoveryReview.id };
}
