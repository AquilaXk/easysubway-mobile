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
