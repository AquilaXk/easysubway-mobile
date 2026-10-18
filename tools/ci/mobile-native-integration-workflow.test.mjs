import assert from "node:assert/strict";
import { existsSync, readFileSync } from "node:fs";
import test from "node:test";

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

test("Android drive script fails the job on any failed step and never lets PASS overwrite FAIL", () => {
  const targets = workflow.match(/^      NATIVE_TARGETS: (.+)$/mu)?.[1].split(" ") ?? [];
  assert.deepEqual(targets, ["native_test", "core_screen_a11y_smoke_test"]);
  for (const target of targets) {
    assert.ok(existsSync(new URL(`../../apps/mobile/integration_test/${target}.dart`, import.meta.url)));
  }
  assert.doesNotMatch(driveScript, /native_test|core_screen_a11y_smoke_test/u);
  assert.match(workflow, /^          script: bash \.\.\/\.\.\/tools\/ci\/android-native-drive\.sh$/m);

  // 실패 분기: 크래시 로그와 FAIL 영수증(대상·단계 포함)을 남긴 뒤 반드시 종료한다.
  assert.match(
    driveScript,
    /^fail\(\) \{\n  adb logcat -d -b crash > "\$\{evidence\}\/adb-crash\.log" 2>&1 \|\| true\n  write_receipt FAIL ",\\"target\\":\\"\$1\\",\\"step\\":\\"\$2\\""\n  exit 1\n\}$/mu,
  );
  assert.match(driveScript, /"\$\{evidence\}\/flutter-drive-\$\{target\}\.log" 2>&1 \|\| fail "\$\{target\}" drive$/mu);
  assert.match(driveScript, /^dart format --output=none --set-exit-if-changed "\$\{sources\[@\]\}" \|\| fail "\$\{NATIVE_TARGETS\}" format$/mu);
  assert.match(driveScript, /^flutter analyze "\$\{sources\[@\]\}" \|\| fail "\$\{NATIVE_TARGETS\}" analyze$/mu);
  assert.match(driveScript, /timeout 12m flutter drive --driver=test_driver\/integration_test\.dart "--target=integration_test\/\$\{target\}\.dart" -d emulator-5554 --no-dds/u);

  // PASS 영수증은 모든 대상이 끝난 뒤 마지막 줄에서 한 번만 쓰고, 실패를 삼키는 구문은 없다.
  const lines = driveScript.trimEnd().split("\n");
  assert.equal(lines.at(-1), "write_receipt PASS");
  assert.equal(lines.at(-2), "");
  assert.equal(lines.at(-3), "done");
  assert.equal((driveScript.match(/write_receipt PASS/gu) ?? []).length, 1);
  assert.equal((driveScript.match(/\|\| true/gu) ?? []).length, 1);
  assert.doesNotMatch(driveScript, /set -e|continue-on-error|\bbreak\b|\bcontinue\b/u);
  assert.doesNotMatch(workflow, /continue-on-error/u);
  assert.doesNotMatch(workflow.slice(0, workflow.indexOf("  ios-native:")), /\|\| true/u);
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
