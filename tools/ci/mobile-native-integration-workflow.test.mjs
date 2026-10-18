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
const driveScript = readFileSync(
  new URL("./android-native-drive.sh", import.meta.url),
  "utf8",
);
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

  assert.match(workflow, /^  ios-native:\n    name: iOS Journey native smoke\n    runs-on: macos-15\n    timeout-minutes: 35$/m);
  assert.equal((workflow.match(/flutter-version: "3\.44\.0"/gu) ?? []).length, 2);
  assert.match(
    workflow,
    /^        env:\n          DEVELOPER_DIR: \/Applications\/Xcode_26\.3\.app\/Contents\/Developer\n        run: \|$/m,
  );
  assert.match(workflow, /flutter build ios --simulator --debug 2>&1 \| tee "\$\{RUNNER_TEMP\}\/mobile-native-ios\/flutter-build-ios\.log"/u);
  assert.match(workflow, /xcrun simctl boot "\$simulator" \|\| xcrun simctl bootstatus "\$simulator" -b/u);
  assert.match(workflow, /xcrun simctl bootstatus "\$simulator" -b/u);
  assert.match(workflow, /perl -e 'alarm shift; exec @ARGV' 720 flutter drive --driver=test_driver\/integration_test\.dart --target=integration_test\/native_test\.dart -d "\$simulator" --no-dds > "\$\{RUNNER_TEMP\}\/mobile-native-ios\/flutter-drive\.log" 2>&1/u);
  assert.match(workflow, /xcrun simctl spawn "\$simulator" log show --last 5m --style compact > "\$\{RUNNER_TEMP\}\/mobile-native-ios\/simulator\.log" 2>&1 \|\| true/u);
  assert.match(workflow, /\{"schemaVersion":1,"lane":"ios-native","status":"PENDING"\}/u);
  assert.match(workflow, /\{"schemaVersion":1,"lane":"ios-native","status":"PASS"\}/u);
  assert.match(workflow, /\{"schemaVersion":1,"lane":"ios-native","status":"FAIL"\}/u);
  assert.match(workflow, /^          name: mobile-native-ios-\$\{\{ github\.run_id \}\}-\$\{\{ github\.run_attempt \}\}$/m);
  assert.equal(
    (workflow.match(/uses: actions\/upload-artifact@65462800fd760344b1a7b4382951275a0abb4808/gu) ?? []).length,
    2,
  );
  assert.equal((workflow.match(/^        if: always\(\)$/gmu) ?? []).length, 2);
  assert.equal((workflow.match(/^          if-no-files-found: error$/gmu) ?? []).length, 2);
  assert.equal((workflow.match(/^          retention-days: 5$/gmu) ?? []).length, 2);
  assert.doesNotMatch(workflow, /secrets\.|EASYSUBWAY_API_BASE_URL|release|store/iu);
});

test("Android drive script wiring: targets exist, PASS is written once at the end, nothing swallows failures", () => {
  const targets = workflow.match(/^      NATIVE_TARGETS: (.+)$/mu)?.[1].split(" ") ?? [];
  assert.deepEqual(targets, ["native_test", "core_screen_a11y_smoke_test"]);
  for (const target of targets) {
    assert.ok(existsSync(new URL(`../../apps/mobile/integration_test/${target}.dart`, import.meta.url)));
  }
  assert.doesNotMatch(driveScript, /native_test|core_screen_a11y_smoke_test/u);
  assert.match(workflow, /^          script: bash \.\.\/\.\.\/tools\/ci\/android-native-drive\.sh$/m);

  const lines = driveScript.trimEnd().split("\n");
  assert.equal(lines.at(-1), "write_receipt PASS");
  assert.equal((driveScript.match(/write_receipt PASS/gu) ?? []).length, 1);
  assert.doesNotMatch(driveScript, /set -e|continue-on-error/u);
  assert.doesNotMatch(workflow, /continue-on-error/u);
  assert.doesNotMatch(workflow.slice(0, workflow.indexOf("  ios-native:")), /\|\| true/u);
});

test("emulator boot failure that never reaches the drive script is recorded in the receipt", () => {
  const androidJob = workflow.slice(0, workflow.indexOf("  ios-native:"));
  assert.match(androidJob, /^        id: smoke$/m);
  assert.match(androidJob, /^        if: failure\(\) && steps\.smoke\.conclusion == 'failure'$/m);
  assert.match(androidJob, /"status":"FAIL","target":"emulator","step":"boot"/u);
  assert.ok(
    androidJob.indexOf("Record Android boot failure") < androidJob.indexOf("Upload Android native evidence"),
  );
});

const fixtureDir = fileURLToPath(new URL("./fixtures/android-drive/", import.meta.url));
const fixture = (name) => readFileSync(path.join(fixtureDir, name), "utf8");

// 스텁 adb/flutter/dart로 실제 스크립트를 실행한다.
// drives: drive 호출 순서별 { log, exit } (log는 재생할 로그 본문, exit 기본 1).
// boot: adb getprop sys.boot_completed 호출 순서별 "1"/"0" (마지막 값을 반복). 호출은 await_device 한 번에 1회(BOOT_POLL_LIMIT=1).
function runDriveScript({ drives = [], boot = ["1"], waitFails = false, targets = "native_test", env = {} }) {
  const root = mkdtempSync(path.join(tmpdir(), "android-drive-"));
  const bin = path.join(root, "bin");
  const evidence = path.join(root, "mobile-native-android");
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
  stub(
    "adb",
    [
      `echo "adb $*" >> "${root}/calls"`,
      `[ "$3" = wait-for-device ] && ${waitFails ? "exit 1" : "exit 0"}`,
      '[ "$3" = shell ] || exit 0',
      `n=$(grep -c '^getprop$' "${root}/calls" 2>/dev/null)`,
      `echo getprop >> "${root}/calls"`,
      `n=$((n + 1)); line=$(sed -n "\${n}p" "${root}/boot"); [ -n "$line" ] || line=$(tail -n 1 "${root}/boot")`,
      'echo "$line"',
    ].join("\n"),
  );
  stub("dart", "exit 0");
  stub("sleep", "exit 0");
  stub("timeout", 'shift\nexec "$@"');
  stub(
    "flutter",
    [
      '[ "$1" = drive ] || exit 0',
      `echo drive >> "${root}/calls"`,
      `n=$(grep -c '^drive$' "${root}/calls")`,
      `cat "${root}/drive-$n.log"`,
      `exit "$(cat "${root}/drive-$n.exit")"`,
    ].join("\n"),
  );
  const result = spawnSync("bash", [fileURLToPath(new URL("./android-native-drive.sh", import.meta.url))], {
    env: {
      PATH: `${bin}:${process.env.PATH}`,
      RUNNER_TEMP: root,
      NATIVE_TARGETS: targets,
      BOOT_POLL_LIMIT: "1",
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
    driveCalls: calls.filter((line) => line === "drive").length,
    reconnects: calls.filter((line) => line === "adb reconnect offline").length,
    read,
    exists: (name) => existsSync(path.join(evidence, name)),
  };
}

const passLog = { log: fixture("pass-with-uninstall-noise.log"), exit: 0 };
const failedReceipt = (extra) => ({ schemaVersion: 1, lane: "android-native", status: "FAIL", ...extra });

test("real offline-before-tests log retries once, keeps the first log, and reports the retry", () => {
  const offline = fixture("offline-before-tests.log");
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
    drives: [passLog, { log: fixture("offline-before-tests-second-target.log") }, passLog],
  });
  assert.equal(run.status, 0);
  assert.deepEqual(run.receipt.retried, ["drive:adb_offline"]);
  assert.equal(run.driveCalls, 3);
  assert.ok(run.exists("flutter-drive-core_screen_a11y_smoke_test.attempt1.log"));
  assert.equal(run.exists("flutter-drive-native_test.attempt1.log"), false);
});

for (const [name, reason] of [
  ["synthetic-device-not-found.log", "device_not_found"],
  ["synthetic-install-failed.log", "install_failed"],
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
  const mixed = `${fixture("assertion-failure.log")}\nadb: device offline\nadb uninstall failed: ProcessException\n`;
  for (const log of [fixture("assertion-failure.log"), mixed]) {
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
    const log = `${fixture("offline-before-tests.log")}\n${signal}\n`;
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
  const run = runDriveScript({ drives: [{ log: fixture("offline-before-tests.log"), exit: 124 }, passLog] });
  assert.equal(run.status, 1);
  assert.deepEqual(run.receipt, failedReceipt({ target: "native_test", step: "drive", reason: "timeout" }));
  assert.equal(run.driveCalls, 1);
  assert.equal(run.reconnects, 0);
});

test("each target is retried at most once and a failed retry stays FAIL with retried recorded", () => {
  const offline = { log: fixture("offline-before-tests.log") };
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
  const run = runDriveScript({ boot: ["1", "1", "0"], drives: [{ log: fixture("offline-before-tests.log") }, passLog] });
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

test("core screen accessibility smoke reuses the sweep screen table and checks only tap targets", () => {
  assert.equal(
    (workflow.match(/"apps\/mobile\/integration_test\/core_screen_a11y_smoke_test\.dart"/gu) ?? []).length,
    2,
  );
  assert.equal(
    (workflow.match(/"apps\/mobile\/test\/support\/core_screen_sweep_\*\.dart"/gu) ?? []).length,
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
  ]) {
    assert.equal(workflow.split("\n").filter((line) => line === `      - "${glob}"`).length, 2, glob);
  }
  assert.match(a11ySmokeTest, /IntegrationTestWidgetsFlutterBinding\.ensureInitialized\(\)/u);
  assert.match(a11ySmokeTest, /import '\.\.\/test\/support\/core_screen_sweep_screens\.dart'/u);
  assert.match(a11ySmokeTest, /meetsGuideline\(androidTapTargetGuideline\)/u);
  assert.match(a11ySmokeTest, /meetsGuideline\(labeledTapTargetGuideline\)/u);
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
