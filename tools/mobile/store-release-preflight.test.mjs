import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

test("store preflight validates signing and no-upload Play edit lifecycle from trusted main", async () => {
  const workflow = await readFile(".github/workflows/store-distribution-evidence.yml", "utf8");
  const access = await readFile("tools/ci/check-google-play-api-access.mjs", "utf8");
  const auth = await readFile("tools/ci/lib/google-play-auth.mjs", "utf8");

  assert.match(workflow, /environment:\s+name: store-release/);
  assert.match(workflow, /if: github\.ref == 'refs\/heads\/main'/);
  assert.match(workflow, /ref: main/);
  assert.match(workflow, /permissions:\s+contents: read/);
  for (const name of [
    "EASYSUBWAY_GOOGLE_PLAY_SERVICE_ACCOUNT_BASE64",
    "EASYSUBWAY_ANDROID_UPLOAD_KEYSTORE_BASE64",
    "EASYSUBWAY_ANDROID_STORE_PASSWORD",
    "EASYSUBWAY_ANDROID_KEY_ALIAS",
    "EASYSUBWAY_ANDROID_KEY_PASSWORD",
  ]) {
    assert.match(workflow, new RegExp(`${name}: \\$\\{\\{ secrets\\.${name} \\}\\}`));
  }
  assert.match(
    workflow,
    /EASYSUBWAY_ANDROID_UPLOAD_CERT_SHA256: \$\{\{ vars\.EASYSUBWAY_ANDROID_UPLOAD_CERT_SHA256 \}\}/,
  );
  assert.match(workflow, /trim_signing_value/);
  assert.match(workflow, /keytool .* -list/);
  assert.match(workflow, /-J-Duser\.language=en -J-Duser\.country=US/);
  assert.match(workflow, /Entry type: PrivateKeyEntry/);
  assert.match(workflow, /fingerprint256/);
  assert.match(workflow, /"\$\{fingerprint\}" != "\$\{expected_fingerprint\}"/);
  assert.match(workflow, /trap .* EXIT/);
  assert.match(workflow, /-storepass:env EASYSUBWAY_ANDROID_STORE_PASSWORD/);
  assert.match(workflow, /-srcstorepass:env EASYSUBWAY_ANDROID_STORE_PASSWORD/);
  assert.match(workflow, /-srckeypass:env EASYSUBWAY_ANDROID_KEY_PASSWORD/);
  assert.match(workflow, /randomBytes/);
  assert.match(workflow, /-deststorepass:env EASYSUBWAY_EPHEMERAL_KEYSTORE_PASSWORD/);
  assert.match(workflow, /rm -f .*signing_check/);
  assert.doesNotMatch(workflow, /changeit-for-ephemeral-check/);
  assert.match(workflow, /version_code.*=~.*\[1-9\]/);
  assert.match(workflow, /2100000000/);
  assert.match(workflow, /service_account_base64=.*\[\[:space:\]\]/);
  assert.match(workflow, /node tools\/ci\/check-google-play-api-access\.mjs/);
  assert.match(
    workflow,
    /play_status=0[\s\S]*\|\| play_status=\$\?[\s\S]*cat .*google-play-api-access\.txt[\s\S]*exit "\$\{play_status\}"/,
  );
  assert.doesNotMatch(workflow, /upload-play|edits\/.*:commit|bundle upload|play publish/i);
  assert.match(workflow, /name: Validate no-upload Google Play edit lifecycle/);
  // 같은 service account의 열린 edit은 `edits.insert`가 무효화하므로(Android Publisher
  // 공식 문서) Play 자격증명을 쓰는 실행은 직렬화하고, 진행 중 실행은 취소하지 않는다.
  // 취소하면 `finally` delete가 건너뛰어져 열린 edit이 남는다.
  assert.match(workflow, /^concurrency:\n  group: store-release-google-play-edit\n  cancel-in-progress: false$/m);

  // no-upload edit 라이프사이클: 임시 edit 1개 생성 → track 조회 → validate → finally delete.
  assert.match(access, /\/edits`,\s*\{\s*\n\s*method: "POST",\s*\n\s*token,\s*\n\s*body: \{\},/);
  assert.match(access, /\/edits\/\$\{encodePath\(editId\)\}\/tracks`,\s*\n\s*\{ method: "GET", token \}/);
  assert.match(access, /\/edits\/\$\{encodePath\(editId\)\}:validate`,\s*\n\s*\{ method: "POST", token \}/);
  assert.match(access, /\} finally \{[\s\S]*method: "DELETE"/);
  // mutation·upload·publish 경로는 없어야 한다.
  assert.doesNotMatch(access, /:commit|method: "PATCH"|method: "PUT"|uploadMedia|\/bundles|\/apks|\/deobfuscationfiles/);
  assert.doesNotMatch(access, /\/reviews/);
  assert.match(access, /maskSecrets\(value\)/);
  assert.match(access, /console\.error\("google play api access check failed; see sanitized report"\)/);
  assert.doesNotMatch(access, /console\.error\(error\.message\)/);
  assert.match(auth, /google play request url must be https/);
  assert.match(auth, /maskSecrets/);
  assert.doesNotMatch(auth, /uploadMedia|google play upload/);
  assert.doesNotMatch(auth, /replaceAll\("%2E"/);
});
