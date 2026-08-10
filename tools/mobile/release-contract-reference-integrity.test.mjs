import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const issueUrlPattern = /https:\/\/github\.com\/AquilaXk\/(?:easysubway|easysubway-mobile)\/issues\/\d+(?=["\s),.])/g;
const bareIssuePattern = /#\d+\b/g;

const expectedReferences = {
  'apps/mobile/release/android-rc-store-evidence.json': [
    'https://github.com/AquilaXk/easysubway/issues/1020',
  ],
  'apps/mobile/release/android-release-quality-gate.json': [
    'https://github.com/AquilaXk/easysubway-mobile/issues/7',
    'https://github.com/AquilaXk/easysubway/issues/1015',
    'https://github.com/AquilaXk/easysubway-mobile/issues/8',
    'https://github.com/AquilaXk/easysubway/issues/1020',
    'https://github.com/AquilaXk/easysubway-mobile/issues/9',
  ],
  'apps/mobile/release/external-map-deeplink-policy.json': [
    'https://github.com/AquilaXk/easysubway/issues/1770',
  ],
  'apps/mobile/release/route-result-v2-ui-copy-gate.json': [
    'https://github.com/AquilaXk/easysubway/issues/1230',
  ],
  'apps/mobile/release/store-submission-readiness.json': [
    'https://github.com/AquilaXk/easysubway/issues/1018',
  ],
  'contracts/mobile/crash-data-store-disclosure.json': [
    'https://github.com/AquilaXk/easysubway/issues/2435',
    'https://github.com/AquilaXk/easysubway/issues/2435',
  ],
};

test('issue URL extraction rejects a Korean particle appended to its numeric id', () => {
  const url = 'https://github.com/AquilaXk/easysubway-mobile/issues/9';

  assert.equal(`${url}은`.match(issueUrlPattern), null);
  assert.deepEqual(
    [`${url}"`, `${url} `, `${url},`, `${url}.`, `${url})`].map((value) => value.match(issueUrlPattern)),
    [[url], [url], [url], [url], [url]],
  );
});

test('release contract issue references use canonical GitHub URLs', async () => {
  const actualReferences = [];

  for (const [file, expectedUrls] of Object.entries(expectedReferences)) {
    const source = await readFile(file, 'utf8');
    assert.doesNotThrow(() => JSON.parse(source), `${file} must remain valid JSON`);

    const actualUrls = source.match(issueUrlPattern) ?? [];
    assert.deepEqual(actualUrls, expectedUrls, `${file} issue URL projection`);
    assert.deepEqual(source.match(bareIssuePattern) ?? [], [], `${file} has no bare issue locators`);
    actualReferences.push(...actualUrls);
  }

  assert.equal(actualReferences.length, 11, 'physical issue reference count');
  assert.equal(
    actualReferences.filter((url) => url === 'https://github.com/AquilaXk/easysubway/issues/2435').length,
    2,
    'Hub issue 2435 is retained in both physical crash disclosure references',
  );
});
