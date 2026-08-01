#!/usr/bin/env node
import { appendFile, readFile, writeFile } from "node:fs/promises";
import { pathToFileURL } from "node:url";
import {
  defaultApiBaseUrl,
  detectServiceAccountSource,
  encodePath,
  fetchAccessToken,
  maskSecrets,
  parseDotenv,
  readServiceAccount,
  requestJson,
} from "./lib/google-play-auth.mjs";

async function main() {
  const args = parseArgs(process.argv.slice(2));
  await runGooglePlayApiAccess({
    envFile: requireArg(args, "env-file"),
    githubOutput: requireArg(args, "github-output"),
    reportPath: requireArg(args, "report"),
    apiBaseUrl: args.get("api-base-url") ?? defaultApiBaseUrl,
  });
}

export async function runGooglePlayApiAccess({
  envFile,
  githubOutput,
  reportPath,
  apiBaseUrl = defaultApiBaseUrl,
  fetchImpl = fetch,
}) {
  const normalizedApiBaseUrl = apiBaseUrl.replace(/\/$/, "");
  const env = parseDotenv(await readFile(envFile, "utf8"));
  const packageName = env.EASYSUBWAY_GOOGLE_PLAY_PACKAGE_NAME?.trim() || "unknown";
  const latestVersionCode = env.EASYSUBWAY_GOOGLE_PLAY_LATEST_VERSION_CODE?.trim() || "unknown";
  const serviceAccountSource = detectServiceAccountSource(env);
  let ready = true;
  let failureMessage;
  let reportSecrets = [];
  const report = [
    "google_play_api_access",
    `package_name=${packageName}`,
    `service_account_json_source=${serviceAccountSource}`,
    "oauth_scope=androidpublisher",
    `latest_version_code_env=${latestVersionCode}`,
  ];

  try {
    if (packageName === "unknown") {
      throw new Error("missing required env: EASYSUBWAY_GOOGLE_PLAY_PACKAGE_NAME");
    }
    const serviceAccount = readServiceAccount(env);
    reportSecrets = [
      serviceAccount.client_email,
      serviceAccount.project_id,
      serviceAccount.private_key_id,
    ].filter((value) => typeof value === "string" && value.length > 0);
    const token = await fetchAccessToken(serviceAccount, fetchImpl);
    const response = await requestJson(
      `${normalizedApiBaseUrl}/applications/${encodePath(packageName)}/reviews?maxResults=1`,
      { method: "GET", token },
      fetchImpl,
    );
    if (response.reviews !== undefined && !Array.isArray(response.reviews)) {
      throw new Error("invalid google play reviews response");
    }
    report.push("reviews_list.ready=true");
    report.push(`reviews.count=${response.reviews?.length ?? 0}`);
  } catch (error) {
    ready = false;
    const currentFailure = error instanceof Error ? error.message : "google play api access failed";
    failureMessage = redactReportValue(currentFailure, reportSecrets);
    report.push(`failure=${failureMessage}`);
  }

  report.push("secret_values_printed=false");
  report.push("");
  await appendFile(githubOutput, `google_play_api_access_ready=${ready}\n`);
  await writeFile(reportPath, report.join("\n"));
  if (!ready) {
    throw new Error(failureMessage);
  }
}

function redactReportValue(value, secrets) {
  const masked = secrets.reduce(
    (current, secret) => current.replaceAll(secret, "***"),
    maskSecrets(value),
  );
  return masked.replace(/\s+/g, " ").slice(0, 220);
}

function parseArgs(argv) {
  const args = new Map();
  for (let index = 0; index < argv.length; index += 1) {
    const key = argv[index];
    const value = argv[index + 1];
    if (!key?.startsWith("--") || value === undefined || value.startsWith("--")) {
      throw new Error(`invalid argument near ${key ?? "<end>"}`);
    }
    args.set(key.slice(2), value);
    index += 1;
  }
  return args;
}

function requireArg(args, name) {
  const value = args.get(name);
  if (!value) {
    throw new Error(`missing required argument: --${name}`);
  }
  return value;
}

if (import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch(() => {
    console.error("google play api access check failed; see sanitized report");
    process.exitCode = 1;
  });
}
