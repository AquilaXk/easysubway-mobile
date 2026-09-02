function requireCondition(condition, message) {
  if (!condition) throw new Error(`release GO rejected: ${message}`);
}

const GIT_SHA = /^[a-f0-9]{40}$/;
const SHA256 = /^[a-f0-9]{64}$/;
const COLON_DELIMITED_SHA256_FINGERPRINT = /^(?:[a-fA-F0-9]{2}:){31}[a-fA-F0-9]{2}$/;
const FULL_SAME_RC_IDENTITY_FIELDS = [
  'mobile',
  'journeyContract',
  'mapCatalog',
  'dataFinal',
  'serverRoute',
  'backend',
  'platform',
  'hub',
];

function requireExactObject(value, fields, label) {
  requireCondition(value && typeof value === 'object' && !Array.isArray(value), `${label} is required`);
  const actualFields = Object.keys(value).sort();
  const expectedFields = [...fields].sort();
  requireCondition(actualFields.length === expectedFields.length && actualFields.every((field, index) => field === expectedFields[index]), `${label} must contain the exact required fields`);
}

function requireSha256(value, label) {
  requireCondition(typeof value === 'string' && SHA256.test(value), `${label} must be a lowercase SHA-256 digest`);
}

function requireGitSha(value, label) {
  requireCondition(typeof value === 'string' && GIT_SHA.test(value), `${label} must be a lowercase 40-hex SHA`);
}

function requireNonBlank(value, label) {
  requireCondition(typeof value === 'string' && value.trim().length > 0, `${label} is required`);
}

function requirePositiveInteger(value, label) {
  requireCondition(Number.isSafeInteger(value) && value > 0, `${label} must be a positive integer`);
}

function requireEqual(left, right, label) {
  requireCondition(left === right, `${label} must exactly match`);
}

function requireSameRcIdentity(identity, fields) {
  requireCondition(identity && typeof identity === 'object' && !Array.isArray(identity), 'sameRcIdentity is required');
  for (const field of fields) {
    requireCondition(Object.hasOwn(identity, field), `sameRcIdentity.${field} is required`);
  }
  requireCondition(typeof identity.gitSha === 'string' && GIT_SHA.test(identity.gitSha), 'sameRcIdentity.gitSha must be a lowercase 40-hex SHA');
  requireCondition(typeof identity.packageId === 'string' && identity.packageId.length > 0, 'sameRcIdentity.packageId is required');
  requireCondition(typeof identity.versionName === 'string' && identity.versionName.length > 0, 'sameRcIdentity.versionName is required');
  requireCondition(Number.isSafeInteger(identity.versionCode) && identity.versionCode > 0, 'sameRcIdentity.versionCode must be a positive integer');
  requireCondition(
    typeof identity.appSigningKeySha256Fingerprint === 'string'
      && (SHA256.test(identity.appSigningKeySha256Fingerprint) || COLON_DELIMITED_SHA256_FINGERPRINT.test(identity.appSigningKeySha256Fingerprint)),
    'sameRcIdentity.appSigningKeySha256Fingerprint must be a SHA-256 fingerprint',
  );
  requireCondition(typeof identity.dataPackManifestSha256 === 'string' && SHA256.test(identity.dataPackManifestSha256), 'sameRcIdentity.dataPackManifestSha256 must be a lowercase SHA-256 digest');
}

function requireFullSameRcIdentity(identity, policy, contract) {
  requireCondition(
    Array.isArray(policy.requiredFullSameRcIdentityFields)
      && JSON.stringify(policy.requiredFullSameRcIdentityFields) === JSON.stringify(FULL_SAME_RC_IDENTITY_FIELDS),
    'full same-RC identity field set is required',
  );
  requireExactObject(identity, FULL_SAME_RC_IDENTITY_FIELDS, 'fullSameRcIdentity');

  const { mobile, journeyContract, mapCatalog, dataFinal, serverRoute, backend, platform, hub } = identity;
  requireExactObject(mobile, [
    'sourceGitSha', 'aabSha256', 'aabPayloadSha256', 'playGeneratedApkSha256', 'packageId', 'versionName', 'versionCode',
    'appSigningKeySha256Fingerprint', 'dataPackManifestSha256',
  ], 'fullSameRcIdentity.mobile');
  requireGitSha(mobile.sourceGitSha, 'fullSameRcIdentity.mobile.sourceGitSha');
  for (const field of ['aabSha256', 'aabPayloadSha256', 'playGeneratedApkSha256', 'dataPackManifestSha256']) requireSha256(mobile[field], `fullSameRcIdentity.mobile.${field}`);
  requireNonBlank(mobile.packageId, 'fullSameRcIdentity.mobile.packageId');
  requireNonBlank(mobile.versionName, 'fullSameRcIdentity.mobile.versionName');
  requirePositiveInteger(mobile.versionCode, 'fullSameRcIdentity.mobile.versionCode');
  requireCondition(
    typeof mobile.appSigningKeySha256Fingerprint === 'string'
      && (SHA256.test(mobile.appSigningKeySha256Fingerprint) || COLON_DELIMITED_SHA256_FINGERPRINT.test(mobile.appSigningKeySha256Fingerprint)),
    'fullSameRcIdentity.mobile.appSigningKeySha256Fingerprint must be a SHA-256 fingerprint',
  );

  requireExactObject(journeyContract, ['backendGitSha', 'contractLockSha256', 'contractPayloadSha256', 'contractPublicationReceiptSha256'], 'fullSameRcIdentity.journeyContract');
  requireGitSha(journeyContract.backendGitSha, 'fullSameRcIdentity.journeyContract.backendGitSha');
  for (const field of ['contractLockSha256', 'contractPayloadSha256', 'contractPublicationReceiptSha256']) requireSha256(journeyContract[field], `fullSameRcIdentity.journeyContract.${field}`);

  requireExactObject(mapCatalog, ['mapCatalogLockSha256', 'aabReceiptSha256', 'aabSha256', 'artifactInventorySha256', 'dataPackManifestSha256', 'dataProducerGitSha', 'releaseSequence', 'signedFinalDescriptorSha256', 'publicationReceiptSha256'], 'fullSameRcIdentity.mapCatalog');
  for (const field of ['mapCatalogLockSha256', 'aabReceiptSha256', 'aabSha256', 'artifactInventorySha256', 'dataPackManifestSha256', 'signedFinalDescriptorSha256', 'publicationReceiptSha256']) requireSha256(mapCatalog[field], `fullSameRcIdentity.mapCatalog.${field}`);
  requireGitSha(mapCatalog.dataProducerGitSha, 'fullSameRcIdentity.mapCatalog.dataProducerGitSha');
  requirePositiveInteger(mapCatalog.releaseSequence, 'fullSameRcIdentity.mapCatalog.releaseSequence');

  requireExactObject(dataFinal, ['candidateId', 'producerGitSha', 'releaseSequence', 'signedFinalDescriptorSha256', 'publicationReceiptSha256', 'sourceSetSha256'], 'fullSameRcIdentity.dataFinal');
  requireNonBlank(dataFinal.candidateId, 'fullSameRcIdentity.dataFinal.candidateId');
  requireGitSha(dataFinal.producerGitSha, 'fullSameRcIdentity.dataFinal.producerGitSha');
  requirePositiveInteger(dataFinal.releaseSequence, 'fullSameRcIdentity.dataFinal.releaseSequence');
  for (const field of ['signedFinalDescriptorSha256', 'publicationReceiptSha256', 'sourceSetSha256']) requireSha256(dataFinal[field], `fullSameRcIdentity.dataFinal.${field}`);

  requireExactObject(serverRoute, ['candidateId', 'releaseSequence', 'signedFinalDescriptorSha256', 'publicationReceiptSha256', 'sourceSetSha256', 'routeBundleId', 'routeBundleSha256'], 'fullSameRcIdentity.serverRoute');
  requireNonBlank(serverRoute.candidateId, 'fullSameRcIdentity.serverRoute.candidateId');
  requirePositiveInteger(serverRoute.releaseSequence, 'fullSameRcIdentity.serverRoute.releaseSequence');
  for (const field of ['signedFinalDescriptorSha256', 'publicationReceiptSha256', 'sourceSetSha256', 'routeBundleSha256']) requireSha256(serverRoute[field], `fullSameRcIdentity.serverRoute.${field}`);
  requireNonBlank(serverRoute.routeBundleId, 'fullSameRcIdentity.serverRoute.routeBundleId');

  requireExactObject(backend, ['candidateId', 'dataProducerGitSha', 'releaseSequence', 'signedFinalDescriptorSha256', 'publicationReceiptSha256', 'backendGitSha', 'imageDigest', 'configSha256', 'contractLockSha256', 'contractPayloadSha256', 'contractPublicationReceiptSha256', 'activeBundleId', 'activeBundleSha256', 'routeBundleId', 'routeBundleSha256'], 'fullSameRcIdentity.backend');
  requireNonBlank(backend.candidateId, 'fullSameRcIdentity.backend.candidateId');
  for (const field of ['dataProducerGitSha', 'backendGitSha']) requireGitSha(backend[field], `fullSameRcIdentity.backend.${field}`);
  requirePositiveInteger(backend.releaseSequence, 'fullSameRcIdentity.backend.releaseSequence');
  for (const field of ['signedFinalDescriptorSha256', 'publicationReceiptSha256', 'imageDigest', 'configSha256', 'contractLockSha256', 'contractPayloadSha256', 'contractPublicationReceiptSha256', 'activeBundleSha256', 'routeBundleSha256']) requireSha256(backend[field], `fullSameRcIdentity.backend.${field}`);
  for (const field of ['activeBundleId', 'routeBundleId']) requireNonBlank(backend[field], `fullSameRcIdentity.backend.${field}`);

  requireExactObject(platform, ['candidateId', 'releaseSequence', 'signedFinalDescriptorSha256', 'publicationReceiptSha256', 'backendImageDigest', 'backendConfigSha256', 'activeBundleId', 'activeBundleSha256', 'routeBundleId', 'routeBundleSha256', 'activationReceiptSha256', 'environment', 'revision', 'servingState'], 'fullSameRcIdentity.platform');
  requireNonBlank(platform.candidateId, 'fullSameRcIdentity.platform.candidateId');
  requirePositiveInteger(platform.releaseSequence, 'fullSameRcIdentity.platform.releaseSequence');
  for (const field of ['signedFinalDescriptorSha256', 'publicationReceiptSha256', 'backendImageDigest', 'backendConfigSha256', 'activeBundleSha256', 'routeBundleSha256', 'activationReceiptSha256']) requireSha256(platform[field], `fullSameRcIdentity.platform.${field}`);
  for (const field of ['activeBundleId', 'routeBundleId', 'environment', 'revision']) requireNonBlank(platform[field], `fullSameRcIdentity.platform.${field}`);
  requireCondition(platform.servingState === 'ACTIVE_SERVING', 'Platform ACTIVE_SERVING identity is required');

  requireExactObject(hub, ['candidateId', 'releaseSequence', 'signedFinalDescriptorSha256', 'publicationReceiptSha256', 'componentManifestSha256', 'systemReleaseManifestSha256', 'mobileAabSha256', 'mobileAabPayloadSha256', 'productId'], 'fullSameRcIdentity.hub');
  requireNonBlank(hub.candidateId, 'fullSameRcIdentity.hub.candidateId');
  requirePositiveInteger(hub.releaseSequence, 'fullSameRcIdentity.hub.releaseSequence');
  for (const field of ['signedFinalDescriptorSha256', 'publicationReceiptSha256', 'componentManifestSha256', 'systemReleaseManifestSha256', 'mobileAabSha256', 'mobileAabPayloadSha256']) requireSha256(hub[field], `fullSameRcIdentity.hub.${field}`);
  requireNonBlank(hub.productId, 'fullSameRcIdentity.hub.productId');

  const sameRc = contract.sameRcIdentity;
  requireEqual(mobile.sourceGitSha, sameRc.gitSha, 'Mobile source SHA and same-RC git SHA');
  requireEqual(mobile.packageId, sameRc.packageId, 'Mobile package and same-RC package');
  requireEqual(mobile.versionName, sameRc.versionName, 'Mobile versionName and same-RC versionName');
  requireEqual(mobile.versionCode, sameRc.versionCode, 'Mobile versionCode and same-RC versionCode');
  requireEqual(mobile.appSigningKeySha256Fingerprint, sameRc.appSigningKeySha256Fingerprint, 'Mobile signing fingerprint and same-RC signing fingerprint');
  requireEqual(mobile.dataPackManifestSha256, sameRc.dataPackManifestSha256, 'Mobile datapack manifest and same-RC datapack manifest');
  requireEqual(mobile.packageId, contract.androidApplicationId, 'Mobile package and Android application id');
  requireEqual(mobile.versionName, contract.latestPlayGeneratedArtifact.versionName, 'Mobile versionName and Play-generated artifact versionName');
  requireEqual(mobile.versionCode, contract.latestPlayGeneratedArtifact.versionCode, 'Mobile versionCode and Play-generated artifact versionCode');
  requireEqual(mobile.playGeneratedApkSha256, contract.latestPlayGeneratedArtifact.generatedUniversalApkSha256, 'Mobile Play-generated APK and artifact identity');

  requireEqual(mapCatalog.aabSha256, mobile.aabSha256, 'Map/catalog AAB and Mobile source AAB');
  requireEqual(mapCatalog.dataPackManifestSha256, mobile.dataPackManifestSha256, 'Map/catalog datapack manifest and Mobile datapack manifest');
  requireEqual(mapCatalog.dataProducerGitSha, dataFinal.producerGitSha, 'Map/catalog Data producer SHA and Data FINAL producer SHA');
  for (const field of ['releaseSequence', 'signedFinalDescriptorSha256', 'publicationReceiptSha256']) requireEqual(mapCatalog[field], dataFinal[field], `Map/catalog ${field} and Data FINAL ${field}`);
  for (const field of ['candidateId', 'releaseSequence', 'signedFinalDescriptorSha256', 'publicationReceiptSha256', 'sourceSetSha256']) requireEqual(serverRoute[field], dataFinal[field], `Server route ${field} and Data FINAL ${field}`);
  for (const field of ['candidateId', 'releaseSequence', 'signedFinalDescriptorSha256', 'publicationReceiptSha256']) requireEqual(backend[field], dataFinal[field], `Backend ${field} and Data FINAL ${field}`);
  requireEqual(backend.dataProducerGitSha, dataFinal.producerGitSha, 'Backend Data producer SHA and Data FINAL producer SHA');
  for (const field of ['backendGitSha', 'contractLockSha256', 'contractPayloadSha256', 'contractPublicationReceiptSha256']) requireEqual(backend[field], journeyContract[field], `Backend ${field} and Journey contract ${field}`);
  for (const field of ['routeBundleId', 'routeBundleSha256']) requireEqual(backend[field], serverRoute[field], `Backend ${field} and server route ${field}`);
  for (const field of ['candidateId', 'releaseSequence', 'signedFinalDescriptorSha256', 'publicationReceiptSha256']) requireEqual(platform[field], dataFinal[field], `Platform ${field} and Data FINAL ${field}`);
  requireEqual(platform.backendImageDigest, backend.imageDigest, 'Platform backend image and Backend image');
  requireEqual(platform.backendConfigSha256, backend.configSha256, 'Platform backend config and Backend config');
  for (const field of ['activeBundleId', 'activeBundleSha256', 'routeBundleId', 'routeBundleSha256']) requireEqual(platform[field], backend[field], `Platform ${field} and Backend ${field}`);
  for (const field of ['candidateId', 'releaseSequence', 'signedFinalDescriptorSha256', 'publicationReceiptSha256']) requireEqual(hub[field], dataFinal[field], `Hub ${field} and Data FINAL ${field}`);
  requireEqual(hub.mobileAabSha256, mobile.aabSha256, 'Hub candidate AAB and Mobile source AAB');
  requireEqual(hub.mobileAabPayloadSha256, mobile.aabPayloadSha256, 'Hub candidate AAB payload and Mobile AAB payload');
  requireEqual(hub.productId, contract.applicationId, 'Hub product and application identity');
}

export function validatePlayInstalledReleaseContract(contract) {
  requireCondition(contract && typeof contract === 'object' && !Array.isArray(contract), 'contract must be an object');
  requireCondition(['NO_GO', 'GO'].includes(contract.goNoGoDecision), 'goNoGoDecision must be NO_GO or GO');
  if (contract.goNoGoDecision === 'NO_GO') return { decision: 'NO_GO' };

  const policy = contract.releaseBlockingGoPolicy;
  requireCondition(policy && typeof policy === 'object', 'releaseBlockingGoPolicy is required');
  requireCondition(policy.requiredBuildSource === 'play-installed-build', 'current Play-installed build source is required');
  requireCondition(policy.currentRcOnly === true, 'current RC evidence is required');
  requireCondition(policy.historicalOrCrossRcEvidenceDisposition === 'NO_GO', 'historical or cross-RC evidence must remain NO_GO');
  requireCondition(policy.playGeneratedApkEvidenceRole === 'identity-and-inspection-only', 'Play-generated APK evidence must remain identity and inspection only');
  requireCondition(policy.localEmulatorAndShellSideloadEvidenceRole === 'diagnostic-only', 'local emulator and shell sideload evidence must remain diagnostic only');
  requireCondition(Array.isArray(policy.requiredSameRcIdentityFields) && policy.requiredSameRcIdentityFields.length > 0, 'same-RC identity fields are required');

  const device = contract.latestPhysicalDevice;
  requireCondition(device && device.playStoreInstalled === true, 'Play-installed device evidence is required');
  requireCondition(device.currentInstallerPackageName === 'com.android.vending', 'Play installer package is required');
  requireCondition(device.currentInitiatingPackageName === 'com.android.vending', 'Play initiating package is required');
  requireCondition(device.playInstallerProvenanceVerified === true, 'Play installer provenance is required');
  requireCondition(device.currentSigningCertificateMatchesPlay === true, 'Play signing match is required');
  requireCondition(device.verificationState === 'PLAY_INSTALLED_VERIFIED', 'terminal Play-installed verification state is required');
  requireCondition(device.playInstallRequiresCurrentAppUninstall === false, 'Play-installed evidence must not require uninstall');

  requireSameRcIdentity(contract.sameRcIdentity, policy.requiredSameRcIdentityFields);
  const artifact = contract.latestPlayGeneratedArtifact;
  requireCondition(artifact && contract.sameRcIdentity.packageId === contract.androidApplicationId, 'same-RC package must match the Android application id');
  requireCondition(contract.sameRcIdentity.packageId === artifact.packageId, 'same-RC package must match the generated artifact');
  requireCondition(contract.sameRcIdentity.versionName === artifact.versionName, 'same-RC versionName must match the generated artifact');
  requireCondition(contract.sameRcIdentity.versionCode === artifact.versionCode, 'same-RC versionCode must match the generated artifact');
  requireCondition(device.currentInstalledVersionCode === contract.sameRcIdentity.versionCode, 'installed versionCode must match the same-RC identity');
  requireFullSameRcIdentity(contract.fullSameRcIdentity, policy, contract);

  const releaseBlockingItems = Array.isArray(contract.deviceMatrix)
    ? contract.deviceMatrix.filter((item) => item.releaseBlocker === true)
    : [];
  requireCondition(releaseBlockingItems.length > 0, 'release-blocking device matrix evidence is required');
  for (const item of releaseBlockingItems) {
    requireCondition(item.result === 'PASS', `device matrix ${item.id} must pass`);
    requireCondition(item.sameRcIdentityVerified === true, `device matrix ${item.id} must verify the same RC identity`);
  }

  return { decision: 'GO' };
}
