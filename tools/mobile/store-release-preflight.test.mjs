import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

test("store preflight validates signing and temporary Play access without publishing", async () => {
  const workflow = await readFile(".github/workflows/store-distribution-evidence.yml", "utf8");
  const access = await readFile("tools/ci/check-google-play-api-access.mjs", "utf8");
  const auth = await readFile("tools/ci/lib/google-play-auth.mjs", "utf8");

  assert.match(workflow, /environment:\s+name: store-release/);
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
  assert.match(workflow, /keytool -list/);
  assert.match(workflow, /version_code.*=~.*\[0-9\]/);
  assert.match(workflow, /service_account_base64=.*\[\[:space:\]\]/);
  assert.match(workflow, /node tools\/ci\/check-google-play-api-access\.mjs/);
  assert.match(
    workflow,
    /play_status=0[\s\S]*\|\| play_status=\$\?[\s\S]*cat .*google-play-api-access\.txt[\s\S]*exit "\$\{play_status\}"/,
  );
  assert.doesNotMatch(workflow, /upload-play|edits\/.*:commit|bundle upload|play publish/i);

  assert.match(access, /method: "POST"/);
  assert.match(access, /\/tracks`/);
  assert.match(access, /:validate`/);
  assert.match(access, /method: "DELETE"/);
  assert.match(access, /finally/);
  assert.match(auth, /google play request url must be https/);
  assert.match(auth, /maskSecrets/);
});
