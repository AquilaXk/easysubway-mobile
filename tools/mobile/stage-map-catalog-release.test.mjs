import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { lstat, mkdir, mkdtemp, readFile, symlink, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import test from "node:test";
import { parseJsonWithoutDuplicateKeys, stageMapCatalogRelease, validateMapCatalogReleaseLock } from "./stage-map-catalog-release.mjs";

const sha256 = (value) => createHash("sha256").update(value).digest("hex");
const canonical = (value) => Array.isArray(value) ? `[${value.map(canonical).join(",")}]` : value && typeof value === "object" ? `{${Object.keys(value).sort().map((key) => `${JSON.stringify(key)}:${canonical(value[key])}`).join(",")}}` : JSON.stringify(value);
const bytewise = (left, right) => Buffer.compare(Buffer.from(left), Buffer.from(right));

function fixture() {
  const payloads = {
    "map-pack/payload/metropolitan.svg": Buffer.from("<svg/>\n"),
    "map-pack/payload/stations-layout.json": Buffer.from("[]\n"),
    "map-pack/payload/line-styles.json": Buffer.from("[]\n"),
    "map-pack/payload/interchange-layout.json": Buffer.from("[]\n"),
    "station-catalog-pack/payload/catalog.sqlite": Buffer.from("SQLite fixture"),
  };
  const stationSetSha256 = sha256("stations");
  const makeManifest = (artifactKind, idKey, id, paths) => {
    const inventory = paths.map((entryPath) => ({ path: entryPath.replace(/^[^/]+\//, ""), sizeBytes: payloads[entryPath].length, sha256: sha256(payloads[entryPath]) })).sort((left, right) => bytewise(left.path, right.path));
    return { manifestVersion: 1, artifactKind, [idKey]: id, stationSetSha256, payloadSha256: sha256(Buffer.from(canonical(inventory), "utf8")) };
  };
  const mapPayloadPaths = Object.keys(payloads).filter((entryPath) => entryPath.startsWith("map-pack/"));
  const catalogPayloadPaths = Object.keys(payloads).filter((entryPath) => entryPath.startsWith("station-catalog-pack/"));
  const manifests = {
    "map-pack/manifest.json": makeManifest("map-pack", "mapPackId", "map-1", mapPayloadPaths),
    "station-catalog-pack/manifest.json": makeManifest("station-catalog-pack", "catalogPackId", "catalog-1", catalogPayloadPaths),
  };
  const files = { ...payloads, ...Object.fromEntries(Object.entries(manifests).map(([entryPath, value]) => [entryPath, Buffer.from(`${JSON.stringify(value)}\n`)])) };
  const file = (entryPath) => ({ path: entryPath, sizeBytes: files[entryPath].length, sha256: sha256(files[entryPath]) });
  const artifact = (artifactKind, idKey, paths) => ({ artifactKind, manifest: { ...file(`${artifactKind}/manifest.json`), ...manifests[`${artifactKind}/manifest.json`] }, payload: paths.map(file) });
  return {
    files,
    lock: {
      schemaVersion: 1,
      contractVersion: "mobile-map-catalog-content-lock-v1",
      dataRelease: { producerRepository: "AquilaXk/easysubway-data", producerGitSha: "a".repeat(40), releaseSequence: 1, signedFinalDescriptorSha256: "b".repeat(64), publicationReceiptSha256: "c".repeat(64) },
      artifacts: [artifact("map-pack", "mapPackId", mapPayloadPaths), artifact("station-catalog-pack", "catalogPackId", catalogPayloadPaths)],
    },
  };
}

async function createInput(root, files) {
  for (const [entryPath, bytes] of Object.entries(files)) { const target = path.join(root, entryPath); await mkdir(path.dirname(target), { recursive: true }); await writeFile(target, bytes); }
}

test("lock is closed and fixes Data release raw identities plus ordered current artifact content", async () => {
  const schema = JSON.parse(await readFile(new URL("../../contracts/mobile/map-catalog-release-lock.schema.json", import.meta.url), "utf8"));
  assert.equal(schema.$id, "https://easysubway.kr/contracts/mobile/map-catalog-release-lock.schema.json");
  assert.equal(schema.additionalProperties, false);
  assert.deepEqual(schema.properties.artifacts.prefixItems.map((item) => item.properties.artifactKind.const), ["map-pack", "station-catalog-pack"]);
  const { lock } = fixture();
  assert.equal(validateMapCatalogReleaseLock(lock).artifacts[0].payload.length, 4);
  assert.equal(validateMapCatalogReleaseLock(lock).artifacts[1].payload.length, 1);
});

test("JSON parser rejects malformed UTF-8 and non-JSON whitespace, and retains __proto__ as an own unknown key", () => {
  assert.throws(() => parseJsonWithoutDuplicateKeys(Buffer.from([0x7b, 0x22, 0x78, 0x22, 0x3a, 0x22, 0xc3, 0x28, 0x22, 0x7d])), /UTF-8 JSON/);
  assert.throws(() => parseJsonWithoutDuplicateKeys('{\u000b"x":1}'), /invalid JSON/);
  const parsed = parseJsonWithoutDuplicateKeys('{"__proto__":true}');
  assert.equal(Object.getPrototypeOf(parsed), null);
  assert.deepEqual(Object.keys(parsed), ["__proto__"]);
  assert.throws(() => validateMapCatalogReleaseLock(parsed), /unknown or missing/);
});

test("lock runtime validator matches schema non-whitespace ID boundaries", () => {
  for (const id of [" map-1", "map-1 ", "\tmap-1", "map-1\n"]) {
    const { lock } = fixture();
    lock.artifacts[0].manifest.mapPackId = id;
    assert.throws(() => validateMapCatalogReleaseLock(lock), /component semantics/);
  }
});

test("stager accepts only exact manifest semantics and payload bytes into a create-only lock version", async () => {
  const root = await mkdtemp(path.join(tmpdir(), "map-catalog-stage-")); const inputRoot = path.join(root, "input"); const stageRoot = path.join(root, "stage"); const { lock, files } = fixture();
  await createInput(inputRoot, files);
  const result = await stageMapCatalogRelease({ lock, inputRoot, stageRoot });
  assert.match(path.basename(result.versionDirectory), /^[a-f0-9]{64}$/);
  assert.deepEqual(await readFile(path.join(result.versionDirectory, "map-pack/payload/metropolitan.svg")), files["map-pack/payload/metropolitan.svg"]);
  await assert.rejects(stageMapCatalogRelease({ lock, inputRoot, stageRoot }), /already exists/);
});

test("stager rejects traversal, symlink, extra, reverse-order, and semantic drift before creating a version", async () => {
  for (const mutate of [
    async ({ inputRoot }) => writeFile(path.join(inputRoot, "extra"), "extra"),
    async ({ inputRoot }) => symlink("payload/metropolitan.svg", path.join(inputRoot, "map-pack", "linked")),
    async ({ lock }) => { lock.artifacts.reverse(); },
    async ({ files, lock, inputRoot }) => { const manifest = JSON.parse(files["map-pack/manifest.json"]); manifest.mapPackId = "semantic-drift"; files["map-pack/manifest.json"] = Buffer.from(`${JSON.stringify(manifest)}\n`); lock.artifacts[0].manifest.sizeBytes = files["map-pack/manifest.json"].length; lock.artifacts[0].manifest.sha256 = sha256(files["map-pack/manifest.json"]); await writeFile(path.join(inputRoot, "map-pack/manifest.json"), files["map-pack/manifest.json"]); },
  ]) {
    const root = await mkdtemp(path.join(tmpdir(), "map-catalog-reject-")); const inputRoot = path.join(root, "input"); const stageRoot = path.join(root, "stage"); const value = fixture(); await createInput(inputRoot, value.files); await mutate({ ...value, inputRoot });
    await assert.rejects(stageMapCatalogRelease({ lock: value.lock, inputRoot, stageRoot }));
    await assert.rejects(lstat(path.join(stageRoot, "versions")));
  }
});
