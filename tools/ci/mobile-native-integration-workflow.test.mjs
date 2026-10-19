import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { chmodSync, existsSync, mkdirSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

const workflow = readFileSync(
  new URL("../../.github/workflows/mobile-native-integration.yml", import.meta.url),
  "utf8",
);
const readScript = (name) => readFileSync(new URL(`./${name}`, import.meta.url), "utf8");
const androidDriveScript = readScript("android-native-drive.sh");
const iosDriveScript = readScript("ios-native-drive.sh");
const commonDriveScript = readScript("native-drive-common.sh");
const nativeTest = readFileSync(
  new URL("../../apps/mobile/integration_test/native_test.dart", import.meta.url),
  "utf8",
);

const a11ySmokeTest = readFileSync(
  new URL("../../apps/mobile/integration_test/core_screen_a11y_smoke_test.dart", import.meta.url),
  "utf8",
);

test("native workflow runs one bounded Android and iOS simulator Journey smoke", () => {
  assert.match(workflow, /^name: Mobile Native Integration$/m);
  assert.match(workflow, /^  pull_request:\n    branches: \[main\]\n    paths:/m);
  assert.match(workflow, /^  push:\n    branches: \[main\]\n    paths:/m);
  assert.match(workflow, /^  workflow_dispatch:$/m);
  assert.match(workflow, /^permissions:\n  contents: read$/m);
  assert.match(workflow, /^  cancel-in-progress: true$/m);
  assert.equal(
    (workflow.match(/"apps\/mobile\/lib\/features\/route_draft\/\*\*"/gu) ?? [])
      .length,
    2,
  );
  assert.equal(
    (workflow.match(/"apps\/mobile\/lib\/features\/routes\/\*\*"/gu) ?? [])
      .length,
    2,
  );

  assert.match(workflow, /^  android-native:\n    name: Android Journey native smoke\n    runs-on: ubuntu-latest\n    timeout-minutes: 35$/m);
  assert.match(workflow, /reactivecircus\/android-emulator-runner@a421e43855164a8197daf9d8d40fe71c6996bb0d/iu);
  assert.match(workflow, /^          api-level: 35$/m);
  assert.match(workflow, /^          target: google_apis$/m);
  assert.match(workflow, /^          arch: x86_64$/m);
  assert.match(workflow, /^          emulator-port: 5554$/m);
  assert.match(workflow, /^          disable-animations: true$/m);
  assert.match(workflow, /^          emulator-boot-timeout: 600$/m);
  assert.match(
    workflow,
    /^          emulator-options: -no-window -gpu swiftshader_indirect -no-snapshot -noaudio -no-boot-anim$/m,
  );
  assert.ok(
    workflow.indexOf("      - name: Prepare Android native evidence") <
      workflow.indexOf("      - name: Enable KVM"),
  );
  assert.doesNotMatch(
    workflow,
    /\bflutter test\b/u,
  );
  assert.match(workflow, /\{"schemaVersion":1,"lane":"android-native","status":"PENDING"\}/u);
  assert.match(workflow, /^          name: mobile-native-android-\$\{\{ github\.run_id \}\}-\$\{\{ github\.run_attempt \}\}$/m);

  assert.match(workflow, /^  ios-native:\n    name: iOS Journey native smoke\n    runs-on: macos-15\n    timeout-minutes: 35\n    env:\n      DEVELOPER_DIR: \/Applications\/Xcode_26\.3\.app\/Contents\/Developer\n      NATIVE_TARGETS: /m);
  assert.equal((workflow.match(/flutter-version: "3\.44\.0"/gu) ?? []).length, 2);
  assert.match(workflow, /^        run: bash \.\.\/\.\.\/tools\/ci\/ios-native-drive\.sh$/m);
  assert.match(workflow, /\{"schemaVersion":1,"lane":"ios-native","status":"PENDING"\}/u);
  assert.match(workflow, /"lane":"ios-native","status":"FAIL","target":"simulator","step":"boot"/u);
  assert.match(workflow, /^          name: mobile-native-ios-\$\{\{ github\.run_id \}\}-\$\{\{ github\.run_attempt \}\}$/m);
  assert.match(workflow, /^            \$\{\{ runner\.temp \}\}\/mobile-native-ios\/flutter-drive-\*\.log$/m);
  assert.equal(
    (workflow.match(/uses: actions\/upload-artifact@65462800fd760344b1a7b4382951275a0abb4808/gu) ?? []).length,
    2,
  );
  assert.equal((workflow.match(/^        if: always\(\)$/gmu) ?? []).length, 2);
  assert.equal((workflow.match(/^          if-no-files-found: error$/gmu) ?? []).length, 2);
  assert.equal((workflow.match(/^          retention-days: 5$/gmu) ?? []).length, 2);
  assert.doesNotMatch(workflow, /secrets\.|EASYSUBWAY_API_BASE_URL|release|\bstore\b/iu);
});

const androidJob = workflow.slice(0, workflow.indexOf("  ios-native:"));
const iosJob = workflow.slice(workflow.indexOf("  ios-native:"));
const jobTargets = (job) => job.match(/^      NATIVE_TARGETS: (.+)$/mu)?.[1].split(" ") ?? [];

for (const [lane, job, adapter, script, expectedTargets] of [
  ["Android", androidJob, androidDriveScript, "android-native-drive.sh", ["native_test", "core_screen_a11y_smoke_test", "core_screen_a11y_smoke_test:2.0"]],
  ["iOS", iosJob, iosDriveScript, "ios-native-drive.sh", ["native_test", "core_screen_a11y_smoke_test", "core_screen_a11y_smoke_test:3.12"]],
]) {
  test(`${lane} drive script wiring: targets exist, the adapter only calls the shared flow, nothing swallows failures`, () => {
    const targets = jobTargets(job);
    assert.deepEqual(targets, expectedTargets);
    for (const target of targets) {
      assert.ok(existsSync(new URL(`../../apps/mobile/integration_test/${target.split(":")[0]}.dart`, import.meta.url)));
    }
    assert.doesNotMatch(adapter, /native_test|core_screen_a11y_smoke_test|write_receipt/u);
    assert.equal(adapter.trimEnd().split("\n").at(-1), "run_native_drive");
    assert.match(adapter, /^source "\$\(dirname "\$\{BASH_SOURCE\[0\]\}"\)\/native-drive-common\.sh"$/mu);
    assert.ok(job.includes(`bash ../../tools/ci/${script}`) || job.includes(`script: bash ../../tools/ci/${script}`));
    assert.doesNotMatch(adapter, /set -e|continue-on-error/u);
  });
}

test("shared drive flow writes PASS once at the end and nothing swallows failures", () => {
  const lines = commonDriveScript.trimEnd().split("\n");
  assert.equal(lines.at(-4), "  assert_all_passed");
  assert.equal(lines.at(-3), "  report_verdicts");
  assert.equal(lines.at(-2), "  write_receipt PASS");
  assert.equal(lines.at(-1), "}");
  assert.equal((commonDriveScript.match(/write_receipt PASS/gu) ?? []).length, 1);
  assert.doesNotMatch(commonDriveScript, /set -e|continue-on-error/u);
  assert.doesNotMatch(workflow, /continue-on-error/u);
  assert.doesNotMatch(androidJob, /\|\| true/u);
  assert.doesNotMatch(iosJob, /\|\| true/u);
});

test("emulator boot failure that never reaches the drive script is recorded in the receipt", () => {
  assert.match(androidJob, /^        id: smoke$/m);
  assert.match(androidJob, /^        if: failure\(\) && steps\.smoke\.conclusion == 'failure'$/m);
  assert.match(androidJob, /"status":"FAIL","target":"emulator","step":"boot"/u);
  assert.ok(
    androidJob.indexOf("Record Android boot failure") < androidJob.indexOf("Upload Android native evidence"),
  );
});

const fixtureDir = fileURLToPath(new URL("./fixtures/android-drive/", import.meta.url));
const fixture = (name) => readFileSync(path.join(fixtureDir, name), "utf8");

// 스텁 기기 도구(android: adb, ios: xcrun)와 flutter/dart로 실제 스크립트를 실행한다.
// drives: drive 호출 순서별 { log, exit } (log는 재생할 로그 본문, exit 기본 1).
// boot: android는 adb getprop sys.boot_completed, ios는 simctl bootstatus 호출 순서별 "1"/"0" (마지막 값을 반복).
//   android는 await_device 한 번에 1회 호출한다(BOOT_POLL_LIMIT=1).
// drives[].results: host driver가 남긴 구조화 결과(reportData). 있으면 FLUTTER_TEST_OUTPUTS_DIR/integration_response_data.json으로 쓴다.
// binary: "built"는 --use-application-binary 없이 호출된 drive(첫 drive)가 app_binary를 만든 것으로 친다.
//   "stale"은 실행 전에 이미 있던 산출물만 있고 drive는 만들지 않는다. "none"은 아무것도 없다.
function runDriveScript({ platform = "android", drives = [], boot = ["1"], waitFails = false, targets = "native_test", binary = "built", env = {} }) {
  const root = mkdtempSync(path.join(tmpdir(), `${platform}-drive-`));
  const bin = path.join(root, "bin");
  const evidence = path.join(root, `mobile-native-${platform}`);
  const appBinary = path.join(root, "app-binary");
  mkdirSync(bin);
  mkdirSync(evidence);
  if (binary === "stale") writeFileSync(appBinary, "");
  const stub = (name, body) => {
    writeFileSync(path.join(bin, name), `#!/usr/bin/env bash\n${body}\n`);
    chmodSync(path.join(bin, name), 0o755);
  };
  writeFileSync(path.join(root, "boot"), `${boot.join("\n")}\n`);
  drives.forEach((drive, index) => {
    writeFileSync(path.join(root, `drive-${index + 1}.log`), drive.log);
    writeFileSync(path.join(root, `drive-${index + 1}.exit`), String(drive.exit ?? 1));
    if (drive.results) writeFileSync(path.join(root, `drive-${index + 1}.json`), JSON.stringify(drive.results));
  });
  const deviceStubs = {
    android: () =>
      stub(
        "adb",
        [
          `echo "adb $*" >> "${root}/calls"`,
          `[ "$3" = wait-for-device ] && ${waitFails ? "exit 1" : "exit 0"}`,
          `[ "$3" = shell ] && [ "$4" = settings ] && { n=$(grep -c '^font_scale ' "${root}/calls"); echo "font_scale $8" >> "${root}/calls"; if [ "$n" -lt "$FONT_SCALE_FAILS" ]; then echo "$FONT_SCALE_FAIL_LOG" >&2; exit 1; fi; exit 0; }`,
          '[ "$3" = shell ] && [ "$4" = getprop ] || exit 0',
          `n=$(grep -c '^getprop$' "${root}/calls" 2>/dev/null)`,
          `echo getprop >> "${root}/calls"`,
          `n=$((n + 1)); line=$(sed -n "\${n}p" "${root}/boot"); [ -n "$line" ] || line=$(tail -n 1 "${root}/boot")`,
          'echo "$line"',
        ].join("\n"),
      ),
    // xcrun simctl <하위 명령> <기기> ... 형태로 호출된다. content_size는 설정값을 state 파일에 저장해 되읽기를 흉내 낸다.
    ios: () =>
      stub(
        "xcrun",
        [
          `echo "xcrun $*" >> "${root}/calls"`,
          'case "$2" in',
          `  bootstatus) n=$(grep -c '^bootstatus$' "${root}/calls" 2>/dev/null); echo bootstatus >> "${root}/calls"; n=$((n + 1)); line=$(sed -n "\${n}p" "${root}/boot"); [ -n "$line" ] || line=$(tail -n 1 "${root}/boot"); [ "$line" = 1 ] ;;`,
          `  ui) if [ -n "$5" ]; then echo "content_size $5" >> "${root}/calls"; [ "$CONTENT_SIZE_STUCK" = 1 ] || echo "$5" > "${root}/content-size"; else cat "${root}/content-size" 2>/dev/null; fi ;;`,
          `  shutdown) echo shutdown >> "${root}/calls" ;;`,
          '  spawn) echo "SIMULATOR LOG" ;;',
          "esac",
        ].join("\n"),
      ),
  };
  deviceStubs[platform]();
  stub("dart", "exit 0");
  stub("sleep", "exit 0");
  stub("timeout", `[ "$2" = flutter ] && echo "drive-timeout $1" >> "${root}/calls"\nshift\nexec "$@"`);
  stub(
    "flutter",
    [
      '[ "$1" = drive ] || exit 0',
      `echo drive >> "${root}/calls"`,
      `echo "args $*" >> "${root}/calls"`,
      `echo "outputs-dir $FLUTTER_TEST_OUTPUTS_DIR" >> "${root}/calls"`,
      `n=$(grep -c '^drive$' "${root}/calls")`,
      `if [ -f "${root}/drive-$n.json" ]; then mkdir -p "$FLUTTER_TEST_OUTPUTS_DIR"; cp "${root}/drive-$n.json" "$FLUTTER_TEST_OUTPUTS_DIR/integration_response_data.json"; fi`,
      ...(binary === "built" ? [`case "$*" in *--use-application-binary*) ;; *) : > "${appBinary}" ;; esac`] : []),
      `cat "${root}/drive-$n.log"`,
      `exit "$(cat "${root}/drive-$n.exit")"`,
    ].join("\n"),
  );
  const result = spawnSync("bash", [fileURLToPath(new URL(`./${platform}-native-drive.sh`, import.meta.url))], {
    env: {
      PATH: `${bin}:${process.env.PATH}`,
      RUNNER_TEMP: root,
      NATIVE_TARGETS: targets,
      APP_BINARY: appBinary,
      BOOT_POLL_LIMIT: "1",
      FONT_SCALE_FAILS: "0",
      FONT_SCALE_FAIL_LOG: "",
      CONTENT_SIZE_STUCK: "0",
      ...env,
    },
    encoding: "utf8",
  });
  const calls = existsSync(path.join(root, "calls")) ? readFileSync(path.join(root, "calls"), "utf8").split("\n") : [];
  const read = (name) => readFileSync(path.join(evidence, name), "utf8");
  return {
    status: result.status,
    stdout: result.stdout,
    receipt: JSON.parse(read("receipt.json")),
    appBinary,
    fontScales: calls.filter((line) => line.startsWith("font_scale ")).map((line) => line.slice("font_scale ".length)),
    driveArgs: calls.filter((line) => line.startsWith("args drive ")).map((line) => line.slice("args drive ".length)),
    driveCalls: calls.filter((line) => line === "drive").length,
    outputsDirs: calls.filter((line) => line.startsWith("outputs-dir ")).map((line) => line.slice("outputs-dir ".length)),
    timeouts: calls.filter((line) => line.startsWith("drive-timeout ")).map((line) => line.slice("drive-timeout ".length)),
    reconnects: calls.filter((line) => line === "adb reconnect offline").length,
    contentSizes: calls.filter((line) => line.startsWith("content_size ")).map((line) => line.slice("content_size ".length)),
    shutdowns: calls.filter((line) => line === "shutdown").length,
    bootstatuses: calls.filter((line) => line === "bootstatus").length,
    read,
    exists: (name) => existsSync(path.join(evidence, name)),
  };
}

// flutter drive가 남기는 로그: 대상 group마다 테스트 시작 줄, 앱이 읽은 배율 줄(observed가 배열이면 줄마다 하나씩, 빈 값이면 없음),
// 요약 줄(과 실패 줄·실패 상세). failing: 실패한 테스트 줄([E])을 남길 group. integrationDriver의 실패 상세는 실제 로그처럼
// group 이름 없이 테스트 이름만 적는다. complete=false는 요약 없이 끊긴 로그. counterOnly: [E] 없이 실패 카운터(+N -M)만 남긴다.
const linePrefix = { android: "I/flutter ( 4098): ", ios: "flutter: " };
function driveLog({ platform = "android", groups = ["native_test"], observed = "1.0", failing = [], complete = true, counterOnly = false, noise = "" }) {
  const prefix = linePrefix[platform];
  const lines = groups.map((group, index) => `${prefix}00:0${index} +${index}: ${group} 첫 테스트`);
  for (const value of [observed].flat()) if (value) lines.push(`${prefix}${markerName}${value}`);
  lines.push(...failing.map((group, index) => `${prefix}00:0${index} +1 -${index + 1}: ${group} 첫 테스트${counterOnly ? "" : " [E]"}`));
  if (complete) {
    lines.push(`${prefix}00:09 +9: ${failing.length ? "Some tests failed." : "All tests passed!"}`);
    lines.push(...(failing.length ? ["Failure Details:", "Failure in method: 첫 테스트", "end of failure 1"] : ["All tests passed."]));
  }
  return `${lines.join("\n")}\n${noise}`;
}
// host driver가 남기는 구조화 결과: group마다 통과한 테스트 수와 실패한 테스트 이름.
const structured = (groups, failing = []) => ({
  nativeGroups: Object.fromEntries(groups.map((group) => [group, { passed: 2, failed: failing.includes(group) ? ["첫 테스트"] : [] }])),
});
const markerName = "NATIVE_SYSTEM_TEXT_SCALE=";
// 통과한 drive. results를 null로 주면 구조화 결과 없이 끝난 drive다.
const passDrive = (options = {}) => ({
  log: driveLog(options),
  exit: 0,
  results: options.results === null ? undefined : (options.results ?? structured(options.groups ?? ["native_test"])),
});
const passA11y = (scale, options = {}) => passDrive({ groups: ["core_screen_a11y_smoke_test"], observed: scale, ...options });
const bothGroups = ["native_test", "core_screen_a11y_smoke_test"];

const receiptOf = (platform, status, results, extra = {}) => ({ schemaVersion: 1, lane: `${platform}-native`, status, ...extra, results });
const passedReceipt = (results = { native_test: "PASS" }, extra = {}) => receiptOf("android", "PASS", results, extra);
const failedReceipt = (extra, results = { native_test: "FAIL" }) => receiptOf("android", "FAIL", results, extra);

test("real offline-before-tests log retries once, keeps the first log, and reports the retry", () => {
  const offline = fixture("offline-before-tests.txt");
  const summary = path.join(mkdtempSync(path.join(tmpdir(), "summary-")), "summary.md");
  const run = runDriveScript({
    drives: [{ log: offline }, passDrive()],
    env: { GITHUB_STEP_SUMMARY: summary },
  });
  assert.equal(run.status, 0);
  assert.deepEqual(run.receipt, passedReceipt({ native_test: "PASS" }, { retried: ["drive:adb_offline"] }));
  assert.equal(run.driveCalls, 2);
  assert.equal(run.reconnects, 1);
  assert.equal(run.read("flutter-drive-scale-1.0.attempt1.log"), offline);
  assert.match(run.stdout, /^::warning::native_test drive가 adb_offline 때문에 1회 재시도 후 통과했습니다\./mu);
  assert.match(readFileSync(summary, "utf8"), /native_test: drive 재시도 후 통과 \(adb_offline\)/u);
  assert.match(readFileSync(summary, "utf8"), /- native_test: PASS/u);
});

test("offline-before-tests log on the second scale retries only that scale's drive", () => {
  const run = runDriveScript({
    targets: "native_test core_screen_a11y_smoke_test:2.0",
    drives: [passDrive(), { log: fixture("offline-before-tests-second-target.txt") }, passA11y("2.0")],
  });
  assert.equal(run.status, 0);
  assert.deepEqual(run.receipt.retried, ["drive:adb_offline"]);
  assert.equal(run.driveCalls, 3);
  assert.ok(run.exists("flutter-drive-scale-2.0.attempt1.log"));
  assert.equal(run.exists("flutter-drive-scale-1.0.attempt1.log"), false);
});

for (const [name, reason] of [
  ["synthetic-device-not-found.txt", "device_not_found"],
  ["synthetic-install-failed.txt", "install_failed"],
]) {
  test(`${reason} infra error before tests retries once`, () => {
    const run = runDriveScript({ drives: [{ log: fixture(name) }, passDrive()] });
    assert.equal(run.status, 0);
    assert.deepEqual(run.receipt.retried, [`drive:${reason}`]);
    assert.equal(run.driveCalls, 2);
  });
}

for (const line of ["error: no devices/emulators found", "error: device not found"]) {
  test(`"${line}" before tests retries once`, () => {
    const run = runDriveScript({ drives: [{ log: `${line}\n` }, passDrive()] });
    assert.equal(run.status, 0);
    assert.deepEqual(run.receipt.retried, ["drive:device_not_found"]);
  });
}

test("real assertion failure never retries, even with offline lines mixed in", () => {
  const mixed = `${fixture("assertion-failure.txt")}\nadb: device offline\nadb uninstall failed: ProcessException\n`;
  for (const log of [fixture("assertion-failure.txt"), mixed]) {
    const run = runDriveScript({ drives: [{ log }, passDrive()] });
    assert.equal(run.status, 1);
    assert.deepEqual(run.receipt, failedReceipt({ target: "native_test", step: "drive" }));
    assert.equal(run.driveCalls, 1);
    assert.equal(run.reconnects, 0);
  }
});

// 결과 신호가 하나라도 있으면(실제 offline 로그에 섞어도) 재시도하지 않는다. 신호마다 하나씩 단독으로 확인한다.
for (const signal of [
  "I/flutter ( 4098): 00:03 +1: 어떤 테스트",
  "All tests passed.",
  "Failure Details:",
  "Some tests failed.",
  "EXCEPTION CAUGHT BY FLUTTER TEST FRAMEWORK",
  "Test failed. See exception logs above.",
]) {
  test(`result signal "${signal}" blocks the retry`, () => {
    const log = `${fixture("offline-before-tests.txt")}\n${signal}\n`;
    const run = runDriveScript({ drives: [{ log }, passDrive()] });
    assert.equal(run.status, 1);
    assert.equal(run.receipt.status, "FAIL");
    assert.equal(run.receipt.target, "native_test");
    assert.equal(run.receipt.step, "drive");
    assert.equal(run.receipt.retried, undefined);
    assert.equal(run.driveCalls, 1);
  });
}

test("drive log without positive infra evidence is not retried", () => {
  const run = runDriveScript({ drives: [{ log: "Launching integration_test/native_smoke_test.dart\nsomething unknown\n" }, passDrive()] });
  assert.equal(run.status, 1);
  assert.deepEqual(run.receipt, failedReceipt({ target: "native_test", step: "drive" }, { native_test: "NOT_RUN" }));
  assert.equal(run.driveCalls, 1);
});

test("timeout exit 124 is a hang: no retry even with an offline line, receipt records timeout", () => {
  const run = runDriveScript({ drives: [{ log: fixture("offline-before-tests.txt"), exit: 124 }, passDrive()] });
  assert.equal(run.status, 1);
  assert.deepEqual(run.receipt, failedReceipt({ target: "native_test", step: "drive", reason: "timeout" }, { native_test: "NOT_RUN" }));
  assert.equal(run.driveCalls, 1);
  assert.equal(run.reconnects, 0);
});

test("each drive is retried at most once and a failed retry stays FAIL with retried recorded", () => {
  const offline = { log: fixture("offline-before-tests.txt") };
  const run = runDriveScript({ drives: [offline, offline, passDrive()] });
  assert.equal(run.status, 1);
  assert.deepEqual(run.receipt, failedReceipt({ target: "native_test", step: "drive", retried: ["drive:adb_offline"] }, { native_test: "NOT_RUN" }));
  assert.equal(run.driveCalls, 2);
});

test("device never ready before the format step writes a boot FAIL receipt without running anything", () => {
  const run = runDriveScript({ boot: ["0"], targets: "native_test core_screen_a11y_smoke_test", drives: [passDrive({ groups: bothGroups })] });
  assert.equal(run.status, 1);
  assert.deepEqual(
    run.receipt,
    failedReceipt({ target: "native_test core_screen_a11y_smoke_test", step: "boot" }, { native_test: "NOT_RUN", core_screen_a11y_smoke_test: "NOT_RUN" }),
  );
  assert.equal(run.driveCalls, 0);
});

test("adb wait-for-device failure is a boot FAIL even when getprop says ready", () => {
  const run = runDriveScript({ waitFails: true, drives: [passDrive()] });
  assert.equal(run.status, 1);
  assert.deepEqual(run.receipt, failedReceipt({ target: "native_test", step: "boot" }, { native_test: "NOT_RUN" }));
  assert.equal(run.driveCalls, 0);
});

test("device lost before a drive fails that drive's targets at boot, not drive", () => {
  const first = runDriveScript({ boot: ["1", "0"], drives: [passDrive()] });
  assert.equal(first.status, 1);
  assert.deepEqual(first.receipt, failedReceipt({ target: "native_test", step: "boot" }, { native_test: "NOT_RUN" }));
  assert.equal(first.driveCalls, 0);

  const second = runDriveScript({
    boot: ["1", "1", "0"],
    targets: "native_test core_screen_a11y_smoke_test:2.0",
    drives: [passDrive(), passA11y("2.0")],
  });
  assert.equal(second.status, 1);
  assert.deepEqual(
    second.receipt,
    failedReceipt({ target: "core_screen_a11y_smoke_test:2.0", step: "boot" }, { native_test: "PASS", "core_screen_a11y_smoke_test:2.0": "NOT_RUN" }),
  );
  assert.equal(second.driveCalls, 1);
});

test("device that does not come back after adb reconnect fails at boot and keeps the retried record", () => {
  const run = runDriveScript({ boot: ["1", "1", "0"], drives: [{ log: fixture("offline-before-tests.txt") }, passDrive()] });
  assert.equal(run.status, 1);
  assert.deepEqual(run.receipt, failedReceipt({ target: "native_test", step: "boot", retried: ["drive:adb_offline"] }, { native_test: "NOT_RUN" }));
  assert.equal(run.driveCalls, 1);
  assert.equal(run.reconnects, 1);
});

test("clean drive passes without a retried entry, and uninstall noise after the result does not matter", () => {
  const noise = fixture("pass-with-uninstall-noise.txt").trimEnd().split("\n").slice(-5).join("\n");
  assert.match(noise, /adb uninstall failed/u);
  const run = runDriveScript({ drives: [passDrive({ noise })] });
  assert.equal(run.status, 0);
  assert.deepEqual(run.receipt, passedReceipt());
});

test("targets at the same scale share one drive and each target gets its own verdict", () => {
  const run = runDriveScript({
    targets: "native_test core_screen_a11y_smoke_test",
    drives: [passDrive({ groups: bothGroups })],
  });
  assert.equal(run.status, 0);
  assert.deepEqual(run.receipt, passedReceipt({ native_test: "PASS", core_screen_a11y_smoke_test: "PASS" }));
  assert.equal(run.driveCalls, 1);
  assert.ok(run.exists("flutter-drive-scale-1.0.log"));
});

test("a failing group fails only its own target while the other group at that scale stays PASS", () => {
  const failing = ["core_screen_a11y_smoke_test"];
  const run = runDriveScript({
    targets: "native_test core_screen_a11y_smoke_test",
    drives: [{ log: driveLog({ groups: bothGroups, failing }), results: structured(bothGroups, failing) }, passDrive({ groups: bothGroups })],
  });
  assert.equal(run.status, 1);
  assert.deepEqual(
    run.receipt,
    failedReceipt({ target: "core_screen_a11y_smoke_test", step: "drive" }, { native_test: "PASS", core_screen_a11y_smoke_test: "FAIL" }),
  );
  assert.equal(run.driveCalls, 1);
});

test("a failing large-scale group fails only that scale's target and earlier targets stay PASS", () => {
  const run = runDriveScript({
    targets: "native_test core_screen_a11y_smoke_test core_screen_a11y_smoke_test:2.0",
    drives: [
      passDrive({ groups: bothGroups }),
      {
        log: driveLog({ groups: ["core_screen_a11y_smoke_test"], observed: "2.0", failing: ["core_screen_a11y_smoke_test"] }),
        results: structured(["core_screen_a11y_smoke_test"], ["core_screen_a11y_smoke_test"]),
      },
    ],
  });
  assert.equal(run.status, 1);
  assert.deepEqual(
    run.receipt,
    failedReceipt(
      { target: "core_screen_a11y_smoke_test:2.0", step: "drive" },
      { native_test: "PASS", core_screen_a11y_smoke_test: "PASS", "core_screen_a11y_smoke_test:2.0": "FAIL" },
    ),
  );
  assert.equal(run.driveCalls, 2);
});

test("a drive that ends without a summary never turns started groups into PASS", () => {
  const log = driveLog({ groups: bothGroups, complete: false });
  const run = runDriveScript({ targets: "native_test core_screen_a11y_smoke_test", drives: [{ log, exit: 1 }] });
  assert.equal(run.status, 1);
  assert.deepEqual(
    run.receipt,
    failedReceipt({ target: "native_test core_screen_a11y_smoke_test", step: "drive" }, { native_test: "NOT_RUN", core_screen_a11y_smoke_test: "NOT_RUN" }),
  );
});

test("a green drive missing a target's group fails that target instead of passing", () => {
  const run = runDriveScript({ targets: "native_test core_screen_a11y_smoke_test", drives: [passDrive({ groups: ["core_screen_a11y_smoke_test"] })] });
  assert.equal(run.status, 1);
  assert.deepEqual(
    run.receipt,
    failedReceipt({ target: "native_test", step: "drive", reason: "group_missing" }, { native_test: "FAIL", core_screen_a11y_smoke_test: "PASS" }),
  );
});

test("a group name that only shares a prefix with a target does not count as that target", () => {
  const log = driveLog({ groups: ["native_test_extra"] });
  const run = runDriveScript({ drives: [{ log, exit: 0 }] });
  assert.equal(run.status, 1);
  assert.deepEqual(run.receipt, failedReceipt({ target: "native_test", step: "drive", reason: "group_missing" }));
});

test("the scale the app read must match the requested scale, otherwise the drive is a FAIL even when green", () => {
  for (const observed of ["1.0", "", "abc"]) {
    const run = runDriveScript({
      targets: "core_screen_a11y_smoke_test:2.0",
      drives: [passA11y(observed)],
    });
    assert.equal(run.status, 1, observed);
    assert.deepEqual(
      run.receipt,
      failedReceipt({ target: "core_screen_a11y_smoke_test:2.0", step: "drive", reason: "font_scale_mismatch" }, { "core_screen_a11y_smoke_test:2.0": "NOT_RUN" }),
      observed,
    );
  }
});

test("the observed scale may differ from the requested one by the tolerance only, exactly at the boundary included", () => {
  const cases = [["2.004", true], ["1.996", true], ["2.01", true], ["1.99", true], ["2.0101", false], ["1.9899", false], ["2.02", false], ["1.98", false]];
  for (const [observed, ok] of cases) {
    const run = runDriveScript({ targets: "core_screen_a11y_smoke_test:2.0", drives: [passA11y(observed)] });
    assert.equal(run.status, ok ? 0 : 1, observed);
    if (!ok) assert.equal(run.receipt.reason, "font_scale_mismatch", observed);
  }
});

test("the scale line must appear exactly once: none, several, or a bad one before or after the good one all fail", () => {
  const variants = {
    none: [],
    "good twice": ["2.0", "2.0"],
    "bad then good": ["1.0", "2.0"],
    "good then bad": ["2.0", "1.0"],
  };
  for (const [name, observed] of Object.entries(variants)) {
    const run = runDriveScript({ targets: "core_screen_a11y_smoke_test:2.0", drives: [passA11y(observed)] });
    assert.equal(run.status, 1, name);
    assert.equal(run.receipt.reason, "font_scale_mismatch", name);
    assert.deepEqual(run.receipt.results, { "core_screen_a11y_smoke_test:2.0": "NOT_RUN" }, name);
  }
});

test("native_test alone still gets its scale line because the entry point prints it outside any group", () => {
  const run = runDriveScript({ targets: "native_test", drives: [passDrive({ groups: ["native_test"], observed: "1.0" })] });
  assert.equal(run.status, 0);
  assert.deepEqual(run.receipt, passedReceipt());
});

test("real Android large-text log from the shared entry point passes the scale-suffixed target", () => {
  const log = readFileSync(path.join(fixtureDir, "real-pass-large-text-a11y-only.txt"), "utf8");
  const results = JSON.parse(readFileSync(path.join(fixtureDir, "real-results-large-text-a11y-only.json"), "utf8"));
  const run = runDriveScript({ targets: "core_screen_a11y_smoke_test:2.0", drives: [{ log, exit: 0, results }] });
  assert.equal(run.status, 0);
  assert.deepEqual(run.receipt, passedReceipt({ "core_screen_a11y_smoke_test:2.0": "PASS" }));
});

// 실제 CI(RED 확인 run)에서 testWidgets가 아닌 test()가 실패했는데 integrationDriver가 종료 코드 0과
// "All tests passed."로 끝낸 로그다. 요약 줄은 "Some tests failed."이고 실패 상세는 없다.
test("real log where a failing test() leaves the driver green still fails that group's target", () => {
  const log = readFileSync(path.join(fixtureDir, "real-silent-failure-exit-zero.txt"), "utf8");
  assert.match(log, /Some tests failed\./u);
  assert.match(log, /All tests passed\./u);
  assert.doesNotMatch(log, /Failure Details/u);
  const run = runDriveScript({ targets: "core_screen_a11y_smoke_test:2.0", drives: [{ log, exit: 0 }] });
  assert.equal(run.status, 1);
  assert.deepEqual(
    run.receipt,
    failedReceipt({ target: "core_screen_a11y_smoke_test:2.0", step: "drive" }, { "core_screen_a11y_smoke_test:2.0": "FAIL" }),
  );
});

// 실제 CI(RED 확인 run)의 iOS 큰 글자 실행: test()와 testWidgets 실패가 함께 있고, 실패 상세에는 group 이름이 없다.
test("real iOS RED log fails only the large-text target while the other targets keep their own verdicts", () => {
  const log = readFileSync(new URL("./fixtures/ios-drive/real-red-large-text-failures.txt", import.meta.url), "utf8");
  assert.match(log, /Failure in method: RED 확인용 testWidgets/u);
  const run = runIos({
    targets: iosAllTargets,
    drives: [iosPass({ groups: bothGroups }), { log, exit: 1 }],
  });
  assert.equal(run.status, 1);
  assert.deepEqual(
    run.receipt,
    iosReceipt(
      "FAIL",
      { native_test: "PASS", core_screen_a11y_smoke_test: "PASS", "core_screen_a11y_smoke_test:3.12": "FAIL" },
      { target: "core_screen_a11y_smoke_test:3.12", step: "drive" },
    ),
  );
  assert.equal(run.driveCalls, 2);
});

test("a green exit with a failed test line fails only the group that owns it, and a summary-only failure fails the whole drive", () => {
  const failedLine = `I/flutter ( 4098): 00:05 +3 -1: core_screen_a11y_smoke_test 화면 - 글자 1.00배 탭 영역 48dp [E]`;
  const attributed = `${driveLog({ groups: bothGroups })}${failedLine}\n`.replace("All tests passed!", "Some tests failed.");
  const run = runDriveScript({
    targets: "native_test core_screen_a11y_smoke_test",
    drives: [{ log: attributed, exit: 0, results: structured(bothGroups) }],
  });
  assert.equal(run.status, 1);
  assert.deepEqual(
    run.receipt,
    failedReceipt({ target: "core_screen_a11y_smoke_test", step: "drive" }, { native_test: "PASS", core_screen_a11y_smoke_test: "FAIL" }),
  );

  const unattributed = driveLog({ groups: bothGroups }).replace("All tests passed!", "Some tests failed.");
  const whole = runDriveScript({
    targets: "native_test core_screen_a11y_smoke_test",
    drives: [{ log: unattributed, exit: 0, results: structured(bothGroups) }],
  });
  assert.equal(whole.status, 1);
  assert.deepEqual(
    whole.receipt,
    failedReceipt({ target: "native_test core_screen_a11y_smoke_test", step: "drive" }, { native_test: "FAIL", core_screen_a11y_smoke_test: "FAIL" }),
  );
});

// 구조화 결과가 1차 판정이고 로그는 보조다. 둘이 다르면 FAIL이다.
const a11yGroup = ["core_screen_a11y_smoke_test"];
const a11yTarget = { targets: "core_screen_a11y_smoke_test" };

test("structured result says the group failed while the log looks clean: FAIL", () => {
  const run = runDriveScript({ ...a11yTarget, drives: [{ log: driveLog({ groups: a11yGroup }), exit: 0, results: structured(a11yGroup, a11yGroup) }] });
  assert.equal(run.status, 1);
  assert.deepEqual(run.receipt, failedReceipt({ target: "core_screen_a11y_smoke_test", step: "drive" }, { core_screen_a11y_smoke_test: "FAIL" }));
});

test("structured failure is trusted even when the log was cut before its summary", () => {
  const log = driveLog({ groups: a11yGroup, complete: false });
  const run = runDriveScript({ ...a11yTarget, drives: [{ log, exit: 1, results: structured(a11yGroup, a11yGroup) }] });
  assert.equal(run.status, 1);
  assert.deepEqual(run.receipt, failedReceipt({ target: "core_screen_a11y_smoke_test", step: "drive" }, { core_screen_a11y_smoke_test: "FAIL" }));
});

test("structured result says passed but the log carries a failed test line: FAIL", () => {
  const log = driveLog({ groups: a11yGroup, failing: a11yGroup });
  const run = runDriveScript({ ...a11yTarget, drives: [{ log, exit: 0, results: structured(a11yGroup) }] });
  assert.equal(run.status, 1);
  assert.deepEqual(run.receipt, failedReceipt({ target: "core_screen_a11y_smoke_test", step: "drive" }, { core_screen_a11y_smoke_test: "FAIL" }));
});

test("a failure counter alone (no failed-line marker, summary says passed) still fails the drive even if the structured result passes", () => {
  const log = driveLog({ groups: bothGroups, failing: a11yGroup, counterOnly: true })
    .replace("Some tests failed.", "All tests passed!")
    .replace("Failure Details:", "All tests passed.");
  assert.doesNotMatch(log, /\[E\]|Some tests failed|Failure Details/u);
  const run = runDriveScript({ targets: "native_test core_screen_a11y_smoke_test", drives: [{ log, exit: 0, results: structured(bothGroups) }] });
  assert.equal(run.status, 1);
  assert.deepEqual(
    run.receipt,
    failedReceipt({ target: "native_test core_screen_a11y_smoke_test", step: "drive" }, { native_test: "FAIL", core_screen_a11y_smoke_test: "FAIL" }),
  );
});

test("a green exit without a structured result file or with no passed test in the group is not a PASS", () => {
  const withoutFile = runDriveScript({ ...a11yTarget, drives: [passDrive({ groups: a11yGroup, results: null })] });
  assert.equal(withoutFile.status, 1);
  assert.deepEqual(
    withoutFile.receipt,
    failedReceipt({ target: "core_screen_a11y_smoke_test", step: "drive", reason: "group_missing" }, { core_screen_a11y_smoke_test: "FAIL" }),
  );

  const empty = runDriveScript({
    ...a11yTarget,
    drives: [{ log: driveLog({ groups: a11yGroup }), exit: 0, results: { nativeGroups: { core_screen_a11y_smoke_test: { passed: 0, failed: [] } } } }],
  });
  assert.equal(empty.status, 1);
  assert.equal(empty.receipt.reason, "group_missing");
});

test("structured PASS for a group whose tests never started in the log is a disagreement and fails", () => {
  const run = runDriveScript({ ...a11yTarget, drives: [{ log: driveLog({ groups: ["other_group"] }), exit: 0, results: structured(a11yGroup) }] });
  assert.equal(run.status, 1);
  assert.equal(run.receipt.results.core_screen_a11y_smoke_test, "FAIL");
});

test("structured results are kept per scale in the evidence and each drive writes into its own outputs directory", () => {
  const run = runDriveScript({
    targets: "native_test core_screen_a11y_smoke_test:2.0",
    drives: [passDrive(), passA11y("2.0")],
  });
  assert.equal(run.status, 0);
  assert.deepEqual(JSON.parse(run.read("results-scale-1.0.json")), structured(["native_test"]));
  assert.deepEqual(JSON.parse(run.read("results-scale-2.0.json")), structured(a11yGroup));
  assert.equal(new Set(run.outputsDirs).size, 2);
});

test("an app binary left over from an earlier build is removed first, so only a binary the first drive built can be reused", () => {
  const run = runDriveScript({
    binary: "stale",
    targets: "native_test core_screen_a11y_smoke_test:2.0",
    drives: [passDrive(), passA11y("2.0")],
  });
  assert.equal(run.status, 1);
  assert.deepEqual(run.receipt, failedReceipt({ target: "native_test", step: "build" }, { native_test: "PASS", "core_screen_a11y_smoke_test:2.0": "NOT_RUN" }));
  assert.equal(run.driveCalls, 1);
});

test("assert_all_passed refuses a PASS receipt while any verdict is not PASS", () => {
  const commonPath = fileURLToPath(new URL("./native-drive-common.sh", import.meta.url));
  const harness = (verdicts) => {
    const evidence = mkdtempSync(path.join(tmpdir(), "assert-"));
    const result = spawnSync(
      "bash",
      ["-c", 'lane=android-native; evidence="$1"; platform_collect_failure_log() { :; }; source "$2"; verdicts=($3); assert_all_passed', "bash", evidence, commonPath, verdicts],
      { env: { PATH: process.env.PATH, NATIVE_TARGETS: "native_test core_screen_a11y_smoke_test" }, encoding: "utf8" },
    );
    return { status: result.status, receipt: existsSync(path.join(evidence, "receipt.json")) ? JSON.parse(readFileSync(path.join(evidence, "receipt.json"), "utf8")) : null };
  };
  assert.deepEqual(harness("PASS PASS"), { status: 0, receipt: null });
  for (const verdicts of ["PASS NOT_RUN", "PASS FAIL"]) {
    const { status, receipt } = harness(verdicts);
    assert.equal(status, 1, verdicts);
    assert.deepEqual(
      receipt,
      failedReceipt(
        { target: "core_screen_a11y_smoke_test", step: "drive", reason: "verdict_not_pass" },
        { native_test: "PASS", core_screen_a11y_smoke_test: verdicts.split(" ")[1] },
      ),
    );
  }
});

test("only the first drive builds: later drives reuse the app binary and the scale is never a dart-define", () => {
  const run = runDriveScript({
    targets: "native_test core_screen_a11y_smoke_test core_screen_a11y_smoke_test:2.0",
    drives: [passDrive({ groups: bothGroups }), passA11y("2.0")],
  });
  assert.equal(run.status, 0);
  assert.deepEqual(run.receipt, passedReceipt({ native_test: "PASS", core_screen_a11y_smoke_test: "PASS", "core_screen_a11y_smoke_test:2.0": "PASS" }));
  assert.equal(run.driveArgs.length, 2);
  assert.doesNotMatch(run.driveArgs[0], /--use-application-binary/u);
  assert.ok(run.driveArgs[1].includes(`--use-application-binary=${run.appBinary}`));
  for (const args of run.driveArgs) {
    assert.match(args, /--target=integration_test\/native_smoke_test\.dart/u);
    assert.doesNotMatch(args, /dart-define|A11Y_FONT_SCALE/u);
  }
  assert.deepEqual(run.fontScales, ["1.0", "2.0"]);
  assert.ok(run.exists("flutter-drive-scale-1.0.log"));
  assert.ok(run.exists("flutter-drive-scale-2.0.log"));
  // 빌드를 포함하는 첫 drive만 넉넉한 시간 제한을 받는다.
  assert.deepEqual(run.timeouts, ["900s", "300s"]);
});

test("a run with one scale never needs a reusable binary", () => {
  const run = runDriveScript({ binary: "none", drives: [passDrive()] });
  assert.equal(run.status, 0);
  assert.deepEqual(run.driveArgs.map((args) => args.includes("--use-application-binary")), [false]);
});

test("a missing app binary after the first drive is a build FAIL and the later scale never runs", () => {
  const run = runDriveScript({
    binary: "none",
    targets: "native_test core_screen_a11y_smoke_test:2.0",
    drives: [passDrive(), passA11y("2.0")],
  });
  assert.equal(run.status, 1);
  assert.deepEqual(run.receipt, failedReceipt({ target: "native_test", step: "build" }, { native_test: "PASS", "core_screen_a11y_smoke_test:2.0": "NOT_RUN" }));
  assert.equal(run.driveCalls, 1);
});

test("a retried first drive still builds, and the retry keeps the reuse arguments off", () => {
  const run = runDriveScript({
    targets: "native_test core_screen_a11y_smoke_test:2.0",
    drives: [{ log: fixture("offline-before-tests.txt") }, passDrive(), passA11y("2.0")],
  });
  assert.equal(run.status, 0);
  assert.equal(run.driveArgs.filter((args) => args.includes("--use-application-binary")).length, 1);
  assert.ok(run.driveArgs[2].includes("--use-application-binary"));
});

test("font scale write that fails on an offline device retries once and re-applies the scale", () => {
  const run = runDriveScript({
    targets: "core_screen_a11y_smoke_test:2.0",
    drives: [passA11y("2.0")],
    env: { FONT_SCALE_FAILS: "1", FONT_SCALE_FAIL_LOG: "error: device offline" },
  });
  assert.equal(run.status, 0);
  assert.deepEqual(run.receipt, passedReceipt({ "core_screen_a11y_smoke_test:2.0": "PASS" }, { retried: ["drive:adb_offline"] }));
  assert.equal(run.read("flutter-drive-scale-2.0.attempt1.log"), "error: device offline\n");
  assert.deepEqual(run.fontScales, ["2.0", "2.0"]);
  assert.equal(run.driveCalls, 1);
});

test("a retried drive sets the font scale again before the second attempt", () => {
  const run = runDriveScript({
    targets: "core_screen_a11y_smoke_test:2.0",
    drives: [{ log: fixture("offline-before-tests.txt") }, passA11y("2.0")],
  });
  assert.equal(run.status, 0);
  assert.deepEqual(run.fontScales, ["2.0", "2.0"]);
  assert.equal(run.driveArgs.length, 2);
});

test("failing to set the font scale fails the drive's targets without running the test", () => {
  const run = runDriveScript({
    targets: "core_screen_a11y_smoke_test:2.0",
    drives: [passA11y("2.0")],
    env: { FONT_SCALE_FAILS: "1" },
  });
  assert.equal(run.status, 1);
  assert.deepEqual(
    run.receipt,
    failedReceipt({ target: "core_screen_a11y_smoke_test:2.0", step: "drive" }, { "core_screen_a11y_smoke_test:2.0": "NOT_RUN" }),
  );
  assert.equal(run.driveCalls, 0);
  assert.equal(run.fontScales.length, 1);
});

const iosReceipt = (status, results, extra = {}) => receiptOf("ios", status, results, extra);
const iosAx5 = "accessibility-extra-extra-extra-large";
const runIos = (options) => runDriveScript({ platform: "ios", ...options });
const iosPass = (options = {}) => passDrive({ platform: "ios", ...options });
const iosA11yPass = (scale) => iosPass({ groups: ["core_screen_a11y_smoke_test"], observed: scale });
// 합성 로그: 실제 CoreSimulatorService 오류 로그를 채집하기 전까지의 가정이다. 패턴이 맞지 않으면 재시도 없이 FAIL이라 안전하다.
const simulatorUnavailableLog = "CoreSimulatorService connection became invalid\nSimulator services will no longer be available.\n";
const iosAllTargets = "native_test core_screen_a11y_smoke_test core_screen_a11y_smoke_test:3.12";

test("iOS clean run sets the content size once per scale, drives the shared entry point, and reads the AX5 scale Flutter reports", () => {
  const run = runIos({
    targets: iosAllTargets,
    drives: [iosPass({ groups: bothGroups }), iosA11yPass("3.1176470588235294")],
  });
  assert.equal(run.status, 0);
  assert.deepEqual(
    run.receipt,
    iosReceipt("PASS", { native_test: "PASS", core_screen_a11y_smoke_test: "PASS", "core_screen_a11y_smoke_test:3.12": "PASS" }),
  );
  assert.deepEqual(run.contentSizes, ["large", iosAx5]);
  assert.equal(run.driveCalls, 2);
  for (const log of ["flutter-drive-scale-1.0.log", "flutter-drive-scale-3.12.log"]) {
    assert.ok(run.exists(log), log);
  }
});

test("real iOS large-text log from the shared entry point passes only the scale-suffixed target", () => {
  const log = readFileSync(new URL("./fixtures/ios-drive/real-pass-large-text-a11y-only.txt", import.meta.url), "utf8");
  const results = JSON.parse(readFileSync(new URL("./fixtures/ios-drive/real-results-large-text-a11y-only.json", import.meta.url), "utf8"));
  const run = runIos({ targets: "core_screen_a11y_smoke_test:3.12", drives: [{ log, exit: 0, results }] });
  assert.equal(run.status, 0);
  assert.deepEqual(run.receipt, iosReceipt("PASS", { "core_screen_a11y_smoke_test:3.12": "PASS" }));

  // native_test는 큰 글자 실행에 group이 없으므로 같은 배율로 요구하면 PASS로 읽지 않는다.
  const missing = runIos({ targets: "native_test:3.12 core_screen_a11y_smoke_test:3.12", drives: [{ log, exit: 0, results }] });
  assert.equal(missing.status, 1);
  assert.deepEqual(
    missing.receipt,
    iosReceipt("FAIL", { "native_test:3.12": "FAIL", "core_screen_a11y_smoke_test:3.12": "PASS" }, { target: "native_test:3.12", step: "drive", reason: "group_missing" }),
  );
});

test("iOS font scale outside the content size table fails the drive's targets without running the test", () => {
  const run = runIos({ targets: "core_screen_a11y_smoke_test:2.5", drives: [iosA11yPass("2.5")] });
  assert.equal(run.status, 1);
  assert.deepEqual(
    run.receipt,
    iosReceipt("FAIL", { "core_screen_a11y_smoke_test:2.5": "NOT_RUN" }, { target: "core_screen_a11y_smoke_test:2.5", step: "drive" }),
  );
  assert.equal(run.driveCalls, 0);
  assert.deepEqual(run.contentSizes, []);
  assert.match(run.read("flutter-drive-scale-2.5.log"), /지원하지 않는 iOS 글꼴 배율: 2\.5/u);
});

test("iOS content size that reads back differently fails the drive's targets", () => {
  const run = runIos({ targets: "core_screen_a11y_smoke_test:3.12", drives: [iosA11yPass("3.12")], env: { CONTENT_SIZE_STUCK: "1" } });
  assert.equal(run.status, 1);
  assert.deepEqual(
    run.receipt,
    iosReceipt("FAIL", { "core_screen_a11y_smoke_test:3.12": "NOT_RUN" }, { target: "core_screen_a11y_smoke_test:3.12", step: "drive" }),
  );
  assert.equal(run.driveCalls, 0);
});

test("iOS simulator infra error before tests retries once after shutting the simulator down", () => {
  const run = runIos({ drives: [{ log: simulatorUnavailableLog }, iosPass()] });
  assert.equal(run.status, 0);
  assert.deepEqual(run.receipt, iosReceipt("PASS", { native_test: "PASS" }, { retried: ["drive:simulator_unavailable"] }));
  assert.equal(run.driveCalls, 2);
  assert.equal(run.shutdowns, 1);
  assert.equal(run.read("flutter-drive-scale-1.0.attempt1.log"), simulatorUnavailableLog);
  assert.match(run.stdout, /^::warning::native_test drive가 simulator_unavailable 때문에 1회 재시도 후 통과했습니다\./mu);
});

test("iOS result signal blocks the retry, and a failed retry stays FAIL with retried recorded", () => {
  const blocked = runIos({ drives: [{ log: `${simulatorUnavailableLog}00:03 +1: 어떤 테스트\n` }, iosPass()] });
  assert.equal(blocked.status, 1);
  assert.deepEqual(blocked.receipt, iosReceipt("FAIL", { native_test: "NOT_RUN" }, { target: "native_test", step: "drive" }));
  assert.equal(blocked.driveCalls, 1);

  const twice = runIos({ drives: [{ log: simulatorUnavailableLog }, { log: simulatorUnavailableLog }, iosPass()] });
  assert.equal(twice.status, 1);
  assert.deepEqual(
    twice.receipt,
    iosReceipt("FAIL", { native_test: "NOT_RUN" }, { target: "native_test", step: "drive", retried: ["drive:simulator_unavailable"] }),
  );
  assert.equal(twice.driveCalls, 2);
});

test("iOS drive log without positive infra evidence is not retried, and perl alarm exit 142 is a timeout", () => {
  const unknown = runIos({ drives: [{ log: "something unknown\n" }, iosPass()] });
  assert.equal(unknown.status, 1);
  assert.deepEqual(unknown.receipt, iosReceipt("FAIL", { native_test: "NOT_RUN" }, { target: "native_test", step: "drive" }));
  assert.equal(unknown.driveCalls, 1);

  const timeout = runIos({ drives: [{ log: simulatorUnavailableLog, exit: 142 }, iosPass()] });
  assert.equal(timeout.status, 1);
  assert.deepEqual(timeout.receipt, iosReceipt("FAIL", { native_test: "NOT_RUN" }, { target: "native_test", step: "drive", reason: "timeout" }));
  assert.equal(timeout.driveCalls, 1);
  assert.equal(timeout.shutdowns, 0);
});

test("iOS simulator boot failure is recorded by step and keeps the simulator log", () => {
  const boot = runIos({ boot: ["0"], drives: [iosPass()] });
  assert.equal(boot.status, 1);
  assert.deepEqual(boot.receipt, iosReceipt("FAIL", { native_test: "NOT_RUN" }, { target: "native_test", step: "boot" }));
  assert.equal(boot.driveCalls, 0);
  assert.equal(boot.read("simulator.log"), "SIMULATOR LOG\n");
});

// 실제 CI에서 native_test drive가 빌드 뒤 12분 동안 멈춰 perl alarm(142)으로 끝난 로그다(PR #490 RED 확인 run).
// 시뮬레이터 인프라 오류 문구가 전혀 없다. 실제 CoreSimulatorService 오류 로그는 아직 채집하지 못했다.
const realHangLog = readFileSync(path.join(fileURLToPath(new URL("./fixtures/ios-drive/", import.meta.url)), "real-hang-after-build-timeout.txt"), "utf8");

test("real iOS hang log is a timeout, never retried, and carries no simulator infra evidence", () => {
  const timeout = runIos({ drives: [{ log: realHangLog, exit: 142 }, iosPass()] });
  assert.equal(timeout.status, 1);
  assert.deepEqual(timeout.receipt, iosReceipt("FAIL", { native_test: "NOT_RUN" }, { target: "native_test", step: "drive", reason: "timeout" }));
  assert.equal(timeout.driveCalls, 1);
  assert.equal(timeout.shutdowns, 0);

  const unknown = runIos({ drives: [{ log: realHangLog, exit: 1 }, iosPass()] });
  assert.equal(unknown.status, 1);
  assert.deepEqual(unknown.receipt, iosReceipt("FAIL", { native_test: "NOT_RUN" }, { target: "native_test", step: "drive" }));
  assert.equal(unknown.driveCalls, 1);
});

const systemTextScaleSource = readFileSync(new URL("../../apps/mobile/integration_test/system_text_scale.dart", import.meta.url), "utf8");
const entryPoint = readFileSync(new URL("../../apps/mobile/integration_test/native_smoke_test.dart", import.meta.url), "utf8");

test("iOS AX5 scale is defined once in the Dart constant and the lane values stay within the smoke test tolerance", () => {
  const constant = readFileSync(new URL("../../apps/mobile/test/support/ios_text_scale.dart", import.meta.url), "utf8");
  const [, numerator, denominator] = constant.match(/const iosAx5TextScale = (\d+) \/ (\d+);/u) ?? [];
  const ax5 = Number(numerator) / Number(denominator);
  const tolerance = Number(systemTextScaleSource.match(/const textScaleTolerance = ([\d.]+);/u)?.[1]);
  assert.ok(tolerance > 0);
  const laneScale = jobTargets(iosJob).find((target) => target.endsWith(":3.12"))?.split(":")[1];
  const tableScale = iosDriveScript.match(/^\s+([\d.]+)\) echo "accessibility-extra-extra-extra-large" ;;$/mu)?.[1];
  assert.equal(laneScale, "3.12");
  assert.equal(tableScale, laneScale);
  assert.ok(Math.abs(Number(laneScale) - ax5) <= tolerance, `${laneScale} vs ${ax5}`);
});

test("the shared entry point groups every lane target by name, builds once, and the host and Dart agree on the contract", () => {
  const groupNames = [...entryPoint.matchAll(/resultGroup\('([a-z_0-9]+)'/gu)].map((match) => match[1]);
  assert.deepEqual(groupNames, ["native_test", "core_screen_a11y_smoke_test"]);
  assert.match(entryPoint, /import 'native_test\.dart' as native_journey/u);
  assert.match(entryPoint, /import 'core_screen_a11y_smoke_test\.dart' as core_screen_a11y_smoke/u);
  assert.match(entryPoint, /resultGroup\('native_test', native_journey\.main\)/u);
  assert.match(entryPoint, /resultGroup\('core_screen_a11y_smoke_test', core_screen_a11y_smoke\.main\)/u);
  assert.match(entryPoint, /isLargeTextScale\(systemTextScale\)/u);
  for (const job of [androidJob, iosJob]) {
    for (const target of jobTargets(job)) {
      assert.ok(groupNames.includes(target.split(":")[0]), target);
    }
  }
  // 배율 줄은 group 밖 setUpAll에서 한 번만 남긴다(대상 조합과 무관하게 스크립트가 읽을 수 있다).
  const setUpAllAt = entryPoint.indexOf("setUpAll(");
  assert.ok(setUpAllAt >= 0 && setUpAllAt < entryPoint.indexOf("resultGroup('native_test'"));
  assert.match(entryPoint, /setUpAll\(\(\) \{\s*\/\/ ignore: avoid_print\s*print\('\$systemTextScaleMarker\$systemTextScale'\);\s*\}\);/u);
  assert.equal((entryPoint.match(/systemTextScaleMarker/gu) ?? []).length, 1);
  assert.doesNotMatch(a11ySmokeTest, /systemTextScaleMarker|print\(/u);

  assert.match(commonDriveScript, /^entrypoint="integration_test\/native_smoke_test\.dart"$/mu);
  assert.match(commonDriveScript, /^driver="test_driver\/native_smoke_driver\.dart"$/mu);
  for (const file of ["integration_test/native_smoke_test.dart", "test_driver/native_smoke_driver.dart"]) {
    assert.ok(existsSync(new URL(`../../apps/mobile/${file}`, import.meta.url)), file);
  }
  const hostDriver = readFileSync(new URL("../../apps/mobile/test_driver/native_smoke_driver.dart", import.meta.url), "utf8");
  assert.match(hostDriver, /integrationDriver\(writeResponseOnFailure: true\)/u);
  for (const adapter of [androidDriveScript, iosDriveScript]) {
    assert.match(adapter, /"--driver=\$\{driver\}" "--target=\$\{entrypoint\}"/u);
    assert.match(adapter, /\$\{drive_reuse_args\[@\]\+"\$\{drive_reuse_args\[@\]\}"\}/u);
    assert.doesNotMatch(adapter, /dart-define|A11Y_FONT_SCALE|flutter build/u);
  }
  assert.doesNotMatch(commonDriveScript, /dart-define|A11Y_FONT_SCALE|flutter build/u);
  assert.match(androidDriveScript, /^app_binary="\$\{APP_BINARY:-build\/app\/outputs\/flutter-apk\/app-debug\.apk\}"$/mu);
  assert.match(iosDriveScript, /^app_binary="\$\{APP_BINARY:-build\/ios\/iphonesimulator\/Runner\.app\}"$/mu);

  const hostTolerance = commonDriveScript.match(/^scale_tolerance="([\d.]+)"$/mu)?.[1];
  assert.equal(hostTolerance, systemTextScaleSource.match(/const textScaleTolerance = ([\d.]+);/u)?.[1]);
  const hostMarker = commonDriveScript.match(/^scale_marker="([A-Z_]+=)"$/mu)?.[1];
  assert.equal(hostMarker, markerName);
  assert.equal(hostMarker, systemTextScaleSource.match(/const systemTextScaleMarker = '([A-Z_]+=)';/u)?.[1]);
  const hostResultsKey = commonDriveScript.match(/^results_key="(\w+)"$/mu)?.[1];
  assert.equal(hostResultsKey, "nativeGroups");
  assert.equal(hostResultsKey, entryPoint.match(/const _resultsKey = '(\w+)';/u)?.[1]);
});

test("target suites use testWidgets only, because the integration binding cannot see a failing test()", () => {
  for (const [name, source] of [["native_test.dart", nativeTest], ["core_screen_a11y_smoke_test.dart", a11ySmokeTest]]) {
    assert.doesNotMatch(source, /^\s*test\(/mu, name);
    assert.match(source, /testWidgets\(/u, name);
  }
});

test("the shared entry point lists its sources in the workflow path filters of both events and uploads the structured results", () => {
  for (const lane of ["android", "ios"]) {
    assert.equal(
      workflow.split("\n").filter((line) => line === `            \${{ runner.temp }}/mobile-native-${lane}/results-scale-*.json`).length,
      1,
      lane,
    );
  }
  for (const glob of [
    "apps/mobile/integration_test/native_smoke_test.dart",
    "apps/mobile/integration_test/system_text_scale.dart",
    "apps/mobile/test_driver/native_smoke_driver.dart",
  ]) {
    assert.equal(workflow.split("\n").filter((line) => line === `      - "${glob}"`).length, 2, glob);
  }
});

test("core screen accessibility smoke reuses the sweep screen table and checks tap targets, labels, render exceptions, and the applied font scale", () => {
  assert.equal(
    (workflow.match(/"apps\/mobile\/integration_test\/core_screen_a11y_smoke_test\.dart"/gu) ?? []).length,
    2,
  );
  assert.equal(
    (workflow.match(/"apps\/mobile\/test\/support\/core_screen_sweep_\*\.dart"/gu) ?? []).length,
    2,
  );
  assert.equal(
    (workflow.match(/"apps\/mobile\/test\/support\/full_tap_target_guideline\.dart"/gu) ?? []).length,
    2,
  );
  for (const glob of [
    "apps/mobile/lib/accessible_design.dart",
    "apps/mobile/lib/app/**",
    "apps/mobile/lib/features/network_map/**",
    "apps/mobile/lib/features/notifications/**",
    "apps/mobile/lib/features/settings/**",
    "apps/mobile/lib/features/stations/**",
    "tools/ci/android-native-drive.sh",
    "tools/ci/ios-native-drive.sh",
    "tools/ci/native-drive-common.sh",
  ]) {
    assert.equal(workflow.split("\n").filter((line) => line === `      - "${glob}"`).length, 2, glob);
  }
  assert.match(a11ySmokeTest, /IntegrationTestWidgetsFlutterBinding\.ensureInitialized\(\)/u);
  assert.match(a11ySmokeTest, /import '\.\.\/test\/support\/core_screen_sweep_screens\.dart'/u);
  assert.match(a11ySmokeTest, /TargetPlatform\.android => \(\s*guideline: androidTapTargetGuideline/u);
  assert.match(a11ySmokeTest, /TargetPlatform\.iOS => \(\s*guideline: iOSTapTargetGuideline/u);
  assert.match(a11ySmokeTest, /throw StateError\('탭 영역 기준이 없는 플랫폼/u);
  assert.match(a11ySmokeTest, /meetsGuideline\(_tapTarget\.guideline\)/u);
  assert.match(a11ySmokeTest, /meetsGuideline\(_tapTarget\.fullGuideline\)/u);
  assert.match(a11ySmokeTest, /fullGuideline: FullTapTargetGuideline\(androidMinTapTarget\)/u);
  assert.match(a11ySmokeTest, /fullGuideline: FullTapTargetGuideline\(iosMinTapTarget\)/u);
  assert.match(a11ySmokeTest, /meetsGuideline\(labeledTapTargetGuideline\)/u);
  assert.doesNotMatch(a11ySmokeTest, /fromEnvironment|A11Y_FONT_SCALE/u);
  assert.match(a11ySmokeTest, /final _fontScale = systemTextScale;/u);
  assert.match(a11ySmokeTest, /platformDispatcher\.textScaleFactor,\s*closeTo\(_fontScale, textScaleTolerance\)/u);
  assert.match(a11ySmokeTest, /expect\(tester\.takeException\(\), isNull\)/u);
  assert.doesNotMatch(a11ySmokeTest, /textContrastGuideline/u);
});

test("native Journey smoke stays server-only and bounded to success, failure, and restart", () => {
  assert.match(nativeTest, /IntegrationTestWidgetsFlutterBinding\.ensureInitialized\(\)/u);
  assert.match(nativeTest, /JourneyPlanSource\.serverTimetableRaptor/u);
  assert.match(nativeTest, /JourneyTransportFailure/u);
  assert.match(nativeTest, /restartAndRestore\(\)/u);
  assert.match(nativeTest, /expect\(repository\.searchRequests, 1\)/u);
  assert.doesNotMatch(nativeTest, /route[_ -]?v[12]|local route|previous result|provider refresh/iu);
});

// iOS lane: Xcode 빌드 캐시와 Flutter iOS 시뮬레이터 VM service 연결 수정(#3036).
const flutterVersion = workflow.match(/flutter-version: "([\d.]+)"/u)?.[1];
const flutterPatchDir = new URL("./flutter-patches/", import.meta.url);
const flutterPatchFile = `${flutterVersion}-ios-simulator-log-stream-ready.patch`;
const flutterPatch = readFileSync(new URL(flutterPatchFile, flutterPatchDir), "utf8");
const applyPatchScript = readScript("apply-flutter-patch.sh");
const androidSteps = androidJob.slice(androidJob.indexOf("\njobs:"));
const stepNames = (job) => [...job.matchAll(/^      - name: (.+)$/gmu)].map((match) => match[1]);
const stepBlock = (job, name) => job.split(/^      - name: /mu).find((block) => block.startsWith(`${name}\n`)) ?? "";
const applyPatchMarker = "The iOS simulator log stream did not start";

test("iOS job applies the pinned Flutter tool fix before anything runs flutter, and the fix is tied to the pinned version", () => {
  const steps = stepNames(iosJob);
  const applyStep = stepBlock(iosJob, "Apply Flutter iOS simulator log stream fix");
  assert.match(applyStep, /^        run: bash "\$\{GITHUB_WORKSPACE\}\/tools\/ci\/apply-flutter-patch\.sh" "\$\{GITHUB_WORKSPACE\}\/tools\/ci\/flutter-patches\/3\.44\.0-ios-simulator-log-stream-ready\.patch" "The iOS simulator log stream did not start"$/mu);
  for (const later of ["Resolve Xcode build cache key", "Restore Xcode build cache", "Install Flutter dependencies", "Run iOS simulator native smoke"]) {
    assert.ok(steps.indexOf("Apply Flutter iOS simulator log stream fix") < steps.indexOf(later), later);
  }
  assert.ok(steps.indexOf("Set up Flutter") < steps.indexOf("Apply Flutter iOS simulator log stream fix"));
  assert.doesNotMatch(androidSteps, /apply-flutter-patch/u);
  // 패치 대상은 iOS 시뮬레이터 어댑터 한 파일이고, 패치가 더하는 문자열이 본문에 있다.
  assert.deepEqual([...flutterPatch.matchAll(/^diff --git a\/(\S+) /gmu)].map((match) => match[1]), ["packages/flutter_tools/lib/src/ios/simulators.dart"]);
  assert.ok(flutterPatch.split("\n").some((line) => line.startsWith("+") && line.includes(applyPatchMarker)));
  assert.match(flutterPatch, /flutter\/flutter\/pull\/193142/u);
  // 드라이버가 앱 시작 뒤에 붙이는 두 번째 log stream도 테스트가 시작되기 전에 준비되도록 기다린다.
  assert.ok(flutterPatch.includes("+  Future<void> provideVmService(FlutterVmService connectedVmService) => waitUntilReady();"));
  assert.ok(flutterPatch.includes("-  Future<void> provideVmService(FlutterVmService connectedVmService) async {}"));
  assert.ok(flutterPatch.includes("+      await logReader.waitUntilReady();"));
  for (const trigger of ["tools/ci/apply-flutter-patch.sh", `tools/ci/flutter-patches/${flutterPatchFile}`]) {
    assert.equal(workflow.split("\n").filter((line) => line === `      - "${trigger}"`).length, 2, trigger);
  }
});

test("iOS job restores the Xcode build cache keyed by toolchain, lockfile, and iOS sources; Android keeps none", () => {
  const steps = stepNames(iosJob);
  const keyStep = stepBlock(iosJob, "Resolve Xcode build cache key");
  const cacheStep = stepBlock(iosJob, "Restore Xcode build cache");
  assert.match(keyStep, /^        id: toolchain$/mu);
  assert.match(keyStep, /xcodebuild -version/u);
  assert.match(keyStep, /flutter --version --machine/u);
  assert.match(cacheStep, /^        id: xcode-cache$/mu);
  assert.match(cacheStep, /uses: actions\/cache@55cc8345863c7cc4c66a329aec7e433d2d1c52a9/u);
  assert.match(cacheStep, /^            ~\/Library\/Developer\/Xcode\/DerivedData$/mu);
  assert.match(cacheStep, /^            apps\/mobile\/build\/ios\/SourcePackages$/mu);
  const toolchainPrefix = "xcode-build-${{ runner.os }}-${{ runner.arch }}-${{ steps.toolchain.outputs.id }}-";
  assert.ok(cacheStep.includes(`key: ${toolchainPrefix}\${{ hashFiles('apps/mobile/pubspec.lock', 'apps/mobile/ios/**') }}`));
  // 부분 복원은 같은 Xcode·Flutter 안에서만 허용한다. 다른 toolchain의 DerivedData는 복원하지 않는다.
  assert.ok(cacheStep.includes(`restore-keys: ${toolchainPrefix}\n`));
  assert.equal((cacheStep.match(/restore-keys:/gu) ?? []).length, 1);
  assert.ok(steps.indexOf("Resolve Xcode build cache key") < steps.indexOf("Restore Xcode build cache"));
  assert.ok(steps.indexOf("Restore Xcode build cache") < steps.indexOf("Install Flutter dependencies"));
  assert.doesNotMatch(androidSteps, /actions\/cache|DerivedData/u);
});

test("iOS job records whether the Xcode build cache was used and how large it is, even when the smoke fails", () => {
  const reportStep = stepBlock(iosJob, "Report Xcode build cache");
  assert.match(reportStep, /^        if: \$\{\{ !cancelled\(\) \}\}$/mu);
  assert.match(reportStep, /CACHE_HIT: \$\{\{ steps\.xcode-cache\.outputs\.cache-hit \}\}/u);
  assert.match(reportStep, /MATCHED_KEY: \$\{\{ steps\.xcode-cache\.outputs\.cache-matched-key \}\}/u);
  assert.match(reportStep, /GITHUB_STEP_SUMMARY/u);
  assert.ok(stepNames(iosJob).indexOf("Run iOS simulator native smoke") < stepNames(iosJob).indexOf("Report Xcode build cache"));
});

// 가짜 Flutter SDK(git 저장소)에 패치를 적용하는 스크립트를 실제로 실행한다.
// flutter 스텁은 stamp가 없으면 tool을 다시 빌드한 것으로 치고, 소스에 패치 줄이 있을 때만 스냅샷에 표지를 쓴다.
const patchedLine = "wait for the log stream";
const sdkSource = (patched) => `class Simulator {\n  launch() {}\n${patched ? `  ${patchedLine}();\n` : ""}}\n`;
function runApplyPatch({ sdk = "unpatched", snapshot = "none", compileIgnoresSource = false } = {}) {
  const root = mkdtempSync(path.join(tmpdir(), "apply-flutter-patch-"));
  const flutterRoot = path.join(root, "sdk");
  const git = (...args) => spawnSync("git", ["-C", flutterRoot, ...args], { encoding: "utf8" });
  const source = path.join(flutterRoot, "lib.dart");
  mkdirSync(path.join(flutterRoot, "bin", "cache"), { recursive: true });
  writeFileSync(source, sdkSource(false));
  git("init", "-q");
  git("-c", "user.name=t", "-c", "user.email=t@example.com", "add", "lib.dart");
  git("-c", "user.name=t", "-c", "user.email=t@example.com", "commit", "-q", "-m", "sdk");
  writeFileSync(source, sdkSource(true));
  const patchFile = path.join(root, "fix.patch");
  writeFileSync(patchFile, `Flutter 수정 설명\n\n${git("diff").stdout}`);
  writeFileSync(source, sdkSource(sdk === "patched"));
  if (sdk === "different") writeFileSync(source, "class Other {}\n");
  const calls = path.join(root, "calls");
  const stub = path.join(flutterRoot, "bin", "flutter");
  writeFileSync(
    stub,
    [
      "#!/usr/bin/env bash",
      `cache="${flutterRoot}/bin/cache"`,
      `if [ ! -s "$cache/flutter_tools.stamp" ]; then echo rebuild >> "${calls}"; : > "$cache/flutter_tools.snapshot"; ${compileIgnoresSource ? ":" : `grep -q '${patchedLine}' "${source}" && echo '${applyPatchMarker.replace(/'/gu, "")}' > "$cache/flutter_tools.snapshot"`}; echo key > "$cache/flutter_tools.stamp"; fi`,
    ].join("\n"),
  );
  chmodSync(stub, 0o755);
  if (snapshot === "current") {
    writeFileSync(path.join(flutterRoot, "bin/cache/flutter_tools.snapshot"), `${applyPatchMarker}\n`);
    writeFileSync(path.join(flutterRoot, "bin/cache/flutter_tools.stamp"), "key\n");
  } else if (snapshot === "stale") {
    writeFileSync(path.join(flutterRoot, "bin/cache/flutter_tools.snapshot"), "old\n");
    writeFileSync(path.join(flutterRoot, "bin/cache/flutter_tools.stamp"), "key\n");
  }
  const result = spawnSync("bash", [fileURLToPath(new URL("./apply-flutter-patch.sh", import.meta.url)), patchFile, applyPatchMarker], {
    env: { PATH: process.env.PATH, FLUTTER_ROOT: flutterRoot },
    encoding: "utf8",
  });
  return {
    status: result.status,
    output: `${result.stdout}${result.stderr}`,
    source: readFileSync(source, "utf8"),
    rebuilds: existsSync(calls) ? readFileSync(calls, "utf8").split("\n").filter((line) => line === "rebuild").length : 0,
  };
}

test("apply-flutter-patch patches an unpatched SDK once and rebuilds the tool so the fix is in the snapshot", () => {
  const run = runApplyPatch();
  assert.equal(run.status, 0, run.output);
  assert.equal(run.source, sdkSource(true));
  assert.equal(run.rebuilds, 1);
});

test("apply-flutter-patch leaves an already patched SDK with a current snapshot alone (cache-restored SDK)", () => {
  const run = runApplyPatch({ sdk: "patched", snapshot: "current" });
  assert.equal(run.status, 0, run.output);
  assert.equal(run.source, sdkSource(true));
  assert.equal(run.rebuilds, 0);
});

test("apply-flutter-patch rebuilds when the SDK is patched but the snapshot predates the patch", () => {
  const run = runApplyPatch({ sdk: "patched", snapshot: "stale" });
  assert.equal(run.status, 0, run.output);
  assert.equal(run.rebuilds, 1);
});

test("apply-flutter-patch fails closed when the SDK is not the version the patch targets", () => {
  const run = runApplyPatch({ sdk: "different" });
  assert.notEqual(run.status, 0);
  assert.equal(run.source, "class Other {}\n");
  assert.equal(run.rebuilds, 0);
});

test("apply-flutter-patch fails closed when the rebuilt snapshot does not carry the fix", () => {
  const run = runApplyPatch({ compileIgnoresSource: true });
  assert.notEqual(run.status, 0);
  assert.match(run.output, /스냅샷/u);
});

test("apply-flutter-patch cannot be told to ignore a failure", () => {
  assert.match(applyPatchScript, /^set -euo pipefail$/mu);
  assert.doesNotMatch(applyPatchScript, /\|\| true|continue-on-error|2>\s*\/dev\/null \|\|/u);
});
