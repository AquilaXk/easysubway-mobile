import assert from "node:assert/strict";
import { generateKeyPairSync } from "node:crypto";
import { mkdtemp, readFile, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import test from "node:test";

import { runGooglePlayApiAccess } from "./check-google-play-api-access.mjs";

const baseUrl = "https://androidpublisher.example.invalid";
const { privateKey } = generateKeyPairSync("rsa", { modulusLength: 2048 });
const serviceAccount = {
  client_email: "play-service@example.invalid",
  project_id: "secret-project-id",
  private_key: privateKey.export({ type: "pkcs8", format: "pem" }),
  token_uri: `${baseUrl}/token`,
};

test("Google Play API access checker는 read-only reviews probe만 실행한다", async () => {
  const fixture = await createFixture(
    `EASYSUBWAY_GOOGLE_PLAY_SERVICE_ACCOUNT_BASE64=${Buffer.from(JSON.stringify(serviceAccount)).toString("base64")}`,
  );
  const requests = [];

  await runGooglePlayApiAccess({
    ...fixture,
    apiBaseUrl: `${baseUrl}/androidpublisher/v3`,
    fetchImpl: mockGooglePlayFetch(requests),
  });

  const output = await readFile(fixture.githubOutput, "utf8");
  const report = await readFile(fixture.reportPath, "utf8");
  assert.match(output, /^google_play_api_access_ready=true$/m);
  assert.match(report, /^reviews_list\.ready=true$/m);
  assert.match(report, /^reviews\.count=1$/m);
  assert.doesNotMatch(report, /play-service@example\.invalid/);
  assert.deepEqual(requests, [
    `POST ${baseUrl}/token`,
    `GET ${baseUrl}/androidpublisher/v3/applications/com.easysubway.app/reviews?maxResults=1`,
  ]);
});

test("Google Play API 실패는 secret을 제외한 report로 남긴다", async () => {
  const fixture = await createFixture(
    `EASYSUBWAY_GOOGLE_PLAY_SERVICE_ACCOUNT_BASE64=${Buffer.from(JSON.stringify(serviceAccount)).toString("base64")}`,
  );

  await assert.rejects(
    runGooglePlayApiAccess({
      ...fixture,
      apiBaseUrl: `${baseUrl}/androidpublisher/v3`,
      fetchImpl: mockGooglePlayFetch([], {
        status: 403,
        body: {
          error: {
            status: "PERMISSION_DENIED",
            message: "Android Publisher API is disabled for project secret-project-id",
          },
        },
      }),
    }),
    (error) => {
      assert.match(error.message, /google play api GET failed: 403/);
      assert.doesNotMatch(error.message, /secret-project-id|play-service@example\.invalid/);
      return true;
    },
  );

  const output = await readFile(fixture.githubOutput, "utf8");
  const report = await readFile(fixture.reportPath, "utf8");
  assert.match(output, /^google_play_api_access_ready=false$/m);
  assert.match(report, /^failure=google play api GET failed: 403 status=PERMISSION_DENIED/m);
  assert.doesNotMatch(report, /secret-project-id|play-service@example\.invalid/);
});

for (const [name, credential] of [
  ["base64", "EASYSUBWAY_GOOGLE_PLAY_SERVICE_ACCOUNT_BASE64=not-json"],
  ["json", "EASYSUBWAY_GOOGLE_PLAY_SERVICE_ACCOUNT_JSON=abc123secret"],
]) {
  test(`Google Play API access checker는 malformed ${name} credential을 redaction한다`, async () => {
    const fixture = await createFixture(credential);
    await assert.rejects(
      runGooglePlayApiAccess({
        ...fixture,
        apiBaseUrl: `${baseUrl}/androidpublisher/v3`,
        fetchImpl: async () => {
          throw new Error("fetch must not be called");
        },
      }),
      /invalid google play service account json/,
    );

    const report = await readFile(fixture.reportPath, "utf8");
    assert.match(report, new RegExp(`^service_account_json_source=${name}$`, "m"));
    assert.match(report, /^failure=invalid google play service account json$/m);
    assert.doesNotMatch(report, /not-json|abc123secret/);
  });
}

async function createFixture(credential) {
  const dir = await mkdtemp(path.join(tmpdir(), "easysubway-google-play-api-"));
  const envFile = path.join(dir, "store.env");
  const githubOutput = path.join(dir, "github-output.txt");
  const reportPath = path.join(dir, "report.txt");
  await writeFile(
    envFile,
    [
      credential,
      "EASYSUBWAY_GOOGLE_PLAY_PACKAGE_NAME=com.easysubway.app",
      "EASYSUBWAY_GOOGLE_PLAY_LATEST_VERSION_CODE=7",
      "",
    ].join("\n"),
  );
  return { envFile, githubOutput, reportPath };
}

function mockGooglePlayFetch(requests, config = {}) {
  return async (url, options = {}) => {
    requests.push(`${options.method ?? "GET"} ${url}`);
    if (url === `${baseUrl}/token`) {
      return jsonResponse({ access_token: "access-token", token_type: "Bearer", expires_in: 3600 });
    }
    return jsonResponse(config.body ?? { reviews: [{ reviewId: "review-1" }] }, config.status ?? 200);
  };
}

function jsonResponse(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
}
