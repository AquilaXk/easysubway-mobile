import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { mkdir, mkdtemp, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";

const execFileAsync = promisify(execFile);
const here = path.dirname(fileURLToPath(import.meta.url));
const analyzer = path.join(here, "analyze-route-map-android-evidence.mjs");

// network_map_canvas.dart routeMapFrameTimingLine과 같은 형식의 logcat 줄.
function frameLine({ build, raster, frame, vsyncStartUs }) {
  return (
    `10-24 19:52:25.333 I/flutter (29971): routeMapFrame buildMs=${build.toFixed(2)} ` +
    `rasterMs=${raster.toFixed(2)} totalMs=${(build + raster + 1).toFixed(2)} ` +
    `frame=${frame} vsyncStartUs=${vsyncStartUs}`
  );
}

async function writeRun(root, name, { refreshRateHz, rasters }) {
  const dir = path.join(root, name);
  await mkdir(dir, { recursive: true });
  const metadata = ["serial=test", "build_mode=profile", "focus_line=2호선"];
  if (refreshRateHz != null) {
    metadata.push(`refresh_rate_hz=${refreshRateHz}`, "thermal_status=0");
  }
  await writeFile(path.join(dir, "metadata.env"), `${metadata.join("\n")}\n`);
  await writeFile(path.join(dir, "gfxinfo.txt"), "Total frames rendered: 0\n");
  await writeFile(path.join(dir, "meminfo.txt"), "TOTAL PSS: 1 TOTAL RSS: 2\n");
  const lines = rasters.map((raster, index) =>
    frameLine({
      build: 2,
      raster,
      frame: 100 + index,
      vsyncStartUs: 1_000_000 + index * 11_111,
    }),
  );
  await writeFile(path.join(dir, "route-map-frames.log"), `${lines.join("\n")}\n`);
  return dir;
}

async function analyze(args) {
  const { stdout } = await execFileAsync("node", [analyzer, ...args, "--format", "json"]);
  return JSON.parse(stdout);
}

test("frame budget comes from the recorded refresh rate, so 12 ms raster is janky at 90 Hz", async () => {
  const root = await mkdtemp(path.join(tmpdir(), "route-map-frames-"));
  const dir = await writeRun(root, "r1", { refreshRateHz: "90.0", rasters: [10, 12, 13, 5] });

  const { runs } = await analyze(["--artifact-dir", dir]);

  assert.equal(runs[0].refreshRateHz, 90);
  assert.equal(runs[0].frameTiming.frameBudgetMs, 11.11);
  assert.equal(runs[0].frameTiming.jankyFrames, 2);
  assert.equal(runs[0].frameTiming.medianVsyncIntervalMs, 11.111);
  assert.equal(runs[0].frameTiming.rasterP99Ms, 13);
});

test("a run without a refresh rate has no budget instead of an assumed 60 Hz", async () => {
  const root = await mkdtemp(path.join(tmpdir(), "route-map-frames-"));
  const dir = await writeRun(root, "r1", { refreshRateHz: null, rasters: [20, 30] });

  const { runs } = await analyze(["--artifact-dir", dir]);

  assert.equal(runs[0].frameTiming.frameBudgetMs, null);
  assert.equal(runs[0].frameTiming.jankyFrames, null);
  assert.equal(runs[0].frameTiming.jankyPercent, null);
});

test("groups report per-round raster p50 median and range plus pooled frames", async () => {
  const root = await mkdtemp(path.join(tmpdir(), "route-map-frames-"));
  const a1 = await writeRun(root, "a1", { refreshRateHz: "90.0", rasters: [14, 15, 16] });
  const a2 = await writeRun(root, "a2", { refreshRateHz: "90.0", rasters: [13, 14, 15] });
  const b1 = await writeRun(root, "b1", { refreshRateHz: "90.0", rasters: [5, 6, 7] });

  const result = await analyze([
    "--group", "main", "--artifact-dir", a1, "--artifact-dir", a2,
    "--group", "fix", "--artifact-dir", b1,
  ]);

  const [main, fix] = result.groups;
  assert.equal(main.group, "main");
  assert.deepEqual(main.roundRasterP50Ms, [15, 14]);
  assert.deepEqual(main.roundRasterP50RangeMs, [14, 15]);
  assert.equal(main.pooled.frameSampleCount, 6);
  assert.equal(main.pooled.jankyFrames, 6);
  assert.equal(fix.group, "fix");
  assert.equal(fix.pooled.jankyFrames, 0);
  assert.equal(result.runs[0].frames, undefined);
});

test("--frames keeps every parsed frame for the raw JSON artifact", async () => {
  const root = await mkdtemp(path.join(tmpdir(), "route-map-frames-"));
  const dir = await writeRun(root, "r1", { refreshRateHz: "90.0", rasters: [10, 12] });

  const { runs } = await analyze(["--artifact-dir", dir, "--frames"]);

  assert.deepEqual(
    runs[0].frames.map(({ raster, frame }) => [raster, frame]),
    [[10, 100], [12, 101]],
  );
});

async function writeVsyncRun(root, name, vsyncStartsUs, meminfo = "TOTAL PSS: 1 TOTAL RSS: 2\n") {
  const dir = await writeRun(root, name, { refreshRateHz: "90.0", rasters: [] });
  const lines = vsyncStartsUs.map((vsyncStartUs, index) =>
    frameLine({ build: 2, raster: 3, frame: 100 + index, vsyncStartUs }),
  );
  await writeFile(path.join(dir, "route-map-frames.log"), `${lines.join("\n")}\n`);
  await writeFile(path.join(dir, "meminfo.txt"), meminfo);
  return dir;
}

test("work outside the frame's raster time shows up as vsyncs with no frame", async () => {
  const root = await mkdtemp(path.join(tmpdir(), "route-map-frames-"));
  // 11.1 ms 간격 3장, 한 vsync를 건너뛴 22.2 ms, 두 vsync를 건너뛴 33.3 ms,
  // 입력이 없어 그리지 않은 88.9 ms(8 vsync)와 400 ms를 둔다.
  const dir = await writeVsyncRun(root, "r1", [
    0, 11_111, 22_222, 44_444, 77_777, 166_666, 566_666, 577_777,
  ]);

  const { runs, groups } = await analyze(["--group", "tiles", "--artifact-dir", dir]);

  assert.equal(runs[0].frameTiming.missedVsyncs, 3);
  assert.equal(groups[0].pooled.missedVsyncs, 3);
});

test("pooled runs do not count the gap between two runs as missed vsyncs", async () => {
  const root = await mkdtemp(path.join(tmpdir(), "route-map-frames-"));
  const a = await writeVsyncRun(root, "a", [5_000_000, 5_011_111]);
  const b = await writeVsyncRun(root, "b", [1_000_000, 1_011_111, 1_033_333]);

  const { groups } = await analyze(["--group", "g", "--artifact-dir", a, "--artifact-dir", b]);

  assert.equal(groups[0].pooled.missedVsyncs, 1);
});

test("groups report the PSS and GL mtrack range over rounds", async () => {
  const root = await mkdtemp(path.join(tmpdir(), "route-map-frames-"));
  const meminfo = (pss, gl) =>
    `    GL mtrack    ${gl}    ${gl}        0        0    ${gl}\n` +
    `           TOTAL PSS:   ${pss}            TOTAL RSS:   353705\n`;
  const a = await writeVsyncRun(root, "a", [0, 11_111], meminfo(229647, 25828));
  const b = await writeVsyncRun(root, "b", [0, 11_111], meminfo(238325, 26100));

  const { runs, groups } = await analyze(["--group", "g", "--artifact-dir", a, "--artifact-dir", b]);

  assert.equal(runs[0].meminfo.glMtrackKb, 25828);
  assert.deepEqual(groups[0].totalPssRangeKb, [229647, 238325]);
  assert.deepEqual(groups[0].glMtrackRangeKb, [25828, 26100]);
});

async function writeEmptyFrameRun(root, buildMode) {
  const dir = await writeRun(root, buildMode, { refreshRateHz: "60.0", rasters: [5] });
  await writeFile(
    path.join(dir, "metadata.env"),
    `serial=test\nbuild_mode=${buildMode}\nrefresh_rate_hz=60.0\n`,
  );
  await writeFile(path.join(dir, "route-map-frames.log"), "");
  await writeFile(path.join(dir, "meminfo.txt"), "TOTAL PSS: 150000 TOTAL RSS: 250000\n");
  return dir;
}

test("a release run has no frame log and still reports its PSS", async () => {
  const root = await mkdtemp(path.join(tmpdir(), "route-map-frames-"));
  const dir = await writeEmptyFrameRun(root, "release");

  const { runs } = await analyze(["--artifact-dir", dir]);

  assert.equal(runs[0].buildMode, "release");
  assert.equal(runs[0].frameTiming.frameSampleCount, 0);
  assert.equal(runs[0].meminfo.totalPssKb, 150000);
});

test("a profile run without frame logs fails instead of reporting no frames", async () => {
  const root = await mkdtemp(path.join(tmpdir(), "route-map-frames-"));
  const dir = await writeEmptyFrameRun(root, "profile");

  await assert.rejects(analyze(["--artifact-dir", dir]), /Expected non-empty file/);
});
