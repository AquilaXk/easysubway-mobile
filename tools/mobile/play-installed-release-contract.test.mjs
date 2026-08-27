import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';
import { validatePlayInstalledReleaseContract } from './validate-play-installed-release-contract.mjs';

const paths = {
  matrix: 'apps/mobile/release/play-generated-apk-device-matrix-gate.json',
  signed: 'apps/mobile/release/signed-release-artifact-gate.json',
  rc: 'apps/mobile/release/android-rc-store-evidence.json',
  quality: 'apps/mobile/release/android-release-quality-gate.json',
  pageSize: 'apps/mobile/release/android-16kb-page-size-gate.json',
};

async function readContracts() {
  return Object.fromEntries(await Promise.all(
    Object.entries(paths).map(async ([name, file]) => [name, JSON.parse(await readFile(file, 'utf8'))]),
  ));
}

test('release GO requires an exact current-RC Play-installed identity', async () => {
  const { matrix, signed, rc, quality, pageSize } = await readContracts();
  const requiredIdentity = [
    'gitSha',
    'packageId',
    'versionName',
    'versionCode',
    'appSigningKeySha256Fingerprint',
    'dataPackManifestSha256',
  ];

  assert.deepEqual(matrix.releaseBlockingGoPolicy.requiredSameRcIdentityFields, requiredIdentity);
  assert.equal(matrix.releaseBlockingGoPolicy.requiredBuildSource, 'play-installed-build');
  assert.equal(matrix.releaseBlockingGoPolicy.currentRcOnly, true);
  assert.equal(matrix.releaseBlockingGoPolicy.historicalOrCrossRcEvidenceDisposition, 'NO_GO');

  assert.equal(matrix.releaseBlockingGoPolicy.playGeneratedApkEvidenceRole, 'identity-and-inspection-only');
  assert.equal(matrix.releaseBlockingGoPolicy.localEmulatorAndShellSideloadEvidenceRole, 'diagnostic-only');
  assert.equal(matrix.goNoGoRules.historicalOrCrossRcEvidence, 'NO_GO');
  assert.equal(quality.deviceEvidencePolicy.localEmulatorEvidenceRole, 'diagnostic-only');
  assert.equal(pageSize.runtimeSmoke.localEmulatorEvidenceRole, 'diagnostic-only');
  assert.deepEqual(quality.buildIdentityPolicy.acceptedBuildSources, ['play-installed-build']);
  assert.deepEqual(quality.buildIdentityPolicy.diagnosticOnlyBuildSources, ['rc-aab', 'play-generated-apk', 'local-emulator', 'shell-sideload']);
  assert.ok(signed.artifacts.android.storeReadyRequires.includes('exact current-RC Play-installed package/version/signing/manifest identity evidence'));
  assert.ok(signed.artifacts.android.storeReadyRequires.includes('Play-generated APK identity/inspection and exact current-RC Play-installed smoke evidence'));
  assert.ok(rc.requiredEvidence.playGeneratedArtifact.includes('exact-current-rc-play-installed-identity-record'));
  assert.ok(rc.requiredEvidence.playGeneratedArtifact.includes('exact-current-rc-play-installed-logcat-no-crash'));
  assert.equal(signed.releaseBlockingGoPolicy, undefined);
  assert.equal(rc.releaseBlockingGoPolicy, undefined);
  assert.equal(quality.releaseBlockingGoPolicy, undefined);
  assert.equal(pageSize.releaseBlockingGoPolicy, undefined);
});

test('route and offline evidence records explicit server-route typed failure recovery', async () => {
  const { matrix, quality } = await readContracts();

  assert.deepEqual(matrix.deviceMatrix[2].smoke, ['server-route-typed-failure-recovery', 'error-message-recovery', 'app-relaunch-state-restore']);
  assert.equal(quality.requiredChecks.find(({ id }) => id === 'network_server_upload_error_recovery').passCriteria, 'Server route failures return an explicit typed failure and recovery action; map-pack and station-catalog-pack remain display and search only.');
  assert.equal(quality.requiredEvidenceSet.find(({ id }) => id === 'route_map_fallback').proves, 'Route-map interaction and performance evidence never treats map-pack or offline datapack as route-calculation success.');
});

test('release contract fails closed for GO without complete current Play-installed evidence', async () => {
  const { matrix } = await readContracts();
  assert.doesNotThrow(() => validatePlayInstalledReleaseContract(matrix), 'NO_GO remains valid');

  const completeGo = structuredClone(matrix);
  completeGo.goNoGoDecision = 'GO';
  completeGo.latestPhysicalDevice = {
    ...completeGo.latestPhysicalDevice,
    playStoreInstalled: true,
    currentInstallerPackageName: 'com.android.vending',
    currentInitiatingPackageName: 'com.android.vending',
    playInstallerProvenanceVerified: true,
    currentSigningCertificateMatchesPlay: true,
  };
  completeGo.sameRcIdentity = {
    gitSha: 'a'.repeat(40),
    packageId: completeGo.androidApplicationId,
    versionName: completeGo.latestPlayGeneratedArtifact.versionName,
    versionCode: completeGo.latestPlayGeneratedArtifact.versionCode,
    appSigningKeySha256Fingerprint: 'b'.repeat(64),
    dataPackManifestSha256: 'c'.repeat(64),
  };
  completeGo.deviceMatrix = completeGo.deviceMatrix.map((item) => ({
    ...item,
    result: 'PASS',
    sameRcIdentityVerified: true,
  }));

  assert.doesNotThrow(() => validatePlayInstalledReleaseContract(completeGo));

  const invalidGoMutations = [
    (value) => { value.releaseBlockingGoPolicy.requiredBuildSource = 'rc-aab'; },
    (value) => { value.releaseBlockingGoPolicy.currentRcOnly = false; },
    (value) => { value.releaseBlockingGoPolicy.playGeneratedApkEvidenceRole = 'smoke-evidence'; },
    (value) => { value.releaseBlockingGoPolicy.localEmulatorAndShellSideloadEvidenceRole = 'release-evidence'; },
    (value) => { value.latestPhysicalDevice.playStoreInstalled = false; },
    (value) => { value.latestPhysicalDevice.currentInstallerPackageName = null; },
    (value) => { value.latestPhysicalDevice.currentInitiatingPackageName = 'com.android.shell'; },
    (value) => { value.latestPhysicalDevice.playInstallerProvenanceVerified = false; },
    (value) => { value.latestPhysicalDevice.currentSigningCertificateMatchesPlay = false; },
    (value) => { delete value.sameRcIdentity; },
    (value) => { delete value.sameRcIdentity.gitSha; },
    (value) => { value.sameRcIdentity.packageId = 'different.package'; },
    (value) => { value.sameRcIdentity.versionName = 'different-version'; },
    (value) => { value.sameRcIdentity.versionCode += 1; },
    (value) => { value.deviceMatrix[0].result = 'FAIL'; },
    (value) => { value.deviceMatrix[0].sameRcIdentityVerified = false; },
    (value) => { value.releaseBlockingGoPolicy.historicalOrCrossRcEvidenceDisposition = 'PASS'; },
  ];

  for (const invalidateGoRequirement of invalidGoMutations) {
    const invalidGo = structuredClone(completeGo);
    invalidateGoRequirement(invalidGo);
    assert.throws(() => validatePlayInstalledReleaseContract(invalidGo));
  }
});
