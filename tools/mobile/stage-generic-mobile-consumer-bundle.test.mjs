import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { lstat, mkdtemp, readFile, rename, rm, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";
import {
  parseJsonWithoutDuplicateKeys,
  stageGenericMobileConsumerBundle,
  validateBundle,
  validateGenericMobileConsumerBundleLock,
} from "./stage-generic-mobile-consumer-bundle.mjs";

const root = path.resolve(fileURLToPath(new URL("../..", import.meta.url)));
const lockPath = path.join(root, "contracts/mobile/generic-mobile-consumer-bundle.lock.json");
const sha256 = (value) => createHash("sha256").update(value).digest("hex");
const clone = (value) => structuredClone(value);

async function exactLock() { return JSON.parse(await readFile(lockPath, "utf8")); }
function canonical(value) {
  return Array.isArray(value)
    ? `[${value.map(canonical).join(",")}]`
    : value && typeof value === "object"
    ? `{${Object.keys(value).sort().map((key) => `${JSON.stringify(key)}:${canonical(value[key])}`).join(",")}}`
    : JSON.stringify(value);
}
async function temporary() { return mkdtemp(path.join(os.tmpdir(), "mobile-generic-consumer-")); }

async function buildBundle(options = {}) {
  const lock = clone(await exactLock());
  const resourceBytes = await Promise.all(lock.resources.map((resource) => readFile(path.join(root, resource.fixturePath))));
  if (options.mutateResource) options.mutateResource(resourceBytes, lock);
  for (const [index, resource] of lock.resources.entries()) {
    resource.rawSha256 = sha256(resourceBytes[index]);
    resource.sizeBytes = resourceBytes[index].length;
  }
  const resources = lock.resources.map((resource, index) => ({
    resourceId: resource.resourceId,
    mediaType: resource.mediaType,
    schemaVersion: resource.schemaVersion,
    ownerRepository: resource.ownerRepository,
    ownerIssue: resource.ownerIssue,
    sourcePath: resource.sourcePath,
    contentBase64: resourceBytes[index].toString("base64"),
    rawSha256: resource.rawSha256,
    sizeBytes: resource.sizeBytes,
  }));
  lock.resourceInventorySha256 = sha256(canonical(resources.map(({ resourceId, mediaType, schemaVersion, ownerRepository, ownerIssue, sourcePath }) => ({ resourceId, mediaType, schemaVersion, ownerRepository, ownerIssue, sourcePath }))));
  lock.payloadSha256 = sha256(canonical(resources.map(({ resourceId, sizeBytes, rawSha256 }) => ({ resourceId, sizeBytes, rawSha256 }))));
  const bundle = {
    schemaVersion: 1,
    artifactKind: "generic-mobile-consumer-bundle",
    component: lock.component,
    bundleVersion: lock.bundleVersion,
    producer: lock.producer,
    resources,
    resourceInventorySha256: lock.resourceInventorySha256,
    payloadSha256: lock.payloadSha256,
  };
  if (options.mutateBundle) options.mutateBundle(bundle);
  const bundleBytes = Buffer.from(`${JSON.stringify(bundle, null, 2)}\n`);
  lock.bundle.rawSha256 = sha256(bundleBytes);
  lock.bundle.sizeBytes = bundleBytes.length;
  return { bundleBytes, lock };
}

async function withTemporary(callback) {
  const directory = await temporary();
  try { return await callback(directory); }
  finally { await rm(directory, { recursive: true, force: true }); }
}

test("exact Hub permanent bundle lock validates and pins the published identities", async () => {
  const lock = validateGenericMobileConsumerBundleLock(await exactLock());
  assert.deepEqual(
    [lock.producer.repository, lock.producer.gitSha],
    ["AquilaXk/easysubway", "978260c3bedfca8b7a2c35f07b3e780eee0fa4ec"]
  );
  assert.deepEqual(
    [lock.bundle.path, lock.bundle.rawSha256, lock.bundle.sizeBytes],
    [
      "contracts/bundles/generic-mobile-consumer-bundle-v1.json",
      "7f666d016119591e5c958e7d55c936fffb5e753898e69ec28e4f0cb50b5555ff",
      4415,
    ]
  );
  assert.equal(
    lock.bundle.url,
    "https://raw.githubusercontent.com/AquilaXk/easysubway/978260c3bedfca8b7a2c35f07b3e780eee0fa4ec/contracts/bundles/generic-mobile-consumer-bundle-v1.json"
  );
  assert.deepEqual(lock.resources, [
    {
      resourceId: "errors/error-codes.json",
      mediaType: "application/json",
      schemaVersion: null,
      ownerRepository: "AquilaXk/easysubway",
      ownerIssue: 2747,
      sourcePath: "contracts/error-codes.json",
      rawSha256: "7527a60514a7000ae8df0c958516a856dfdc288b6e085e4efbde9e3ce61d4bf9",
      sizeBytes: 1723,
      fixturePath: "apps/mobile/test/fixtures/contracts/error-codes.json",
    },
    {
      resourceId: "product/mobility-profile-policy.json",
      mediaType: "application/json",
      schemaVersion: 1,
      ownerRepository: "AquilaXk/easysubway",
      ownerIssue: 2747,
      sourcePath: "release/product-gates/mobility-profile-policy.json",
      rawSha256: "5a63a03ff9ec9b61e0366d947251ee9294ebd48777b28b1ad6e2bdbe2d3fcc50",
      sizeBytes: 635,
      fixturePath: "apps/mobile/test/fixtures/contracts/product/mobility-profile-policy.json",
    },
  ]);
});

test("lock rejects mutable, unknown, and mismatched identities", async () => {
  const lock = await exactLock();
  for (const mutate of [
    (value) => { value.bundle.url = "https://example.invalid/latest"; },
    (value) => { value.resources.push(clone(value.resources[0])); },
    (value) => { value.bundle.untrusted = true; },
    (value) => { value.bundle.rawSha256 = "not-a-sha256"; },
  ]) {
    const invalid = clone(lock);
    mutate(invalid);
    assert.throws(() => validateGenericMobileConsumerBundleLock(invalid));
  }
});

test("duplicate JSON keys fail before semantic validation", () => {
  assert.throws(() => parseJsonWithoutDuplicateKeys('{"schemaVersion":1,"schemaVersion":1}', "bundle"), /duplicate key/);
});

test("valid local bundle stages immutable resources and atomically writes current", async () => withTemporary(async (directory) => {
  const { bundleBytes, lock } = await buildBundle();
  const stageRoot = path.join(directory, "stage");
  const result = await stageGenericMobileConsumerBundle({ lock, bundleBytes, fixtureRoot: root, stageRoot });
  assert.equal(result.rawSha256, lock.bundle.rawSha256);
  assert.deepEqual(JSON.parse(await readFile(path.join(stageRoot, "current.json"))), {
    rawSha256: lock.bundle.rawSha256,
    versionDirectory: `versions/${lock.bundle.rawSha256}`,
  });
  for (const resource of lock.resources) {
    assert.deepEqual(
      await readFile(path.join(result.versionDirectory, "resources", resource.resourceId)),
      await readFile(path.join(root, resource.fixturePath))
    );
  }
}));

test("bundle digest and size mismatches fail closed before current mutation", async () => withTemporary(async (directory) => {
  const { bundleBytes, lock } = await buildBundle();
  const stageRoot = path.join(directory, "stage");
  const tamperedBytes = Buffer.from(bundleBytes);
  tamperedBytes[tamperedBytes.length - 2] ^= 1;
  await assert.rejects(
    stageGenericMobileConsumerBundle({ lock, bundleBytes: tamperedBytes, fixtureRoot: root, stageRoot }),
    /raw identity/
  );
  await assert.rejects(lstat(path.join(stageRoot, "current.json")), { code: "ENOENT" });
}));

test("raw and semantic bundle, inventory, payload, base64, and fixture mismatches fail closed", async () => withTemporary(async (directory) => {
  const cases = [
    { name: "bundle component", options: { mutateBundle: (bundle) => { bundle.component = "other"; } } },
    { name: "resource identity", options: { mutateBundle: (bundle) => { bundle.resources[0].sourcePath = "unexpected.json"; } } },
    { name: "bundle base64", options: { mutateBundle: (bundle) => { bundle.resources[0].contentBase64 = "bad"; } } },
    { name: "inventory", options: { mutateBundle: (bundle) => { bundle.resourceInventorySha256 = "0".repeat(64); } } },
    { name: "payload", options: { mutateBundle: (bundle) => { bundle.payloadSha256 = "0".repeat(64); } } },
    { name: "fixture", options: { mutateResource: (bytes) => { bytes[0][0] = bytes[0][0] ^ 1; } } },
  ];
  for (const [index, item] of cases.entries()) {
    const caseDirectory = path.join(directory, String(index));
    const { bundleBytes, lock } = await buildBundle(item.options);
    await assert.rejects(
      stageGenericMobileConsumerBundle({ lock, bundleBytes, fixtureRoot: root, stageRoot: path.join(caseDirectory, "stage") }),
      undefined,
      item.name
    );
  }
}));

test("failed pointer writes and renames preserve an existing current pointer", async () => withTemporary(async (directory) => {
  const previous = Buffer.from('{"rawSha256":"old","versionDirectory":"versions/old"}\n');
  const promises = await import("node:fs/promises");
  for (const [index, fs] of [
    { lstat, mkdir: promises.mkdir, rm, rename: async (from, to) => { if (path.basename(to) === "current.json") throw new Error("injected rename failure"); return rename(from, to); }, writeFile },
    { lstat, mkdir: promises.mkdir, rm, rename, writeFile: async (target, bytes, options) => { if (path.basename(target).startsWith(".current-")) throw new Error("injected write failure"); return writeFile(target, bytes, options); } },
    { lstat, mkdir: promises.mkdir, rm: async (target, options) => { if (target.includes(`${path.sep}versions${path.sep}`)) throw new Error("injected cleanup failure"); return rm(target, options); }, rename: async (from, to) => { if (path.basename(to) === "current.json") throw new Error("injected rename failure"); return rename(from, to); }, writeFile },
  ].entries()) {
    const stageRoot = path.join(directory, `stage-${index}`);
    await promises.mkdir(stageRoot, { recursive: true });
    await writeFile(path.join(stageRoot, "current.json"), previous);
    const { bundleBytes, lock } = await buildBundle();
    await assert.rejects(
      stageGenericMobileConsumerBundle({ lock, bundleBytes, fixtureRoot: root, stageRoot, fs }),
      /injected (rename|write) failure/
    );
    assert.deepEqual(await readFile(path.join(stageRoot, "current.json")), previous);
    const stagedVersion = path.join(stageRoot, "versions", lock.bundle.rawSha256);
    if (index === 2) assert.equal((await lstat(stagedVersion)).isDirectory(), true);
    else await assert.rejects(lstat(stagedVersion), { code: "ENOENT" });
  }
}));

test("stager has no network primitive", async () => {
  const source = await readFile(new URL("./stage-generic-mobile-consumer-bundle.mjs", import.meta.url), "utf8");
  assert.doesNotMatch(source, /\b(fetch|https?\.request|net\.connect|child_process\.exec\()\b/);
});

test("CI fetches permanent bundle from raw URL and stages it before residual snapshots", async () => {
  const workflow = await readFile(path.join(root, ".github/workflows/ci.yml"), "utf8");
  const snapshots = await readFile(path.join(root, "contracts/mobile/consumer-snapshots.sha256"), "utf8");
  const bundleUrlExpr = "contracts/mobile/generic-mobile-consumer-bundle.lock.json";
  const fetchIndex = workflow.indexOf("Fetch exact generic mobile consumer bundle");
  const stageIndex = workflow.indexOf("Stage exact generic mobile consumer bundle");
  const checksumIndex = workflow.indexOf("Verify residual consumer snapshots");

  assert.ok(fetchIndex >= 0 && stageIndex > fetchIndex && checksumIndex > stageIndex, "fetch, stage, and residual checksum steps must be ordered");
  assert.match(workflow, /bundle_url="\$\(jq -er '\.bundle\.url' contracts\/mobile\/generic-mobile-consumer-bundle\.lock\.json\)"/);
  assert.match(workflow, /curl --fail --silent --show-error --location/);
  assert.match(workflow, /node tools\/mobile\/stage-generic-mobile-consumer-bundle\.mjs \\\n\s+--lock contracts\/mobile\/generic-mobile-consumer-bundle\.lock\.json \\\n\s+--bundle "\$\{RUNNER_TEMP\}\/generic-mobile-consumer-bundle-v1\.json" \\\n\s+--fixture-root "\$GITHUB_WORKSPACE" \\\n\s+--stage-root "\$BUNDLE_STAGE_ROOT"/);
  assert.match(workflow, /tools\/mobile\/stage-generic-mobile-consumer-bundle\.test\.mjs/);
  assert.equal(snapshots, [
    "1ea9a8511b290acb8092f87d7d087e16636013b5cd950157d4782b4437da17fe  apps/mobile/test/fixtures/contracts/api/report-status.ok.json",
    "351ed8d5021c825751eaadaf97a3a76621480ea8f5e8ae522e028a416fcc655d  apps/mobile/test/fixtures/contracts/api/report-upload-intent.created.json",
    "b2eef2284186a12e18ac06de1d339c0feca2194c5d556db8628e84287536d7e0  apps/mobile/test/fixtures/contracts/datapack/canonical-number-contract.json",
    "c3f6f3e8d13806dc6a3f10ce5e900b5477f8f866c04225f9eca85d278597bb31  apps/mobile/test/fixtures/contracts/backend/messages.properties",
    "",
  ].join("\n"));
});
