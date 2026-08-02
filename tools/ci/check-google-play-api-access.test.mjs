import assert from "node:assert/strict";
import { generateKeyPairSync } from "node:crypto";
import { mkdtemp, readFile, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import test from "node:test";

import { runGooglePlayApiAccess } from "./check-google-play-api-access.mjs";

const baseUrl = "https://androidpublisher.example.invalid";
const apiBaseUrl = `${baseUrl}/androidpublisher/v3`;
const applicationUrl = `${apiBaseUrl}/applications/com.easysubway.app`;
const editUrl = `${applicationUrl}/edits/edit-1`;
const { privateKey } = generateKeyPairSync("rsa", { modulusLength: 2048 });
const serviceAccount = {
  client_email: "play-service@example.invalid",
  project_id: "secret-project-id",
  private_key: privateKey.export({ type: "pkcs8", format: "pem" }),
  token_uri: `${baseUrl}/token`,
};
const credentialLine = `EASYSUBWAY_GOOGLE_PLAY_SERVICE_ACCOUNT_BASE64=${
  Buffer.from(JSON.stringify(serviceAccount)).toString("base64")
}`;

test("Google Play API access checker는 임시 edit을 만들고 track·validate 후 삭제한다", async () => {
  const fixture = await createFixture(credentialLine);
  const requests = [];

  await runGooglePlayApiAccess({
    ...fixture,
    apiBaseUrl,
    fetchImpl: mockGooglePlayFetch(requests),
  });

  const output = await readFile(fixture.githubOutput, "utf8");
  const report = await readFile(fixture.reportPath, "utf8");
  assert.match(output, /^google_play_api_access_ready=true$/m);
  assert.match(report, /^edit_insert\.ready=true$/m);
  assert.match(report, /^tracks_list\.ready=true$/m);
  assert.match(report, /^tracks\.count=2$/m);
  assert.match(report, /^tracks\.ids=internal,production$/m);
  assert.match(report, /^tracks\.max_version_code=6$/m);
  assert.match(report, /^latest_version_code_covers_track_max=true$/m);
  assert.match(report, /^edit_validate\.ready=true$/m);
  assert.match(report, /^edit_delete\.ready=true$/m);
  assert.match(report, /^secret_values_printed=false$/m);
  assert.doesNotMatch(report, /play-service@example\.invalid|secret-project-id/);
  assert.deepEqual(requests, [
    `POST ${baseUrl}/token`,
    `POST ${applicationUrl}/edits`,
    `GET ${editUrl}/tracks`,
    `POST ${editUrl}:validate`,
    `DELETE ${editUrl}`,
  ]);
});

test("edit validate 실패에도 finally에서 edit을 삭제하고 sanitized 원인만 남긴다", async () => {
  const fixture = await createFixture(credentialLine);
  const requests = [];

  await assert.rejects(
    runGooglePlayApiAccess({
      ...fixture,
      apiBaseUrl,
      fetchImpl: mockGooglePlayFetch(requests, {
        failures: {
          [`POST ${editUrl}:validate`]: {
            status: 403,
            body: {
              error: {
                status: "PERMISSION_DENIED",
                message: "caller lacks release manager rights on secret-project-id",
              },
            },
          },
        },
      }),
    }),
    (error) => {
      assert.match(error.message, /google play api POST failed: 403/);
      assert.doesNotMatch(error.message, /secret-project-id|play-service@example\.invalid/);
      return true;
    },
  );

  const output = await readFile(fixture.githubOutput, "utf8");
  const report = await readFile(fixture.reportPath, "utf8");
  assert.match(output, /^google_play_api_access_ready=false$/m);
  assert.match(report, /^edit_insert\.ready=true$/m);
  assert.match(report, /^tracks_list\.ready=true$/m);
  assert.doesNotMatch(report, /^edit_validate\.ready=true$/m);
  assert.match(report, /^failure=google play api POST failed: 403 status=PERMISSION_DENIED/m);
  assert.doesNotMatch(report, /secret-project-id|play-service@example\.invalid/);
  assert.match(report, /^edit_delete\.ready=true$/m);
  assert.equal(requests.at(-1), `DELETE ${editUrl}`);
});

test("edit delete 실패는 readiness를 무너뜨리고 sanitized 원인을 남긴다", async () => {
  const fixture = await createFixture(credentialLine);
  const requests = [];

  await assert.rejects(
    runGooglePlayApiAccess({
      ...fixture,
      apiBaseUrl,
      fetchImpl: mockGooglePlayFetch(requests, {
        failures: {
          [`DELETE ${editUrl}`]: {
            status: 500,
            body: { error: { status: "INTERNAL", message: "edit delete failed" } },
          },
        },
      }),
    }),
    /google play api DELETE failed: 500/,
  );

  const output = await readFile(fixture.githubOutput, "utf8");
  const report = await readFile(fixture.reportPath, "utf8");
  assert.match(output, /^google_play_api_access_ready=false$/m);
  assert.match(report, /^edit_validate\.ready=true$/m);
  assert.match(report, /^edit_delete\.failure=google play api DELETE failed: 500 status=INTERNAL/m);
  assert.match(report, /^edit_delete\.ready=false$/m);
});

test("로컬 versionCode가 track 최고 versionCode보다 낮으면 실패한다", async () => {
  const fixture = await createFixture(credentialLine);
  const requests = [];

  await assert.rejects(
    runGooglePlayApiAccess({
      ...fixture,
      apiBaseUrl,
      fetchImpl: mockGooglePlayFetch(requests, {
        tracks: {
          tracks: [{ track: "production", releases: [{ versionCodes: ["9"] }] }],
        },
      }),
    }),
    /google play latest versionCode is lower than track max versionCode/,
  );

  const report = await readFile(fixture.reportPath, "utf8");
  assert.match(report, /^tracks\.max_version_code=9$/m);
  assert.match(report, /^latest_version_code_covers_track_max=false$/m);
  assert.match(report, /^edit_delete\.ready=true$/m);
  assert.equal(requests.at(-1), `DELETE ${editUrl}`);
});

test("edit 생성 전에 실패하면 delete를 시도하지 않는다", async () => {
  const fixture = await createFixture(credentialLine);
  const requests = [];

  await assert.rejects(
    runGooglePlayApiAccess({
      ...fixture,
      apiBaseUrl,
      fetchImpl: mockGooglePlayFetch(requests, {
        failures: {
          [`POST ${applicationUrl}/edits`]: {
            status: 401,
            body: { error: { status: "UNAUTHENTICATED", message: "invalid credential" } },
          },
        },
      }),
    }),
    /google play api POST failed: 401/,
  );

  const report = await readFile(fixture.reportPath, "utf8");
  assert.doesNotMatch(report, /^edit_insert\.ready=true$/m);
  assert.match(report, /^edit_delete\.ready=false$/m);
  assert.deepEqual(requests, [`POST ${baseUrl}/token`, `POST ${applicationUrl}/edits`]);
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
        apiBaseUrl,
        fetchImpl: async () => {
          throw new Error("fetch must not be called");
        },
      }),
      /invalid google play service account json/,
    );

    const report = await readFile(fixture.reportPath, "utf8");
    assert.match(report, new RegExp(`^service_account_json_source=${name}$`, "m"));
    assert.match(report, /^failure=invalid google play service account json$/m);
    assert.match(report, /^edit_delete\.ready=false$/m);
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

const defaultTracks = {
  tracks: [
    { track: "production", releases: [{ versionCodes: ["5"] }] },
    { track: "internal", releases: [{ versionCodes: ["6"] }] },
  ],
};

function mockGooglePlayFetch(requests, config = {}) {
  return async (url, options = {}) => {
    const method = options.method ?? "GET";
    const key = `${method} ${url}`;
    requests.push(key);
    if (url === `${baseUrl}/token`) {
      return jsonResponse({ access_token: "ya29.mock-access-token", token_type: "Bearer", expires_in: 3600 });
    }
    const failure = config.failures?.[key];
    if (failure) {
      return jsonResponse(failure.body, failure.status);
    }
    if (key === `POST ${applicationUrl}/edits`) {
      return jsonResponse({ id: "edit-1", expiryTimeSeconds: "0" });
    }
    if (key === `GET ${editUrl}/tracks`) {
      return jsonResponse(config.tracks ?? defaultTracks);
    }
    if (key === `POST ${editUrl}:validate`) {
      return jsonResponse({ id: "edit-1" });
    }
    if (key === `DELETE ${editUrl}`) {
      return new Response(null, { status: 204 });
    }
    throw new Error(`unexpected google play request: ${key}`);
  };
}

function jsonResponse(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
}
