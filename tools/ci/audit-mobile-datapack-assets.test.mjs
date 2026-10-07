import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { createHash } from "node:crypto";
import { mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { DatabaseSync } from "node:sqlite";
import test from "node:test";
import { promisify } from "node:util";
import { constants as zlibConstants, gzipSync } from "node:zlib";

const execFileAsync = promisify(execFile);
const script = path.resolve(import.meta.dirname, "audit-mobile-datapack-assets.mjs");

const sha256 = (bytes) => createHash("sha256").update(bytes).digest("hex");

// 감사 최소 요건(station_exits·data_quality_records·facilities·station_facility_evidence 각 1행)을 채우고
// 인덱스가 있는 SQLite 팩을 만든다. 페이지 반복 구조가 있어야 압축 전략 차이가 드러난다.
async function buildSqlitePack(directory) {
  const sqlitePath = path.join(directory, "source.sqlite");
  const database = new DatabaseSync(sqlitePath);
  try {
    database.exec(`
      CREATE TABLE catalog_metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL);
      INSERT INTO catalog_metadata VALUES ('artifactKind', 'production'), ('schemaVersion', '1');
      CREATE TABLE station_exits (id TEXT PRIMARY KEY, station_id TEXT NOT NULL, label TEXT NOT NULL);
      CREATE TABLE data_quality_records (id TEXT PRIMARY KEY, target_id TEXT NOT NULL, quality_level TEXT NOT NULL);
      CREATE TABLE facilities (id TEXT PRIMARY KEY, station_id TEXT NOT NULL, kind TEXT NOT NULL);
      CREATE TABLE station_facility_evidence (id TEXT PRIMARY KEY, station_id TEXT NOT NULL, facility_id TEXT NOT NULL);
      CREATE INDEX station_exits_by_station ON station_exits (station_id, label);
      CREATE INDEX facilities_by_station ON facilities (station_id, kind);
    `);
    const insertExit = database.prepare("INSERT INTO station_exits VALUES (?, ?, ?)");
    const insertFacility = database.prepare("INSERT INTO facilities VALUES (?, ?, ?)");
    database.exec("BEGIN");
    for (let index = 0; index < 20000; index += 1) {
      const station = `station-${String(index % 700).padStart(4, "0")}`;
      insertExit.run(`exit-${index}`, station, `${index % 9 + 1}번 출구`);
      insertFacility.run(`facility-${index}`, station, index % 3 === 0 ? "ELEVATOR" : "ESCALATOR");
    }
    database.exec(`
      INSERT INTO data_quality_records VALUES ('quality-1', 'station-0001', 'LEVEL_1');
      INSERT INTO station_facility_evidence VALUES ('evidence-1', 'station-0001', 'facility-1');
      COMMIT;
    `);
  } finally {
    database.close();
  }
  return readFile(sqlitePath);
}

async function stageAudit(compress) {
  const root = await mkdtemp(path.join(tmpdir(), "easysubway-mobile-datapack-audit-test-"));
  const sqliteBytes = await buildSqlitePack(root);
  const gzipBytes = compress(sqliteBytes);
  await mkdir(path.join(root, "assets/datapacks"), { recursive: true });
  await writeFile(path.join(root, "assets/datapacks/test.sqlite.gz"), gzipBytes);
  const indexPath = path.join(root, "assets/datapacks/index.json");
  await writeFile(indexPath, `${JSON.stringify({
    schemaVersion: 1,
    packs: [{
      id: "test",
      asset: "assets/datapacks/test.sqlite.gz",
      sha256: sha256(gzipBytes),
      sqliteSha256: sha256(sqliteBytes),
      byteSize: gzipBytes.length,
    }],
  }, null, 2)}\n`);
  return { root, indexPath, gzipBytes, sqliteBytes };
}

function runAudit({ root, indexPath }) {
  return execFileAsync(process.execPath, [script, "--index", indexPath, "--root", root]);
}

// 허용 상한(1.05)을 양쪽에서 고정한다. fixture 실측 비율: level 6 약 1.013(허용), level 4 약 1.084(거부),
// level 1 약 1.155(거부), Z_RLE 3배 이상(거부). 상한을 1.5나 3으로 풀거나 1.0으로 조이면 아래 중 하나가 깨진다.
const acceptedCases = [
  ["기본 deflate level 9", { level: 9 }],
  ["level 6(약 1.013배)", { level: 6 }],
];
const rejectedCases = [
  ["level 4(약 1.084배)", { level: 4 }],
  ["level 1(약 1.155배)", { level: 1 }],
  ["Z_RLE(3배 이상)", { level: 9, strategy: zlibConstants.Z_RLE }],
];

for (const [name, options] of acceptedCases) {
  test(`감사는 ${name}로 압축된 번들 팩을 통과시킨다`, async () => {
    const staged = await stageAudit((bytes) => gzipSync(bytes, { ...options, mtime: 0 }));
    try {
      const baseline = gzipSync(staged.sqliteBytes, { level: 9, mtime: 0 });
      assert.ok(staged.gzipBytes.length <= baseline.length * 1.05, "fixture must be within the tolerance");
      const { stdout } = await runAudit(staged);
      assert.equal(JSON.parse(stdout).packs[0].id, "test");
    } finally {
      await rm(staged.root, { recursive: true, force: true });
    }
  });
}

for (const [name, options] of rejectedCases) {
  test(`감사는 내용·해시가 맞아도 ${name}로 비효율 압축된 번들 팩을 거부한다`, async () => {
    const staged = await stageAudit((bytes) => gzipSync(bytes, { ...options, mtime: 0 }));
    try {
      const baseline = gzipSync(staged.sqliteBytes, { level: 9, mtime: 0 });
      assert.ok(staged.gzipBytes.length > baseline.length * 1.05, "fixture must be inefficiently compressed");
      await assert.rejects(runAudit(staged), (error) => {
        assert.match(error.stderr, /compression/);
        return true;
      });
    } finally {
      await rm(staged.root, { recursive: true, force: true });
    }
  });
}

// 감사는 실행 Node의 zlib로 기준 크기를 다시 계산하므로 CI Node를 .nvmrc 고정과 같게 둔다.
test("ci.yml은 floating Node 버전 대신 .nvmrc를 쓴다", async () => {
  const workflow = await readFile(path.resolve(import.meta.dirname, "../../.github/workflows/ci.yml"), "utf8");
  assert.doesNotMatch(workflow, /^\s*node-version:/mu);
  assert.match(workflow, /^\s*node-version-file: \.nvmrc$/mu);
});
