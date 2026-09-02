import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
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

const digest = (label) => createHash('sha256').update(`mobile-317-test:${label}`).digest('hex');
const gitSha = (label) => digest(label).slice(0, 40);

function fullSameRcIdentity(contract) {
  const mobileSourceGitSha = gitSha('mobile-source');
  const dataProducerGitSha = gitSha('data-producer');
  const backendGitSha = gitSha('backend-source');
  const candidateId = `candidate-${digest('candidate').slice(0, 16)}`;
  const releaseSequence = 42;
  const signedFinalDescriptorSha256 = digest('signed-final-descriptor');
  const dataPublicationReceiptSha256 = digest('data-publication-receipt');
  const sourceSetSha256 = digest('source-set');
  const routeBundleId = `route-bundle-${digest('route-bundle-id').slice(0, 16)}`;
  const routeBundleSha256 = digest('route-bundle');
  const activeBundleId = `active-bundle-${digest('active-bundle-id').slice(0, 16)}`;
  const activeBundleSha256 = digest('active-bundle');
  const backendImageDigest = digest('backend-image');
  const backendConfigSha256 = digest('backend-config');

  return {
    mobile: {
      sourceGitSha: mobileSourceGitSha,
      aabSha256: digest('source-aab'),
      aabPayloadSha256: digest('source-aab-payload'),
      playGeneratedApkSha256: contract.latestPlayGeneratedArtifact.generatedUniversalApkSha256,
      packageId: contract.androidApplicationId,
      versionName: contract.latestPlayGeneratedArtifact.versionName,
      versionCode: contract.latestPlayGeneratedArtifact.versionCode,
      appSigningKeySha256Fingerprint: digest('signing-fingerprint'),
      dataPackManifestSha256: digest('datapack-manifest'),
    },
    journeyContract: {
      backendGitSha,
      contractLockSha256: digest('journey-contract-lock'),
      contractPayloadSha256: digest('journey-contract-payload'),
      contractPublicationReceiptSha256: digest('journey-contract-publication-receipt'),
    },
    mapCatalog: {
      mapCatalogLockSha256: digest('map-catalog-lock'),
      aabReceiptSha256: digest('map-catalog-aab-receipt'),
      aabSha256: digest('source-aab'),
      artifactInventorySha256: digest('map-catalog-artifact-inventory'),
      dataPackManifestSha256: digest('datapack-manifest'),
      dataProducerGitSha,
      releaseSequence,
      signedFinalDescriptorSha256,
      publicationReceiptSha256: dataPublicationReceiptSha256,
    },
    dataFinal: {
      candidateId,
      producerGitSha: dataProducerGitSha,
      releaseSequence,
      signedFinalDescriptorSha256,
      publicationReceiptSha256: dataPublicationReceiptSha256,
      sourceSetSha256,
    },
    serverRoute: {
      candidateId,
      releaseSequence,
      signedFinalDescriptorSha256,
      publicationReceiptSha256: dataPublicationReceiptSha256,
      sourceSetSha256,
      routeBundleId,
      routeBundleSha256,
    },
    backend: {
      candidateId,
      dataProducerGitSha,
      releaseSequence,
      signedFinalDescriptorSha256,
      publicationReceiptSha256: dataPublicationReceiptSha256,
      backendGitSha,
      imageDigest: backendImageDigest,
      configSha256: backendConfigSha256,
      contractLockSha256: digest('journey-contract-lock'),
      contractPayloadSha256: digest('journey-contract-payload'),
      contractPublicationReceiptSha256: digest('journey-contract-publication-receipt'),
      activeBundleId,
      activeBundleSha256,
      routeBundleId,
      routeBundleSha256,
    },
    platform: {
      candidateId,
      releaseSequence,
      signedFinalDescriptorSha256,
      publicationReceiptSha256: dataPublicationReceiptSha256,
      backendImageDigest,
      backendConfigSha256,
      activeBundleId,
      activeBundleSha256,
      routeBundleId,
      routeBundleSha256,
      activationReceiptSha256: digest('platform-activation-receipt'),
      environment: 'production',
      revision: `revision-${digest('platform-revision').slice(0, 16)}`,
      servingState: 'ACTIVE_SERVING',
    },
    hub: {
      candidateId,
      releaseSequence,
      signedFinalDescriptorSha256,
      publicationReceiptSha256: dataPublicationReceiptSha256,
      componentManifestSha256: digest('hub-component-manifest'),
      systemReleaseManifestSha256: digest('hub-system-release-manifest'),
      mobileAabSha256: digest('source-aab'),
      mobileAabPayloadSha256: digest('source-aab-payload'),
      productId: contract.applicationId,
    },
  };
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
  assert.deepEqual(matrix.releaseBlockingGoPolicy.requiredFullSameRcIdentityFields, [
    'mobile',
    'journeyContract',
    'mapCatalog',
    'dataFinal',
    'serverRoute',
    'backend',
    'platform',
    'hub',
  ]);

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
    verificationState: 'PLAY_INSTALLED_VERIFIED',
    playInstallRequiresCurrentAppUninstall: false,
  };
  completeGo.sameRcIdentity = {
    gitSha: gitSha('mobile-source'),
    packageId: completeGo.androidApplicationId,
    versionName: completeGo.latestPlayGeneratedArtifact.versionName,
    versionCode: completeGo.latestPlayGeneratedArtifact.versionCode,
    appSigningKeySha256Fingerprint: digest('signing-fingerprint'),
    dataPackManifestSha256: digest('datapack-manifest'),
  };
  completeGo.fullSameRcIdentity = fullSameRcIdentity(completeGo);
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
    (value) => { value.latestPhysicalDevice.currentInstalledVersionCode += 1; },
    (value) => { value.latestPhysicalDevice.verificationState = 'PLAY_INSTALL_AND_OWNER_UNLOCK_PENDING'; },
    (value) => { value.latestPhysicalDevice.playInstallRequiresCurrentAppUninstall = true; },
    (value) => { delete value.sameRcIdentity; },
    (value) => { delete value.fullSameRcIdentity; },
    (value) => { delete value.fullSameRcIdentity.mobile.aabSha256; },
    (value) => { value.fullSameRcIdentity.mapCatalog.aabSha256 = digest('other-source-aab'); },
    (value) => { value.fullSameRcIdentity.hub.mobileAabPayloadSha256 = digest('other-source-aab-payload'); },
    (value) => { value.fullSameRcIdentity.mobile.playGeneratedApkSha256 = digest('other-play-apk'); },
    (value) => { value.fullSameRcIdentity.mobile.dataPackManifestSha256 = digest('other-datapack'); },
    (value) => { value.fullSameRcIdentity.journeyContract.contractPayloadSha256 = 'not-a-sha256'; },
    (value) => { value.fullSameRcIdentity.mapCatalog.releaseSequence += 1; },
    (value) => { value.fullSameRcIdentity.dataFinal.sourceSetSha256 = digest('other-source-set'); },
    (value) => { value.fullSameRcIdentity.serverRoute.routeBundleSha256 = digest('other-route-bundle'); },
    (value) => { value.fullSameRcIdentity.backend.backendGitSha = gitSha('other-backend'); },
    (value) => { value.fullSameRcIdentity.backend.activeBundleId = `active-bundle-${digest('other-active-bundle').slice(0, 16)}`; },
    (value) => { value.fullSameRcIdentity.platform.backendConfigSha256 = digest('other-backend-config'); },
    (value) => { value.fullSameRcIdentity.platform.servingState = 'PENDING'; },
    (value) => { value.fullSameRcIdentity.hub.candidateId = `candidate-${digest('other-candidate').slice(0, 16)}`; },
    (value) => { value.fullSameRcIdentity.hub.productId = 'different-product'; },
    (value) => { delete value.sameRcIdentity.gitSha; },
    (value) => { value.sameRcIdentity.gitSha = 123; },
    (value) => { value.sameRcIdentity.gitSha = 'A'.repeat(40); },
    (value) => { value.sameRcIdentity.packageId = 'different.package'; },
    (value) => { value.sameRcIdentity.versionName = 'different-version'; },
    (value) => { value.sameRcIdentity.versionCode = 0; },
    (value) => { value.sameRcIdentity.versionCode = 1.5; },
    (value) => { value.sameRcIdentity.versionCode += 1; },
    (value) => { value.sameRcIdentity.appSigningKeySha256Fingerprint = 123; },
    (value) => { value.sameRcIdentity.appSigningKeySha256Fingerprint = 'not-a-fingerprint'; },
    (value) => { value.sameRcIdentity.dataPackManifestSha256 = 123; },
    (value) => { value.sameRcIdentity.dataPackManifestSha256 = 'not-a-sha256'; },
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
