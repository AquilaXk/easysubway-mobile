function requireCondition(condition, message) {
  if (!condition) throw new Error(`release GO rejected: ${message}`);
}

function requireNonEmptyIdentity(identity, fields) {
  requireCondition(identity && typeof identity === 'object' && !Array.isArray(identity), 'sameRcIdentity is required');
  for (const field of fields) {
    const value = identity[field];
    requireCondition(
      (typeof value === 'string' && value.length > 0) || (typeof value === 'number' && Number.isFinite(value)),
      `sameRcIdentity.${field} is required`,
    );
  }
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

  requireNonEmptyIdentity(contract.sameRcIdentity, policy.requiredSameRcIdentityFields);
  const artifact = contract.latestPlayGeneratedArtifact;
  requireCondition(artifact && contract.sameRcIdentity.packageId === contract.androidApplicationId, 'same-RC package must match the Android application id');
  requireCondition(contract.sameRcIdentity.packageId === artifact.packageId, 'same-RC package must match the generated artifact');
  requireCondition(contract.sameRcIdentity.versionName === artifact.versionName, 'same-RC versionName must match the generated artifact');
  requireCondition(contract.sameRcIdentity.versionCode === artifact.versionCode, 'same-RC versionCode must match the generated artifact');

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
