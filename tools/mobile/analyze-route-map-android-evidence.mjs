#!/usr/bin/env node
import { existsSync, readFileSync, statSync } from "node:fs";
import path from "node:path";
import process from "node:process";

function usage() {
  return `Usage:
  node tools/mobile/analyze-route-map-android-evidence.mjs [--group <name>] --artifact-dir <dir> [--artifact-dir <dir> ...] [--format json|markdown] [--frames]

Options:
  --artifact-dir <dir>  Evidence directory created by run-route-map-android-evidence.sh.
  --group <name>        Put the following --artifact-dir runs in this group (A/B rounds).
                        Each group reports per-round raster p50 (median and range) and
                        pooled percentiles. Runs before the first --group go to "all".
  --format <format>     Output format. Defaults to markdown.
  --frames              Include every parsed frame in the JSON output.
  -h, --help            Show this help.

The frame budget is 1000 / refresh_rate_hz from metadata.env. A run without
refresh_rate_hz has no budget, so its janky counts are null.
`;
}

function parseArgs(argv) {
  const artifactDirs = [];
  let format = "markdown";
  let group = "all";
  let includeFrames = false;
  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    switch (arg) {
      case "--artifact-dir":
        artifactDirs.push({ dir: argv[index + 1] ?? "", group });
        index += 1;
        break;
      case "--group":
        group = argv[index + 1] ?? "";
        if (group.length === 0) {
          throw new Error("--group needs a name.");
        }
        index += 1;
        break;
      case "--frames":
        includeFrames = true;
        break;
      case "--format":
        format = argv[index + 1] ?? "";
        index += 1;
        break;
      case "-h":
      case "--help":
        return { help: true, artifactDirs, format, includeFrames };
      default:
        throw new Error(`Unknown argument: ${arg}`);
    }
  }
  if (artifactDirs.length === 0 || artifactDirs.some(({ dir }) => dir.length === 0)) {
    throw new Error("At least one --artifact-dir value is required.");
  }
  if (!["json", "markdown"].includes(format)) {
    throw new Error(`Unsupported format: ${format}`);
  }
  return { help: false, artifactDirs, format, includeFrames };
}

function readRequired(filePath) {
  const stat = statSync(filePath);
  if (!stat.isFile() || stat.size === 0) {
    throw new Error(`Expected non-empty file: ${filePath}`);
  }
  return readFileSync(filePath, "utf8");
}

function parseMetadata(text) {
  return Object.fromEntries(
    text
      .split(/\r?\n/)
      .filter((line) => line.includes("="))
      .map((line) => {
        const separator = line.indexOf("=");
        return [line.slice(0, separator), line.slice(separator + 1)];
      }),
  );
}

function parseNumber(value) {
  return Number.parseInt(value.replace(/,/g, ""), 10);
}

function parseGfxinfo(text) {
  const total = text.match(/Total frames rendered:\s*([\d,]+)/);
  const janky = text.match(/Janky frames:\s*([\d,]+)\s*\(([\d.]+)%\)/);
  const percentiles = {};
  for (const match of text.matchAll(/(50th|90th|95th|99th) percentile:\s*([\d,]+)ms/g)) {
    percentiles[match[1]] = parseNumber(match[2]);
  }
  const totalFrames = total ? parseNumber(total[1]) : null;
  // Flutter는 자체 canvas 렌더 파이프라인이라 dumpsys gfxinfo(HWUI)가 노선도
  // 프레임을 잡지 못한다. totalFrames=0이면 percentile/jankyPercent는 "측정
  // 불가"이며, histogram 최상단 버킷(4950ms)이 그대로 튀어나온 잔재이므로
  // null로 두어 FrameTiming 정본을 오염시키지 않는다.
  const captured = totalFrames != null && totalFrames > 0;
  return {
    totalFrames,
    measurementStatus: captured ? "captured" : "not_captured_flutter_canvas",
    jankyFrames: janky ? parseNumber(janky[1]) : null,
    jankyPercent: captured && janky ? Number.parseFloat(janky[2]) : null,
    p50Ms: captured ? percentiles["50th"] ?? null : null,
    p90Ms: captured ? percentiles["90th"] ?? null : null,
    p95Ms: captured ? percentiles["95th"] ?? null : null,
    p99Ms: captured ? percentiles["99th"] ?? null : null,
  };
}

function parseMeminfo(text) {
  const total = text.match(/TOTAL PSS:\s*([\d,]+)\s+TOTAL RSS:\s*([\d,]+)/);
  const javaHeap = text.match(/Java Heap:\s*([\d,]+)/);
  const nativeHeap = text.match(/Native Heap:\s*([\d,]+)/);
  const graphics = text.match(/Graphics:\s*([\d,]+)/);
  return {
    totalPssKb: total ? parseNumber(total[1]) : null,
    totalRssKb: total ? parseNumber(total[2]) : null,
    javaHeapKb: javaHeap ? parseNumber(javaHeap[1]) : null,
    nativeHeapKb: nativeHeap ? parseNumber(nativeHeap[1]) : null,
    graphicsKb: graphics ? parseNumber(graphics[1]) : null,
  };
}

function percentile(values, percentileValue) {
  if (values.length === 0) {
    return null;
  }
  const sorted = [...values].sort((a, b) => a - b);
  const index = Math.min(
    sorted.length - 1,
    Math.ceil((percentileValue / 100) * sorted.length) - 1,
  );
  return sorted[index];
}

// 구조화 canvas 렌더러(#1641)는 WebView cameraLatency/dispose 로그를 내지 않는다.
// pan/zoom 구간의 렌더러 크래시 시그니처 수만 집계해 안정성 게이트로 쓴다.
function parseRendererCrashes(text) {
  const signatures = text
    .split("\n")
    .map((line) => line.trim())
    .filter((line) => line.length > 0);
  return { crashSignatureCount: signatures.length };
}

// #1643 프레임 성능 정본: 앱이 로깅한 routeMapFrame build/raster/total(ms).
// frame·vsyncStartUs는 #517부터 붙는다. 이전 로그도 읽도록 선택 그룹으로 둔다.
const FRAME_LINE =
  /routeMapFrame buildMs=([\d.]+) rasterMs=([\d.]+) totalMs=([\d.]+)(?: frame=(\d+) vsyncStartUs=(\d+))?/g;

function parseFrames(text) {
  return [...text.matchAll(FRAME_LINE)].map((match) => ({
    build: Number.parseFloat(match[1]),
    raster: Number.parseFloat(match[2]),
    total: Number.parseFloat(match[3]),
    frame: match[4] == null ? null : Number.parseInt(match[4], 10),
    vsyncStartUs: match[5] == null ? null : Number(match[5]),
  }));
}

// 프레임 예산은 그 run의 실제 화면 주사율에서 정한다(90 Hz면 11.1 ms). 주사율을 모르면
// 예산도 모르므로 jank는 null이다. Flutter DevTools와 같이 build 또는 raster가 예산을
// 넘은 프레임을 jank로 센다.
function frameBudgetMs(metadata) {
  const hz = Number.parseFloat(metadata.refresh_rate_hz ?? "");
  return Number.isFinite(hz) && hz > 0 ? 1000 / hz : null;
}

function countJanky(frames, budgetMs) {
  return budgetMs == null
    ? null
    : frames.filter((frame) => frame.build > budgetMs || frame.raster > budgetMs)
        .length;
}

// 연속 번호 프레임 사이 vsync 간격의 중앙값. 기록된 주사율과 실제 vsync가 맞는지 본다.
function medianVsyncIntervalMs(frames) {
  const intervals = [];
  for (let index = 1; index < frames.length; index += 1) {
    const previous = frames[index - 1];
    const current = frames[index];
    if (
      previous.frame != null &&
      current.frame === previous.frame + 1 &&
      current.vsyncStartUs != null
    ) {
      intervals.push((current.vsyncStartUs - previous.vsyncStartUs) / 1000);
    }
  }
  return percentile(intervals, 50);
}

function summarizeFrames(frames, budgetMs) {
  const builds = frames.map((frame) => frame.build);
  const rasters = frames.map((frame) => frame.raster);
  const totals = frames.map((frame) => frame.total);
  const jankyFrames = countJanky(frames, budgetMs);
  return {
    frameSampleCount: frames.length,
    frameBudgetMs: budgetMs == null ? null : Math.round(budgetMs * 100) / 100,
    medianVsyncIntervalMs: medianVsyncIntervalMs(frames),
    buildP50Ms: percentile(builds, 50),
    buildP90Ms: percentile(builds, 90),
    buildP99Ms: percentile(builds, 99),
    rasterP50Ms: percentile(rasters, 50),
    rasterP90Ms: percentile(rasters, 90),
    rasterP99Ms: percentile(rasters, 99),
    totalP90Ms: percentile(totals, 90),
    totalP99Ms: percentile(totals, 99),
    jankyFrames,
    jankyPercent:
      frames.length > 0 && jankyFrames != null
        ? Math.round((jankyFrames / frames.length) * 10000) / 100
        : null,
  };
}

function analyzeRun({ dir: artifactDir, group }) {
  const dir = path.resolve(artifactDir);
  const metadata = parseMetadata(readRequired(path.join(dir, "metadata.env")));
  const gfxinfo = parseGfxinfo(readRequired(path.join(dir, "gfxinfo.txt")));
  const meminfo = parseMeminfo(readRequired(path.join(dir, "meminfo.txt")));
  const crashesPath = path.join(dir, "renderer-crashes.log");
  const renderer = parseRendererCrashes(
    existsSync(crashesPath) ? readFileSync(crashesPath, "utf8") : "",
  );
  const frames = parseFrames(readRequired(path.join(dir, "route-map-frames.log")));
  const budgetMs = frameBudgetMs(metadata);
  return {
    artifactDir: dir,
    group,
    focusLine: metadata.focus_line ?? "",
    thermalStatus: metadata.thermal_status ?? "unknown",
    refreshRateHz: metadata.refresh_rate_hz == null
      ? null
      : Number.parseFloat(metadata.refresh_rate_hz),
    serial: metadata.serial ?? "",
    package: metadata.package ?? "",
    buildMode: metadata.build_mode ?? "",
    measurementScope: metadata.measurement_scope ?? "route_map_entry_and_pan",
    gfxinfoResetAfterRouteMapSettle:
      metadata.gfxinfo_reset_after_route_map_settle === "true",
    viewport: `${metadata.width ?? ""}x${metadata.height ?? ""}`,
    capturedAtUtc: metadata.captured_at_utc ?? "",
    panCount: Number.parseInt(metadata.pan_count ?? "0", 10),
    gfxinfo,
    meminfo,
    renderer,
    frameTiming: summarizeFrames(frames, budgetMs),
    frames,
  };
}

function median(values) {
  return percentile(values, 50);
}

// A/B 비교 단위. 회차마다 raster p50을 내고 그 중앙값과 범위를 본다. 두 쪽 범위가 겹치면
// 차이를 주장하지 않는다. 모든 회차 프레임을 합친 백분위와 jank 수도 같이 낸다.
// 한 그룹 안 run들의 주사율이 다르면 예산이 섞이므로 null로 둔다.
function summarizeGroups(runs) {
  const groups = new Map();
  for (const run of runs) {
    groups.set(run.group, [...(groups.get(run.group) ?? []), run]);
  }
  return [...groups.entries()].map(([name, groupRuns]) => {
    const roundRasterP50 = groupRuns.map((run) => run.frameTiming.rasterP50Ms);
    const rates = new Set(groupRuns.map((run) => run.refreshRateHz));
    const budgetMs =
      rates.size === 1 ? frameBudgetMs({ refresh_rate_hz: String([...rates][0]) }) : null;
    return {
      group: name,
      rounds: groupRuns.length,
      refreshRatesHz: [...rates],
      thermalStatuses: [...new Set(groupRuns.map((run) => run.thermalStatus))],
      roundRasterP50Ms: roundRasterP50,
      roundRasterP50MedianMs: median(roundRasterP50),
      roundRasterP50RangeMs: [Math.min(...roundRasterP50), Math.max(...roundRasterP50)],
      pooled: summarizeFrames(
        groupRuns.flatMap((run) => run.frames),
        budgetMs,
      ),
    };
  });
}

function maxKnown(values) {
  const known = values.filter((value) => value != null);
  return known.length === 0 ? null : Math.max(...known);
}

function aggregate(runs) {
  // gfxinfo(HWUI) 지표는 프레임을 실제로 캡처한(captured) run만 반영한다.
  // Flutter canvas run(not_captured)의 4950ms 잔재가 프레임 게이트를 오염시키지
  // 않도록 배제하고, captured run이 하나도 없으면 null로 명시한다.
  const capturedRuns = runs.filter(
    (run) => run.gfxinfo.measurementStatus === "captured",
  );
  // captured run이 있어도 특정 지표가 모든 run에서 측정되지 않으면(예: gfxinfo.txt에
  // 해당 percentile/Janky 라인이 없어 null) 그 지표는 "측정 불가"다. null을 0으로
  // 폴백하면 Math.max(0)=0이 "0ms 측정됨"으로 둔갑하므로, null을 걸러낸 유효값만
  // 집계하고 유효값이 하나도 없으면 null을 전파한다.
  const maxCapturedGfxinfo = (selector) => {
    const values = capturedRuns
      .map((run) => selector(run.gfxinfo))
      .filter((value) => value != null);
    return values.length === 0 ? null : Math.max(...values);
  };
  return {
    runCount: runs.length,
    measurementScopes: [...new Set(runs.map((run) => run.measurementScope))],
    maxJankyPercent: maxCapturedGfxinfo((gfxinfo) => gfxinfo.jankyPercent),
    maxP95FrameMs: maxCapturedGfxinfo((gfxinfo) => gfxinfo.p95Ms),
    maxP99FrameMs: maxCapturedGfxinfo((gfxinfo) => gfxinfo.p99Ms),
    maxTotalPssKb: Math.max(...runs.map((run) => run.meminfo.totalPssKb ?? 0)),
    maxFrameJankyPercent: maxKnown(runs.map((run) => run.frameTiming.jankyPercent)),
    maxBuildP90Ms: Math.max(...runs.map((run) => run.frameTiming.buildP90Ms ?? 0)),
    maxRasterP90Ms: Math.max(
      ...runs.map((run) => run.frameTiming.rasterP90Ms ?? 0),
    ),
    totalCrashSignatures: runs.reduce(
      (sum, run) => sum + (run.renderer.crashSignatureCount ?? 0),
      0,
    ),
    noCrashesInAllRuns: runs.every(
      (run) => (run.renderer.crashSignatureCount ?? 0) === 0,
    ),
  };
}

function markdownReport(result) {
  const lines = [
    "# Android route map profile evidence summary",
    "",
    `- runs: ${result.aggregate.runCount}`,
    `- measurement_scopes: ${result.aggregate.measurementScopes.join(", ")}`,
    `- max_janky_percent: ${result.aggregate.maxJankyPercent}`,
    `- max_p95_frame_ms: ${result.aggregate.maxP95FrameMs}`,
    `- max_p99_frame_ms_gfxinfo_hwui_only: ${result.aggregate.maxP99FrameMs}`,
    `- max_total_pss_kb: ${result.aggregate.maxTotalPssKb}`,
    `- total_crash_signatures: ${result.aggregate.totalCrashSignatures}`,
    `- no_crashes_in_all_runs: ${result.aggregate.noCrashesInAllRuns}`,
    "",
    "FrameTiming(정본, Flutter canvas 프레임):",
    `- max_frame_janky_percent: ${result.aggregate.maxFrameJankyPercent}`,
    `- max_build_p90_ms: ${result.aggregate.maxBuildP90Ms}`,
    `- max_raster_p90_ms: ${result.aggregate.maxRasterP90Ms}`,
    "",
    "> gfxinfo frame 지표는 HWUI 전용이라 Flutter canvas 노선도 프레임을 반영하지 않는다. 프레임 성능은 FrameTiming(build/raster p90·janky%)이 정본이다.",
    "",
    "| run | group | scope | focus line | build | viewport | Hz | budget | frame samples | frame janky | build p90 | raster p50 | raster p90 | raster p99 | total PSS | crashes | evidence |",
    "| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |",
  ];
  for (const [index, run] of result.runs.entries()) {
    const cells = [
      index + 1,
      run.group,
      run.measurementScope,
      run.focusLine || "none",
      run.buildMode,
      run.viewport,
      run.refreshRateHz ?? "unknown",
      run.frameTiming.frameBudgetMs == null ? "unknown" : `${run.frameTiming.frameBudgetMs}ms`,
      run.frameTiming.frameSampleCount ?? "",
      run.frameTiming.jankyPercent == null
        ? ""
        : `${run.frameTiming.jankyFrames} (${run.frameTiming.jankyPercent}%)`,
      run.frameTiming.buildP90Ms == null ? "" : `${run.frameTiming.buildP90Ms}ms`,
      run.frameTiming.rasterP50Ms == null ? "" : `${run.frameTiming.rasterP50Ms}ms`,
      run.frameTiming.rasterP90Ms == null ? "" : `${run.frameTiming.rasterP90Ms}ms`,
      run.frameTiming.rasterP99Ms == null ? "" : `${run.frameTiming.rasterP99Ms}ms`,
      run.meminfo.totalPssKb ?? "",
      run.renderer.crashSignatureCount ?? "",
      run.artifactDir,
    ];
    lines.push(`| ${cells.join(" | ")} |`);
  }
  lines.push(
    "",
    "Groups (raster p50 per round, pooled frames):",
    "",
    "| group | rounds | Hz | thermal | round raster p50 median | range | pooled raster p50 | p90 | p99 | janky / frames | vsync interval |",
    "| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |",
  );
  for (const group of result.groups) {
    const pooled = group.pooled;
    lines.push(
      `| ${[
        group.group,
        group.rounds,
        group.refreshRatesHz.join("/"),
        group.thermalStatuses.join("/"),
        `${group.roundRasterP50MedianMs}ms`,
        `${group.roundRasterP50RangeMs[0]}~${group.roundRasterP50RangeMs[1]}ms`,
        `${pooled.rasterP50Ms}ms`,
        `${pooled.rasterP90Ms}ms`,
        `${pooled.rasterP99Ms}ms`,
        `${pooled.jankyFrames ?? "unknown"} / ${pooled.frameSampleCount}`,
        pooled.medianVsyncIntervalMs == null ? "" : `${pooled.medianVsyncIntervalMs}ms`,
      ].join(" | ")} |`,
    );
  }
  return `${lines.join("\n")}\n`;
}

function main() {
  try {
    const args = parseArgs(process.argv.slice(2));
    if (args.help) {
      process.stdout.write(usage());
      return;
    }
    const runs = args.artifactDirs.map(analyzeRun);
    const result = {
      schemaVersion: 2,
      artifactKind: "route-map-android-evidence-summary",
      runs: runs.map(({ frames, ...run }) =>
        args.includeFrames ? { ...run, frames } : run,
      ),
      groups: summarizeGroups(runs),
      aggregate: aggregate(runs),
    };
    process.stdout.write(
      args.format === "json"
        ? `${JSON.stringify(result, null, 2)}\n`
        : markdownReport(result),
    );
  } catch (error) {
    process.stderr.write(`${error.message}\n\n${usage()}`);
    process.exitCode = 2;
  }
}

main();
