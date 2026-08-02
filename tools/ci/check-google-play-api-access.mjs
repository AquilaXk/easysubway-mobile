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

// no-upload preflight: 실제 릴리스가 사용하는 edit 경로 권한만 증명한다.
// 임시 edit 1개 생성 → track 목록 조회 → edit validate → `finally` delete.
// AAB upload, edit commit, track mutation, publish 경로는 의도적으로 없다.
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
  let token;
  let editId;
  let editDeleted = false;
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
    token = await fetchAccessToken(serviceAccount, fetchImpl);

    const edit = await requestJson(`${normalizedApiBaseUrl}/applications/${encodePath(packageName)}/edits`, {
      method: "POST",
      token,
      body: {},
    }, fetchImpl);
    if (typeof edit.id !== "string" || edit.id.trim().length === 0) {
      throw new Error("google play edit insert returned no edit id");
    }
    editId = edit.id;
    report.push("edit_insert.ready=true");

    const tracks = await requestJson(
      `${normalizedApiBaseUrl}/applications/${encodePath(packageName)}/edits/${encodePath(editId)}/tracks`,
      { method: "GET", token },
      fetchImpl,
    );
    // 형태가 어긋난 응답을 빈 목록으로 삼키면 `tracks_list.ready=true`라는 허위 증거가
    // 남는다. `tracks`가 있는데 배열이 아니면 fail-closed한다(없는 것은 정상 = track 0개).
    if (tracks.tracks !== undefined && !Array.isArray(tracks.tracks)) {
      throw new Error("google play tracks list returned a non-array tracks field");
    }
    const trackList = tracks.tracks ?? [];
    const trackIds = trackList
      .map((track) => track.trackId ?? track.track)
      .filter((track) => typeof track === "string" && track.length > 0)
      .toSorted();
    const maxTrackVersionCode = maxVersionCode(trackList);
    report.push("tracks_list.ready=true");
    report.push(`tracks.count=${trackList.length}`);
    report.push(`tracks.ids=${trackIds.join(",") || "none"}`);
    report.push(`tracks.max_version_code=${maxTrackVersionCode ?? "none"}`);
    // versionCode 비교는 정보성 증거이지 readiness 게이트가 아니다. Play의 업로드
    // 하드 규칙은 "이미 쓴 versionCode 재사용 금지"라는 유일성이고, 전 track을 관통하는
    // 전역 순서가 아니다. 테스트 track이 production보다 앞선 versionCode를 갖는 것은
    // 정상 운영 상태(shadowing)이므로, 그 상태만으로 자격증명 preflight를 실패시키면
    // false negative가 된다. 판단 근거는 사람이 아래 두 줄을 보고 내린다.
    const versionCodeComparison = compareVersionCode(latestVersionCode, maxTrackVersionCode);
    report.push(
      `latest_version_code_covers_track_max=${booleanOrUnknown(versionCodeComparison, (value) => value >= 0)}`,
    );
    report.push(
      `latest_version_code_exceeds_track_max=${booleanOrUnknown(versionCodeComparison, (value) => value > 0)}`,
    );

    await requestJson(
      `${normalizedApiBaseUrl}/applications/${encodePath(packageName)}/edits/${encodePath(editId)}:validate`,
      { method: "POST", token },
      fetchImpl,
    );
    report.push("edit_validate.ready=true");
  } catch (error) {
    ready = false;
    const currentFailure = error instanceof Error ? error.message : "google play api access failed";
    failureMessage = redactReportValue(currentFailure, reportSecrets);
    report.push(`failure=${failureMessage}`);
  } finally {
    // 성공·실패와 무관하게 임시 edit을 남기지 않는다.
    if (editId && token) {
      try {
        await requestJson(
          `${normalizedApiBaseUrl}/applications/${encodePath(packageName)}/edits/${encodePath(editId)}`,
          { method: "DELETE", token },
          fetchImpl,
        );
        editDeleted = true;
      } catch (error) {
        ready = false;
        const deleteFailure = redactReportValue(
          error instanceof Error ? error.message : "google play edit delete failed",
          reportSecrets,
        );
        failureMessage ??= deleteFailure;
        report.push(`edit_delete.failure=${deleteFailure}`);
      }
    }
  }

  report.push(`edit_delete.ready=${editDeleted}`);
  // readiness가 무엇을 보증하는지 명시한다. versionCode 라인은 근거일 뿐이며
  // 업로드 적격 판정은 이 preflight의 범위가 아니다.
  report.push("readiness_scope=credential_and_api_access");
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

function maxVersionCode(tracks) {
  const versions = tracks.flatMap((track) =>
    (track.releases ?? []).flatMap((release) => release.versionCodes ?? []),
  );
  let max;
  for (const version of versions) {
    if (!/^(0|[1-9]\d*)$/.test(String(version))) {
      continue;
    }
    const parsed = BigInt(version);
    if (max === undefined || parsed > max) {
      max = parsed;
    }
  }
  return max?.toString();
}

// 로컬 versionCode와 track 최고 versionCode를 비교한다. 어느 한쪽이 없거나
// 정수가 아니면 판정 불가를 뜻하는 undefined를 돌려준다.
function compareVersionCode(latestVersionCode, maxTrackVersionCode) {
  if (latestVersionCode === "unknown" || maxTrackVersionCode === undefined) {
    return undefined;
  }
  if (!/^(0|[1-9]\d*)$/.test(latestVersionCode)) {
    return undefined;
  }
  const latest = BigInt(latestVersionCode);
  const max = BigInt(maxTrackVersionCode);
  if (latest > max) {
    return 1;
  }
  return latest === max ? 0 : -1;
}

function booleanOrUnknown(comparison, predicate) {
  return comparison === undefined ? "unknown" : String(predicate(comparison));
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
