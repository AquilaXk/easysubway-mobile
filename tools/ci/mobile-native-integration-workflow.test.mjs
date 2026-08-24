import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const workflow = readFileSync(
  new URL("../../.github/workflows/mobile-native-integration.yml", import.meta.url),
  "utf8",
);
const nativeTest = readFileSync(
  new URL("../../apps/mobile/integration_test/native_test.dart", import.meta.url),
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
  assert.match(
    workflow,
    /timeout 12m flutter drive --driver=test_driver\/integration_test\.dart --target=integration_test\/native_test\.dart -d emulator-5554 --no-dds > "\$\{RUNNER_TEMP\}\/mobile-native-android\/flutter-drive\.log" 2>&1/u,
  );
  assert.doesNotMatch(
    workflow,
    /\bflutter test\b/u,
  );
  assert.match(workflow, /adb logcat -d -b crash > "\$\{RUNNER_TEMP\}\/mobile-native-android\/adb-crash\.log" 2>&1/u);
  assert.match(workflow, /\{"schemaVersion":1,"lane":"android-native","status":"PENDING"\}/u);
  assert.match(workflow, /\{"schemaVersion":1,"lane":"android-native","status":"PASS"\}/u);
  assert.match(workflow, /\{"schemaVersion":1,"lane":"android-native","status":"FAIL"\}/u);
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

test("native Journey smoke stays server-only and bounded to success, failure, and restart", () => {
  assert.match(nativeTest, /IntegrationTestWidgetsFlutterBinding\.ensureInitialized\(\)/u);
  assert.match(nativeTest, /JourneyPlanSource\.serverTimetableRaptor/u);
  assert.match(nativeTest, /JourneyTransportFailure/u);
  assert.match(nativeTest, /restartAndRestore\(\)/u);
  assert.match(nativeTest, /expect\(repository\.searchRequests, 1\)/u);
  assert.doesNotMatch(nativeTest, /route[_ -]?v[12]|local route|previous result|provider refresh/iu);
});
