import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { execFile } from "node:child_process";
import { mkdir, mkdtemp, readFile, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { promisify } from "node:util";
import test from "node:test";
import { verifyMapCatalogAab } from "./verify-map-catalog-aab.mjs";

const run = promisify(execFile);
const sha256 = (value) => createHash("sha256").update(value).digest("hex");
const canonical = (value) => Array.isArray(value) ? `[${value.map(canonical).join(",")}]` : value && typeof value === "object" ? `{${Object.keys(value).sort().map((key) => `${JSON.stringify(key)}:${canonical(value[key])}`).join(",")}}` : JSON.stringify(value);
const bytewise = (left, right) => Buffer.compare(Buffer.from(left), Buffer.from(right));

function fixture({ catalogPayload = Buffer.from("SQLite fixture") } = {}) {
  const payloads = { "map-pack/payload/metropolitan.svg": Buffer.from("<svg/>\n"), "map-pack/payload/stations-layout.json": Buffer.from("[]\n"), "map-pack/payload/line-styles.json": Buffer.from("[]\n"), "map-pack/payload/interchange-layout.json": Buffer.from("[]\n"), "station-catalog-pack/payload/catalog.sqlite": catalogPayload };
  const stationSetSha256 = sha256("stations");
  const pathsFor = (artifactKind) => Object.keys(payloads).filter((entryPath) => entryPath.startsWith(`${artifactKind}/`));
  const manifest = (artifactKind, idKey, id) => ({ manifestVersion: 1, artifactKind, [idKey]: id, stationSetSha256, payloadSha256: sha256(Buffer.from(canonical(pathsFor(artifactKind).map((entryPath) => ({ path: entryPath.replace(/^[^/]+\//, ""), sizeBytes: payloads[entryPath].length, sha256: sha256(payloads[entryPath]) })).sort((left, right) => bytewise(left.path, right.path))), "utf8")) });
  const manifests = { "map-pack/manifest.json": manifest("map-pack", "mapPackId", "map-1"), "station-catalog-pack/manifest.json": manifest("station-catalog-pack", "catalogPackId", "catalog-1") };
  const files = { ...payloads, ...Object.fromEntries(Object.entries(manifests).map(([entryPath, value]) => [entryPath, Buffer.from(`${JSON.stringify(value)}\n`)])) };
  const file = (entryPath) => ({ path: entryPath, sizeBytes: files[entryPath].length, sha256: sha256(files[entryPath]) });
  const artifact = (artifactKind) => ({ artifactKind, manifest: { ...file(`${artifactKind}/manifest.json`), ...manifests[`${artifactKind}/manifest.json`] }, payload: pathsFor(artifactKind).map(file) });
  return { files, lock: { schemaVersion: 1, contractVersion: "mobile-map-catalog-content-lock-v1", dataRelease: { producerRepository: "AquilaXk/easysubway-data", producerGitSha: "a".repeat(40), releaseSequence: 1, signedFinalDescriptorSha256: "b".repeat(64), publicationReceiptSha256: "c".repeat(64) }, artifacts: [artifact("map-pack"), artifact("station-catalog-pack")] } };
}

async function makeAab({ forbidden = false, drift = false, catalogPayload } = {}) {
  const root = await mkdtemp(path.join(tmpdir(), "map-catalog-aab-")); const value = fixture({ catalogPayload });
  for (const [entryPath, bytes] of Object.entries(value.files)) { const target = path.join(root, "base/assets/flutter_assets/assets/datapacks", entryPath); await mkdir(path.dirname(target), { recursive: true }); await writeFile(target, bytes); }
  if (drift) await writeFile(path.join(root, "base/assets/flutter_assets/assets/datapacks/map-pack/payload/metropolitan.svg"), "drift");
  if (forbidden) { const target = path.join(root, "base/assets/flutter_assets/assets/datapacks/server-route-bundle/payload/topology.sqlite.zst"); await mkdir(path.dirname(target), { recursive: true }); await writeFile(target, "forbidden"); }
  const aabPath = path.join(root, "app.aab"); await run("zip", ["-qr", aabPath, "base"], { cwd: root });
  return { ...value, aabPath, receiptPath: path.join(root, "evidence.json") };
}

const mobile = { repository: "AquilaXk/easysubway-mobile", gitSha: "d".repeat(40), versionName: "1.0.0", versionCode: 1 };

test("AAB readback validates exact map/catalog content and creates a receipt once", async () => {
  const { lock, aabPath, receiptPath } = await makeAab();
  const receipt = await verifyMapCatalogAab({ lock, aabPath, receiptPath, mobile });
  assert.equal(receipt.mobile.gitSha, mobile.gitSha);
  assert.deepEqual(JSON.parse(await readFile(receiptPath, "utf8")), receipt);
  await assert.rejects(verifyMapCatalogAab({ lock, aabPath, receiptPath, mobile }), /already exists/);
});

test("AAB readback rejects content drift and route/server/legacy payload entries", async () => {
  for (const options of [{ drift: true }, { forbidden: true }]) { const { lock, aabPath, receiptPath } = await makeAab(options); await assert.rejects(verifyMapCatalogAab({ lock, aabPath, receiptPath, mobile })); }
  const source = await readFile(new URL("./verify-map-catalog-aab.mjs", import.meta.url), "utf8");
  assert.doesNotMatch(source, /\b(fetch|https?\.request|net\.connect)\b/);
});

test("AAB readback accepts a lock-valid payload larger than 16 MiB", async () => {
  const { lock, aabPath, receiptPath } = await makeAab({ catalogPayload: Buffer.alloc(16 * 1024 * 1024 + 1, 0x61) });
  const receipt = await verifyMapCatalogAab({ lock, aabPath, receiptPath, mobile });
  assert.equal(receipt.artifacts[1].payload[0].sizeBytes, 16 * 1024 * 1024 + 1);
});

test("AAB readback keeps one immutable snapshot when the original path is replaced during inspection", async () => {
  const { lock, aabPath, receiptPath } = await makeAab(); const originalSha = sha256(await readFile(aabPath)); let replaced = false;
  const replacementDuringInspection = async (...args) => {
    const result = await run(...args);
    if (!replaced && args[1][0] === "-Z1") { replaced = true; await writeFile(aabPath, "replacement"); }
    return result;
  };
  const receipt = await verifyMapCatalogAab({ lock, aabPath, receiptPath, mobile, execFileImpl: replacementDuringInspection });
  assert.equal(receipt.aabSha256, originalSha);
});
