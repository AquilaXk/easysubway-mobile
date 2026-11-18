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
  for (const keyword of ['계단', '엘리베이터', '휠체어 리프트', '화장실', '수유실', '하차 알람', '시간표', '위젯', '가입 없이', '수도권', '부산', '대구', '대전', '광주']) {
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

  const expectedTypes = [
    'App info and performance — Crash logs',
    'App info and performance — Diagnostics',
    'Device or other IDs',
  ];
  assert.deepEqual(decision.playDataTypes, expectedTypes);
  assert.deepEqual(disclosure.playDataSafety.map((item) => item.dataType), expectedTypes);
  for (const item of disclosure.playDataSafety) {
    assert.equal(item.collected, true);
    assert.equal(item.shared, true);
    assert.match(item.sharedWith, /Crashlytics/);
    assert.equal(item.purpose, 'App functionality');
    assert.equal(item.usedForTracking, false);
    assert.equal(item.usedForAds, false);
  }
  const inventoryTypes = [
    entry.googlePlayDataSafety.dataType,
    ...entry.additionalGooglePlayDataSafety.map((item) => item.dataType),
  ];
  assert.deepEqual(inventoryTypes, expectedTypes);
  for (const item of [entry.googlePlayDataSafety, ...entry.additionalGooglePlayDataSafety]) {
    assert.equal(item.collected, true);
    assert.equal(item.shared, true);
    assert.equal(item.purpose, 'App functionality');
  }
  const submissionGroups = content.dataSafetyDeclarations.answerMatrix;
  assert.ok(Array.isArray(submissionGroups), 'submission data type declarations');
  assert.deepEqual(content.crashAnrProviderDecision.playDataTypes, expectedTypes);
  const crashGroups = submissionGroups.filter((group) => group.inventoryDataIds.includes('diagnostics_crash_logs'));
  assert.equal(crashGroups.length, 3, 'crash logs are declared in three Play data type groups');
  assert.ok(crashGroups.some((group) => group.dataType === 'App info and performance — Crash logs'));
  assert.ok(crashGroups.some((group) => group.dataType === 'Device or other IDs'));

  assert.equal(content.crashAnrProviderDecision.separateCrashProvider, true);
  assert.equal(content.crashAnrProviderDecision.linkedInventory, 'apps/mobile/release/store-privacy-inventory.json');

  for (const path of STORE_DOCUMENTS) {
    const source = await readFile(path, 'utf8');
    assert.ok(!/no-crash-sdk|noCrashSdk|crash SDK를 사용하지/.test(source), `${path} must not claim "no crash SDK"`);
  }
});

test('등록정보에는 면책 문구가 없고 개인정보 요구 항목은 서버 경로 검색을 기준으로 한다', async () => {
  const content = await readJson('apps/mobile/release/play-store-submission-content.json');
  const listing = collectStrings(content.koreanListing).join('\n');
  assert.ok(!/다를 수 있|역무원|운영기관 안내/.test(listing), 'listing has no disclaimer sentence');
  const required = content.privacyPolicyRequirements.requiredContentKo.join('\n');
  assert.ok(!/단말에서만 처리/.test(required), 'route search is not on-device only');
  assert.match(required, /Journey V3 서버 경로 검색/);
});

function playBlocks(entry) {
  return [entry.googlePlayDataSafety, ...(entry.additionalGooglePlayDataSafety ?? [])].filter(Boolean);
}

test('Data safety 필수·선택·삭제 값이 인벤토리, 계약, 제출 문서에서 같다', async () => {
  const inventory = await readJson('apps/mobile/release/store-privacy-inventory.json');
  const disclosure = await readJson('contracts/mobile/crash-data-store-disclosure.json');
  const content = await readJson('apps/mobile/release/play-store-submission-content.json');
  const matrix = content.dataSafetyDeclarations.answerMatrix;
  const crash = inventory.dataTypes.find((item) => item.id === 'diagnostics_crash_logs');

  for (const item of disclosure.playDataSafety) {
    const block = playBlocks(crash).find((candidate) => candidate.dataType === item.dataType);
    assert.ok(block, `inventory has ${item.dataType}`);
    assert.equal(item.optional, block.optional, `${item.dataType} optional`);
    assert.equal(item.required, block.required, `${item.dataType} required`);
    assert.equal(item.deletionSupported, block.deletionSupported, `${item.dataType} deletionSupported`);
    assert.equal(item.collected, block.collected, `${item.dataType} collected`);
    assert.equal(item.shared, block.shared, `${item.dataType} shared`);
  }

  // 그룹 플래그는 그룹에 속한 인벤토리 항목에서 도출한 값과 같아야 한다.
  for (const item of disclosure.playDataSafety) {
    const group = matrix.find((candidate) => candidate.dataType === item.dataType);
    assert.ok(group, `submission has ${item.dataType}`);
    const blocks = group.inventoryDataIds.map((id) => {
      const entry = inventory.dataTypes.find((candidate) => candidate.id === id);
      assert.ok(entry, `inventory entry ${id}`);
      const block = playBlocks(entry).find((candidate) => candidate.dataType === item.dataType);
      assert.ok(block, `${id} declares ${item.dataType}`);
      return block;
    });
    assert.equal(group.containsRequiredData, blocks.some((block) => block.required === true), `${item.dataType} containsRequiredData`);
    assert.equal(group.containsOptionalData, blocks.some((block) => block.optional === true), `${item.dataType} containsOptionalData`);
    assert.equal(
      group.containsDeletionUnsupportedData,
      blocks.some((block) => block.deletionSupported === false),
      `${item.dataType} containsDeletionUnsupportedData`,
    );
  }
});
