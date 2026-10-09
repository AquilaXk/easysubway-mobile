import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const STORE_DOCUMENTS = [
  'apps/mobile/release/store-privacy-inventory.json',
  'apps/mobile/release/store-submission-readiness.json',
  'apps/mobile/release/play-store-submission-content.json',
  'contracts/mobile/crash-data-store-disclosure.json',
];

const readJson = async (path) => JSON.parse(await readFile(path, 'utf8'));

function collectStrings(value, out = []) {
  if (typeof value === 'string') out.push(value);
  else if (Array.isArray(value)) value.forEach((item) => collectStrings(item, out));
  else if (value && typeof value === 'object') Object.values(value).forEach((item) => collectStrings(item, out));
  return out;
}

test('Play 등록정보 문구에는 내부 거버넌스·개발 용어가 없다', async () => {
  const content = await readJson('apps/mobile/release/play-store-submission-content.json');
  const listingKeys = Object.keys(content).filter((key) => /listing/i.test(key));
  assert.ok(listingKeys.includes('koreanListing'), 'koreanListing must exist');
  const forbidden = /pilot|파일럿|출시 근거|검증|게이트|\bgate\b|\bsource\b|\bserver\b|\bmobile\b|준비 중|근거가 모두/i;
  for (const key of listingKeys) {
    for (const text of collectStrings(content[key])) {
      assert.doesNotMatch(text, forbidden, `${key} contains internal wording: ${text.slice(0, 40)}`);
    }
  }
});

test('Play 등록정보는 단문 소개와 현재 제공 기능만 서술한다', async () => {
  const { koreanListing } = await readJson('apps/mobile/release/play-store-submission-content.json');
  assert.ok(koreanListing.shortDescription.length <= 80, 'Play short description limit is 80 characters');
  assert.ok(koreanListing.fullDescriptionKo.length <= 4000, 'Play full description limit is 4000 characters');
  for (const keyword of ['계단', '엘리베이터', '하차 알람', '시간표', '수도권', '부산', '대구', '대전', '광주']) {
    assert.ok(koreanListing.fullDescriptionKo.includes(keyword), `listing mentions ${keyword}`);
  }
});

test('스토어 문서에는 iOS·App Store 항목이 없다(Android 단독 배포)', async () => {
  for (const path of STORE_DOCUMENTS) {
    const source = await readFile(path, 'utf8');
    assert.ok(!/app ?store|appstore|PrivacyInfo|xcprivacy|NSPrivacy|\bios\b|iphone/i.test(source), `${path} has iOS wording`);
  }
});

test('충돌 진단 공시는 인벤토리와 계약 문서가 같은 사실을 말한다', async () => {
  const inventory = await readJson('apps/mobile/release/store-privacy-inventory.json');
  const disclosure = await readJson('contracts/mobile/crash-data-store-disclosure.json');
  const content = await readJson('apps/mobile/release/play-store-submission-content.json');

  const decision = inventory.crashAnrProviderDecision;
  assert.equal(decision.separateCrashProvider, true);
  assert.equal(decision.collected, true);
  assert.equal(decision.sharedWith, 'Google (Firebase Crashlytics)');
  assert.equal(decision.usedForTracking, false);
  assert.equal(decision.usedForAds, false);

  const entry = inventory.dataTypes.find((item) => item.id === 'diagnostics_crash_logs');
  assert.equal(entry.googlePlayDataSafety.collected, true);
  assert.equal(entry.sharedWithThirdParties, true);
  assert.equal(entry.usedForTracking, false);

  const [crashLogs] = disclosure.playDataSafety;
  assert.equal(crashLogs.collected, entry.googlePlayDataSafety.collected);
  assert.equal(crashLogs.shared, entry.sharedWithThirdParties);
  assert.match(crashLogs.sharedWith, /Crashlytics/);

  assert.equal(content.crashAnrProviderDecision.separateCrashProvider, true);
  assert.equal(content.crashAnrProviderDecision.linkedInventory, 'apps/mobile/release/store-privacy-inventory.json');

  for (const path of STORE_DOCUMENTS) {
    const source = await readFile(path, 'utf8');
    assert.ok(!/no-crash-sdk|noCrashSdk|crash SDK를 사용하지/.test(source), `${path} must not claim "no crash SDK"`);
  }
});
