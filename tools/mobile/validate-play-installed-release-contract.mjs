function requireCondition(condition, message) {
  if (!condition) throw new Error(`release GO rejected: ${message}`);
}

const GIT_SHA = /^[a-f0-9]{40}$/;
const SHA256 = /^[a-f0-9]{64}$/;
const COLON_DELIMITED_SHA256_FINGERPRINT = /^(?:[a-fA-F0-9]{2}:){31}[a-fA-F0-9]{2}$/;

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
