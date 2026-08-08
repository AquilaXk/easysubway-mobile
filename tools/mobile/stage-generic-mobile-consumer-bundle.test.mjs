import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { execFile } from "node:child_process";
import { lstat, mkdtemp, readFile, rename, rm, symlink, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { promisify } from "node:util";
import { parseJsonWithoutDuplicateKeys, stageGenericMobileConsumerBundle, validateArtifactMetadata, validateGenericMobileConsumerBundleLock } from "./stage-generic-mobile-consumer-bundle.mjs";

const run = promisify(execFile);
const root = path.resolve(new URL("../..", import.meta.url).pathname);
const lockPath = path.join(root, "contracts/mobile/generic-mobile-consumer-bundle.lock.json");
const sha256 = (value) => createHash("sha256").update(value).digest("hex");
const clone = (value) => structuredClone(value);

async function exactLock() { return JSON.parse(await readFile(lockPath, "utf8")); }
function canonical(value) { return Array.isArray(value) ? `[${value.map(canonical).join(",")}]` : value && typeof value === "object" ? `{${Object.keys(value).sort().map((key) => `${JSON.stringify(key)}:${canonical(value[key])}`).join(",")}}` : JSON.stringify(value); }
async function temporary() { return mkdtemp(path.join(os.tmpdir(), "mobile-generic-consumer-")); }
function artifactMetadata(lock) {
  return { id: lock.artifact.id, name: lock.artifact.name, size_in_bytes: lock.artifact.sizeBytes, digest: `sha256:${lock.artifact.archiveSha256}`, archive_download_url: lock.artifact.archiveUrl, expired: false, created_at: lock.artifact.createdAt, expires_at: lock.artifact.expiresAt, workflow_run: { id: lock.publication.runId, head_branch: "main", head_sha: lock.publication.headSha, repository_id: lock.publication.repositoryId, head_repository_id: lock.publication.repositoryId } };
}
function runMetadata(lock) {
  return { id: lock.publication.runId, workflow_id: lock.publication.workflowId, run_attempt: lock.publication.runAttempt, path: `${lock.publication.workflowPath}@refs/heads/main`, event: "workflow_dispatch", status: "completed", conclusion: "success", head_branch: "main", head_sha: lock.publication.headSha, repository: { id: lock.publication.repositoryId, full_name: lock.producer.repository } };
}
async function buildArtifact(directory, options = {}) {
  const lock = clone(await exactLock());
  const resourceBytes = await Promise.all(lock.resources.map((resource) => readFile(path.join(root, resource.fixturePath))));
  if (options.mutateResource) options.mutateResource(resourceBytes, lock);
  for (const [index, resource] of lock.resources.entries()) { resource.rawSha256 = sha256(resourceBytes[index]); resource.sizeBytes = resourceBytes[index].length; }
  const resources = lock.resources.map((resource, index) => ({ resourceId: resource.resourceId, mediaType: resource.mediaType, schemaVersion: resource.schemaVersion, ownerRepository: resource.ownerRepository, ownerIssue: resource.ownerIssue, sourcePath: resource.sourcePath, contentBase64: resourceBytes[index].toString("base64"), rawSha256: resource.rawSha256, sizeBytes: resource.sizeBytes }));
  lock.resourceInventorySha256 = sha256(canonical(resources.map(({ resourceId, mediaType, schemaVersion, ownerRepository, ownerIssue, sourcePath }) => ({ resourceId, mediaType, schemaVersion, ownerRepository, ownerIssue, sourcePath }))));
  lock.payloadSha256 = sha256(canonical(resources.map(({ resourceId, sizeBytes, rawSha256 }) => ({ resourceId, sizeBytes, rawSha256 }))));
  const bundle = { schemaVersion: 1, artifactKind: "generic-mobile-consumer-bundle", component: lock.component, bundleVersion: lock.bundleVersion, producer: lock.producer, resources, resourceInventorySha256: lock.resourceInventorySha256, payloadSha256: lock.payloadSha256 };
  if (options.mutateBundle) options.mutateBundle(bundle);
  const bundleBytes = Buffer.from(`${JSON.stringify(bundle, null, 2)}\n`);
  lock.files.bundle.rawSha256 = sha256(bundleBytes); lock.files.bundle.sizeBytes = bundleBytes.length;
  const receipt = { schemaVersion: 1, artifactKind: "generic-mobile-consumer-publication-receipt", component: lock.component, bundleVersion: lock.bundleVersion, producer: lock.producer, bundle: { fileName: lock.files.bundle.path, rawSha256: lock.files.bundle.rawSha256, sizeBytes: lock.files.bundle.sizeBytes, resourceInventorySha256: lock.resourceInventorySha256, payloadSha256: lock.payloadSha256 }, resources: lock.resources.map(({ resourceId, rawSha256, sizeBytes }) => ({ resourceId, rawSha256, sizeBytes })), publication: { repository: lock.producer.repository, workflowPath: lock.publication.workflowPath, artifactName: lock.artifact.name, transport: "github-actions-artifact-v4", retentionDays: 90, overwrite: false } };
  if (options.mutateReceipt) options.mutateReceipt(receipt);
  const receiptBytes = Buffer.from(`${JSON.stringify(receipt, null, 2)}\n`);
  lock.files.receipt.rawSha256 = sha256(receiptBytes); lock.files.receipt.sizeBytes = receiptBytes.length;
  const bundlePath = path.join(directory, lock.files.bundle.path); const receiptPath = path.join(directory, lock.files.receipt.path); const archivePath = path.join(directory, "artifact.zip");
  await writeFile(bundlePath, bundleBytes); await writeFile(receiptPath, receiptBytes);
  if (options.symlinkBundle) { await rm(bundlePath); await symlink(lock.files.receipt.path, bundlePath); }
  if (options.extraEntry) await writeFile(path.join(directory, options.extraEntry), "unexpected");
  await run("zip", ["-q", ...(options.symlinkBundle ? ["-y"] : []), archivePath, lock.files.bundle.path, lock.files.receipt.path, ...(options.extraEntry ? [options.extraEntry] : [])], { cwd: directory });
  const archive = await readFile(archivePath); lock.artifact.archiveSha256 = sha256(archive); lock.artifact.sizeBytes = archive.length;
  return { archivePath, lock, metadata: artifactMetadata(lock), runMetadata: runMetadata(lock) };
}
async function withTemporary(callback) { const directory = await temporary(); try { return await callback(directory); } finally { await rm(directory, { recursive: true, force: true }); } }

test("exact Hub #2747 lock validates and pins the published identities", async () => {
  const lock = validateGenericMobileConsumerBundleLock(await exactLock());
  assert.deepEqual([lock.publication.repositoryId, lock.publication.workflowId, lock.publication.runId, lock.publication.runAttempt, lock.publication.headSha], [1266821737, 330153489, 31280042807, 1, "135922eaafad9367d001e1d100518cd7395fa962"]);
  assert.deepEqual([lock.artifact.id, lock.artifact.archiveSha256, lock.artifact.createdAt, lock.artifact.expiresAt, lock.artifact.retentionDays], [9028141921, "ce37e33ac2ef76ce4f909685415bf1653c4397c5fbeaf503d8f60af672c38a8e", "2026-08-08T21:44:51Z", "2026-11-06T21:44:38Z", 90]);
  assert.deepEqual([lock.artifact.name, lock.artifact.metadataUrl, lock.artifact.archiveUrl, lock.files.bundle.rawSha256, lock.files.bundle.sizeBytes, lock.files.receipt.rawSha256, lock.files.receipt.sizeBytes, lock.resourceInventorySha256, lock.payloadSha256], ["easysubway-generic-mobile-consumer-bundle-1.0.0-604a2ae525cc20b3bdcd3cbe2e22f93de19fefc3", "https://api.github.com/repos/AquilaXk/easysubway/actions/artifacts/9028141921", "https://api.github.com/repos/AquilaXk/easysubway/actions/artifacts/9028141921/zip", "7f666d016119591e5c958e7d55c936fffb5e753898e69ec28e4f0cb50b5555ff", 4415, "d0776145278f212aaf0c06038873e640b68f300fa9429b6dc88491e391a501bc", 1365, "b5b40b2585af7ac6255426018e30f785e28df80f1fcbac56d9d7089b332cdef9", "d355c6c40814faad293c200ddd72a2cc019005bef2e5e608970ae8e4837a1b3c"]);
  assert.deepEqual(lock.resources, [
    { resourceId: "errors/error-codes.json", mediaType: "application/json", schemaVersion: null, ownerRepository: "AquilaXk/easysubway", ownerIssue: 2747, sourcePath: "contracts/error-codes.json", rawSha256: "7527a60514a7000ae8df0c958516a856dfdc288b6e085e4efbde9e3ce61d4bf9", sizeBytes: 1723, fixturePath: "apps/mobile/test/fixtures/contracts/error-codes.json" },
    { resourceId: "product/mobility-profile-policy.json", mediaType: "application/json", schemaVersion: 1, ownerRepository: "AquilaXk/easysubway", ownerIssue: 2747, sourcePath: "release/product-gates/mobility-profile-policy.json", rawSha256: "5a63a03ff9ec9b61e0366d947251ee9294ebd48777b28b1ad6e2bdbe2d3fcc50", sizeBytes: 635, fixturePath: "apps/mobile/test/fixtures/contracts/product/mobility-profile-policy.json" },
  ]);
});

test("lock and artifact/run metadata reject mutable, unknown, and mismatched identities", async () => {
  const lock = await exactLock();
  for (const mutate of [
    (value) => { value.artifact.archiveUrl = "https://example.invalid/latest"; },
    (value) => { value.resources.push(clone(value.resources[0])); },
    (value) => { value.publication.untrusted = true; },
    (value) => { value.artifact.expiresAt = "2026-11-06T21:30:00Z"; },
    (value) => { value.artifact.expiresAt = "2026-11-07T21:44:51Z"; },
  ]) { const invalid = clone(lock); mutate(invalid); assert.throws(() => validateGenericMobileConsumerBundleLock(invalid)); }
  const metadata = artifactMetadata(lock);
  for (const mutate of [(value) => { value.id += 1; }, (value) => { value.expired = true; }, (value) => { value.digest = "sha256:0".repeat(64); }, (value) => { value.workflow_run.head_branch = "release"; }, (value) => { value.workflow_run.head_sha = "0".repeat(40); }, (value) => { value.workflow_run.head_repository_id += 1; }, (value) => { delete value.workflow_run.repository_id; }]) { const invalid = clone(metadata); mutate(invalid); assert.throws(() => validateArtifactMetadata(invalid, lock)); }
  assert.equal(Object.hasOwn(metadata.workflow_run, "workflow_id"), false);
  assert.equal(Object.hasOwn(metadata.workflow_run, "run_attempt"), false);
  for (const mutate of [(value) => { value.id += 1; }, (value) => { value.workflow_id += 1; }, (value) => { value.run_attempt += 1; }, (value) => { value.path = ".github/workflows/other.yml@refs/heads/main"; }, (value) => { value.event = "push"; }, (value) => { value.status = "in_progress"; }, (value) => { value.conclusion = "failure"; }, (value) => { value.head_branch = "release"; }, (value) => { value.head_sha = "0".repeat(40); }, (value) => { value.repository.id += 1; }, (value) => { value.repository.full_name = "AquilaXk/other"; }, (value) => { delete value.workflow_id; }, (value) => { value.repository = []; }]) { const invalid = clone(runMetadata(lock)); mutate(invalid); await assert.rejects(stageGenericMobileConsumerBundle({ lock, metadata, runMetadata: invalid, archivePath: "/invalid/archive.zip", fixtureRoot: root, stageRoot: "/invalid/stage" }), /workflow run metadata/); }
});

test("duplicate JSON keys fail before semantic validation", () => {
  assert.throws(() => parseJsonWithoutDuplicateKeys('{"schemaVersion":1,"schemaVersion":1}', "bundle"), /duplicate key/);
});

test("valid local ZIP stages immutable resources and atomically writes current", async () => withTemporary(async (directory) => {
  const artifact = await buildArtifact(directory); const stageRoot = path.join(directory, "stage");
  const result = await stageGenericMobileConsumerBundle({ ...artifact, fixtureRoot: root, stageRoot });
  assert.equal(result.archiveSha256, artifact.lock.artifact.archiveSha256);
  assert.deepEqual(JSON.parse(await readFile(path.join(stageRoot, "current.json"))), { archiveSha256: artifact.lock.artifact.archiveSha256, versionDirectory: `versions/${artifact.lock.artifact.archiveSha256}` });
  for (const resource of artifact.lock.resources) assert.deepEqual(await readFile(path.join(result.versionDirectory, "resources", resource.resourceId)), await readFile(path.join(root, resource.fixturePath)));
}));

test("archive digest and ZIP entry list fail before current mutation", async () => withTemporary(async (directory) => {
  const artifact = await buildArtifact(directory, { extraEntry: "unexpected.json" }); const stageRoot = path.join(directory, "stage");
  await assert.rejects(stageGenericMobileConsumerBundle({ ...artifact, fixtureRoot: root, stageRoot }), /ZIP entries/);
  await assert.rejects(lstat(path.join(stageRoot, "current.json")), { code: "ENOENT" });
  const wrongDigest = clone(artifact); wrongDigest.lock.artifact.archiveSha256 = "0".repeat(64); wrongDigest.metadata.digest = `sha256:${wrongDigest.lock.artifact.archiveSha256}`;
  await assert.rejects(stageGenericMobileConsumerBundle({ ...wrongDigest, fixtureRoot: root, stageRoot }), /archive digest/);
}));

test("run metadata mismatch fails before ZIP listing, extraction, and current mutation", async () => withTemporary(async (directory) => {
  const artifact = await buildArtifact(directory); const stageRoot = path.join(directory, "stage"); const previous = Buffer.from('{"archiveSha256":"old","versionDirectory":"versions/old"}\n');
  await (await import("node:fs/promises")).mkdir(stageRoot); await writeFile(path.join(stageRoot, "current.json"), previous);
  const invalid = clone(artifact); invalid.runMetadata.workflow_id += 1;
  let unzipCalls = 0;
  await assert.rejects(stageGenericMobileConsumerBundle({ ...invalid, fixtureRoot: root, stageRoot, execFileImpl: async () => { unzipCalls += 1; throw new Error("unzip must not run"); } }), /workflow run metadata/);
  assert.equal(unzipCalls, 0);
  assert.deepEqual(await readFile(path.join(stageRoot, "current.json")), previous);
}));

test("symlinked extracted files fail even when the ZIP entry list is exact", async () => withTemporary(async (directory) => {
  const artifact = await buildArtifact(directory, { symlinkBundle: true });
  await assert.rejects(stageGenericMobileConsumerBundle({ ...artifact, fixtureRoot: root, stageRoot: path.join(directory, "stage") }), /regular non-symlink/);
}));

test("raw and semantic bundle, receipt, inventory, payload, base64, and fixture mismatches fail closed", async () => withTemporary(async (directory) => {
  const cases = [
    { name: "bundle component", options: { mutateBundle: (bundle) => { bundle.component = "other"; } } },
    { name: "resource identity", options: { mutateBundle: (bundle) => { bundle.resources[0].sourcePath = "unexpected.json"; } } },
    { name: "bundle base64", options: { mutateBundle: (bundle) => { bundle.resources[0].contentBase64 = "bad"; } } },
    { name: "inventory", options: { mutateBundle: (bundle) => { bundle.resourceInventorySha256 = "0".repeat(64); } } },
    { name: "payload", options: { mutateBundle: (bundle) => { bundle.payloadSha256 = "0".repeat(64); } } },
    { name: "receipt policy", options: { mutateReceipt: (receipt) => { receipt.publication.overwrite = true; } } },
    { name: "fixture", options: { mutateResource: (bytes) => { bytes[0][0] = bytes[0][0] ^ 1; } } },
  ];
  for (const [index, item] of cases.entries()) {
    const caseDirectory = path.join(directory, String(index)); await (await import("node:fs/promises")).mkdir(caseDirectory);
    const artifact = await buildArtifact(caseDirectory, item.options);
    await assert.rejects(stageGenericMobileConsumerBundle({ ...artifact, fixtureRoot: root, stageRoot: path.join(caseDirectory, "stage") }), undefined, item.name);
  }
}));

test("failed pointer writes and renames preserve an existing current pointer", async () => withTemporary(async (directory) => {
  const previous = Buffer.from('{"archiveSha256":"old","versionDirectory":"versions/old"}\n');
  const promises = await import("node:fs/promises");
  for (const [index, fs] of [
    { lstat, mkdir: promises.mkdir, rm, rename: async (from, to) => { if (path.basename(to) === "current.json") throw new Error("injected rename failure"); return rename(from, to); }, writeFile },
    { lstat, mkdir: promises.mkdir, rm, rename, writeFile: async (target, bytes, options) => { if (path.basename(target).startsWith(".current-")) throw new Error("injected write failure"); return writeFile(target, bytes, options); } },
  ].entries()) {
    const artifactDirectory = path.join(directory, `artifact-${index}`); const stageRoot = path.join(directory, `stage-${index}`); await promises.mkdir(artifactDirectory); await promises.mkdir(stageRoot, { recursive: true }); await writeFile(path.join(stageRoot, "current.json"), previous);
    const artifact = await buildArtifact(artifactDirectory);
    await assert.rejects(stageGenericMobileConsumerBundle({ ...artifact, fixtureRoot: root, stageRoot, fs }), /injected (rename|write) failure/);
    assert.deepEqual(await readFile(path.join(stageRoot, "current.json")), previous);
    await assert.rejects(lstat(path.join(stageRoot, "versions", artifact.lock.artifact.archiveSha256)), { code: "ENOENT" });
  }
}));

test("stager has no network primitive", async () => {
  const source = await readFile(new URL("./stage-generic-mobile-consumer-bundle.mjs", import.meta.url), "utf8");
  assert.doesNotMatch(source, /\b(fetch|https?\.request|net\.connect|child_process\.exec\()\b/);
});

test("CI fetches and stages only the exact Hub artifact before residual snapshots", async () => {
  const workflow = await readFile(path.join(root, ".github/workflows/ci.yml"), "utf8");
  const snapshots = await readFile(path.join(root, "contracts/mobile/consumer-snapshots.sha256"), "utf8");
  const metadataEndpoint = "/repos/AquilaXk/easysubway/actions/artifacts/9028141921";
  const archiveEndpoint = `${metadataEndpoint}/zip`;
  const runMetadataEndpoint = "/repos/AquilaXk/easysubway/actions/runs/31280042807";
  const runMetadataFetchIndex = workflow.indexOf(runMetadataEndpoint);
  const artifactMetadataFetchIndex = workflow.indexOf(metadataEndpoint);
  const archiveFetchIndex = workflow.indexOf(archiveEndpoint);
  const fetchIndex = workflow.indexOf("Fetch exact generic mobile consumer bundle");
  const stageIndex = workflow.indexOf("Stage exact generic mobile consumer bundle");
  const checksumIndex = workflow.indexOf("Verify residual consumer snapshots");

  assert.ok(fetchIndex >= 0 && stageIndex > fetchIndex && checksumIndex > stageIndex, "fetch, stage, and residual checksum steps must be ordered");
  assert.ok(runMetadataFetchIndex >= 0 && artifactMetadataFetchIndex > runMetadataFetchIndex && archiveFetchIndex > artifactMetadataFetchIndex, "run metadata must be fetched once before artifact metadata and ZIP");
  assert.match(workflow, /GH_TOKEN: \$\{\{ secrets\.HUB_ACTIONS_ARTIFACT_READ_TOKEN \}\}/);
  assert.match(workflow, new RegExp(`gh api --method GET[^\\n]*${metadataEndpoint}`));
  assert.match(workflow, new RegExp(`gh api --method GET[^\\n]*${archiveEndpoint}`));
  assert.match(workflow, new RegExp(`gh api --method GET[^\\n]*${runMetadataEndpoint}`));
  assert.equal(workflow.match(new RegExp(runMetadataEndpoint.replaceAll("/", "\\/"), "g"))?.length, 1);
  assert.match(workflow, /if \[\[ -z "\$\{GH_TOKEN:-\}" \]\]; then/);
  assert.match(workflow, /umask 077/);
  assert.match(workflow, /if \[\[ -e "\$BUNDLE_INPUT_ROOT" \|\| -L "\$BUNDLE_INPUT_ROOT" \]\]; then/);
  assert.match(workflow, /node tools\/mobile\/stage-generic-mobile-consumer-bundle\.mjs \\\n\s+--lock contracts\/mobile\/generic-mobile-consumer-bundle\.lock\.json \\\n\s+--metadata "\$BUNDLE_INPUT_ROOT\/metadata\.json" \\\n\s+--workflow-run "\$BUNDLE_INPUT_ROOT\/run-metadata\.json" \\\n\s+--archive "\$BUNDLE_INPUT_ROOT\/artifact\.zip" \\\n\s+--fixture-root "\$GITHUB_WORKSPACE" \\\n\s+--stage-root "\$BUNDLE_STAGE_ROOT"/);
  assert.match(workflow, /tools\/mobile\/stage-generic-mobile-consumer-bundle\.test\.mjs/);
  assert.equal(snapshots, [
    "1ea9a8511b290acb8092f87d7d087e16636013b5cd950157d4782b4437da17fe  apps/mobile/test/fixtures/contracts/api/report-status.ok.json",
    "351ed8d5021c825751eaadaf97a3a76621480ea8f5e8ae522e028a416fcc655d  apps/mobile/test/fixtures/contracts/api/report-upload-intent.created.json",
    "b2eef2284186a12e18ac06de1d339c0feca2194c5d556db8628e84287536d7e0  apps/mobile/test/fixtures/contracts/datapack/canonical-number-contract.json",
    "c3f6f3e8d13806dc6a3f10ce5e900b5477f8f866c04225f9eca85d278597bb31  apps/mobile/test/fixtures/contracts/backend/messages.properties",
    "",
  ].join("\n"));
});
