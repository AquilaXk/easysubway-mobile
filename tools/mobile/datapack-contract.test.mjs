import assert from "node:assert/strict";
import { readFile, readdir, writeFile } from "node:fs/promises";
import { mkdtemp } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import test from "node:test";

import {
  CONTRACT_VERSION,
  buildMobileComponentManifest,
  canonicalJson,
  sha256,
  validateOfflineCandidate,
  verifyTrustedAabEntries,
  writeMobileComponentManifest,
  writeAtomicStagingPlan,
} from "./datapack-contract.mjs";

const here = path.dirname(new URL(import.meta.url).pathname);
const fixture = JSON.parse(await readFile(path.join(here, "fixtures/datapack-lock.valid.json"), "utf8"));

function clone(value) { return JSON.parse(JSON.stringify(value)); }
function bytesFor(pack) { return Buffer.from(pack.id); }
function identityWithFixtureBytes() {
  const identity = clone(fixture);
  identity.manifestSha256 = sha256(Buffer.from("manifest"));
  identity.packs = identity.packs.map((pack) => ({ ...pack, sha256: sha256(bytesFor(pack)) }));
  return identity;
}

test("schema snapshots are fixed to the Task 6 contract version and digest", async () => {
  const lockSchema = await readFile(path.join(here, "fixtures/datapack-lock.schema.json"));
  const componentSchema = await readFile(path.join(here, "fixtures/mobile-component-manifest.schema.json"));
  assert.equal(CONTRACT_VERSION, "mobile-datapack-contract-v1");
  assert.equal(sha256(lockSchema), "2f55469b913016d531be32bd4360bc0079d1ae5a7b3ce305466a6ede6116be11");
  assert.equal(sha256(componentSchema), "5ea2b4e05dd80822ebebef4e6674cddb1cd4d107c75f74182a7c7a512c480175");
});

test("offline candidate accepts only the exactly pinned identity", () => {
  const valid = identityWithFixtureBytes();
  assert.deepEqual(validateOfflineCandidate({ lock: valid, candidateManifest: clone(valid) }), valid);
  for (const mutate of [
    (value) => { value.schemaVersion = 2; },
    (value) => { value.contractVersion = "other"; },
    (value) => { value.releaseSequence += 1; },
    (value) => { value.manifestSha256 = "b".repeat(64); },
    (value) => { value.packs[0].sha256 = "c".repeat(64); },
  ]) {
    const invalid = clone(valid); mutate(invalid);
    assert.throws(() => validateOfflineCandidate({ lock: valid, candidateManifest: invalid }));
  }
});

test("offline candidate rejects unknown root and pack fields", () => {
  const valid = identityWithFixtureBytes();
  const lockWithUnknown = clone(valid);
  lockWithUnknown.unreviewed = true;
  assert.throws(() => validateOfflineCandidate({ lock: lockWithUnknown, candidateManifest: valid }));
  const candidateWithUnknownPackField = clone(valid);
  candidateWithUnknownPackField.packs[0].unreviewed = true;
  assert.throws(() => validateOfflineCandidate({ lock: valid, candidateManifest: candidateWithUnknownPackField }));
});

test("offline candidate rejects noncanonical POSIX pack path aliases", () => {
  const valid = identityWithFixtureBytes();
  for (const alias of ["nested//core.sqlite.gz", "nested/./core.sqlite.gz", "nested/core.sqlite.gz/"]) {
    const invalid = clone(valid);
    invalid.packs[0].path = alias;
    assert.throws(() => validateOfflineCandidate({ lock: invalid, candidateManifest: invalid }));
  }
});

test("atomic staging plan is deterministic and preserves old output on failure", async () => {
  const directory = await mkdtemp(path.join(tmpdir(), "datapack-contract-"));
  const targetPath = path.join(directory, "plan.json");
  const identity = identityWithFixtureBytes();
  const plan = await writeAtomicStagingPlan({ targetPath, lock: identity, candidateManifest: clone(identity) });
  assert.equal(await readFile(targetPath, "utf8"), `${canonicalJson(plan)}\n`);
  await writeFile(targetPath, "old-plan", "utf8");
  await assert.rejects(() => writeAtomicStagingPlan({
    targetPath,
    lock: identity,
    candidateManifest: clone(identity),
    writeFileImpl: async () => { throw new Error("injected write failure"); },
  }));
  assert.equal(await readFile(targetPath, "utf8"), "old-plan");
  assert.deepEqual((await readdir(directory)).filter((name) => name.includes(".tmp-")), []);
});

test("trusted AAB entries require exact, unique, safe pinned bytes", () => {
  const identity = identityWithFixtureBytes();
  const valid = [
    { name: "assets/datapacks/index.json", bytes: Buffer.from("manifest") },
    ...identity.packs.map((pack) => ({ name: `assets/datapacks/${pack.path}`, bytes: bytesFor(pack) })),
  ];
  assert.deepEqual(verifyTrustedAabEntries({ identity, entries: valid }), { manifestSha256: identity.manifestSha256, packCount: 2 });
  for (const entries of [
    valid.slice(1),
    [...valid, valid[0]],
    [...valid, { name: "assets/datapacks/extra.gz", bytes: Buffer.from("extra") }],
    [{ name: "assets//datapacks/core.sqlite.gz", bytes: Buffer.from("core") }, ...valid.slice(2)],
    [{ ...valid[0], bytes: Buffer.from("wrong") }, ...valid.slice(1)],
  ]) assert.throws(() => verifyTrustedAabEntries({ identity, entries }));
});

test("component manifest is deterministic and rejects noncanonical evidence", async () => {
  const evidence = { aabEntries: 2, verified: true };
  const input = {
    repository: "AquilaXk/easysubway-mobile",
    gitSha: "d".repeat(40),
    versionName: "1.2.3",
    versionCode: 123,
    aabSha256: "e".repeat(64),
    bundledDataManifestSha256: "f".repeat(64),
    contractVersion: CONTRACT_VERSION,
    evidence,
    evidenceSha256: sha256(canonicalJson(evidence)),
    issueRefs: ["AquilaXk/easysubway#2718", "AquilaXk/easysubway-mobile#4"],
  };
  const first = buildMobileComponentManifest(input);
  const second = buildMobileComponentManifest({ ...input, evidence: { verified: true, aabEntries: 2 }, issueRefs: [...input.issueRefs].reverse() });
  assert.deepEqual(first, second);
  assert.throws(() => buildMobileComponentManifest({ ...input, evidenceSha256: "0".repeat(64) }));
  assert.throws(() => buildMobileComponentManifest({ ...input, unreviewed: true }));
  for (const invalid of [
    { ...input, repository: "AquilaXk/easysubway-mobile\n" },
    { ...input, gitSha: `${"d".repeat(40)}\n` },
    { ...input, issueRefs: ["AquilaXk/easysubway-mobile#4\n"] },
    { ...input, aabSha256: `${"e".repeat(64)}\n` },
  ]) assert.throws(() => buildMobileComponentManifest(invalid));
  const directory = await mkdtemp(path.join(tmpdir(), "component-manifest-"));
  const targetPath = path.join(directory, "mobile-component-manifest.json");
  await writeMobileComponentManifest({ targetPath, input });
  assert.equal(await readFile(targetPath, "utf8"), first.text);
  await writeFile(targetPath, "old-manifest", "utf8");
  await assert.rejects(() => writeMobileComponentManifest({
    targetPath,
    input,
    writeFileImpl: async () => { throw new Error("injected write failure"); },
  }));
  assert.equal(await readFile(targetPath, "utf8"), "old-manifest");
  assert.deepEqual((await readdir(directory)).filter((name) => name.includes(".tmp-")), []);
});

test("component issue references use codepoint order, not the host locale", () => {
  const evidence = { verified: true };
  const component = buildMobileComponentManifest({
    repository: "AquilaXk/easysubway-mobile",
    gitSha: "d".repeat(40),
    versionName: "1.2.3",
    versionCode: 123,
    aabSha256: "e".repeat(64),
    bundledDataManifestSha256: "f".repeat(64),
    contractVersion: CONTRACT_VERSION,
    evidence,
    evidenceSha256: sha256(canonicalJson(evidence)),
    issueRefs: ["AquilaXk/a#2", "AquilaXk/Z#1"],
  });
  assert.deepEqual(component.manifest.issueRefs, ["AquilaXk/Z#1", "AquilaXk/a#2"]);
});

test("contract writers hide local filesystem paths on write failure", async () => {
  const directory = await mkdtemp(path.join(tmpdir(), "datapack-contract-private-"));
  const identity = identityWithFixtureBytes();
  await assert.rejects(
    () => writeAtomicStagingPlan({ targetPath: directory, lock: identity, candidateManifest: identity }),
    (error) => error.message === "failed to write contract output" && !error.message.includes(directory),
  );
});
