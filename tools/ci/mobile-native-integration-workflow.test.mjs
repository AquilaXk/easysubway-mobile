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
  assert.doesNotMatch(workflow, /secrets\.|EASYSUBWAY_API_BASE_URL|release|store/iu);
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
function runDriveScript({ platform = "android", drives = [], boot = ["1"], waitFails = false, targets = "native_test", env = {} }) {
  const root = mkdtempSync(path.join(tmpdir(), `${platform}-drive-`));
  const bin = path.join(root, "bin");
  const evidence = path.join(root, `mobile-native-${platform}`);
  mkdirSync(bin);
  mkdirSync(evidence);
  const stub = (name, body) => {
    writeFileSync(path.join(bin, name), `#!/usr/bin/env bash\n${body}\n`);
    chmodSync(path.join(bin, name), 0o755);
  };
  writeFileSync(path.join(root, "boot"), `${boot.join("\n")}\n`);
  drives.forEach((drive, index) => {
    writeFileSync(path.join(root, `drive-${index + 1}.log`), drive.log);
    writeFileSync(path.join(root, `drive-${index + 1}.exit`), String(drive.exit ?? 1));
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
  stub("timeout", 'shift\nexec "$@"');
  stub(
    "flutter",
    [
      '[ "$1" = drive ] || exit 0',
      `echo drive >> "${root}/calls"`,
      `echo "define $4" >> "${root}/calls"`,
      `n=$(grep -c '^drive$' "${root}/calls")`,
      `cat "${root}/drive-$n.log"`,
      `exit "$(cat "${root}/drive-$n.exit")"`,
    ].join("\n"),
  );
  const result = spawnSync("bash", [fileURLToPath(new URL(`./${platform}-native-drive.sh`, import.meta.url))], {
    env: {
      PATH: `${bin}:${process.env.PATH}`,
      RUNNER_TEMP: root,
      NATIVE_TARGETS: targets,
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
    fontScales: calls.filter((line) => line.startsWith("font_scale ")).map((line) => line.slice("font_scale ".length)),
    driveDefines: calls.filter((line) => line.startsWith("define --dart-define=")).map((line) => line.slice("define --dart-define=".length)),
    driveCalls: calls.filter((line) => line === "drive").length,
    reconnects: calls.filter((line) => line === "adb reconnect offline").length,
    contentSizes: calls.filter((line) => line.startsWith("content_size ")).map((line) => line.slice("content_size ".length)),
    shutdowns: calls.filter((line) => line === "shutdown").length,
    bootstatuses: calls.filter((line) => line === "bootstatus").length,
    read,
    exists: (name) => existsSync(path.join(evidence, name)),
  };
}

const passLog = { log: fixture("pass-with-uninstall-noise.txt"), exit: 0 };
const failedReceipt = (extra) => ({ schemaVersion: 1, lane: "android-native", status: "FAIL", ...extra });

test("real offline-before-tests log retries once, keeps the first log, and reports the retry", () => {
  const offline = fixture("offline-before-tests.txt");
  const summary = path.join(mkdtempSync(path.join(tmpdir(), "summary-")), "summary.md");
  const run = runDriveScript({
    drives: [{ log: offline }, passLog],
    env: { GITHUB_STEP_SUMMARY: summary },
  });
  assert.equal(run.status, 0);
  assert.deepEqual(run.receipt, {
    schemaVersion: 1,
    lane: "android-native",
    status: "PASS",
    retried: ["drive:adb_offline"],
  });
  assert.equal(run.driveCalls, 2);
  assert.equal(run.reconnects, 1);
  assert.equal(run.read("flutter-drive-native_test.attempt1.log"), offline);
  assert.match(run.stdout, /^::warning::native_test drive가 adb_offline 때문에 1회 재시도 후 통과했습니다\./mu);
  assert.match(readFileSync(summary, "utf8"), /native_test: drive 재시도 후 통과 \(adb_offline\)/u);
});

test("second target offline-before-tests log retries only that target", () => {
  const run = runDriveScript({
    targets: "native_test core_screen_a11y_smoke_test",
    drives: [passLog, { log: fixture("offline-before-tests-second-target.txt") }, passLog],
  });
  assert.equal(run.status, 0);
  assert.deepEqual(run.receipt.retried, ["drive:adb_offline"]);
  assert.equal(run.driveCalls, 3);
  assert.ok(run.exists("flutter-drive-core_screen_a11y_smoke_test.attempt1.log"));
  assert.equal(run.exists("flutter-drive-native_test.attempt1.log"), false);
});

for (const [name, reason] of [
  ["synthetic-device-not-found.txt", "device_not_found"],
  ["synthetic-install-failed.txt", "install_failed"],
]) {
  test(`${reason} infra error before tests retries once`, () => {
    const run = runDriveScript({ drives: [{ log: fixture(name) }, passLog] });
    assert.equal(run.status, 0);
    assert.deepEqual(run.receipt.retried, [`drive:${reason}`]);
    assert.equal(run.driveCalls, 2);
  });
}

for (const line of ["error: no devices/emulators found", "error: device not found"]) {
  test(`"${line}" before tests retries once`, () => {
    const run = runDriveScript({ drives: [{ log: `${line}\n` }, passLog] });
    assert.equal(run.status, 0);
    assert.deepEqual(run.receipt.retried, ["drive:device_not_found"]);
  });
}

test("real assertion failure never retries, even with offline lines mixed in", () => {
  const mixed = `${fixture("assertion-failure.txt")}\nadb: device offline\nadb uninstall failed: ProcessException\n`;
  for (const log of [fixture("assertion-failure.txt"), mixed]) {
    const run = runDriveScript({ drives: [{ log }, passLog] });
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
    const run = runDriveScript({ drives: [{ log }, passLog] });
    assert.equal(run.status, 1);
    assert.deepEqual(run.receipt, failedReceipt({ target: "native_test", step: "drive" }));
    assert.equal(run.driveCalls, 1);
  });
}

test("drive log without positive infra evidence is not retried", () => {
  const run = runDriveScript({ drives: [{ log: "Launching integration_test/native_test.dart\nsomething unknown\n" }, passLog] });
  assert.equal(run.status, 1);
  assert.deepEqual(run.receipt, failedReceipt({ target: "native_test", step: "drive" }));
  assert.equal(run.driveCalls, 1);
});

test("timeout exit 124 is a hang: no retry even with an offline line, receipt records timeout", () => {
  const run = runDriveScript({ drives: [{ log: fixture("offline-before-tests.txt"), exit: 124 }, passLog] });
  assert.equal(run.status, 1);
  assert.deepEqual(run.receipt, failedReceipt({ target: "native_test", step: "drive", reason: "timeout" }));
  assert.equal(run.driveCalls, 1);
  assert.equal(run.reconnects, 0);
});

test("each target is retried at most once and a failed retry stays FAIL with retried recorded", () => {
  const offline = { log: fixture("offline-before-tests.txt") };
  const run = runDriveScript({ drives: [offline, offline, passLog] });
  assert.equal(run.status, 1);
  assert.deepEqual(run.receipt, failedReceipt({ target: "native_test", step: "drive", retried: ["drive:adb_offline"] }));
  assert.equal(run.driveCalls, 2);
});

test("device never ready before the format step writes a boot FAIL receipt without running anything", () => {
  const run = runDriveScript({ boot: ["0"], targets: "native_test core_screen_a11y_smoke_test", drives: [passLog] });
  assert.equal(run.status, 1);
  assert.deepEqual(run.receipt, failedReceipt({ target: "native_test core_screen_a11y_smoke_test", step: "boot" }));
  assert.equal(run.driveCalls, 0);
});

test("adb wait-for-device failure is a boot FAIL even when getprop says ready", () => {
  const run = runDriveScript({ waitFails: true, drives: [passLog] });
  assert.equal(run.status, 1);
  assert.deepEqual(run.receipt, failedReceipt({ target: "native_test", step: "boot" }));
  assert.equal(run.driveCalls, 0);
});

test("device lost before a target's drive fails that target at boot, not drive", () => {
  const first = runDriveScript({ boot: ["1", "0"], drives: [passLog] });
  assert.equal(first.status, 1);
  assert.deepEqual(first.receipt, failedReceipt({ target: "native_test", step: "boot" }));
  assert.equal(first.driveCalls, 0);

  const second = runDriveScript({
    boot: ["1", "1", "0"],
    targets: "native_test core_screen_a11y_smoke_test",
    drives: [passLog, passLog],
  });
  assert.equal(second.status, 1);
  assert.deepEqual(second.receipt, failedReceipt({ target: "core_screen_a11y_smoke_test", step: "boot" }));
  assert.equal(second.driveCalls, 1);
});

test("device that does not come back after adb reconnect fails at boot and keeps the retried record", () => {
  const run = runDriveScript({ boot: ["1", "1", "0"], drives: [{ log: fixture("offline-before-tests.txt") }, passLog] });
  assert.equal(run.status, 1);
  assert.deepEqual(run.receipt, failedReceipt({ target: "native_test", step: "boot", retried: ["drive:adb_offline"] }));
  assert.equal(run.driveCalls, 1);
  assert.equal(run.reconnects, 1);
});

test("clean drive passes without a retried entry", () => {
  const run = runDriveScript({
    targets: "native_test core_screen_a11y_smoke_test",
    drives: [passLog, passLog],
  });
  assert.equal(run.status, 0);
  assert.deepEqual(run.receipt, { schemaVersion: 1, lane: "android-native", status: "PASS" });
});

test("font scale spec sets the system scale before each drive and passes it to the test", () => {
  const run = runDriveScript({
    targets: "core_screen_a11y_smoke_test core_screen_a11y_smoke_test:2.0",
    drives: [passLog, passLog],
  });
  assert.equal(run.status, 0);
  assert.deepEqual(run.receipt, { schemaVersion: 1, lane: "android-native", status: "PASS" });
  assert.deepEqual(run.fontScales, ["1.0", "2.0"]);
  assert.deepEqual(run.driveDefines, ["A11Y_FONT_SCALE=1.0", "A11Y_FONT_SCALE=2.0"]);
  assert.ok(run.exists("flutter-drive-core_screen_a11y_smoke_test.log"));
  assert.ok(run.exists("flutter-drive-core_screen_a11y_smoke_test-2.0.log"));
});

test("font scale write that fails on an offline device retries once and re-applies the scale", () => {
  const run = runDriveScript({
    targets: "core_screen_a11y_smoke_test:2.0",
    drives: [passLog],
    env: { FONT_SCALE_FAILS: "1", FONT_SCALE_FAIL_LOG: "error: device offline" },
  });
  assert.equal(run.status, 0);
  assert.deepEqual(run.receipt, { schemaVersion: 1, lane: "android-native", status: "PASS", retried: ["drive:adb_offline"] });
  assert.equal(run.read("flutter-drive-core_screen_a11y_smoke_test-2.0.attempt1.log"), "error: device offline\n");
  assert.deepEqual(run.fontScales, ["2.0", "2.0"]);
  assert.equal(run.driveCalls, 1);
});

test("a retried drive sets the font scale again before the second attempt", () => {
  const run = runDriveScript({
    targets: "core_screen_a11y_smoke_test:2.0",
    drives: [{ log: fixture("offline-before-tests.txt") }, passLog],
  });
  assert.equal(run.status, 0);
  assert.deepEqual(run.fontScales, ["2.0", "2.0"]);
  assert.deepEqual(run.driveDefines, ["A11Y_FONT_SCALE=2.0", "A11Y_FONT_SCALE=2.0"]);
});

test("failing to set the font scale fails the target at drive without running the test", () => {
  const run = runDriveScript({
    targets: "core_screen_a11y_smoke_test:2.0",
    drives: [passLog],
    env: { FONT_SCALE_FAILS: "1" },
  });
  assert.equal(run.status, 1);
  assert.deepEqual(run.receipt, failedReceipt({ target: "core_screen_a11y_smoke_test:2.0", step: "drive" }));
  assert.equal(run.driveCalls, 0);
  assert.equal(run.fontScales.length, 1);
});

const iosFailedReceipt = (extra) => ({ schemaVersion: 1, lane: "ios-native", status: "FAIL", ...extra });
const iosAx5 = "accessibility-extra-extra-extra-large";
const runIos = (options) => runDriveScript({ platform: "ios", ...options });
// 합성 로그: 실제 CoreSimulatorService 오류 로그를 채집하기 전까지의 가정이다. 패턴이 맞지 않으면 재시도 없이 FAIL이라 안전하다.
const simulatorUnavailableLog = "CoreSimulatorService connection became invalid\nSimulator services will no longer be available.\n";

test("iOS clean drive sets the content size per target and passes it to the test", () => {
  const run = runIos({
    targets: "native_test core_screen_a11y_smoke_test core_screen_a11y_smoke_test:3.12",
    drives: [passLog, passLog, passLog],
  });
  assert.equal(run.status, 0);
  assert.deepEqual(run.receipt, { schemaVersion: 1, lane: "ios-native", status: "PASS" });
  assert.deepEqual(run.contentSizes, ["large", "large", iosAx5]);
  assert.deepEqual(run.driveDefines, ["A11Y_FONT_SCALE=1.0", "A11Y_FONT_SCALE=1.0", "A11Y_FONT_SCALE=3.12"]);
  for (const log of ["native_test", "core_screen_a11y_smoke_test", "core_screen_a11y_smoke_test-3.12"]) {
    assert.ok(run.exists(`flutter-drive-${log}.log`), log);
  }
});

test("iOS font scale outside the content size table fails the target at drive without running the test", () => {
  const run = runIos({ targets: "core_screen_a11y_smoke_test:2.5", drives: [passLog] });
  assert.equal(run.status, 1);
  assert.deepEqual(run.receipt, iosFailedReceipt({ target: "core_screen_a11y_smoke_test:2.5", step: "drive" }));
  assert.equal(run.driveCalls, 0);
  assert.deepEqual(run.contentSizes, []);
  assert.match(run.read("flutter-drive-core_screen_a11y_smoke_test-2.5.log"), /지원하지 않는 iOS 글꼴 배율: 2\.5/u);
});

test("iOS content size that reads back differently fails the target at drive", () => {
  const run = runIos({ targets: "core_screen_a11y_smoke_test:3.12", drives: [passLog], env: { CONTENT_SIZE_STUCK: "1" } });
  assert.equal(run.status, 1);
  assert.deepEqual(run.receipt, iosFailedReceipt({ target: "core_screen_a11y_smoke_test:3.12", step: "drive" }));
  assert.equal(run.driveCalls, 0);
});

test("iOS simulator infra error before tests retries once after shutting the simulator down", () => {
  const run = runIos({ drives: [{ log: simulatorUnavailableLog }, passLog] });
  assert.equal(run.status, 0);
  assert.deepEqual(run.receipt, { schemaVersion: 1, lane: "ios-native", status: "PASS", retried: ["drive:simulator_unavailable"] });
  assert.equal(run.driveCalls, 2);
  assert.equal(run.shutdowns, 1);
  assert.equal(run.read("flutter-drive-native_test.attempt1.log"), simulatorUnavailableLog);
  assert.match(run.stdout, /^::warning::native_test drive가 simulator_unavailable 때문에 1회 재시도 후 통과했습니다\./mu);
});

test("iOS result signal blocks the retry, and a failed retry stays FAIL with retried recorded", () => {
  const blocked = runIos({ drives: [{ log: `${simulatorUnavailableLog}00:03 +1: 어떤 테스트\n` }, passLog] });
  assert.equal(blocked.status, 1);
  assert.deepEqual(blocked.receipt, iosFailedReceipt({ target: "native_test", step: "drive" }));
  assert.equal(blocked.driveCalls, 1);

  const twice = runIos({ drives: [{ log: simulatorUnavailableLog }, { log: simulatorUnavailableLog }, passLog] });
  assert.equal(twice.status, 1);
  assert.deepEqual(twice.receipt, iosFailedReceipt({ target: "native_test", step: "drive", retried: ["drive:simulator_unavailable"] }));
  assert.equal(twice.driveCalls, 2);
});

test("iOS drive log without positive infra evidence is not retried, and perl alarm exit 142 is a timeout", () => {
  const unknown = runIos({ drives: [{ log: "something unknown\n" }, passLog] });
  assert.equal(unknown.status, 1);
  assert.deepEqual(unknown.receipt, iosFailedReceipt({ target: "native_test", step: "drive" }));
  assert.equal(unknown.driveCalls, 1);

  const timeout = runIos({ drives: [{ log: simulatorUnavailableLog, exit: 142 }, passLog] });
  assert.equal(timeout.status, 1);
  assert.deepEqual(timeout.receipt, iosFailedReceipt({ target: "native_test", step: "drive", reason: "timeout" }));
  assert.equal(timeout.driveCalls, 1);
  assert.equal(timeout.shutdowns, 0);
});

test("iOS simulator boot failure is recorded by step and keeps the simulator log", () => {
  const boot = runIos({ boot: ["0"], drives: [passLog] });
  assert.equal(boot.status, 1);
  assert.deepEqual(boot.receipt, iosFailedReceipt({ target: "native_test", step: "boot" }));
  assert.equal(boot.driveCalls, 0);
  assert.equal(boot.read("simulator.log"), "SIMULATOR LOG\n");
});

// 실제 CI에서 native_test drive가 빌드 뒤 12분 동안 멈춰 perl alarm(142)으로 끝난 로그다(PR #490 RED 확인 run).
// 시뮬레이터 인프라 오류 문구가 전혀 없다. 실제 CoreSimulatorService 오류 로그는 아직 채집하지 못했다.
const realHangLog = readFileSync(path.join(fileURLToPath(new URL("./fixtures/ios-drive/", import.meta.url)), "real-hang-after-build-timeout.txt"), "utf8");

test("real iOS hang log is a timeout, never retried, and carries no simulator infra evidence", () => {
  const timeout = runIos({ drives: [{ log: realHangLog, exit: 142 }, passLog] });
  assert.equal(timeout.status, 1);
  assert.deepEqual(timeout.receipt, iosFailedReceipt({ target: "native_test", step: "drive", reason: "timeout" }));
  assert.equal(timeout.driveCalls, 1);
  assert.equal(timeout.shutdowns, 0);

  const unknown = runIos({ drives: [{ log: realHangLog, exit: 1 }, passLog] });
  assert.equal(unknown.status, 1);
  assert.deepEqual(unknown.receipt, iosFailedReceipt({ target: "native_test", step: "drive" }));
  assert.equal(unknown.driveCalls, 1);
});

test("iOS AX5 scale is defined once in the Dart constant and the lane values stay within the smoke test tolerance", () => {
  const constant = readFileSync(new URL("../../apps/mobile/test/support/ios_text_scale.dart", import.meta.url), "utf8");
  const [, numerator, denominator] = constant.match(/const iosAx5TextScale = (\d+) \/ (\d+);/u) ?? [];
  const ax5 = Number(numerator) / Number(denominator);
  const tolerance = Number(a11ySmokeTest.match(/closeTo\(_fontScale, ([\d.]+)\)/u)?.[1]);
  assert.ok(tolerance > 0);
  const laneScale = jobTargets(iosJob).find((target) => target.endsWith(":3.12"))?.split(":")[1];
  const tableScale = iosDriveScript.match(/^\s+([\d.]+)\) echo "accessibility-extra-extra-extra-large" ;;$/mu)?.[1];
  assert.equal(laneScale, "3.12");
  assert.equal(tableScale, laneScale);
  assert.ok(Math.abs(Number(laneScale) - ax5) <= tolerance, `${laneScale} vs ${ax5}`);
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
  assert.match(a11ySmokeTest, /fullGuideline: FullTapTargetGuideline\(Size\(48, 48\)\)/u);
  assert.match(a11ySmokeTest, /fullGuideline: FullTapTargetGuideline\(Size\(44, 44\)\)/u);
  assert.match(a11ySmokeTest, /meetsGuideline\(labeledTapTargetGuideline\)/u);
  assert.match(a11ySmokeTest, /String\.fromEnvironment\('A11Y_FONT_SCALE'/u);
  assert.match(a11ySmokeTest, /platformDispatcher\.textScaleFactor,\s*closeTo\(_fontScale/u);
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
