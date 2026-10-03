import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { constants, closeSync, fstatSync, lstatSync, mkdirSync, mkdtempSync, openSync, readFileSync, rmSync, rmdirSync, unlinkSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const repositoryRoot = resolve(import.meta.dirname, '..', '..');
const generatorSourcePath = fileURLToPath(import.meta.url);
const trackedLock = join(repositoryRoot, 'contracts/mobile/journey-v3-client.lock.json');
const resourcePaths = ['contracts/api/journey-v3-error-catalog.json', 'contracts/api/journey-v3-error-disposition.json', 'contracts/api/journey-v3-session-integrity.json', 'contracts/api/journey-v3.openapi.yaml'];
const generatedDartPaths = ['journey_v3_contract.dart', 'journey_v3_enums.dart', 'journey_v3_error.dart', 'journey_v3_models.dart', 'journey_v3_validation.dart'];
const generationReceiptName = 'journey_v3_generation_receipt.json';
const formatterIdentity = Object.freeze({ command: 'dart format', sdkVersion: '3.12.0' });
const generatorIdentity = Object.freeze({ id: 'easysubway-mobile-journey-v3-client', version: '2.0.0' });
const mobileRepository = 'AquilaXk/easysubway-mobile';
const nodeRuntime = Object.freeze({ command: 'node', majorVersion: 24 });
const mobileSourcePaths = ['contracts/mobile/journey-v3-client.lock.json', 'tools/mobile/generate-journey-v3-client.mjs'];
const logicalCommand = Object.freeze({ program: 'node', script: 'tools/mobile/generate-journey-v3-client.mjs', arguments: ['--contract-root', '<staged-contract-root>', '--lock', 'contracts/mobile/journey-v3-client.lock.json', '--output-root', '<absent-output-root>', '--receipt', '<output-root>/journey_v3_generation_receipt.json'] });
const supportedFeatures = ['array', 'boolean', 'closed-object', 'enum', 'integer-bounds', 'json-post', 'local-ref', 'nullable', 'openapi-3.0.3', 'request-response-security', 'strict-yaml-subset', 'string-constraints', 'tagged-one-of'];
const expectedOperations = new Map([
  ['/api/v3/journeys/session', { id: 'issueJourneySession', responses: ['200', '400', '403', '503'], request: 'JourneySessionRequest', success: 'JourneySessionResponse' }],
  ['/api/v3/journeys/search', { id: 'searchJourneys', responses: ['200', '400', '404', '422', '503', '504', '401', '429'], request: 'JourneySearchRequest', success: 'JourneySearchSuccess' }],
  ['/api/v3/journeys/profile', { id: 'profileJourneys', responses: ['200', '400', '404', '422', '503', '504', '401', '429'], request: 'JourneyProfileRequest', success: 'JourneyProfileSuccess' }],
  ['/api/v3/station-timetables/search', { id: 'searchStationTimetables', responses: ['200', '400', '404', '503', '401', '429'], request: 'StationTimetableSearchRequest', success: 'StationTimetableSearchSuccess' }],
]);
const expectedErrorTuples = [
  ['searchJourneys', 400, 'INVALID_JOURNEY_REQUEST'], ['searchJourneys', 404, 'STATION_NOT_FOUND'], ['searchJourneys', 422, 'ROUTE_NOT_FOUND'], ['searchJourneys', 422, 'ACCESSIBILITY_CONSTRAINT_UNSATISFIED'], ['searchJourneys', 503, 'ROUTING_BUNDLE_UNAVAILABLE'], ['searchJourneys', 503, 'ROUTING_BUNDLE_STALE'], ['searchJourneys', 503, 'TIMETABLE_UNAVAILABLE'], ['searchJourneys', 503, 'TIMETABLE_STALE'], ['searchJourneys', 503, 'REALTIME_REQUIRED_UNAVAILABLE'], ['searchJourneys', 503, 'ROUTING_IDENTITY_MISMATCH'], ['searchJourneys', 503, 'ROUTE_SERVICE_UNAVAILABLE'], ['searchJourneys', 503, 'FACILITY_STATUS_UNAVAILABLE'], ['searchJourneys', 504, 'JOURNEY_SEARCH_TIMEOUT'],
  ['searchStationTimetables', 400, 'INVALID_JOURNEY_REQUEST'], ['searchStationTimetables', 404, 'STATION_LINE_NOT_FOUND'], ['searchStationTimetables', 404, 'TIMETABLE_NOT_COVERED'], ['searchStationTimetables', 503, 'TIMETABLE_UNAVAILABLE'], ['searchStationTimetables', 503, 'TIMETABLE_STALE'], ['searchStationTimetables', 503, 'TIMETABLE_IDENTITY_MISMATCH'],
  ['profileJourneys', 400, 'INVALID_TEMPORAL_QUERY'], ['profileJourneys', 400, 'TEMPORAL_WINDOW_TOO_LARGE'], ['profileJourneys', 404, 'STATION_NOT_FOUND'], ['profileJourneys', 422, 'NO_SERVICE_IN_DEPARTURE_WINDOW'], ['profileJourneys', 422, 'NO_ROUTE_ARRIVING_BY_DEADLINE'], ['profileJourneys', 422, 'NO_LAST_CONNECTION'], ['profileJourneys', 422, 'REALTIME_NOT_APPLICABLE_TO_TEMPORAL_QUERY'], ['profileJourneys', 422, 'TEMPORAL_QUERY_TOO_COMPLEX'], ['profileJourneys', 503, 'REALTIME_REQUIRED_UNAVAILABLE'], ['profileJourneys', 503, 'ROUTING_BUNDLE_UNAVAILABLE'], ['profileJourneys', 503, 'ROUTING_BUNDLE_STALE'], ['profileJourneys', 503, 'ROUTING_IDENTITY_MISMATCH'], ['profileJourneys', 503, 'RAPTOR_FRONTIER_CAPACITY_EXCEEDED'], ['profileJourneys', 503, 'FACILITY_STATUS_UNAVAILABLE'], ['profileJourneys', 504, 'JOURNEY_PROFILE_TIMEOUT'],
  ['searchJourneys', 401, 'ROUTE_SESSION_REQUIRED'], ['searchJourneys', 429, 'ROUTE_RATE_LIMITED'],
  ['searchStationTimetables', 401, 'ROUTE_SESSION_REQUIRED'], ['searchStationTimetables', 429, 'ROUTE_RATE_LIMITED'],
  ['profileJourneys', 401, 'ROUTE_SESSION_REQUIRED'], ['profileJourneys', 429, 'ROUTE_RATE_LIMITED'],
  ['issueJourneySession', 400, 'INVALID_JOURNEY_SESSION_REQUEST'], ['issueJourneySession', 403, 'ROUTE_SESSION_ATTESTATION_REJECTED'], ['issueJourneySession', 503, 'ROUTE_SESSION_ATTESTATION_UNAVAILABLE']
];
const sha256 = (bytes) => createHash('sha256').update(bytes).digest('hex');
const fail = (message) => { throw new Error(`generate-journey-v3-client: ${message}`); };
const isObject = (value) => value !== null && typeof value === 'object' && !Array.isArray(value);
const expectedSchemasProjectionSha256 = '5b6f910bb58bcf8d3c64198653546f5675b37aa78d9f2cda5941280eadf42c71';

function canonicalJson(value) {
  if (Array.isArray(value)) return `[${value.map(canonicalJson).join(',')}]`;
  if (isObject(value)) return `{${Object.keys(value).sort().map((key) => `${JSON.stringify(key)}:${canonicalJson(value[key])}`).join(',')}}`;
  return JSON.stringify(value);
}

function configSha256() {
  return sha256(Buffer.from(canonicalJson({ schemaProjectionSha256: expectedSchemasProjectionSha256, resourcePaths, generatedDartPaths, generationReceiptName, supportedFeatures, formatterIdentity }), 'utf8'));
}

function validateNodeRuntime(nodeMajorVersion = Number(process.versions.node.split('.')[0])) { if (Number(nodeMajorVersion) !== nodeRuntime.majorVersion) fail(`Node ${nodeRuntime.majorVersion} is required`); }
function mobileSourceIdentity(snapshot) {
  const sourceFiles = Object.freeze([
    Object.freeze({ path: mobileSourcePaths[0], sha256: sha256(snapshot.lockBytes) }),
    Object.freeze({ path: mobileSourcePaths[1], sha256: sha256(snapshot.generatorBytes) }),
  ]);
  return Object.freeze({ repository: mobileRepository, sourceFiles, generationSourceTreeSha256: sha256(Buffer.from(sourceFiles.map(({ path, sha256: digest }) => `${path}\0${digest}\n`).join(''), 'utf8')) });
}

function duplicateFreeJson(text, label) {
  let index = 0;
  const whitespace = () => { while (/\s/.test(text[index] ?? '')) index += 1; };
  const string = () => { const start = index; index += 1; let escaped = false; while (index < text.length) { const c = text[index++]; if (!escaped && c === '"') return JSON.parse(text.slice(start, index)); if (!escaped && c < ' ') fail(`${label} has invalid JSON string`); escaped = !escaped && c === '\\'; if (c !== '\\') escaped = false; } fail(`${label} has unterminated JSON string`); };
  const value = () => { whitespace(); const c = text[index]; if (c === '"') { string(); return; } if (c === '{') { index += 1; whitespace(); const keys = new Set(); if (text[index] === '}') { index += 1; return; } while (true) { whitespace(); if (text[index] !== '"') fail(`${label} has malformed JSON object`); const key = string(); if (keys.has(key)) fail(`${label} has duplicate key ${key}`); keys.add(key); whitespace(); if (text[index++] !== ':') fail(`${label} has malformed JSON object`); value(); whitespace(); if (text[index] === '}') { index += 1; return; } if (text[index++] !== ',') fail(`${label} has malformed JSON object`); } } if (c === '[') { index += 1; whitespace(); if (text[index] === ']') { index += 1; return; } while (true) { value(); whitespace(); if (text[index] === ']') { index += 1; return; } if (text[index++] !== ',') fail(`${label} has malformed JSON array`); } } const primitive = /^(?:true|false|null|-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?)/.exec(text.slice(index)); if (!primitive) fail(`${label} has malformed JSON value`); index += primitive[0].length; };
  try { value(); whitespace(); if (index !== text.length) fail(`${label} has trailing JSON content`); return JSON.parse(text); } catch (error) { if (error.message.startsWith('generate-journey-v3-client:')) throw error; fail(`${label} is not valid JSON`); }
}

function exactKeys(value, keys, label) { if (!isObject(value) || Object.keys(value).length !== keys.length || keys.some((key) => !(key in value))) fail(`${label} has unexpected or missing fields`); }
function regular(path, label) { if (constants.O_NOFOLLOW === undefined) fail('O_NOFOLLOW is required'); let fd; try { fd = openSync(path, constants.O_RDONLY | constants.O_NOFOLLOW); if (!fstatSync(fd).isFile()) fail(`${label} must be regular`); return readFileSync(fd); } catch (error) { if (error.message.startsWith('generate-journey-v3-client:')) throw error; fail(`${label} must be a regular non-symlink file`); } finally { if (fd !== undefined) closeSync(fd); } }
function snapshotGenerationInput({ contractRoot, lockPath }, enforceTrackedLock) {
  if (enforceTrackedLock && resolve(lockPath) !== trackedLock) fail('lock must be the tracked journey-v3-client lock');
  return Object.freeze({
    generatorBytes: regular(generatorSourcePath, 'generator source'),
    lockBytes: regular(lockPath, 'lock'),
    stageReceiptBytes: regular(join(contractRoot, 'journey-v3-contract-stage-receipt.json'), 'stage receipt'),
    resourceBytes: Object.freeze(Object.fromEntries(resourcePaths.map((path) => [path, regular(join(contractRoot, path), path)]))),
  });
}
function assertSnapshotUnchanged({ contractRoot, lockPath }, snapshot) {
  const entries = [
    [generatorSourcePath, 'generator source', snapshot.generatorBytes],
    [lockPath, 'lock', snapshot.lockBytes],
    [join(contractRoot, 'journey-v3-contract-stage-receipt.json'), 'stage receipt', snapshot.stageReceiptBytes],
    ...resourcePaths.map((path) => [join(contractRoot, path), path, snapshot.resourceBytes[path]]),
  ];
  for (const [path, label, expected] of entries) if (!regular(path, label).equals(expected)) fail(`${label} changed during generation`);
}
function ref(value, label) { if (typeof value !== 'string' || !/^#\/components\/schemas\/[A-Z][A-Za-z0-9]+$/.test(value)) fail(`${label} must be a local component reference`); return value.slice('#/components/schemas/'.length); }

function parseScalar(raw, label) {
  if (raw === 'true') return true; if (raw === 'false') return false; if (raw === 'null') return null;
  if (/^-?(?:0|[1-9]\d*)$/.test(raw)) return Number(raw);
  if (raw.startsWith('"')) { try { const parsed = JSON.parse(raw); if (typeof parsed !== 'string') throw new Error(); return parsed; } catch { fail(`${label} has invalid quoted scalar`); } }
  if (raw.startsWith('[') && raw.endsWith(']')) {
    const inner = raw.slice(1, -1).trim();
    if (inner === '') return [];
    if (/[{}]/.test(inner)) fail(`${label} has unsupported inline construct`);
    const items = [];
    let cur = '', inQuotes = false;
    for (let i = 0; i < inner.length; i++) {
      const ch = inner[i];
      if (ch === '"') inQuotes = !inQuotes;
      if (ch === ',' && !inQuotes) {
        items.push(cur.trim());
        cur = '';
      } else {
        cur += ch;
      }
    }
    items.push(cur.trim());
    return items.map((part) => parseScalar(part, label));
  }
  if (/^[^\s][^#{}[\]]*$/.test(raw)) return raw;
  fail(`${label} has unsupported YAML scalar`);
}

function parseYaml(text) {
  if (!text.endsWith('\n') || /\t|(^|\s)[&*!]|(^|\s)<<:|(^|\s)(?:\||>[^-]|\>[\r\n])/m.test(text)) fail('OpenAPI has unsupported YAML construct');
  const lines = text.split('\n').slice(0, -1).map((line, index) => ({ line, number: index + 1 }));
  if (lines.some(({ line }) => line === '' || /[ \t]$/.test(line))) fail('OpenAPI has noncanonical YAML whitespace');
  let index = 0;
  const current = () => lines[index];
  const indentOf = (line) => line.match(/^ */)[0].length;
  const keyValue = (body, label) => { const match = /^("(?:[^"\\]|\\.)+"|\$ref|\/[A-Za-z0-9_./{}-]*|[A-Za-z][A-Za-z0-9_./$-]*):(?: ?(.*))?$/.exec(body); if (!match) fail(`${label} has unsupported YAML mapping`); const key = match[1].startsWith('"') ? parseScalar(match[1], label) : match[1]; return [key, match[2] ?? '']; };
  const foldedScalar = (parentIndent) => {
    const parts = [];
    while (current() && indentOf(current().line) > parentIndent) {
      parts.push(current().line.trim());
      index += 1;
    }
    return parts.join(' ');
  };
  const block = (indent) => {
    if (!current() || indentOf(current().line) !== indent) fail(`OpenAPI line ${current()?.number ?? 'EOF'} has noncanonical indentation`);
    const sequence = current().line.slice(indent).startsWith('-'); const result = sequence ? [] : {};
    while (current() && indentOf(current().line) === indent) {
      const body = current().line.slice(indent);
      if (sequence) {
        if (!body.startsWith('- ') || body === '-') fail(`OpenAPI line ${current().number} has unsupported YAML sequence`);
        const rest = body.slice(2); index += 1;
        if (/^[A-Za-z$][A-Za-z0-9_$-]*:/.test(rest)) {
          const [key, raw] = keyValue(rest, `OpenAPI line ${lines[index - 1].number}`);
          const entry = {};
          if (raw === '') entry[key] = current() && indentOf(current().line) > indent ? block(indent + 2) : fail(`OpenAPI line ${lines[index - 1].number} needs child`);
          else if (raw === '>-') entry[key] = foldedScalar(indent);
          else entry[key] = parseScalar(raw, `OpenAPI line ${lines[index - 1].number}`);
          if (current() && indentOf(current().line) === indent + 2 && !current().line.slice(indent + 2).startsWith('-')) {
            const tail = block(indent + 2);
            for (const [tailKey, tailValue] of Object.entries(tail)) {
              if (tailKey in entry) fail(`OpenAPI line ${current()?.number ?? 'EOF'} has duplicate key ${tailKey}`);
              entry[tailKey] = tailValue;
            }
          }
          result.push(entry);
        } else result.push(parseScalar(rest, `OpenAPI line ${lines[index - 1].number}`));
      } else {
        if (body.startsWith('- ')) fail(`OpenAPI line ${current().number} mixes YAML sequence and mapping`);
        const [key, raw] = keyValue(body, `OpenAPI line ${current().number}`);
        if (key in result) fail(`OpenAPI line ${current().number} has duplicate key ${key}`);
        index += 1;
        if (raw === '') result[key] = (current() && indentOf(current().line) > indent ? block(indent + 2) : fail(`OpenAPI line ${lines[index - 1].number} needs child`));
        else if (raw === '>-') result[key] = foldedScalar(indent);
        else result[key] = parseScalar(raw, `OpenAPI line ${lines[index - 1].number}`);
      }
      if (current() && indentOf(current().line) > indent && !sequence) fail(`OpenAPI line ${current().number} has noncanonical indentation`);
    }
    return result;
  };
  const parsed = block(0); if (index !== lines.length) fail(`OpenAPI line ${current().number} has noncanonical indentation`); return parsed;
}

function validateLock(lock) {
  exactKeys(lock, ['schemaVersion', 'component', 'bundleVersion', 'producer', 'artifact', 'payload', 'publicationReceiptSha256', 'resources'], 'lock'); exactKeys(lock.producer, ['repository', 'gitSha'], 'lock.producer'); exactKeys(lock.artifact, ['repository', 'manifestDigest', 'artifactType'], 'lock.artifact'); exactKeys(lock.payload, ['fileName', 'mediaType', 'sha256'], 'lock.payload');
  if (lock.schemaVersion !== 2 || lock.component !== 'backend' || lock.bundleVersion !== '2.0.0' || !/^[a-f0-9]{40}$/.test(lock.producer.gitSha) || !/^sha256:[a-f0-9]{64}$/.test(lock.artifact.manifestDigest) || !/^[a-f0-9]{64}$/.test(lock.payload.sha256) || !/^[a-f0-9]{64}$/.test(lock.publicationReceiptSha256)) fail('lock has unsupported identity');
  if (!Array.isArray(lock.resources) || lock.resources.length !== 4) fail('lock must have exactly four resources'); lock.resources.forEach((resource, index) => { exactKeys(resource, ['id', 'path', 'owner', 'mediaType', 'sha256'], `lock resource ${index}`); if (resource.path !== resourcePaths[index] || !/^[a-f0-9]{64}$/.test(resource.sha256)) fail('lock resource path or SHA-256 is invalid'); });
}

const exactSessionIntegrity = Object.freeze({
  schemaVersion: 'JOURNEY_V3_SESSION_INTEGRITY_V1', artifactKind: 'journey-v3-session-integrity', operationId: 'issueJourneySession',
  nonce: { source: 'CSPRNG', entropyBytes: 16, encoding: 'BASE64URL_NO_PADDING', pattern: '^[A-Za-z0-9_-]{21}[AQgw]$', lifecycle: 'ONE_PER_SESSION_ISSUANCE' },
  requestHash: { requestType: 'PLAY_INTEGRITY_STANDARD', algorithm: 'SHA-256', encoding: 'BASE64URL_NO_PADDING', pattern: '^[A-Za-z0-9_-]{42}[AEIMQUYcgkosw048]$', canonicalPayloadUtf8Template: '{"clientNonce":"<clientNonce>","purpose":"journey:v3:session","version":1}', purpose: 'journey:v3:session', version: 1, sensitivePlaintextAllowed: false },
  verdict: { expectedRequestPackageName: 'com.easysubway.app', expectedAppPackageName: 'com.easysubway.app', maxAgeSeconds: 120, futureTimestampAllowed: false, requiredAppRecognitionVerdict: 'PLAY_RECOGNIZED', requiredAppLicensingVerdict: 'LICENSED', requiredDeviceRecognitionVerdict: 'MEETS_DEVICE_INTEGRITY', configuredCertificateSha256Required: true, configuredCertificateSha256Encoding: 'BASE64URL_NO_PADDING', requestHashConstantTimeEqualityRequired: true, nonceSingleUseRequired: true, nonceClaimTtlSeconds: 120 },
  session: { scope: 'journey:v3', ttlSeconds: 600 },
});
function validateSessionIntegrity(bytes) {
  const sessionIntegrity = duplicateFreeJson(bytes.toString('utf8'), 'session integrity');
  const assertPublishedKeyOrder = (actual, expected) => {
    if (!isObject(actual) || JSON.stringify(Object.keys(actual)) !== JSON.stringify(Object.keys(expected))) fail('session integrity keys must use the published order');
    for (const key of Object.keys(expected)) if (isObject(expected[key])) assertPublishedKeyOrder(actual[key], expected[key]);
  };
  assertPublishedKeyOrder(sessionIntegrity, exactSessionIntegrity);
  if (canonicalJson(sessionIntegrity) !== canonicalJson(exactSessionIntegrity)) fail('session integrity must match the closed published schema');
  return Object.freeze(sessionIntegrity);
}

function validateStage(lock, lockBytes, root, snapshot) {
  const receiptBytes = snapshot?.stageReceiptBytes ?? regular(join(root, 'journey-v3-contract-stage-receipt.json'), 'stage receipt');
  const receipt = duplicateFreeJson(receiptBytes.toString('utf8'), 'stage receipt'); exactKeys(receipt, ['schemaVersion', 'lockSha256', 'payloadSha256', 'publicationReceiptSha256', 'artifact', 'resources'], 'stage receipt');
  if (receipt.schemaVersion !== 1 || receipt.lockSha256 !== sha256(lockBytes) || receipt.payloadSha256 !== lock.payload.sha256 || receipt.publicationReceiptSha256 !== lock.publicationReceiptSha256 || JSON.stringify(receipt.artifact) !== JSON.stringify(lock.artifact) || !isObject(receipt.resources) || JSON.stringify(Object.keys(receipt.resources)) !== JSON.stringify(resourcePaths)) fail('stage receipt does not bind the raw lock identity');
  for (const resource of lock.resources) { const bytes = snapshot?.resourceBytes[resource.path] ?? regular(join(root, resource.path), resource.path); if (sha256(bytes) !== resource.sha256 || receipt.resources[resource.path] !== resource.sha256) fail(`${resource.path} SHA-256 does not match staged lock`); }
}

function assertAllowed(value, keys, label) { if (!isObject(value) || Object.keys(value).some((key) => !keys.includes(key))) fail(`${label} has unsupported schema construct`); }
function validateSchemas(schemas, enforceSchemasProjection) {
  if (!isObject(schemas) || Object.keys(schemas).length === 0) fail('components.schemas must be nonempty'); const state = new Map();
  const visit = (name) => { if (!(name in schemas)) fail(`unresolved schema reference ${name}`); if (state.get(name) === 'visiting') fail(`cyclic schema reference ${name}`); if (state.get(name) === 'done') return; state.set(name, 'visiting'); schema(schemas[name], name); state.set(name, 'done'); };
  const nullableFields = new Set(['JourneySourceIdentity.realtimeSnapshotId', 'JourneyProfileSourceIdentity.realtimeSnapshotId', 'Journey.realtimeDepartureTime', 'Journey.realtimeArrivalTime', 'JourneyRideLeg.realtimeDepartureTime', 'JourneyRideLeg.realtimeArrivalTime', 'JourneyRideStop.plannedArrivalTime', 'JourneyRideStop.plannedDepartureTime', 'JourneyRideStop.realtimeArrivalTime', 'JourneyRideStop.realtimeDepartureTime', 'StationTimetableDirectionGroup.directionName']);
  const schema = (value, label) => {
    if (!isObject(value)) fail(`${label} must be a schema object`);
    if ('$ref' in value) { assertAllowed(value, ['$ref'], label); visit(ref(value.$ref, label)); return; }
    if ('oneOf' in value) {
      assertAllowed(value, ['oneOf', 'description'], label);
      const descriptor = { JourneyDeparture: { tag: 'mode', refs: ['JourneyDepartureNow', 'JourneyDepartureScheduled'] }, JourneyLeg: { tag: 'type', refs: ['JourneyEntryLeg', 'JourneyRideLeg', 'JourneyTransferLeg', 'JourneyExitLeg'] }, StationTimetableSelector: { tag: 'kind', refs: ['StationTimetableServiceDateSelector', 'StationTimetableDayTypeSelector', 'StationTimetableNextDeparturesSelector'] } }[label];
      if (!descriptor) {
        for (const part of value.oneOf) {
          if (!isObject(part) || Object.keys(part).length !== 1 || !('$ref' in part)) fail(`${label} oneOf is unsupported`);
          visit(ref(part.$ref, label));
        }
        return;
      }
      if (value.oneOf.length !== descriptor.refs.length) fail(`${label} must be the exact closed tagged oneOf`);
      const tags = new Set();
      for (const [index, part] of value.oneOf.entries()) {
        if (!isObject(part) || Object.keys(part).length !== 1 || ref(part.$ref, label) !== descriptor.refs[index]) fail(`${label} oneOf is unsupported`);
        const target = descriptor.refs[index]; visit(target); const tag = schemas[target]?.properties?.[descriptor.tag]?.enum;
        if (!Array.isArray(tag) || tag.length !== 1 || tags.has(tag[0])) fail(`${label} oneOf is not tagged by ${descriptor.tag}`);
        tags.add(tag[0]);
      }
      return;
    }
    if (value.type === 'object') {
      assertAllowed(value, ['type', 'additionalProperties', 'required', 'properties', 'not', 'description', 'deprecated'], label);
      if ('deprecated' in value && value.deprecated !== true) fail(`${label} has invalid deprecated flag`);
      const isOptionalAllowed = label === 'JourneyTransferLeg' || label === 'JourneySearchRequest' || label === 'JourneyRideLeg' || label === 'JourneyPlatformGap' || label === 'JourneyFare' || label === 'Journey';
      if (value.additionalProperties !== false || !Array.isArray(value.required) || !isObject(value.properties) || new Set(value.required).size !== value.required.length || (!isOptionalAllowed && Object.keys(value.properties).length !== value.required.length) || value.required.some((key) => !(key in value.properties))) fail(`${label} must have an exact closed required property set`);
      for (const [key, child] of Object.entries(value.properties)) { if (!/^[A-Za-z][A-Za-z0-9]*$/.test(key)) fail(`${label} has unsupported property`); schema(child, `${label}.${key}`); }
      if ('not' in value && (!isObject(value.not) || !Array.isArray(value.not.required) || !isObject(value.not.properties))) fail(`${label} has unsupported not constraint`);
      return;
    }
    if (value.type === 'string') {
      assertAllowed(value, ['type', 'minLength', 'maxLength', 'pattern', 'format', 'enum', 'nullable', 'description'], label);
      for (const key of ['minLength', 'maxLength']) if (key in value && (!Number.isInteger(value[key]) || value[key] < 0)) fail(`${label} has invalid ${key}`);
      if ('minLength' in value && 'maxLength' in value && value.minLength > value.maxLength) fail(`${label} has unordered lengths`);
      if ('pattern' in value) { if (typeof value.pattern !== 'string' || value.pattern.length === 0) fail(`${label} has invalid pattern`); try { new RegExp(value.pattern); } catch { fail(`${label} has invalid pattern`); } }
      if ('format' in value && !['date', 'date-time'].includes(value.format)) fail(`${label} has unsupported string format`);
      if ('enum' in value && (!Array.isArray(value.enum) || value.enum.length === 0 || value.enum.some((item) => typeof item !== 'string') || new Set(value.enum).size !== value.enum.length)) fail(`${label} has invalid string enum`);
      if ('nullable' in value && (value.nullable !== true || !nullableFields.has(label))) fail(`${label} has unsupported nullable string`);
      return;
    }
    if (value.type === 'integer') {
      assertAllowed(value, ['type', 'minimum', 'maximum', 'default', 'description'], label);
      for (const key of ['minimum', 'maximum']) if (key in value && (!Number.isInteger(value[key]))) fail(`${label} has invalid ${key}`);
      if ('minimum' in value && 'maximum' in value && value.minimum > value.maximum) fail(`${label} has unordered integer bounds`);
      return;
    }
    if (value.type === 'boolean') {
      assertAllowed(value, ['type', 'default', 'description'], label);
      return;
    }
    if (value.type === 'array') {
      assertAllowed(value, ['type', 'minItems', 'maxItems', 'uniqueItems', 'items', 'description'], label);
      for (const key of ['minItems', 'maxItems']) if (key in value && (!Number.isInteger(value[key]) || value[key] < 0)) fail(`${label} has invalid ${key}`);
      if ('minItems' in value && 'maxItems' in value && value.minItems > value.maxItems) fail(`${label} has unordered array bounds`);
      if ('uniqueItems' in value && typeof value.uniqueItems !== 'boolean') fail(`${label} has invalid uniqueItems`);
      if (!('items' in value)) fail(`${label} array items are required`);
      schema(value.items, `${label}.items`);
      return;
    }
    fail(`${label} has unsupported schema type`);
  };
  for (const name of Object.keys(schemas)) visit(name);
  if (enforceSchemasProjection) {
    const projectionSha256 = sha256(Buffer.from(canonicalJson(schemas), 'utf8'));
    if (projectionSha256 !== expectedSchemasProjectionSha256) fail(`components.schemas projection SHA-256 does not match ${projectionSha256}`);
  }
  return schemas;
}

// #438 transition policy, part 1: contract additions from backend PRs that are
// approved but not merged, so no published contract bundle carries them yet.
// They are overlaid on the locked contract so the client is ready before the
// backend deploys. Each entry mirrors the PR's journey-v3.openapi.yaml change
// (descriptions omitted). When the lock moves to a bundle that already has an
// entry, generation fails until the entry is removed here.
const pendingContractAdditions = Object.freeze([
  Object.freeze({ source: 'AquilaXk/easysubway-backend#471', schema: 'JourneyStairFreeAlternative', definition: Object.freeze({ type: 'object', additionalProperties: false, required: ['status', 'facilityStatus'], properties: { status: { type: 'string', enum: ['INCLUDED', 'OMITTED', 'NOT_FOUND', 'UNDETERMINED'] }, facilityStatus: { type: 'string', enum: ['APPLIED', 'UNOBSERVED'] } } }) }),
  Object.freeze({ source: 'AquilaXk/easysubway-backend#471', schema: 'JourneySearchSuccess', property: 'stairFreeAlternative', required: true, definition: Object.freeze({ $ref: '#/components/schemas/JourneyStairFreeAlternative' }) }),
  Object.freeze({ source: 'AquilaXk/easysubway-backend#471', schema: 'Journey', property: 'alternativeCategories', required: false, definition: Object.freeze({ type: 'array', uniqueItems: true, maxItems: 3, items: { type: 'string', enum: ['FASTEST', 'FEWEST_TRANSFERS', 'STAIR_FREE'] } }) }),
  Object.freeze({ source: 'AquilaXk/easysubway-backend#479', schema: 'StationTimetableDirectionGroup', property: 'nextStationId', required: true, definition: Object.freeze({ type: 'string', minLength: 1 }) }),
  Object.freeze({ source: 'AquilaXk/easysubway-backend#479', schema: 'StationTimetableDirectionGroup', property: 'directionName', replaces: Object.freeze({ type: 'string', minLength: 1 }), definition: Object.freeze({ type: 'string', minLength: 1, nullable: true }) }),
  Object.freeze({ source: 'AquilaXk/easysubway-backend#479', schema: 'StationTimetableDeparture', property: 'terminalStationId', required: true, definition: Object.freeze({ type: 'string', minLength: 1 }) }),
]);

function applyPendingContractAdditions(lockedSchemas, pendingAdditions = pendingContractAdditions) {
  const schemas = JSON.parse(JSON.stringify(lockedSchemas));
  for (const entry of pendingAdditions) {
    const definition = JSON.parse(JSON.stringify(entry.definition));
    if (entry.property === undefined) {
      if (entry.schema in schemas) fail(`pending contract addition ${entry.schema} (${entry.source}) is already in the locked contract; remove it from pendingContractAdditions`);
      schemas[entry.schema] = definition;
      continue;
    }
    const target = schemas[entry.schema];
    if (!isObject(target) || !isObject(target.properties)) fail(`pending contract addition target ${entry.schema} is missing from the locked contract`);
    const existing = target.properties[entry.property];
    if (entry.replaces !== undefined) {
      if (canonicalJson(existing) === canonicalJson(definition)) fail(`pending contract change ${entry.schema}.${entry.property} (${entry.source}) is already in the locked contract; remove it from pendingContractAdditions`);
      if (canonicalJson(existing) !== canonicalJson(entry.replaces)) fail(`pending contract change ${entry.schema}.${entry.property} (${entry.source}) no longer matches the locked contract`);
      target.properties[entry.property] = definition;
      continue;
    }
    if (existing !== undefined) fail(`pending contract addition ${entry.schema}.${entry.property} (${entry.source}) is already in the locked contract; remove it from pendingContractAdditions`);
    target.properties[entry.property] = definition;
    if (entry.required) target.required = [...target.required, entry.property];
  }
  return schemas;
}

function responseSchema(response, label) { if (!isObject(response) || !isObject(response.content) || Object.keys(response.content).length !== 1 || !isObject(response.content['application/json']) || !isObject(response.content['application/json'].schema)) fail(`${label} must have only JSON response content`); return ref(response.content['application/json'].schema.$ref, label); }
function validateOperations(document) {
  exactKeys(document, ['openapi', 'info', 'paths', 'components'], 'OpenAPI');
  if (document.openapi !== '3.0.3' || !isObject(document.info) || document.info.version !== '3.0.0' || !isObject(document.paths) || Object.keys(document.paths).length !== expectedOperations.size) fail('OpenAPI version or path set is unsupported');
  const operations = [];
  for (const [path, expectation] of expectedOperations) {
    const item = document.paths[path]; if (!isObject(item) || Object.keys(item).length !== 1 || !isObject(item.post)) fail(`${path} must contain only POST`);
    const operation = item.post; const protectedOperation = expectation.id !== 'issueJourneySession';
    const allowedKeys = ['operationId', 'summary', 'description', ...(protectedOperation ? ['security'] : []), 'requestBody', 'responses'];
    if (expectation.id === 'searchJourneys' || expectation.id === 'profileJourneys') {
      allowedKeys.push('x-easysubway-time-policy-contract');
    }
    if (expectation.id === 'profileJourneys') {
      allowedKeys.push('x-easysubway-cache-control');
    }
    assertAllowed(operation, allowedKeys, path);
    if (operation.operationId !== expectation.id || !isObject(operation.requestBody) || operation.requestBody.required !== true || responseSchema({ content: operation.requestBody.content }, `${path} request`) !== expectation.request || !isObject(operation.responses) || expectation.responses.some((status) => !(status in operation.responses)) || Object.keys(operation.responses).length !== expectation.responses.length) fail(`${path} operation contract is unsupported`);
    if (protectedOperation && (!Array.isArray(operation.security) || operation.security.length !== 1 || JSON.stringify(operation.security[0]) !== JSON.stringify({ JourneySessionBearer: [] }))) fail(`${expectation.id} must require JourneySessionBearer`);
    if (expectation.id === 'searchJourneys' || expectation.id === 'profileJourneys') {
      exactKeys(operation['x-easysubway-time-policy-contract'], ['TIMETABLE_REQUIRED', 'REALTIME_REQUIRED'], `${expectation.id} time policy`);
      if (operation['x-easysubway-time-policy-contract'].TIMETABLE_REQUIRED !== 'realtime-fields-null' || operation['x-easysubway-time-policy-contract'].REALTIME_REQUIRED !== 'realtime-fields-required-non-null') fail(`${expectation.id} time policy values are unsupported`);
    }
    const responseNames = expectation.responses.map((status) => ({ status, schema: responseSchema(operation.responses[status], `${path} ${status}`) }));
    if (responseNames[0].schema !== expectation.success || responseNames.slice(1).some(({ schema }) => schema !== 'JourneyError')) fail(`${path} responses must use JourneyError`);
    operations.push({ path, id: expectation.id, responses: responseNames });
  }
  exactKeys(document.components, ['securitySchemes', 'schemas'], 'components'); exactKeys(document.components.securitySchemes, ['JourneySessionBearer'], 'securitySchemes'); const security = document.components.securitySchemes.JourneySessionBearer; exactKeys(security, ['type', 'scheme', 'bearerFormat'], 'JourneySessionBearer'); if (security.type !== 'http' || security.scheme !== 'bearer' || security.bearerFormat !== 'opaque-route-session') fail('JourneySessionBearer is unsupported'); return operations;
}

function validateOperationSchemaReferences(operations, schemas) {
  for (const operation of operations) {
    const expectation = expectedOperations.get(operation.path);
    for (const name of [expectation.request, ...operation.responses.map(({ schema }) => schema)]) {
      if (!(name in schemas)) fail(`operation ${operation.id} references missing schema ${name}`);
    }
  }
}

function validateErrors(catalog, disposition) {
  exactKeys(catalog, ['schemaVersion', 'artifactKind', 'applicationErrors', 'ingressErrors'], 'error catalog'); if (catalog.schemaVersion !== 'JOURNEY_ERROR_CATALOG_V1' || catalog.artifactKind !== 'journey-v3-error-catalog' || !Array.isArray(catalog.applicationErrors) || !Array.isArray(catalog.ingressErrors)) fail('error catalog is unsupported'); const entries = [...catalog.applicationErrors, ...catalog.ingressErrors]; if (entries.length !== expectedErrorTuples.length) fail('error catalog has unexpected entry count'); const tuples = new Set(); const expectedTuples = new Set(expectedErrorTuples.map((entry) => entry.join('\0'))); for (const entry of entries) { exactKeys(entry, ['operation', 'httpStatus', 'code'], 'error catalog entry'); const key = `${entry.operation}\0${entry.httpStatus}\0${entry.code}`; if (!expectedTuples.has(key) || tuples.has(key)) fail('error catalog has duplicate or unsupported entry'); tuples.add(key); } if (tuples.size !== expectedTuples.size) fail('error catalog does not have the exact declared entries');
  exactKeys(disposition, ['schemaVersion', 'artifactKind', 'sourceCatalog', 'entries'], 'error disposition'); exactKeys(disposition.sourceCatalog, ['path', 'schemaVersion', 'sha256'], 'error disposition sourceCatalog'); if (disposition.schemaVersion !== 'JOURNEY_ERROR_DISPOSITION_V1' || disposition.artifactKind !== 'journey-v3-error-disposition' || disposition.sourceCatalog.path !== 'journey-v3-error-catalog.json' || disposition.sourceCatalog.schemaVersion !== 'JOURNEY_ERROR_CATALOG_V1' || !Array.isArray(disposition.entries) || disposition.entries.length !== expectedErrorTuples.length) fail('error disposition is unsupported'); const seen = new Set(); const bindings = []; for (const entry of disposition.entries) { const keys = ['operation', 'httpStatus', 'machineCode', 'semanticCategory', 'exposure', 'userVisible', 'publicMessageKey', 'canonicalKoreanCopy', 'mobileResourceKey', 'mobilePresentation', 'retryDisposition', 'primaryActionKey', 'secondaryActionKey', 'safeDiagnosticKey', 'sensitiveDetailPolicy']; exactKeys(entry, keys, 'error disposition entry'); const key = `${entry.operation}\0${entry.httpStatus}\0${entry.machineCode}`; if (!tuples.has(key) || seen.has(key) || entry.exposure !== 'MOBILE_USER_VISIBLE' || entry.userVisible !== true || entry.mobilePresentation !== 'FAILURE_SCREEN' || entry.retryDisposition !== 'FORBIDDEN' || entry.secondaryActionKey !== null || entry.sensitiveDetailPolicy !== 'NEVER_PUBLIC' || typeof entry.semanticCategory !== 'string' || typeof entry.publicMessageKey !== 'string' || typeof entry.canonicalKoreanCopy !== 'string' || typeof entry.mobileResourceKey !== 'string' || typeof entry.safeDiagnosticKey !== 'string' || !(entry.primaryActionKey === null || typeof entry.primaryActionKey === 'string')) fail('error disposition does not have the fixed mobile policy'); seen.add(key); bindings.push(Object.freeze({ ...entry, code: entry.machineCode })); } if (seen.size !== tuples.size) fail('error catalog and disposition are not one-to-one'); return Object.freeze(bindings); }
function expectedOperationsHas(operation) { return [...expectedOperations.values()].some(({ id }) => id === operation); }

function validate({ contractRoot, lockPath, enforceTrackedLock, enforceSchemasProjection, snapshot, pendingAdditions = pendingContractAdditions }) {
  if (enforceTrackedLock && resolve(lockPath) !== trackedLock) fail('lock must be the tracked journey-v3-client lock'); const lockBytes = snapshot?.lockBytes ?? regular(lockPath, 'lock'); const lock = duplicateFreeJson(lockBytes.toString('utf8'), 'lock'); validateLock(lock); validateStage(lock, lockBytes, contractRoot, snapshot);
  const catalogBytes = snapshot?.resourceBytes[resourcePaths[0]] ?? regular(join(contractRoot, resourcePaths[0]), 'error catalog'); const dispositionBytes = snapshot?.resourceBytes[resourcePaths[1]] ?? regular(join(contractRoot, resourcePaths[1]), 'error disposition'); const sessionIntegrityBytes = snapshot?.resourceBytes[resourcePaths[2]] ?? regular(join(contractRoot, resourcePaths[2]), 'session integrity'); const yaml = (snapshot?.resourceBytes[resourcePaths[3]] ?? regular(join(contractRoot, resourcePaths[3]), 'OpenAPI')).toString('utf8'); const catalog = duplicateFreeJson(catalogBytes.toString('utf8'), 'error catalog'); const disposition = duplicateFreeJson(dispositionBytes.toString('utf8'), 'error disposition'); const sessionIntegrity = validateSessionIntegrity(sessionIntegrityBytes); if (disposition.sourceCatalog?.sha256 !== sha256(catalogBytes)) fail('error disposition source catalog SHA-256 does not match'); const document = parseYaml(yaml); const operations = validateOperations(document); const schemas = validateSchemas(applyPendingContractAdditions(validateSchemas(document.components.schemas, enforceSchemasProjection), pendingAdditions), false); validateOperationSchemaReferences(operations, schemas); const requestNot = schemas.JourneySearchRequest?.not; exactKeys(requestNot, ['required', 'properties'], 'JourneySearchRequest.not'); exactKeys(requestNot.properties, ['mobilityProfile', 'constraintMode'], 'JourneySearchRequest.not.properties'); if (JSON.stringify(requestNot.required) !== JSON.stringify(['mobilityProfile', 'constraintMode']) || JSON.stringify(requestNot.properties.mobilityProfile?.enum) !== JSON.stringify(['NO_STAIRS']) || JSON.stringify(requestNot.properties.constraintMode?.enum) !== JSON.stringify(['NONE'])) fail('JourneySearchRequest must prohibit NO_STAIRS plus NONE'); const errors = validateErrors(catalog, disposition); const errorCodes = schemas.JourneyErrorCode?.enum; const catalogCodes = new Set(errors.map((entry) => entry.code)); if (!Array.isArray(errorCodes) || errorCodes.length !== catalogCodes.size || new Set(errorCodes).size !== errorCodes.length || errorCodes.some((code) => !catalogCodes.has(code))) fail('JourneyErrorCode must exactly bind the declared catalog'); return Object.freeze({ operations: Object.freeze(operations), schemas: Object.freeze(schemas), pendingAdditions, errorCatalog: Object.freeze(errors), errorDispositions: errors, sessionIntegrity });
}

const dartCase = (token) => token.split(/[^A-Za-z0-9]+/).filter(Boolean).map((part, index) => { const normalized = part === part.toUpperCase() ? part.toLowerCase() : `${part[0].toLowerCase()}${part.slice(1)}`; return index === 0 ? normalized : `${normalized[0].toUpperCase()}${normalized.slice(1)}`; }).join('');
const fixedEnums = [
  ['JourneyContractVersion', ['JOURNEY_SEARCH_V3']], ['JourneyErrorContractVersion', ['JOURNEY_ERROR_V1']], ['JourneySessionScope', ['journey:v3']], ['JourneyDepartureMode', ['NOW', 'SCHEDULED']], ['JourneyStatus', ['FOUND']], ['JourneyPlanSource', ['SERVER_TIMETABLE_RAPTOR']], ['JourneyTimeSource', ['TIMETABLE', 'REALTIME']], ['JourneyAccessibilityResult', ['VERIFIED']], ['JourneyLegType', ['ENTRY', 'RIDE', 'TRANSFER', 'EXIT']], ['JourneyOperation', [...expectedOperations.values()].map(({ id }) => id)],
];
const dartReservedWords = new Set(['abstract', 'as', 'assert', 'async', 'await', 'base', 'break', 'case', 'catch', 'class', 'const', 'continue', 'covariant', 'default', 'deferred', 'do', 'dynamic', 'else', 'enum', 'export', 'extends', 'extension', 'external', 'factory', 'false', 'final', 'finally', 'for', 'Function', 'get', 'hide', 'if', 'implements', 'import', 'in', 'interface', 'is', 'late', 'library', 'mixin', 'new', 'null', 'of', 'on', 'operator', 'part', 'required', 'rethrow', 'return', 'sealed', 'set', 'show', 'static', 'super', 'switch', 'sync', 'this', 'throw', 'true', 'try', 'type', 'typedef', 'var', 'void', 'when', 'while', 'with', 'yield']);
function enumDefinitions(ir) {
  const enumAt = (schemaName, property) => {
    const values = ir.schemas[schemaName]?.properties?.[property]?.enum;
    if (!Array.isArray(values) || values.length === 0) fail(`${schemaName}.${property} must be a closed string enum`);
    return values;
  };
  const itemEnumAt = (schemaName, property) => {
    const values = ir.schemas[schemaName]?.properties?.[property]?.items?.enum;
    if (!Array.isArray(values) || values.length === 0) fail(`${schemaName}.${property} items must be a closed string enum`);
    return values;
  };
  const stationSchemaNames = ['StationTimetableServiceDateSelector', 'StationTimetableDayTypeSelector', 'StationTimetableNextDeparturesSelector', 'StationTimetableDeparture', 'StationTimetableSearchSuccess'];
  const hasStationTimetableSchemas = stationSchemaNames.every((name) => name in ir.schemas);
  const stationSelectorKinds = hasStationTimetableSchemas ? [
    ...enumAt('StationTimetableServiceDateSelector', 'kind'),
    ...enumAt('StationTimetableDayTypeSelector', 'kind'),
    ...enumAt('StationTimetableNextDeparturesSelector', 'kind'),
  ] : [];
  const definitions = [
    ...fixedEnums,
    ...(hasStationTimetableSchemas ? [
      ['StationTimetableSelectorKind', stationSelectorKinds],
      ['StationTimetableDayType', enumAt('StationTimetableDayTypeSelector', 'dayType')],
      ['StationTimetableServicePattern', enumAt('StationTimetableDeparture', 'servicePattern')],
      ['StationTimetableServiceClass', enumAt('StationTimetableDeparture', 'serviceClass')],
      ['StationTimetableSearchContractVersion', enumAt('StationTimetableSearchSuccess', 'contractVersion')],
      ['StationTimetableServiceTimezone', enumAt('StationTimetableSearchSuccess', 'serviceTimezone')],
    ] : []),
    ['JourneyErrorSemanticCategory', [...new Set(ir.errorDispositions.map((entry) => entry.semanticCategory))]],
    ['JourneyErrorActionKey', [...new Set(ir.errorDispositions.map((entry) => entry.primaryActionKey).filter((value) => value !== null))]],
    ...('JourneyPlatformGap' in ir.schemas ? [
      ['PlatformGapGrade', enumAt('JourneyPlatformGap', 'gapGrade')],
      ['PlatformHeightDiffGrade', enumAt('JourneyPlatformGap', 'heightDiffGrade')],
    ] : []),
    ...('JourneyAlightingCarDoor' in ir.schemas ? [
      ['AlightingTargetFacilityType', enumAt('JourneyAlightingCarDoor', 'targetFacilityType')],
    ] : []),
    ...('JourneyRideStop' in ir.schemas ? [
      ['JourneyServicePattern', enumAt('JourneyRideLeg', 'servicePattern')],
    ] : []),
    ...('JourneyFare' in ir.schemas ? [
      ['JourneyFareStatus', enumAt('JourneyFare', 'status')],
    ] : []),
    ...('JourneyStairFreeAlternative' in ir.schemas ? [
      ['JourneyStairFreeAlternativeStatus', enumAt('JourneyStairFreeAlternative', 'status')],
      ['JourneyStairFreeFacilityStatus', enumAt('JourneyStairFreeAlternative', 'facilityStatus')],
    ] : []),
    ...(ir.schemas.Journey?.properties?.alternativeCategories ? [
      ['JourneyAlternativeCategory', itemEnumAt('Journey', 'alternativeCategories')],
    ] : []),
    ...Object.entries(ir.schemas).filter(([, schema]) => schema.type === 'string' && Array.isArray(schema.enum)),
  ];
  const names = new Set();
  for (const [name, schemaOrTokens] of definitions) {
    if (names.has(name)) fail(`generated enum name collision ${name}`);
    names.add(name);
    const tokens = Array.isArray(schemaOrTokens) ? schemaOrTokens : schemaOrTokens.enum;
    const identifiers = new Set();
    for (const token of tokens) {
      const identifier = dartCase(token);
      if (!/^[a-z][A-Za-z0-9]*$/.test(identifier) || dartReservedWords.has(identifier) || identifiers.has(identifier)) fail(`generated enum token collision ${name}`);
      identifiers.add(identifier);
    }
  }
  return definitions;
}
function renderEnums(ir) {
  const definitions = enumDefinitions(ir);
  return `// Generated closed Journey V3 wire enums.\n${definitions.map(([name, schemaOrTokens]) => { const tokens = Array.isArray(schemaOrTokens) ? schemaOrTokens : schemaOrTokens.enum; return `enum ${name} {\n${tokens.map((token) => `  ${dartCase(token)},`).join('\n')}\n}\n\nextension ${name}Wire on ${name} {\n  String get wire => switch (this) {\n${tokens.map((token) => `    ${name}.${dartCase(token)} => '${token}',`).join('\n')}\n  };\n  static ${name} fromWire(Object? value) {\n    if (value is! String) throw const FormatException('wire value must be string');\n    return switch (value) {\n${tokens.map((token) => `      '${token}' => ${name}.${dartCase(token)},`).join('\n')}\n      _ => throw const FormatException('unrecognized wire value'),\n    };\n  }\n}\n`; }).join('\n')}`;
}
function renderDartEnums(ir) { let source = renderEnums(ir); for (const [, schemaOrTokens] of enumDefinitions(ir)) for (const token of (Array.isArray(schemaOrTokens) ? schemaOrTokens : schemaOrTokens.enum)) source = source.replaceAll(`'${token}'`, dartLiteral(token)); return source; }
function renderValidation() {
  return `// Generated strict Journey V3 JSON validation helpers.\nclass JourneyDate {\n  final String value;\n  const JourneyDate._(this.value);\n  factory JourneyDate.parse(Object? value) {\n    if (value is! String || !RegExp(r'^\\d{4}-\\d{2}-\\d{2}$').hasMatch(value)) throw const FormatException('invalid JourneyDate');\n    final year = int.parse(value.substring(0, 4)); final month = int.parse(value.substring(5, 7)); final day = int.parse(value.substring(8, 10));\n    final date = DateTime.utc(year, month, day);\n    if (date.year != year || date.month != month || date.day != day) throw const FormatException('invalid JourneyDate');\n    return JourneyDate._(value);\n  }\n  @override String toString() => value;\n}\n\nabstract final class JourneyV3Validation {\n  static void exactKeys(Map<String, Object?> value, Set<String> keys) {\n    if (value.length != keys.length || !value.keys.toSet().containsAll(keys)) throw const FormatException('unexpected JSON keys');\n  }\n  static String string(Object? value, String field) { if (value is! String) throw FormatException('$field must be string'); return value; }\n  static String nonBlank(Object? value, String field) { final text = string(value, field); if (text.trim().isEmpty) throw FormatException('$field must be nonblank'); return text; }\n  static String matching(Object? value, String field, RegExp pattern) { final text = string(value, field); if (!pattern.hasMatch(text)) throw FormatException('$field has invalid format'); return text; }\n  static String ulid(Object? value, String field) => matching(value, field, RegExp(r'^[0-7][0-9A-HJKMNP-TV-Z]{25}$'));\n  static String sha256(Object? value, String field) => matching(value, field, RegExp(r'^[a-f0-9]{64}$'));\n  static int integer(Object? value, String field, int minimum, [int? maximum]) { if (value is! int || value < minimum || (maximum != null && value > maximum)) throw FormatException('$field outside range'); return value; }\n  static bool boolean(Object? value, String field) { if (value is! bool) throw FormatException('$field must be bool'); return value; }\n  static T enumWire<T>(Object? value, String field, T Function(Object?) parse) { try { return parse(value); } on FormatException { throw FormatException('$field has unrecognized wire value'); } }\n  static DateTime rfc3339(Object? value, String field) { final text = string(value, field); if (!RegExp(r'^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}(?:\\.\\d+)?(?:Z|[+-]\\d{2}:\\d{2})$').hasMatch(text)) throw FormatException('$field must be RFC3339 offset/Z'); try { return DateTime.parse(text); } on FormatException { throw FormatException('$field must be RFC3339 offset/Z'); } }\n  static String rfc3339Wire(DateTime value) => value.toIso8601String();\n  static T? nullable<T>(Map<String, Object?> json, String key, T Function(Object?) parse) { if (!json.containsKey(key)) throw FormatException('$key is required'); final value = json[key]; return value == null ? null : parse(value); }\n  static List<T> list<T>(Object? value, String field, T Function(Object?) parse, {int minimum = 0, int? maximum, bool unique = false}) { if (value is! List || value.length < minimum || (maximum != null && value.length > maximum)) throw FormatException('$field has invalid cardinality'); final parsed = value.map(parse).toList(growable: false); if (unique && parsed.toSet().length != parsed.length) throw FormatException('$field must be unique'); return List<T>.unmodifiable(parsed); }\n}\n`;
}
function replaceSection(source, start, end, replacement) {
  const startIndex = source.indexOf(start);
  const endIndex = source.indexOf(end, startIndex);
  if (startIndex < 0 || endIndex < 0) fail('generated source anchor is missing');
  return `${source.slice(0, startIndex)}${replacement}${source.slice(endIndex)}`;
}
function renderStrictValidation() {
  return replaceSection(renderValidation(), '  static DateTime rfc3339(', '  static T? nullable', String.raw`  static DateTime rfc3339(Object? value, String field) {
    final text = string(value, field);
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$').firstMatch(text);
    if (match == null) throw const FormatException('invalid RFC3339 date-time');
    final year = int.parse(match.group(1)!); final month = int.parse(match.group(2)!); final day = int.parse(match.group(3)!);
    final hour = int.parse(match.group(4)!); final minute = int.parse(match.group(5)!); final second = int.parse(match.group(6)!);
    if (hour > 23 || minute > 59 || second > 59) throw const FormatException('invalid RFC3339 date-time');
    final calendar = DateTime.utc(year, month, day, hour, minute, second);
    if (calendar.year != year || calendar.month != month || calendar.day != day || calendar.hour != hour || calendar.minute != minute || calendar.second != second) { throw const FormatException('invalid RFC3339 date-time'); }
    if (!text.endsWith('Z')) {
      final offset = RegExp(r'([+-])(\d{2}):(\d{2})$').firstMatch(text);
      if (offset == null || int.parse(offset.group(2)!) > 23 || int.parse(offset.group(3)!) > 59) throw const FormatException('invalid RFC3339 offset');
    }
    try { return DateTime.parse(text); } on FormatException { throw const FormatException('invalid RFC3339 date-time'); }
  }
  static String rfc3339Wire(DateTime value) => value.toUtc().toIso8601String();
`);
}
function renderRequestModels() {
  return `// Generated strict Journey V3 request models.\nimport 'journey_v3_enums.dart';\nimport 'journey_v3_validation.dart';\n\nclass JourneySessionRequest {\n  final String integrityToken;\n  final String clientNonce;\n  const JourneySessionRequest({required this.integrityToken, required this.clientNonce});\n  factory JourneySessionRequest.fromJson(Map<String, Object?> json) {\n    JourneyV3Validation.exactKeys(json, {'integrityToken', 'clientNonce'});\n    final integrityToken = JourneyV3Validation.string(json['integrityToken'], 'integrityToken');\n    if (integrityToken.isEmpty || integrityToken.length > 16384) throw const FormatException('integrityToken length');\n    return JourneySessionRequest(integrityToken: integrityToken, clientNonce: JourneyV3Validation.matching(json['clientNonce'], 'clientNonce', RegExp(r'^[A-Za-z0-9_-]{22}$')));\n  }\n  Map<String, Object?> toJson() => {'integrityToken': integrityToken, 'clientNonce': clientNonce};\n}\n\nclass JourneySessionResponse {\n  final String token; final JourneySessionScope scope; final DateTime issuedAt; final DateTime expiresAt;\n  const JourneySessionResponse({required this.token, required this.scope, required this.issuedAt, required this.expiresAt});\n  factory JourneySessionResponse.fromJson(Map<String, Object?> json) {\n    JourneyV3Validation.exactKeys(json, {'token', 'scope', 'issuedAt', 'expiresAt'});\n    return JourneySessionResponse(token: JourneyV3Validation.nonBlank(json['token'], 'token'), scope: JourneySessionScopeWire.fromWire(json['scope']), issuedAt: JourneyV3Validation.rfc3339(json['issuedAt'], 'issuedAt'), expiresAt: JourneyV3Validation.rfc3339(json['expiresAt'], 'expiresAt'));\n  }\n  Map<String, Object?> toJson() => {'token': token, 'scope': scope.wire, 'issuedAt': JourneyV3Validation.rfc3339Wire(issuedAt), 'expiresAt': JourneyV3Validation.rfc3339Wire(expiresAt)};\n}\n\nsealed class JourneyDeparture {\n  const JourneyDeparture();\n  Map<String, Object?> toJson();\n  static JourneyDeparture fromJson(Map<String, Object?> json) {\n    final mode = JourneyDepartureModeWire.fromWire(json['mode']);\n    return switch (mode) { JourneyDepartureMode.now => JourneyDepartureNow.fromJson(json), JourneyDepartureMode.scheduled => JourneyDepartureScheduled.fromJson(json) };\n  }\n}\nclass JourneyDepartureNow extends JourneyDeparture {\n  const JourneyDepartureNow();\n  factory JourneyDepartureNow.fromJson(Map<String, Object?> json) { JourneyV3Validation.exactKeys(json, {'mode'}); if (JourneyDepartureModeWire.fromWire(json['mode']) != JourneyDepartureMode.now) throw const FormatException('departure mode'); return const JourneyDepartureNow(); }\n  @override Map<String, Object?> toJson() => {'mode': JourneyDepartureMode.now.wire};\n}\nclass JourneyDepartureScheduled extends JourneyDeparture {\n  final DateTime requestedAt; const JourneyDepartureScheduled(this.requestedAt);\n  factory JourneyDepartureScheduled.fromJson(Map<String, Object?> json) { JourneyV3Validation.exactKeys(json, {'mode', 'requestedAt'}); if (JourneyDepartureModeWire.fromWire(json['mode']) != JourneyDepartureMode.scheduled) throw const FormatException('departure mode'); return JourneyDepartureScheduled(JourneyV3Validation.rfc3339(json['requestedAt'], 'requestedAt')); }\n  @override Map<String, Object?> toJson() => {'mode': JourneyDepartureMode.scheduled.wire, 'requestedAt': JourneyV3Validation.rfc3339Wire(requestedAt)};\n}\n\nclass JourneySearchRequest {\n  final String requestId; final String originStationId; final String destinationStationId; final JourneyDeparture departure; final TimePolicy timePolicy; final MobilityProfile mobilityProfile; final ConstraintMode constraintMode; final int maxTransfers; final int alternativeCount;\n  const JourneySearchRequest({required this.requestId, required this.originStationId, required this.destinationStationId, required this.departure, required this.timePolicy, required this.mobilityProfile, required this.constraintMode, required this.maxTransfers, required this.alternativeCount});\n  factory JourneySearchRequest.fromJson(Map<String, Object?> json) {\n    JourneyV3Validation.exactKeys(json, {'requestId', 'originStationId', 'destinationStationId', 'departure', 'timePolicy', 'mobilityProfile', 'constraintMode', 'maxTransfers', 'alternativeCount'});\n    final mobilityProfile = MobilityProfileWire.fromWire(json['mobilityProfile']); final constraintMode = ConstraintModeWire.fromWire(json['constraintMode']);\n    if (mobilityProfile == MobilityProfile.noStairs && constraintMode == ConstraintMode.none) throw const FormatException('NO_STAIRS plus NONE is forbidden');\n    final departureValue = json['departure']; if (departureValue is! Map<String, Object?>) throw const FormatException('departure must be object');\n    return JourneySearchRequest(requestId: JourneyV3Validation.ulid(json['requestId'], 'requestId'), originStationId: JourneyV3Validation.nonBlank(json['originStationId'], 'originStationId'), destinationStationId: JourneyV3Validation.nonBlank(json['destinationStationId'], 'destinationStationId'), departure: JourneyDeparture.fromJson(departureValue), timePolicy: TimePolicyWire.fromWire(json['timePolicy']), mobilityProfile: mobilityProfile, constraintMode: constraintMode, maxTransfers: JourneyV3Validation.integer(json['maxTransfers'], 'maxTransfers', 0, 3), alternativeCount: JourneyV3Validation.integer(json['alternativeCount'], 'alternativeCount', 1, 3));\n  }\n  Map<String, Object?> toJson() => {'requestId': requestId, 'originStationId': originStationId, 'destinationStationId': destination.toJson(), 'timePolicy': timePolicy.wire, 'mobilityProfile': mobilityProfile.wire, 'constraintMode': constraintMode.wire, 'maxTransfers': maxTransfers, 'alternativeCount': alternativeCount};\n}\n`;
}
function replaceRequired(source, anchor, replacement, label) { if (!source.includes(anchor)) fail(`${label} renderer anchor is missing`); return source.replace(anchor, replacement); }
function renderCorrectedRequestModels() { return replaceRequired(renderRequestModels(), "'destinationStationId': destination.toJson()", "'destinationStationId': destinationStationId, 'departure': departure.toJson()", 'request'); }
function renderValidatedRequestModels() {
  const validated = replaceRequired(replaceRequired(renderCorrectedRequestModels(), 'const JourneySessionRequest({required this.integrityToken, required this.clientNonce});', `const JourneySessionRequest._({required this.integrityToken, required this.clientNonce});
  factory JourneySessionRequest({required String integrityToken, required String clientNonce}) {
    if (integrityToken.isEmpty || integrityToken.length > 16384) throw const FormatException('integrityToken length');
    return JourneySessionRequest._(integrityToken: integrityToken, clientNonce: JourneyV3Validation.matching(clientNonce, 'clientNonce', RegExp(r'^[A-Za-z0-9_-]{22}(?![\\s\\S])')));
  }`, 'session request'), 'const JourneySearchRequest({required this.requestId, required this.originStationId, required this.destinationStationId, required this.departure, required this.timePolicy, required this.mobilityProfile, required this.constraintMode, required this.maxTransfers, required this.alternativeCount});', `const JourneySearchRequest._({required this.requestId, required this.originStationId, required this.destinationStationId, required this.departure, required this.timePolicy, required this.mobilityProfile, required this.constraintMode, required this.maxTransfers, required this.alternativeCount});
  factory JourneySearchRequest({required String requestId, required String originStationId, required String destinationStationId, required JourneyDeparture departure, required TimePolicy timePolicy, required MobilityProfile mobilityProfile, required ConstraintMode constraintMode, required int maxTransfers, required int alternativeCount}) {
    if (mobilityProfile == MobilityProfile.noStairs && constraintMode == ConstraintMode.none) throw const FormatException('NO_STAIRS plus NONE is forbidden');
    return JourneySearchRequest._(requestId: JourneyV3Validation.ulid(requestId, 'requestId'), originStationId: JourneyV3Validation.nonBlank(originStationId, 'originStationId'), destinationStationId: JourneyV3Validation.nonBlank(destinationStationId, 'destinationStationId'), departure: departure, timePolicy: timePolicy, mobilityProfile: mobilityProfile, constraintMode: constraintMode, maxTransfers: JourneyV3Validation.integer(maxTransfers, 'maxTransfers', 0, 3), alternativeCount: JourneyV3Validation.integer(alternativeCount, 'alternativeCount', 1, 3));
  }`, 'search request');
  const withJsonNoncePattern = replaceRequired(validated, "RegExp(r'^[A-Za-z0-9_-]{22}", "RegExp(r'^[A-Za-z0-9_-]{21}[AQgw]", 'session request JSON nonce');
  let source = replaceRequired(withJsonNoncePattern, "RegExp(r'^[A-Za-z0-9_-]{22}", "RegExp(r'^[A-Za-z0-9_-]{21}[AQgw]", 'session request constructor nonce');
  source = replaceRequired(source, 'final JourneyDeparture departure; final TimePolicy timePolicy; final MobilityProfile mobilityProfile;', 'final JourneyDeparture departure; final TimePolicy timePolicy; final WalkingPace walkingPace; final MobilityProfile mobilityProfile;', 'search request walking pace field');
  source = replaceRequired(source, 'required this.timePolicy, required this.mobilityProfile', 'required this.timePolicy, required this.walkingPace, required this.mobilityProfile', 'search request walking pace constructor');
  source = replaceRequired(source, 'required TimePolicy timePolicy, required MobilityProfile mobilityProfile', 'required TimePolicy timePolicy, required WalkingPace walkingPace, required MobilityProfile mobilityProfile', 'search request walking pace factory');
  source = replaceRequired(source, 'departure: departure, timePolicy: timePolicy, mobilityProfile: mobilityProfile', 'departure: departure, timePolicy: timePolicy, walkingPace: walkingPace, mobilityProfile: mobilityProfile', 'search request walking pace construction');
  source = replaceRequired(source, "'departure', 'timePolicy', 'mobilityProfile'", "'departure', 'timePolicy', 'walkingPace', 'mobilityProfile'", 'search request walking pace JSON keys');
  source = replaceRequired(source, "timePolicy: TimePolicyWire.fromWire(json['timePolicy']), mobilityProfile: mobilityProfile", "timePolicy: TimePolicyWire.fromWire(json['timePolicy']), walkingPace: WalkingPaceWire.fromWire(json['walkingPace']), mobilityProfile: mobilityProfile", 'search request walking pace JSON parsing');
  source = replaceRequired(source, "'timePolicy': timePolicy.wire, 'mobilityProfile': mobilityProfile.wire", "'timePolicy': timePolicy.wire, 'walkingPace': walkingPace.wire, 'mobilityProfile': mobilityProfile.wire", 'search request walking pace JSON encoding');
  source = replaceRequired(source, 'final String destinationStationId; final JourneyDeparture departure;', 'final String destinationStationId; final String? viaStationId; final JourneyDeparture departure;', 'search request viaStationId field');
  source = replaceRequired(source, 'required this.destinationStationId, required this.departure,', 'required this.destinationStationId, this.viaStationId, required this.departure,', 'search request viaStationId constructor');
  source = replaceRequired(source, 'required String destinationStationId, required JourneyDeparture departure,', 'required String destinationStationId, String? viaStationId, required JourneyDeparture departure,', 'search request viaStationId factory');
  source = replaceRequired(
    source,
    "if (mobilityProfile == MobilityProfile.noStairs && constraintMode == ConstraintMode.none) throw const FormatException('NO_STAIRS plus NONE is forbidden');",
    `if (mobilityProfile == MobilityProfile.noStairs && constraintMode == ConstraintMode.none) throw const FormatException('NO_STAIRS plus NONE is forbidden');
    if (viaStationId != null) {
      if (viaStationId.trim().isEmpty) throw const FormatException('viaStationId must not be blank');
      if (viaStationId == originStationId || viaStationId == destinationStationId) {
        throw const FormatException('viaStationId cannot be originStationId or destinationStationId');
      }
    }`,
    'search request viaStationId validation'
  );
  source = replaceRequired(source, "destinationStationId: JourneyV3Validation.nonBlank(destinationStationId, 'destinationStationId'), departure: departure,", "destinationStationId: JourneyV3Validation.nonBlank(destinationStationId, 'destinationStationId'), viaStationId: viaStationId, departure: departure,", 'search request viaStationId constructor call');
  source = replaceRequired(
    source,
    "JourneyV3Validation.exactKeys(json, {'requestId', 'originStationId', 'destinationStationId', 'departure',",
    `final expectedKeys = {'requestId', 'originStationId', 'destinationStationId', if (json.containsKey('viaStationId')) 'viaStationId', 'departure',`,
    'search request viaStationId expectedKeys'
  );
  source = replaceRequired(
    source,
    "maxTransfers', 'alternativeCount'});",
    "maxTransfers', 'alternativeCount'};\n    JourneyV3Validation.exactKeys(json, expectedKeys);",
    'search request viaStationId exactKeys call'
  );
  source = replaceRequired(
    source,
    "final departureValue = json['departure']; if (departureValue is! Map<String, Object?>) throw const FormatException('departure must be object');",
    "final departureValue = json['departure']; if (departureValue is! Map<String, Object?>) throw const FormatException('departure must be object');\n    final rawVia = json['viaStationId'];",
    'search request viaStationId rawVia'
  );
  source = replaceRequired(
    source,
    "destinationStationId: JourneyV3Validation.nonBlank(json['destinationStationId'], 'destinationStationId'), departure: JourneyDeparture.fromJson(departureValue),",
    "destinationStationId: JourneyV3Validation.nonBlank(json['destinationStationId'], 'destinationStationId'), viaStationId: rawVia == null ? null : JourneyV3Validation.nonBlank(rawVia, 'viaStationId'), departure: JourneyDeparture.fromJson(departureValue),",
    'search request fromJson viaStationId'
  );
  return replaceRequired(
    source,
    "'destinationStationId': destinationStationId, 'departure': departure.toJson(),",
    "'destinationStationId': destinationStationId, if (viaStationId != null) 'viaStationId': viaStationId, 'departure': departure.toJson(),",
    'search request toJson viaStationId'
  );
}
export function renderJourneyV3ValidationAndEnumsForTest(options) { const ir = validate({ ...options, enforceTrackedLock: false }); return Object.freeze({ validation: renderStrictValidation(), enums: renderDartEnums(ir) }); }
export function renderJourneyV3RequestModelsForTest(options) { validate({ ...options, enforceTrackedLock: false }); return renderValidatedRequestModels(); }
function renderResponseModels() {
  return `// Test-only strict Journey V3 response model source; production output remains closed.\nimport 'journey_v3_enums.dart';\nimport 'journey_v3_validation.dart';\n\nabstract interface class JourneyLeg { Map<String, Object?> toJson(); static JourneyLeg fromJson(Map<String, Object?> json) => throw UnimplementedError(); }\n\nclass JourneySourceIdentity {\n final String routeBundleId; final String routeBundleSha256; final String timetableSnapshotId; final String accessibilitySnapshotId; final String? realtimeSnapshotId;\n const JourneySourceIdentity({required this.routeBundleId, required this.routeBundleSha256, required this.timetableSnapshotId, required this.accessibilitySnapshotId, required this.realtimeSnapshotId});\n factory JourneySourceIdentity.fromJson(Map<String,Object?> json) { JourneyV3Validation.exactKeys(json, {'routeBundleId','routeBundleSha256','timetableSnapshotId','accessibilitySnapshotId','realtimeSnapshotId'}); return JourneySourceIdentity(routeBundleId: JourneyV3Validation.nonBlank(json['routeBundleId'],'routeBundleId'), routeBundleSha256: JourneyV3Validation.sha256(json['routeBundleSha256'],'routeBundleSha256'), timetableSnapshotId: JourneyV3Validation.nonBlank(json['timetableSnapshotId'],'timetableSnapshotId'), accessibilitySnapshotId: JourneyV3Validation.nonBlank(json['accessibilitySnapshotId'],'accessibilitySnapshotId'), realtimeSnapshotId: JourneyV3Validation.nullable(json,'realtimeSnapshotId',(v) => JourneyV3Validation.nonBlank(v,'realtimeSnapshotId'))); }\n Map<String,Object?> toJson() => {'routeBundleId':routeBundleId,'routeBundleSha256':routeBundleSha256,'timetableSnapshotId':timetableSnapshotId,'accessibilitySnapshotId':accessibilitySnapshotId,'realtimeSnapshotId':realtimeSnapshotId};\n}\nclass JourneyRequestPolicy {\n final TimePolicy timePolicy; final MobilityProfile mobilityProfile; final ConstraintMode constraintMode; final int maxTransfers; final int alternativeCount;\n const JourneyRequestPolicy({required this.timePolicy,required this.mobilityProfile,required this.constraintMode,required this.maxTransfers,required this.alternativeCount});\n factory JourneyRequestPolicy.fromJson(Map<String,Object?> json) { JourneyV3Validation.exactKeys(json, {'timePolicy','mobilityProfile','constraintMode','maxTransfers','alternativeCount'}); final mobilityProfile=MobilityProfileWire.fromWire(json['mobilityProfile']); final constraintMode=ConstraintModeWire.fromWire(json['constraintMode']); if(mobilityProfile==MobilityProfile.noStairs&&constraintMode==ConstraintMode.none) throw const FormatException('NO_STAIRS plus NONE is forbidden'); return JourneyRequestPolicy(timePolicy:TimePolicyWire.fromWire(json['timePolicy']),mobilityProfile:mobilityProfile,constraintMode:constraintMode,maxTransfers:JourneyV3Validation.integer(json['maxTransfers'],'maxTransfers',0,3),alternativeCount:JourneyV3Validation.integer(json['alternativeCount'],'alternativeCount',1,3)); }\n Map<String,Object?> toJson()=>{'timePolicy':timePolicy.wire,'mobilityProfile':mobilityProfile.wire,'constraintMode':constraintMode.wire,'maxTransfers':maxTransfers,'alternativeCount':alternativeCount};\n}\nclass JourneyAccessibility {\n final JourneyAccessibilityResult result; final bool stairFree; final List<String> reasonCodes;\n const JourneyAccessibility({required this.result,required this.stairFree,required this.reasonCodes});\n factory JourneyAccessibility.fromJson(Map<String,Object?> json) { JourneyV3Validation.exactKeys(json, {'result','stairFree','reasonCodes'}); return JourneyAccessibility(result:JourneyAccessibilityResultWire.fromWire(json['result']),stairFree:JourneyV3Validation.boolean(json['stairFree'],'stairFree'),reasonCodes:JourneyV3Validation.list(json['reasonCodes'],'reasonCodes',(v)=>JourneyV3Validation.string(v,'reasonCode'),unique:true)); }\n Map<String,Object?> toJson()=>{'result':result.wire,'stairFree':stairFree,'reasonCodes':reasonCodes};\n}\nclass Journey {\n final String journeyId; final JourneyStatus status; final JourneyPlanSource planSource; final DateTime plannedDepartureTime; final DateTime plannedArrivalTime; final DateTime? realtimeDepartureTime; final DateTime? realtimeArrivalTime; final int durationSeconds; final int transferCount; final int walkingDistanceMeters; final JourneyTimeSource timeSource; final JourneyAccessibility accessibility; final List<JourneyLeg> legs;\n const Journey({required this.journeyId,required this.status,required this.planSource,required this.plannedDepartureTime,required this.plannedArrivalTime,required this.realtimeDepartureTime,required this.realtimeArrivalTime,required this.durationSeconds,required this.transferCount,required this.walkingDistanceMeters,required this.timeSource,required this.accessibility,required this.legs});\n factory Journey.fromJson(Map<String,Object?> json) { JourneyV3Validation.exactKeys(json, {'journeyId','status','planSource','plannedDepartureTime','plannedArrivalTime','realtimeDepartureTime','realtimeArrivalTime','durationSeconds','transferCount','walkingDistanceMeters','timeSource','accessibility','legs'}); final accessibility=json['accessibility']; if(accessibility is! Map<String,Object?>) throw const FormatException('accessibility must be object'); return Journey(journeyId:JourneyV3Validation.nonBlank(json['journeyId'],'journeyId'),status:JourneyStatusWire.fromWire(json['status']),planSource:JourneyPlanSourceWire.fromWire(json['planSource']),plannedDepartureTime:JourneyV3Validation.rfc3339(json['plannedDepartureTime'],'plannedDepartureTime'),plannedArrivalTime:JourneyV3Validation.rfc3339(json['plannedArrivalTime'],'plannedArrivalTime'),realtimeDepartureTime:JourneyV3Validation.nullable(json,'realtimeDepartureTime',(v)=>JourneyV3Validation.rfc3339(v,'realtimeDepartureTime')),realtimeArrivalTime:JourneyV3Validation.nullable(json,'realtimeArrivalTime',(v)=>JourneyV3Validation.rfc3339(v,'realtimeArrivalTime')),durationSeconds:JourneyV3Validation.integer(json['durationSeconds'],'durationSeconds',0),transferCount:JourneyV3Validation.integer(json['transferCount'],'transferCount',0,3),walkingDistanceMeters:JourneyV3Validation.integer(json['walkingDistanceMeters'],'walkingDistanceMeters',0),timeSource:JourneyTimeSourceWire.fromWire(json['timeSource']),accessibility:JourneyAccessibility.fromJson(accessibility),legs:JourneyV3Validation.list(json['legs'],'legs',(v){if(v is! Map<String,Object?>) throw const FormatException('leg must be object');return JourneyLeg.fromJson(v);},minimum:1)); }\n Map<String,Object?> toJson()=>{'journeyId':journeyId,'status':status.wire,'planSource':planSource.wire,'plannedDepartureTime':JourneyV3Validation.rfc3339Wire(plannedDepartureTime),'plannedArrivalTime':JourneyV3Validation.rfc3339Wire(plannedArrivalTime),'realtimeDepartureTime':realtimeDepartureTime==null?null:JourneyV3Validation.rfc3339Wire(realtimeDepartureTime!),'realtimeArrivalTime':realtimeArrivalTime==null?null:JourneyV3Validation.rfc3339Wire(realtimeArrivalTime!),'durationSeconds':durationSeconds,'transferCount':transferCount,'walkingDistanceMeters':walkingDistanceMeters,'timeSource':timeSource.wire,'accessibility':accessibility.toJson(),'legs':legs.map((v)=>v.toJson()).toList(growable:false)};\n}\nclass JourneySearchSuccess {\n final JourneyContractVersion contractVersion; final String requestId; final String queryId; final DateTime calculatedAt; final DateTime validUntil; final DateTime effectiveDepartureTime; final JourneyDate serviceDate; final String serviceTimezone; final JourneySourceIdentity sourceIdentity; final JourneyRequestPolicy requestPolicy; final List<Journey> journeys;\n const JourneySearchSuccess({required this.contractVersion,required this.requestId,required this.queryId,required this.calculatedAt,required this.validUntil,required this.effectiveDepartureTime,required this.serviceDate,required this.serviceTimezone,required this.sourceIdentity,required this.requestPolicy,required this.journeys});\n factory JourneySearchSuccess.fromJson(Map<String,Object?> json) { JourneyV3Validation.exactKeys(json, {'contractVersion','requestId','queryId','calculatedAt','validUntil','effectiveDepartureTime','serviceDate','serviceTimezone','sourceIdentity','requestPolicy','journeys'}); final sourceIdentity=json['sourceIdentity']; final requestPolicy=json['requestPolicy']; if(sourceIdentity is! Map<String,Object?>||requestPolicy is! Map<String,Object?>) throw const FormatException('nested response must be object'); final policy=JourneyRequestPolicy.fromJson(requestPolicy); final journeys=JourneyV3Validation.list(json['journeys'],'journeys',(v){if(v is! Map<String,Object?>) throw const FormatException('journey must be object');return Journey.fromJson(v);},minimum:1,maximum:3); for(final journey in journeys){if(policy.timePolicy==TimePolicy.timetableRequired&&(journey.realtimeDepartureTime!=null||journey.realtimeArrivalTime!=null||journey.timeSource!=JourneyTimeSource.timetable)) throw const FormatException('TIMETABLE_REQUIRED realtime contract'); if(policy.timePolicy==TimePolicy.realtimeRequired&&(journey.realtimeDepartureTime==null||journey.realtimeArrivalTime==null||journey.timeSource!=JourneyTimeSource.realtime)) throw const FormatException('REALTIME_REQUIRED realtime contract');} return JourneySearchSuccess(contractVersion:JourneyContractVersionWire.fromWire(json['contractVersion']),requestId:JourneyV3Validation.ulid(json['requestId'],'requestId'),queryId:JourneyV3Validation.nonBlank(json['queryId'],'queryId'),calculatedAt:JourneyV3Validation.rfc3339(json['calculatedAt'],'calculatedAt'),validUntil:JourneyV3Validation.rfc3339(json['validUntil'],'validUntil'),effectiveDepartureTime:JourneyV3Validation.rfc3339(json['effectiveDepartureTime'],'effectiveDepartureTime'),serviceDate:JourneyDate.parse(json['serviceDate']),serviceTimezone:JourneyV3Validation.enumWire(json['serviceTimezone'],'serviceTimezone',(v){if(v!='Asia/Seoul') throw const FormatException(); return 'Asia/Seoul';}),sourceIdentity:JourneySourceIdentity.fromJson(sourceIdentity),requestPolicy:policy,journeys:journeys); }\n Map<String,Object?> toJson()=>{'contractVersion':contractVersion.wire,'requestId':requestId,'queryId':queryId,'calculatedAt':JourneyV3Validation.rfc3339Wire(calculatedAt),'validUntil':JourneyV3Validation.rfc3339Wire(validUntil),'effectiveDepartureTime':JourneyV3Validation.rfc3339Wire(effectiveDepartureTime),'serviceDate':serviceDate.toString(),'serviceTimezone':serviceTimezone,'sourceIdentity':sourceIdentity.toJson(),'requestPolicy':requestPolicy.toJson(),'journeys':journeys.map((v)=>v.toJson()).toList(growable:false)};\n}\n`;
}
function renderWalkingPaceResponseModels(source) {
  source = replaceRequired(source, 'final TimePolicy timePolicy; final MobilityProfile mobilityProfile;', 'final TimePolicy timePolicy; final WalkingPace walkingPace; final MobilityProfile mobilityProfile;', 'response policy walking pace field');
  source = replaceRequired(source, 'required this.timePolicy,required this.mobilityProfile', 'required this.timePolicy,required this.walkingPace,required this.mobilityProfile', 'response policy walking pace constructor');
  source = replaceRequired(source, "{'timePolicy','mobilityProfile','constraintMode','maxTransfers','alternativeCount'}", "{'timePolicy','walkingPace','mobilityProfile','constraintMode','maxTransfers','alternativeCount'}", 'response policy walking pace JSON keys');
  source = replaceRequired(source, "timePolicy:TimePolicyWire.fromWire(json['timePolicy']),mobilityProfile:mobilityProfile", "timePolicy:TimePolicyWire.fromWire(json['timePolicy']),walkingPace:WalkingPaceWire.fromWire(json['walkingPace']),mobilityProfile:mobilityProfile", 'response policy walking pace JSON parsing');
  return replaceRequired(source, "{'timePolicy':timePolicy.wire,'mobilityProfile':mobilityProfile.wire", "{'timePolicy':timePolicy.wire,'walkingPace':walkingPace.wire,'mobilityProfile':mobilityProfile.wire", 'response policy walking pace JSON encoding');
}
export function renderJourneyV3ResponseModelsForTest(options) { validate({ ...options, enforceTrackedLock: false }); return renderWalkingPaceResponseModels(renderResponseModels()); }

function renderLegModels() {
  return `sealed class JourneyLeg {
  const JourneyLeg();
  Map<String, Object?> toJson();
  static JourneyLeg fromJson(Map<String, Object?> json) {
    final type = JourneyLegTypeWire.fromWire(json['type']);
    return switch (type) {
      JourneyLegType.entry => JourneyEntryLeg.fromJson(json),
      JourneyLegType.ride => JourneyRideLeg.fromJson(json),
      JourneyLegType.transfer => JourneyTransferLeg.fromJson(json),
      JourneyLegType.exit => JourneyExitLeg.fromJson(json),
    };
  }
}

class JourneyEntryLeg extends JourneyLeg {
  final String fromStationId;
  final int durationSeconds;
  const JourneyEntryLeg({required this.fromStationId, required this.durationSeconds});
  factory JourneyEntryLeg.fromJson(Map<String, Object?> json) {
    JourneyV3Validation.exactKeys(json, {'type', 'fromStationId', 'durationSeconds'});
    if (JourneyLegTypeWire.fromWire(json['type']) != JourneyLegType.entry) throw const FormatException('leg type');
    return JourneyEntryLeg(fromStationId: JourneyV3Validation.nonBlank(json['fromStationId'], 'fromStationId'), durationSeconds: JourneyV3Validation.integer(json['durationSeconds'], 'durationSeconds', 0));
  }
  @override Map<String, Object?> toJson() => {'type': JourneyLegType.entry.wire, 'fromStationId': fromStationId, 'durationSeconds': durationSeconds};
}

class JourneyPlatformGap {
  final String platformPosition;
  final int? carNumber;
  final int? doorNumber;
  final PlatformGapGrade gapGrade;
  final PlatformHeightDiffGrade heightDiffGrade;
  final bool curved;
  const JourneyPlatformGap({required this.platformPosition, this.carNumber, this.doorNumber, required this.gapGrade, required this.heightDiffGrade, required this.curved});
  factory JourneyPlatformGap.fromJson(Map<String, Object?> json) {
    final expectedKeys = {
      'platformPosition',
      if (json.containsKey('carNumber')) 'carNumber',
      if (json.containsKey('doorNumber')) 'doorNumber',
      'gapGrade',
      'heightDiffGrade',
      'curved',
    };
    JourneyV3Validation.exactKeys(json, expectedKeys);
    final rawCarNumber = json['carNumber'];
    final rawDoorNumber = json['doorNumber'];
    return JourneyPlatformGap(
      platformPosition: JourneyV3Validation.nonBlank(json['platformPosition'], 'platformPosition'),
      carNumber: rawCarNumber == null ? null : JourneyV3Validation.integer(rawCarNumber, 'carNumber', 1),
      doorNumber: rawDoorNumber == null ? null : JourneyV3Validation.integer(rawDoorNumber, 'doorNumber', 1),
      gapGrade: PlatformGapGradeWire.fromWire(json['gapGrade']),
      heightDiffGrade: PlatformHeightDiffGradeWire.fromWire(json['heightDiffGrade']),
      curved: JourneyV3Validation.boolean(json['curved'], 'curved'),
    );
  }
  Map<String, Object?> toJson() => {
    'platformPosition': platformPosition,
    if (carNumber != null) 'carNumber': carNumber,
    if (doorNumber != null) 'doorNumber': doorNumber,
    'gapGrade': gapGrade.wire,
    'heightDiffGrade': heightDiffGrade.wire,
    'curved': curved,
  };
}

typedef JourneyPlatformGapGrade = PlatformGapGrade;
typedef JourneyPlatformHeightDiffGrade = PlatformHeightDiffGrade;

class JourneyAlightingCarDoor {
  final int carNumber;
  final int doorNumber;
  final AlightingTargetFacilityType targetFacilityType;
  const JourneyAlightingCarDoor({required this.carNumber, required this.doorNumber, required this.targetFacilityType});
  factory JourneyAlightingCarDoor.fromJson(Map<String, Object?> json) {
    JourneyV3Validation.exactKeys(json, {'carNumber', 'doorNumber', 'targetFacilityType'});
    return JourneyAlightingCarDoor(
      carNumber: JourneyV3Validation.integer(json['carNumber'], 'carNumber', 1, 10),
      doorNumber: JourneyV3Validation.integer(json['doorNumber'], 'doorNumber', 1, 4),
      targetFacilityType: AlightingTargetFacilityTypeWire.fromWire(json['targetFacilityType']),
    );
  }
  Map<String, Object?> toJson() => {
    'carNumber': carNumber,
    'doorNumber': doorNumber,
    'targetFacilityType': targetFacilityType.wire,
  };
}

typedef JourneyAlightingTargetFacilityType = AlightingTargetFacilityType;

class JourneyRideStop {
  final String stationId;
  final DateTime? plannedArrivalTime;
  final DateTime? plannedDepartureTime;
  final DateTime? realtimeArrivalTime;
  final DateTime? realtimeDepartureTime;
  const JourneyRideStop({required this.stationId, required this.plannedArrivalTime, required this.plannedDepartureTime, required this.realtimeArrivalTime, required this.realtimeDepartureTime});
  factory JourneyRideStop.fromJson(Map<String, Object?> json) {
    JourneyV3Validation.exactKeys(json, {'stationId', 'plannedArrivalTime', 'plannedDepartureTime', 'realtimeArrivalTime', 'realtimeDepartureTime'});
    return JourneyRideStop(
      stationId: JourneyV3Validation.nonBlank(json['stationId'], 'stationId'),
      plannedArrivalTime: JourneyV3Validation.nullable(json, 'plannedArrivalTime', (value) => JourneyV3Validation.rfc3339(value, 'plannedArrivalTime')),
      plannedDepartureTime: JourneyV3Validation.nullable(json, 'plannedDepartureTime', (value) => JourneyV3Validation.rfc3339(value, 'plannedDepartureTime')),
      realtimeArrivalTime: JourneyV3Validation.nullable(json, 'realtimeArrivalTime', (value) => JourneyV3Validation.rfc3339(value, 'realtimeArrivalTime')),
      realtimeDepartureTime: JourneyV3Validation.nullable(json, 'realtimeDepartureTime', (value) => JourneyV3Validation.rfc3339(value, 'realtimeDepartureTime')),
    );
  }
  Map<String, Object?> toJson() => {
    'stationId': stationId,
    'plannedArrivalTime': plannedArrivalTime == null ? null : JourneyV3Validation.rfc3339Wire(plannedArrivalTime!),
    'plannedDepartureTime': plannedDepartureTime == null ? null : JourneyV3Validation.rfc3339Wire(plannedDepartureTime!),
    'realtimeArrivalTime': realtimeArrivalTime == null ? null : JourneyV3Validation.rfc3339Wire(realtimeArrivalTime!),
    'realtimeDepartureTime': realtimeDepartureTime == null ? null : JourneyV3Validation.rfc3339Wire(realtimeDepartureTime!),
  };
}

class JourneyFare {
  final JourneyFareStatus status;
  final int? adultCardWon;
  final int? adultCashWon;
  final int? youthCardWon;
  final int? youthCashWon;
  final int? childCardWon;
  final int? childCashWon;
  final List<String> sourceSnapshotIds;
  const JourneyFare({required this.status, this.adultCardWon, this.adultCashWon, this.youthCardWon, this.youthCashWon, this.childCardWon, this.childCashWon, required this.sourceSnapshotIds});
  factory JourneyFare.fromJson(Map<String, Object?> json) {
    const amountKeys = ['adultCardWon', 'adultCashWon', 'youthCardWon', 'youthCashWon', 'childCardWon', 'childCashWon'];
    JourneyV3Validation.exactKeys(json, {'status', for (final key in amountKeys) if (json.containsKey(key)) key, 'sourceSnapshotIds'});
    int? amount(String key) => json.containsKey(key) ? JourneyV3Validation.integer(json[key], key, 0) : null;
    return JourneyFare(
      status: JourneyFareStatusWire.fromWire(json['status']),
      adultCardWon: amount('adultCardWon'),
      adultCashWon: amount('adultCashWon'),
      youthCardWon: amount('youthCardWon'),
      youthCashWon: amount('youthCashWon'),
      childCardWon: amount('childCardWon'),
      childCashWon: amount('childCashWon'),
      sourceSnapshotIds: JourneyV3Validation.list(json['sourceSnapshotIds'], 'sourceSnapshotIds', (v) => JourneyV3Validation.string(v, 'sourceSnapshotIds')),
    );
  }
  Map<String, Object?> toJson() => {
    'status': status.wire,
    if (adultCardWon != null) 'adultCardWon': adultCardWon,
    if (adultCashWon != null) 'adultCashWon': adultCashWon,
    if (youthCardWon != null) 'youthCardWon': youthCardWon,
    if (youthCashWon != null) 'youthCashWon': youthCashWon,
    if (childCardWon != null) 'childCardWon': childCardWon,
    if (childCashWon != null) 'childCashWon': childCashWon,
    'sourceSnapshotIds': sourceSnapshotIds,
  };
}

class JourneyRideLeg extends JourneyLeg {
  final String lineId; final String tripId; final String directionStationId; final String fromStationId; final String toStationId;
  final DateTime plannedDepartureTime; final DateTime plannedArrivalTime; final DateTime? realtimeDepartureTime; final DateTime? realtimeArrivalTime;
  final JourneyServicePattern servicePattern; final List<JourneyRideStop> stops;
  final List<JourneyAlightingCarDoor> alightingCarDoors; final List<JourneyPlatformGap> boardingPlatformGaps; final List<JourneyPlatformGap> alightingPlatformGaps;
  const JourneyRideLeg({
    required this.lineId,
    required this.tripId,
    required this.directionStationId,
    required this.fromStationId,
    required this.toStationId,
    required this.plannedDepartureTime,
    required this.plannedArrivalTime,
    required this.realtimeDepartureTime,
    required this.realtimeArrivalTime,
    required this.servicePattern,
    required this.stops,
    this.alightingCarDoors = const [],
    this.boardingPlatformGaps = const [],
    this.alightingPlatformGaps = const [],
  });
  factory JourneyRideLeg.fromJson(Map<String, Object?> json) {
    final expectedKeys = {
      'type',
      'lineId',
      'tripId',
      'directionStationId',
      'fromStationId',
      'toStationId',
      'plannedDepartureTime',
      'plannedArrivalTime',
      'realtimeDepartureTime',
      'realtimeArrivalTime',
      'servicePattern',
      'stops',
      if (json.containsKey('alightingCarDoors')) 'alightingCarDoors',
      if (json.containsKey('boardingPlatformGaps')) 'boardingPlatformGaps',
      if (json.containsKey('alightingPlatformGaps')) 'alightingPlatformGaps',
    };
    JourneyV3Validation.exactKeys(json, expectedKeys);
    if (JourneyLegTypeWire.fromWire(json['type']) != JourneyLegType.ride) throw const FormatException('leg type');
    final rawAlightingCarDoors = json['alightingCarDoors'];
    final rawBoardingPlatformGaps = json['boardingPlatformGaps'];
    final rawAlightingPlatformGaps = json['alightingPlatformGaps'];
    return JourneyRideLeg(
      lineId: JourneyV3Validation.nonBlank(json['lineId'], 'lineId'),
      tripId: JourneyV3Validation.nonBlank(json['tripId'], 'tripId'),
      directionStationId: JourneyV3Validation.nonBlank(json['directionStationId'], 'directionStationId'),
      fromStationId: JourneyV3Validation.nonBlank(json['fromStationId'], 'fromStationId'),
      toStationId: JourneyV3Validation.nonBlank(json['toStationId'], 'toStationId'),
      plannedDepartureTime: JourneyV3Validation.rfc3339(json['plannedDepartureTime'], 'plannedDepartureTime'),
      plannedArrivalTime: JourneyV3Validation.rfc3339(json['plannedArrivalTime'], 'plannedArrivalTime'),
      realtimeDepartureTime: JourneyV3Validation.nullable(json, 'realtimeDepartureTime', (value) => JourneyV3Validation.rfc3339(value, 'realtimeDepartureTime')),
      realtimeArrivalTime: JourneyV3Validation.nullable(json, 'realtimeArrivalTime', (value) => JourneyV3Validation.rfc3339(value, 'realtimeArrivalTime')),
      servicePattern: JourneyServicePatternWire.fromWire(json['servicePattern']),
      stops: JourneyV3Validation.list(json['stops'], 'stops', (v) { if (v is! Map<String, Object?>) throw const FormatException('stop must be object'); return JourneyRideStop.fromJson(v); }, minimum: 2),
      alightingCarDoors: rawAlightingCarDoors == null ? const [] : JourneyV3Validation.list(rawAlightingCarDoors, 'alightingCarDoors', (v) => JourneyAlightingCarDoor.fromJson(v as Map<String, Object?>)),
      boardingPlatformGaps: rawBoardingPlatformGaps == null ? const [] : JourneyV3Validation.list(rawBoardingPlatformGaps, 'boardingPlatformGaps', (v) => JourneyPlatformGap.fromJson(v as Map<String, Object?>)),
      alightingPlatformGaps: rawAlightingPlatformGaps == null ? const [] : JourneyV3Validation.list(rawAlightingPlatformGaps, 'alightingPlatformGaps', (v) => JourneyPlatformGap.fromJson(v as Map<String, Object?>)),
    );
  }
  @override Map<String, Object?> toJson() => {
    'type': JourneyLegType.ride.wire,
    'lineId': lineId,
    'tripId': tripId,
    'directionStationId': directionStationId,
    'fromStationId': fromStationId,
    'toStationId': toStationId,
    'plannedDepartureTime': JourneyV3Validation.rfc3339Wire(plannedDepartureTime),
    'plannedArrivalTime': JourneyV3Validation.rfc3339Wire(plannedArrivalTime),
    'realtimeDepartureTime': realtimeDepartureTime == null ? null : JourneyV3Validation.rfc3339Wire(realtimeDepartureTime!),
    'realtimeArrivalTime': realtimeArrivalTime == null ? null : JourneyV3Validation.rfc3339Wire(realtimeArrivalTime!),
    'servicePattern': servicePattern.wire,
    'stops': stops.map((v) => v.toJson()).toList(),
    if (alightingCarDoors.isNotEmpty) 'alightingCarDoors': alightingCarDoors.map((v) => v.toJson()).toList(),
    if (boardingPlatformGaps.isNotEmpty) 'boardingPlatformGaps': boardingPlatformGaps.map((v) => v.toJson()).toList(),
    if (alightingPlatformGaps.isNotEmpty) 'alightingPlatformGaps': alightingPlatformGaps.map((v) => v.toJson()).toList(),
  };
}

class JourneyTransferLeg extends JourneyLeg {
  final String fromStationId; final String toStationId; final int durationSeconds; final String? transferType; final bool farePenaltyApplies; final int? transferLimitMinutes;
  const JourneyTransferLeg({required this.fromStationId, required this.toStationId, required this.durationSeconds, this.transferType, this.farePenaltyApplies = false, this.transferLimitMinutes});
  factory JourneyTransferLeg.fromJson(Map<String, Object?> json) {
    JourneyV3Validation.exactKeys(json, {'type', 'fromStationId', 'toStationId', 'durationSeconds', if (json.containsKey('transferType')) 'transferType', if (json.containsKey('farePenaltyApplies')) 'farePenaltyApplies', if (json.containsKey('transferLimitMinutes')) 'transferLimitMinutes'});
    if (JourneyLegTypeWire.fromWire(json['type']) != JourneyLegType.transfer) throw const FormatException('leg type');
    return JourneyTransferLeg(fromStationId: JourneyV3Validation.nonBlank(json['fromStationId'], 'fromStationId'), toStationId: JourneyV3Validation.nonBlank(json['toStationId'], 'toStationId'), durationSeconds: JourneyV3Validation.integer(json['durationSeconds'], 'durationSeconds', 0), transferType: json['transferType'] == null ? null : JourneyV3Validation.string(json['transferType'], 'transferType'), farePenaltyApplies: json['farePenaltyApplies'] == null ? false : JourneyV3Validation.boolean(json['farePenaltyApplies'], 'farePenaltyApplies'), transferLimitMinutes: json['transferLimitMinutes'] == null ? null : JourneyV3Validation.integer(json['transferLimitMinutes'], 'transferLimitMinutes', 0));
  }
  @override Map<String, Object?> toJson() => {'type': JourneyLegType.transfer.wire, 'fromStationId': fromStationId, 'toStationId': toStationId, 'durationSeconds': durationSeconds, if (transferType != null) 'transferType': transferType, if (farePenaltyApplies) 'farePenaltyApplies': farePenaltyApplies, if (transferLimitMinutes != null) 'transferLimitMinutes': transferLimitMinutes};
}

class JourneyExitLeg extends JourneyLeg {
  final String fromStationId; final int durationSeconds;
  const JourneyExitLeg({required this.fromStationId, required this.durationSeconds});
  factory JourneyExitLeg.fromJson(Map<String, Object?> json) {
    JourneyV3Validation.exactKeys(json, {'type', 'fromStationId', 'durationSeconds'});
    if (JourneyLegTypeWire.fromWire(json['type']) != JourneyLegType.exit) throw const FormatException('leg type');
    return JourneyExitLeg(fromStationId: JourneyV3Validation.nonBlank(json['fromStationId'], 'fromStationId'), durationSeconds: JourneyV3Validation.integer(json['durationSeconds'], 'durationSeconds', 0));
  }
  @override Map<String, Object?> toJson() => {'type': JourneyLegType.exit.wire, 'fromStationId': fromStationId, 'durationSeconds': durationSeconds};
}
`;
}

function renderModels() {
  const responseHeader = `// Test-only strict Journey V3 response model source; production output remains closed.\nimport 'journey_v3_enums.dart';\nimport 'journey_v3_validation.dart';\n\nabstract interface class JourneyLeg { Map<String, Object?> toJson(); static JourneyLeg fromJson(Map<String, Object?> json) => throw UnimplementedError(); }\n\n`;
  const responseBody = renderResponseModels();
  if (!responseBody.startsWith(responseHeader)) fail('response model renderer header is not canonical');
  return `${renderValidatedRequestModels()}\n${renderLegModels()}\n${responseBody.slice(responseHeader.length)}`;
}

function renderFareResponseModels(source) {
  source = replaceRequired(source, 'final JourneyAccessibility accessibility; final List<JourneyLeg> legs;', 'final JourneyAccessibility accessibility; final List<JourneyLeg> legs; final JourneyFare fare;', 'journey fare field');
  source = replaceRequired(source, 'required this.accessibility,required this.legs});', 'required this.accessibility,required this.legs,required this.fare});', 'journey fare constructor');
  source = replaceRequired(source, "'timeSource','accessibility','legs'});", "'timeSource','accessibility','legs','fare'});", 'journey fare JSON keys');
  source = replaceRequired(source, "if(accessibility is! Map<String,Object?>) throw const FormatException('accessibility must be object');", "if(accessibility is! Map<String,Object?>) throw const FormatException('accessibility must be object'); final fare=json['fare']; if(fare is! Map<String,Object?>) throw const FormatException('fare must be object');", 'journey fare JSON object');
  source = replaceRequired(source, 'return JourneyLeg.fromJson(v);},minimum:1)); }', 'return JourneyLeg.fromJson(v);},minimum:1),fare:JourneyFare.fromJson(fare)); }', 'journey fare JSON parsing');
  return replaceRequired(source, "'legs':legs.map((v)=>v.toJson()).toList(growable:false)};", "'legs':legs.map((v)=>v.toJson()).toList(growable:false),'fare':fare.toJson()};", 'journey fare JSON encoding');
}

// #438: serviceDayCutoff (backend #301) and the accessible-route alternatives
// (backend #471). Wire constants come from the contract, not from the template.
function renderServiceDayAndAlternativeResponseModels(source, ir) {
  const cutoffValues = ir.schemas.JourneySearchSuccess?.properties?.serviceDayCutoff?.enum;
  if (!Array.isArray(cutoffValues) || cutoffValues.length !== 1 || !/^\d{2}:\d{2}$/.test(cutoffValues[0])) fail('JourneySearchSuccess.serviceDayCutoff must be one fixed HH:MM wire value');
  const cutoff = cutoffValues[0];
  const categories = ir.schemas.Journey?.properties?.alternativeCategories;
  if (!isObject(categories) || categories.type !== 'array' || categories.uniqueItems !== true || !Number.isInteger(categories.maxItems)) fail('Journey.alternativeCategories must be a bounded unique array');
  source = replaceRequired(source, 'final JourneyDate serviceDate; final String serviceTimezone; final JourneySourceIdentity sourceIdentity;', 'final JourneyDate serviceDate; final String serviceTimezone; final String serviceDayCutoff; final JourneySourceIdentity sourceIdentity;', 'search service day cutoff field');
  source = replaceRequired(source, 'final List<Journey> journeys;\n const JourneySearchSuccess({', 'final List<Journey> journeys; final JourneyStairFreeAlternative? stairFreeAlternative;\n const JourneySearchSuccess({', 'search stair-free alternative field');
  source = replaceRequired(source, 'required this.serviceTimezone,required this.sourceIdentity,required this.requestPolicy,required this.journeys});', 'required this.serviceTimezone,required this.serviceDayCutoff,required this.sourceIdentity,required this.requestPolicy,required this.journeys,this.stairFreeAlternative});', 'search constructor');
  source = replaceRequired(source, "'serviceDate','serviceTimezone','sourceIdentity','requestPolicy','journeys'});", "'serviceDate','serviceTimezone','serviceDayCutoff','sourceIdentity','requestPolicy','journeys',if(json.containsKey('stairFreeAlternative'))'stairFreeAlternative'}); final stairFreeAlternative=json['stairFreeAlternative']; if(json.containsKey('stairFreeAlternative')&&stairFreeAlternative is! Map<String,Object?>){throw const FormatException('stairFreeAlternative must be object');}", 'search JSON keys');
  source = replaceRequired(source, "return 'Asia/Seoul';}),sourceIdentity:", `return 'Asia/Seoul';}),serviceDayCutoff:JourneyV3Validation.enumWire(json['serviceDayCutoff'],'serviceDayCutoff',(v){if(v!='${cutoff}'){throw const FormatException();} return '${cutoff}';}),sourceIdentity:`, 'search service day cutoff parsing');
  source = replaceRequired(source, 'requestPolicy:policy,journeys:journeys); }', 'requestPolicy:policy,journeys:journeys,stairFreeAlternative:stairFreeAlternative is Map<String,Object?>?JourneyStairFreeAlternative.fromJson(stairFreeAlternative):null); }', 'search stair-free alternative parsing');
  source = replaceRequired(source, "'serviceTimezone':serviceTimezone,'sourceIdentity':sourceIdentity.toJson(),", "'serviceTimezone':serviceTimezone,'serviceDayCutoff':serviceDayCutoff,'sourceIdentity':sourceIdentity.toJson(),", 'search service day cutoff encoding');
  source = replaceRequired(source, "'journeys':journeys.map((v)=>v.toJson()).toList(growable:false)};", "'journeys':journeys.map((v)=>v.toJson()).toList(growable:false),if(stairFreeAlternative!=null)'stairFreeAlternative':stairFreeAlternative!.toJson()};", 'search stair-free alternative encoding');
  source = replaceRequired(source, 'final List<JourneyLeg> legs; final JourneyFare fare;', 'final List<JourneyLeg> legs; final JourneyFare fare; final List<JourneyAlternativeCategory>? alternativeCategories;', 'journey alternative categories field');
  source = replaceRequired(source, 'required this.legs,required this.fare});', 'required this.legs,required this.fare,this.alternativeCategories});', 'journey alternative categories constructor');
  source = replaceRequired(source, "'timeSource','accessibility','legs','fare'});", "'timeSource','accessibility','legs','fare',if(json.containsKey('alternativeCategories'))'alternativeCategories'});", 'journey alternative categories JSON keys');
  source = replaceRequired(source, 'fare:JourneyFare.fromJson(fare)); }', `fare:JourneyFare.fromJson(fare),alternativeCategories:json.containsKey('alternativeCategories')?JourneyV3Validation.list(json['alternativeCategories'],'alternativeCategories',(v)=>JourneyAlternativeCategoryWire.fromWire(v),maximum:${categories.maxItems},unique:true):null); }`, 'journey alternative categories parsing');
  source = replaceRequired(source, ",'fare':fare.toJson()};", ",'fare':fare.toJson(),if(alternativeCategories!=null)'alternativeCategories':alternativeCategories!.map((v)=>v.wire).toList(growable:false)};", 'journey alternative categories encoding');
  return `${source}
class JourneyStairFreeAlternative {
  final JourneyStairFreeAlternativeStatus status;
  final JourneyStairFreeFacilityStatus facilityStatus;
  const JourneyStairFreeAlternative({required this.status, required this.facilityStatus});
  factory JourneyStairFreeAlternative.fromJson(Map<String, Object?> json) {
    JourneyV3Validation.exactKeys(json, {'status', 'facilityStatus'});
    return JourneyStairFreeAlternative(status: JourneyStairFreeAlternativeStatusWire.fromWire(json['status']), facilityStatus: JourneyStairFreeFacilityStatusWire.fromWire(json['facilityStatus']));
  }
  Map<String, Object?> toJson() => {'status': status.wire, 'facilityStatus': facilityStatus.wire};
}
`;
}

function renderStrictModels(ir) {
  let source = renderServiceDayAndAlternativeResponseModels(renderFareResponseModels(renderWalkingPaceResponseModels(renderModels())), ir);
  const responseAnchor = "final policy=JourneyRequestPolicy.fromJson(requestPolicy); final journeys=";
  const responseReplacement = "final policy=JourneyRequestPolicy.fromJson(requestPolicy); final parsedSourceIdentity=JourneySourceIdentity.fromJson(sourceIdentity); if(policy.timePolicy==TimePolicy.timetableRequired&&parsedSourceIdentity.realtimeSnapshotId!=null) throw const FormatException('TIMETABLE_REQUIRED source realtime contract'); if(policy.timePolicy==TimePolicy.realtimeRequired&&parsedSourceIdentity.realtimeSnapshotId==null) throw const FormatException('REALTIME_REQUIRED source realtime contract'); final journeys=";
  if (!source.includes(responseAnchor)) fail('source-identity renderer anchor is missing');
  source = source.replace(responseAnchor, responseReplacement).replace('sourceIdentity:JourneySourceIdentity.fromJson(sourceIdentity)', 'sourceIdentity:parsedSourceIdentity');
  const anchor = "for(final journey in journeys){if(policy.timePolicy==TimePolicy.timetableRequired&&(journey.realtimeDepartureTime!=null||journey.realtimeArrivalTime!=null||journey.timeSource!=JourneyTimeSource.timetable)) throw const FormatException('TIMETABLE_REQUIRED realtime contract'); if(policy.timePolicy==TimePolicy.realtimeRequired&&(journey.realtimeDepartureTime==null||journey.realtimeArrivalTime==null||journey.timeSource!=JourneyTimeSource.realtime)) throw const FormatException('REALTIME_REQUIRED realtime contract');}";
  const replacement = "for(final journey in journeys){if(policy.timePolicy==TimePolicy.timetableRequired&&(journey.realtimeDepartureTime!=null||journey.realtimeArrivalTime!=null||journey.timeSource!=JourneyTimeSource.timetable)){throw const FormatException('TIMETABLE_REQUIRED realtime contract');} if(policy.timePolicy==TimePolicy.realtimeRequired&&(journey.realtimeDepartureTime==null||journey.realtimeArrivalTime==null||journey.timeSource!=JourneyTimeSource.realtime)){throw const FormatException('REALTIME_REQUIRED realtime contract');} for(final leg in journey.legs){if(leg is JourneyRideLeg){if(policy.timePolicy==TimePolicy.timetableRequired&&(leg.realtimeDepartureTime!=null||leg.realtimeArrivalTime!=null)){throw const FormatException('TIMETABLE_REQUIRED ride realtime contract');} if(policy.timePolicy==TimePolicy.realtimeRequired&&(leg.realtimeDepartureTime==null||leg.realtimeArrivalTime==null)){throw const FormatException('REALTIME_REQUIRED ride realtime contract');}}}}";
  if (!source.includes(anchor)) fail('time-policy renderer anchor is missing');
  source = source.replace(anchor, replacement);
  return `${source}\n${renderStationTimetableModels()}`;
}

function renderStationTimetableModels() {
  return `
sealed class StationTimetableSelector {
  const StationTimetableSelector();
  Map<String, Object?> toJson();
  static StationTimetableSelector fromJson(Map<String, Object?> json) => switch (StationTimetableSelectorKindWire.fromWire(json['kind'])) {
    StationTimetableSelectorKind.serviceDate => StationTimetableServiceDateSelector.fromJson(json),
    StationTimetableSelectorKind.dayType => StationTimetableDayTypeSelector.fromJson(json),
    StationTimetableSelectorKind.nextDepartures => StationTimetableNextDeparturesSelector.fromJson(json),
  };
}
class StationTimetableServiceDateSelector extends StationTimetableSelector { final JourneyDate serviceDate; const StationTimetableServiceDateSelector(this.serviceDate); factory StationTimetableServiceDateSelector.fromJson(Map<String,Object?> json) { JourneyV3Validation.exactKeys(json, {'kind','serviceDate'}); if (StationTimetableSelectorKindWire.fromWire(json['kind']) != StationTimetableSelectorKind.serviceDate) throw const FormatException('selector kind'); return StationTimetableServiceDateSelector(JourneyDate.parse(json['serviceDate'])); } @override Map<String,Object?> toJson()=>{'kind':StationTimetableSelectorKind.serviceDate.wire,'serviceDate':serviceDate.toString()}; }
class StationTimetableDayTypeSelector extends StationTimetableSelector { final StationTimetableDayType dayType; final JourneyDate referenceDate; const StationTimetableDayTypeSelector({required this.dayType,required this.referenceDate}); factory StationTimetableDayTypeSelector.fromJson(Map<String,Object?> json) { JourneyV3Validation.exactKeys(json, {'kind','dayType','referenceDate'}); if (StationTimetableSelectorKindWire.fromWire(json['kind']) != StationTimetableSelectorKind.dayType) throw const FormatException('selector kind'); return StationTimetableDayTypeSelector(dayType:StationTimetableDayTypeWire.fromWire(json['dayType']),referenceDate:JourneyDate.parse(json['referenceDate'])); } @override Map<String,Object?> toJson()=>{'kind':StationTimetableSelectorKind.dayType.wire,'dayType':dayType.wire,'referenceDate':referenceDate.toString()}; }
class StationTimetableNextDeparturesSelector extends StationTimetableSelector { final DateTime asOf; final int horizonDays; const StationTimetableNextDeparturesSelector({required this.asOf,required this.horizonDays}); factory StationTimetableNextDeparturesSelector.fromJson(Map<String,Object?> json) { JourneyV3Validation.exactKeys(json, {'kind','asOf','horizonDays'}); if (StationTimetableSelectorKindWire.fromWire(json['kind']) != StationTimetableSelectorKind.nextDepartures) throw const FormatException('selector kind'); return StationTimetableNextDeparturesSelector(asOf:JourneyV3Validation.rfc3339(json['asOf'],'asOf'),horizonDays:JourneyV3Validation.integer(json['horizonDays'],'horizonDays',1,8)); } @override Map<String,Object?> toJson()=>{'kind':StationTimetableSelectorKind.nextDepartures.wire,'asOf':JourneyV3Validation.rfc3339Wire(asOf),'horizonDays':horizonDays}; }
class StationTimetableSearchRequest { final String stationId; final String lineId; final StationTimetableSelector selector; const StationTimetableSearchRequest({required this.stationId,required this.lineId,required this.selector}); factory StationTimetableSearchRequest.fromJson(Map<String,Object?> json) { JourneyV3Validation.exactKeys(json, {'stationId','lineId','selector'}); final selector=json['selector']; if(selector is! Map<String,Object?>) throw const FormatException('selector must be object'); return StationTimetableSearchRequest(stationId:JourneyV3Validation.nonBlank(json['stationId'],'stationId'),lineId:JourneyV3Validation.nonBlank(json['lineId'],'lineId'),selector:StationTimetableSelector.fromJson(selector)); } Map<String,Object?> toJson()=>{'stationId':stationId,'lineId':lineId,'selector':selector.toJson()}; }
class StationTimetableDeparture { final JourneyDate serviceDate; final int secondsFromServiceDayStart; final DateTime departureAt; final StationTimetableServicePattern servicePattern; final StationTimetableServiceClass serviceClass; final String? terminalStationId; const StationTimetableDeparture({required this.serviceDate,required this.secondsFromServiceDayStart,required this.departureAt,required this.servicePattern,required this.serviceClass,this.terminalStationId}); factory StationTimetableDeparture.fromJson(Map<String,Object?> json) { JourneyV3Validation.exactKeys(json, {'serviceDate','secondsFromServiceDayStart','departureAt','servicePattern','serviceClass',if(json.containsKey('terminalStationId'))'terminalStationId'}); return StationTimetableDeparture(serviceDate:JourneyDate.parse(json['serviceDate']),secondsFromServiceDayStart:JourneyV3Validation.integer(json['secondsFromServiceDayStart'],'secondsFromServiceDayStart',0,107999),departureAt:JourneyV3Validation.rfc3339(json['departureAt'],'departureAt'),servicePattern:StationTimetableServicePatternWire.fromWire(json['servicePattern']),serviceClass:StationTimetableServiceClassWire.fromWire(json['serviceClass']),terminalStationId:json.containsKey('terminalStationId')?JourneyV3Validation.nonBlank(json['terminalStationId'],'terminalStationId'):null); } Map<String,Object?> toJson()=>{'serviceDate':serviceDate.toString(),'secondsFromServiceDayStart':secondsFromServiceDayStart,'departureAt':JourneyV3Validation.rfc3339Wire(departureAt),'servicePattern':servicePattern.wire,'serviceClass':serviceClass.wire,if(terminalStationId!=null)'terminalStationId':terminalStationId}; }
class StationTimetableDirectionGroup { final String? nextStationId; final String? directionName; final List<StationTimetableDeparture> departures; const StationTimetableDirectionGroup({this.nextStationId,required this.directionName,required this.departures}); factory StationTimetableDirectionGroup.fromJson(Map<String,Object?> json) { JourneyV3Validation.exactKeys(json, {if(json.containsKey('nextStationId'))'nextStationId','directionName','departures'}); return StationTimetableDirectionGroup(nextStationId:json.containsKey('nextStationId')?JourneyV3Validation.nonBlank(json['nextStationId'],'nextStationId'):null,directionName:JourneyV3Validation.nullable(json,'directionName',(v)=>JourneyV3Validation.nonBlank(v,'directionName')),departures:JourneyV3Validation.list(json['departures'],'departures',(v){if(v is! Map<String,Object?>) throw const FormatException('departure must be object');return StationTimetableDeparture.fromJson(v);})); } Map<String,Object?> toJson()=>{if(nextStationId!=null)'nextStationId':nextStationId,'directionName':directionName,'departures':departures.map((v)=>v.toJson()).toList(growable:false)}; }
class StationTimetableSourceIdentity { final String timetableArtifactId; final String timetableSnapshotSha256; final String canonicalStationVersion; final String canonicalStationSetSha256; final String sourceLineageSha256; final String evidenceHash; final DateTime freshUntil; const StationTimetableSourceIdentity({required this.timetableArtifactId,required this.timetableSnapshotSha256,required this.canonicalStationVersion,required this.canonicalStationSetSha256,required this.sourceLineageSha256,required this.evidenceHash,required this.freshUntil}); factory StationTimetableSourceIdentity.fromJson(Map<String,Object?> json) { JourneyV3Validation.exactKeys(json, {'timetableArtifactId','timetableSnapshotSha256','canonicalStationVersion','canonicalStationSetSha256','sourceLineageSha256','evidenceHash','freshUntil'}); return StationTimetableSourceIdentity(timetableArtifactId:JourneyV3Validation.nonBlank(json['timetableArtifactId'],'timetableArtifactId'),timetableSnapshotSha256:JourneyV3Validation.sha256(json['timetableSnapshotSha256'],'timetableSnapshotSha256'),canonicalStationVersion:JourneyV3Validation.nonBlank(json['canonicalStationVersion'],'canonicalStationVersion'),canonicalStationSetSha256:JourneyV3Validation.sha256(json['canonicalStationSetSha256'],'canonicalStationSetSha256'),sourceLineageSha256:JourneyV3Validation.sha256(json['sourceLineageSha256'],'sourceLineageSha256'),evidenceHash:JourneyV3Validation.sha256(json['evidenceHash'],'evidenceHash'),freshUntil:JourneyV3Validation.rfc3339(json['freshUntil'],'freshUntil')); } Map<String,Object?> toJson()=>{'timetableArtifactId':timetableArtifactId,'timetableSnapshotSha256':timetableSnapshotSha256,'canonicalStationVersion':canonicalStationVersion,'canonicalStationSetSha256':canonicalStationSetSha256,'sourceLineageSha256':sourceLineageSha256,'evidenceHash':evidenceHash,'freshUntil':JourneyV3Validation.rfc3339Wire(freshUntil)}; }
class StationTimetableSearchSuccess { final StationTimetableSearchContractVersion contractVersion; final String stationId; final String lineId; final StationTimetableSelector selector; final StationTimetableDayType resolvedDayType; final StationTimetableServiceTimezone serviceTimezone; final List<StationTimetableDirectionGroup> directionGroups; final StationTimetableSourceIdentity sourceIdentity; const StationTimetableSearchSuccess({required this.contractVersion,required this.stationId,required this.lineId,required this.selector,required this.resolvedDayType,required this.serviceTimezone,required this.directionGroups,required this.sourceIdentity}); factory StationTimetableSearchSuccess.fromJson(Map<String,Object?> json) { JourneyV3Validation.exactKeys(json, {'contractVersion','stationId','lineId','selector','resolvedDayType','serviceTimezone','directionGroups','sourceIdentity'}); final selector=json['selector']; final sourceIdentity=json['sourceIdentity']; if(selector is! Map<String,Object?>||sourceIdentity is! Map<String,Object?>) throw const FormatException('nested timetable object'); return StationTimetableSearchSuccess(contractVersion:StationTimetableSearchContractVersionWire.fromWire(json['contractVersion']),stationId:JourneyV3Validation.nonBlank(json['stationId'],'stationId'),lineId:JourneyV3Validation.nonBlank(json['lineId'],'lineId'),selector:StationTimetableSelector.fromJson(selector),resolvedDayType:StationTimetableDayTypeWire.fromWire(json['resolvedDayType']),serviceTimezone:StationTimetableServiceTimezoneWire.fromWire(json['serviceTimezone']),directionGroups:JourneyV3Validation.list(json['directionGroups'],'directionGroups',(v){if(v is! Map<String,Object?>) throw const FormatException('direction group must be object');return StationTimetableDirectionGroup.fromJson(v);}),sourceIdentity:StationTimetableSourceIdentity.fromJson(sourceIdentity)); } Map<String,Object?> toJson()=>{'contractVersion':contractVersion.wire,'stationId':stationId,'lineId':lineId,'selector':selector.toJson(),'resolvedDayType':resolvedDayType.wire,'serviceTimezone':serviceTimezone.wire,'directionGroups':directionGroups.map((v)=>v.toJson()).toList(growable:false),'sourceIdentity':sourceIdentity.toJson()}; }
`;
}

export function renderJourneyV3ModelsForTest(options) { const ir = validate({ ...options, enforceTrackedLock: false }); return renderStrictModels(ir); }
function dartLiteral(value) { return JSON.stringify(value).replaceAll('$', '\\$'); }
function renderErrors(ir) {
  const rows = ir.errorDispositions.map((entry) => `    '${entry.operation}|${entry.httpStatus}|${entry.code}': JourneyErrorDisposition(operation: '${entry.operation}', httpStatus: ${entry.httpStatus}, code: JourneyErrorCode.${dartCase(entry.code)}, semanticCategory: ${dartLiteral(entry.semanticCategory)}, exposure: ${dartLiteral(entry.exposure)}, userVisible: true, publicMessageKey: ${dartLiteral(entry.publicMessageKey)}, canonicalKoreanCopy: ${dartLiteral(entry.canonicalKoreanCopy)}, mobileResourceKey: ${dartLiteral(entry.mobileResourceKey)}, mobilePresentation: ${dartLiteral(entry.mobilePresentation)}, retryDisposition: ${dartLiteral(entry.retryDisposition)}, primaryActionKey: ${entry.primaryActionKey === null ? 'null' : dartLiteral(entry.primaryActionKey)}, secondaryActionKey: null, safeDiagnosticKey: ${dartLiteral(entry.safeDiagnosticKey)}, sensitiveDetailPolicy: ${dartLiteral(entry.sensitiveDetailPolicy)}),`).join('\n');
  return `// Test-only strict Journey V3 error source; production output remains closed.\nimport 'journey_v3_enums.dart';\nimport 'journey_v3_validation.dart';\n\nclass JourneyV3Error {\n final JourneyErrorContractVersion contractVersion; final String requestId; final JourneyErrorCode code; final bool retryable; final DateTime occurredAt;\n const JourneyV3Error({required this.contractVersion,required this.requestId,required this.code,required this.retryable,required this.occurredAt});\n factory JourneyV3Error.fromJson(Map<String,Object?> json) { JourneyV3Validation.exactKeys(json, {'contractVersion','requestId','code','retryable','occurredAt'}); return JourneyV3Error(contractVersion:JourneyErrorContractVersionWire.fromWire(json['contractVersion']),requestId:JourneyV3Validation.ulid(json['requestId'],'requestId'),code:JourneyErrorCodeWire.fromWire(json['code']),retryable:JourneyV3Validation.boolean(json['retryable'],'retryable'),occurredAt:JourneyV3Validation.rfc3339(json['occurredAt'],'occurredAt')); }\n Map<String,Object?> toJson()=>{'contractVersion':contractVersion.wire,'requestId':requestId,'code':code.wire,'retryable':retryable,'occurredAt':JourneyV3Validation.rfc3339Wire(occurredAt)};\n}\nclass JourneyErrorDisposition {\n final String operation; final int httpStatus; final JourneyErrorCode code; final String semanticCategory; final String exposure; final bool userVisible; final String publicMessageKey; final String canonicalKoreanCopy; final String mobileResourceKey; final String mobilePresentation; final String retryDisposition; final String? primaryActionKey; final String? secondaryActionKey; final String safeDiagnosticKey; final String sensitiveDetailPolicy;\n const JourneyErrorDisposition({required this.operation,required this.httpStatus,required this.code,required this.semanticCategory,required this.exposure,required this.userVisible,required this.publicMessageKey,required this.canonicalKoreanCopy,required this.mobileResourceKey,required this.mobilePresentation,required this.retryDisposition,required this.primaryActionKey,required this.secondaryActionKey,required this.safeDiagnosticKey,required this.sensitiveDetailPolicy});\n}\nabstract final class JourneyErrorDispositions {\n static const Map<String,JourneyErrorDisposition> _byContext = {\n${rows}\n };\n static JourneyErrorDisposition lookup(JourneyOperation operation,int httpStatus,JourneyErrorCode code) { final value=_byContext['\${operation.wire}|\$httpStatus|\${code.wire}']; if(value==null) throw const FormatException('unknown Journey error context'); return value; }\n}\n`;
}
function renderContract(lock, sessionIntegrity) { const resources = Array.isArray(lock.resources) ? lock.resources : []; const resource = resources.find(({ path }) => path === resourcePaths[2]); return `// Test-only Journey V3 contract barrel; production output remains closed.\nexport 'journey_v3_enums.dart';\nexport 'journey_v3_error.dart';\nexport 'journey_v3_models.dart';\nexport 'journey_v3_validation.dart';\nconst String journeyV3ProducerRepository = '${lock.producer.repository}';\nconst String journeyV3ProducerSha = '${lock.producer.gitSha}';\nconst String journeyV3ManifestDigest = '${lock.artifact.manifestDigest}';\nconst String journeyV3PayloadSha256 = '${lock.payload.sha256}';\nconst String journeyV3PublicationReceiptSha256 = '${lock.publicationReceiptSha256}';${resource ? `\nconst String journeyV3SessionIntegritySha256 = '${resource.sha256}';\nconst String journeyV3SessionIntegritySpecJson = '${canonicalJson(sessionIntegrity)}';` : ''}\n`; }
function renderDartContract(lock, sessionIntegrity = exactSessionIntegrity) { const resources = Array.isArray(lock.resources) ? lock.resources : []; let source = renderContract(lock, sessionIntegrity); for (const value of [lock.producer.repository, lock.producer.gitSha, lock.artifact.manifestDigest, lock.payload.sha256, lock.publicationReceiptSha256, ...resources.filter(({ path }) => path === resourcePaths[2]).map(({ sha256: digest }) => digest), canonicalJson(sessionIntegrity)]) source = source.replaceAll(`'${value}'`, dartLiteral(value)); return source; }
function renderClosedErrors(ir) {
  let source = renderErrors(ir);
  source = source.replaceAll(/semanticCategory: "([^"]+)"/g, (_, token) => `semanticCategory: JourneyErrorSemanticCategory.${dartCase(token)}`);
  source = source.replaceAll(/primaryActionKey: "([^"]+)"/g, (_, token) => `primaryActionKey: JourneyErrorActionKey.${dartCase(token)}`);
  source = source.replace('final String operation; final int httpStatus; final JourneyErrorCode code; final String semanticCategory;', 'final String operation; final int httpStatus; final JourneyErrorCode code; final JourneyErrorSemanticCategory semanticCategory;');
  source = source.replace('final String retryDisposition; final String? primaryActionKey; final String? secondaryActionKey;', 'final String retryDisposition; final JourneyErrorActionKey? primaryActionKey; final String? secondaryActionKey;');
  const toJsonAnchor = " Map<String,Object?> toJson()=>{'contractVersion':contractVersion.wire";
  const fromResponse = " static JourneyV3Error fromResponse(JourneyOperation operation,int httpStatus,Map<String,Object?> json){final error=JourneyV3Error.fromJson(json);JourneyErrorDispositions.lookup(operation,httpStatus,error.code);return error;}\n";
  if (!source.includes(toJsonAnchor)) fail('error renderer anchor is missing');
  return source.replace(toJsonAnchor, `${fromResponse}${toJsonAnchor}`);
}
export function renderJourneyV3ErrorsAndBarrelForTest(options) { const ir = validate({ ...options, enforceTrackedLock: false }); const lock = duplicateFreeJson(regular(options.lockPath, 'lock').toString('utf8'), 'lock'); return Object.freeze({ error: renderClosedErrors(ir), contract: renderDartContract(lock, ir.sessionIntegrity) }); }
export function renderJourneyV3DartLiteralSeamForTest({ enumToken, lock }) { return Object.freeze({ enums: renderDartEnums({ schemas: { SpecialWire: { type: 'string', enum: [enumToken] } }, errorDispositions: [{ semanticCategory: 'TEST', primaryActionKey: 'test.action' }] }), contract: renderDartContract(lock) }); }

// #438 key coverage gate.
// The Dart renderers are hand-written templates. The schemas projection hash only
// detects that the contract changed; it cannot tell whether the templates were
// updated with it. #344 re-pinned the hash for a contract that added the required
// JourneySearchSuccess.serviceDayCutoff without touching the templates, so the
// generated decoder rejected every production search response. This gate makes
// that impossible: for every object schema the generated client decodes, the key
// set passed to JourneyV3Validation.exactKeys must equal the contract's
// required + optional properties. Unconditional keys must be exactly the required
// keys; `if (json.containsKey('k')) 'k'` keys must be exactly the optional keys
// plus the undeployed required keys below.
// profileJourneys is decoded by hand-written domain models
// (apps/mobile/lib/features/journey/domain/journey_profile_models.dart), not by
// this generator, so its schemas are outside this gate.
const generatedOperationIds = Object.freeze(['issueJourneySession', 'searchJourneys', 'searchStationTimetables']);
const generatedClassBySchema = Object.freeze({ JourneyError: 'JourneyV3Error' });
// Contract-required fields that production does not emit yet. The decoder
// accepts them present or absent until the producing backend change is
// deployed; remove the entry then.
// #438 transition policy, part 2: production does not emit these yet, and the
// backend changes may deploy after this client ships. The decoder accepts each
// key present or absent; any key outside the contract is still rejected.
const undeployedRequiredFields = new Map([
  ['JourneySearchSuccess.stairFreeAlternative', 'AquilaXk/easysubway-backend#471'],
  ['StationTimetableDirectionGroup.nextStationId', 'AquilaXk/easysubway-backend#479'],
  ['StationTimetableDeparture.terminalStationId', 'AquilaXk/easysubway-backend#479'],
]);
const schemaRefPrefix = '#/components/schemas/';

function generatedObjectSchemaNames(ir) {
  const roots = ['JourneyError'];
  for (const operation of ir.operations) {
    if (!generatedOperationIds.includes(operation.id)) continue;
    const expectation = expectedOperations.get(operation.path);
    roots.push(expectation.request, expectation.success);
  }
  const names = new Set(); const seen = new Set();
  const walk = (schema) => {
    if (!isObject(schema)) return;
    if (typeof schema.$ref === 'string') {
      const name = schema.$ref.slice(schemaRefPrefix.length);
      if (seen.has(name)) return;
      seen.add(name);
      const target = ir.schemas[name];
      if (!isObject(target)) fail(`key coverage cannot resolve ${name}`);
      if (target.type === 'object') names.add(name);
      walk(target);
      return;
    }
    if (Array.isArray(schema.oneOf)) schema.oneOf.forEach(walk);
    if (isObject(schema.items)) walk(schema.items);
    if (isObject(schema.properties)) Object.values(schema.properties).forEach(walk);
  };
  for (const root of roots) walk({ $ref: `${schemaRefPrefix}${root}` });
  return [...names].sort();
}

function dartBalancedEnd(source, openIndex) {
  const pairs = { '{': '}', '(': ')', '[': ']' };
  const stack = [pairs[source[openIndex]]];
  if (stack[0] === undefined) fail('key coverage scanner expected an opening bracket');
  let index = openIndex + 1;
  while (index < source.length) {
    const character = source[index];
    if (character === "'" || character === '"') {
      const raw = source[index - 1] === 'r';
      index += 1;
      while (index < source.length && source[index] !== character) {
        if (!raw && source[index] === '\\') index += 1;
        else if (!raw && source[index] === '$' && source[index + 1] === '{') index = dartBalancedEnd(source, index + 1);
        index += 1;
      }
      if (index >= source.length) fail('key coverage scanner found an unterminated Dart string');
    } else if (character in pairs) {
      stack.push(pairs[character]);
    } else if (character === '}' || character === ')' || character === ']') {
      if (stack.pop() !== character) fail('key coverage scanner found unbalanced Dart brackets');
      if (stack.length === 0) return index;
    }
    index += 1;
  }
  fail('key coverage scanner found an unterminated Dart block');
}

function dartTopLevelEntries(text) {
  const entries = []; let depth = 0; let start = 0; let quote = null;
  for (let index = 0; index < text.length; index += 1) {
    const character = text[index];
    if (quote) { if (character === '\\') index += 1; else if (character === quote) quote = null; continue; }
    if (character === "'" || character === '"') quote = character;
    else if ('{(['.includes(character)) depth += 1;
    else if ('})]'.includes(character)) depth -= 1;
    else if (character === ',' && depth === 0) { entries.push(text.slice(start, index)); start = index + 1; }
  }
  entries.push(text.slice(start));
  return entries.map((entry) => entry.trim()).filter((entry) => entry.length > 0);
}

function generatedDecoderKeys(source, className) {
  // Plain string search only: these names come from contract and template text,
  // so they are never compiled into regular expressions.
  const factoryStart = source.indexOf(`factory ${className}.fromJson(Map<String`);
  if (factoryStart < 0) return null;
  const bodyStart = source.indexOf('{', source.indexOf(' json)', factoryStart));
  if (bodyStart < 0) fail(`${className}.fromJson has no body`);
  const body = source.slice(bodyStart, dartBalancedEnd(source, bodyStart) + 1);
  const call = /JourneyV3Validation\.exactKeys\(json,\s*/.exec(body);
  if (!call) fail(`${className}.fromJson does not call JourneyV3Validation.exactKeys`);
  let literal;
  if (body[call.index + call[0].length] === '{') {
    const open = call.index + call[0].length;
    literal = body.slice(open + 1, dartBalancedEnd(body, open));
  } else {
    const variable = /^([A-Za-z_][A-Za-z0-9_]*)\s*\)/.exec(body.slice(call.index + call[0].length));
    const declaration = variable ? body.indexOf(`final ${variable[1]} = {`) : -1;
    if (declaration < 0) fail(`${className}.fromJson exactKeys argument is not a local set literal`);
    const open = body.indexOf('{', declaration);
    literal = body.slice(open + 1, dartBalancedEnd(body, open));
  }
  const keys = { required: new Set(), conditional: new Set() };
  const add = (set, key) => { if (keys.required.has(key) || keys.conditional.has(key)) fail(`${className}.fromJson lists ${key} twice`); set.add(key); };
  for (const entry of dartTopLevelEntries(literal)) {
    const required = /^'([A-Za-z][A-Za-z0-9]*)'$/.exec(entry);
    const conditional = /^if\s*\(\s*json\.containsKey\(\s*'([A-Za-z][A-Za-z0-9]*)'\s*\)\s*\)\s*'([A-Za-z][A-Za-z0-9]*)'$/.exec(entry);
    const loop = /^for\s*\(\s*final\s+([A-Za-z]+)\s+in\s+([A-Za-z]+)\s*\)\s*if\s*\(\s*json\.containsKey\(\s*\1\s*\)\s*\)\s*\1$/.exec(entry);
    if (required) add(keys.required, required[1]);
    else if (conditional && conditional[1] === conditional[2]) add(keys.conditional, conditional[1]);
    else if (loop) {
      const list = body.indexOf(`const ${loop[2]} = [`);
      if (list < 0) fail(`${className}.fromJson loop keys are not a local const list`);
      const open = body.indexOf('[', list);
      for (const item of dartTopLevelEntries(body.slice(open + 1, dartBalancedEnd(body, open)))) {
        const name = /^'([A-Za-z][A-Za-z0-9]*)'$/.exec(item);
        if (!name) fail(`${className}.fromJson loop key ${item} is not a literal`);
        add(keys.conditional, name[1]);
      }
    } else fail(`${className}.fromJson has an unsupported exactKeys entry: ${entry}`);
  }
  return keys;
}

function setDifference(left, right) { return [...left].filter((key) => !right.has(key)).sort(); }

function journeyV3KeyCoverageMismatches(ir, sources, undeployed = undeployedRequiredFields) {
  const source = sources.join('\n');
  const mismatches = [];
  for (const name of generatedObjectSchemaNames(ir)) {
    const schema = ir.schemas[name];
    const className = generatedClassBySchema[name] ?? name;
    const keys = generatedDecoderKeys(source, className);
    if (!keys) { mismatches.push(`${name}: no generated ${className}.fromJson decoder`); continue; }
    const contractRequired = new Set(schema.required);
    const expectedRequired = new Set([...contractRequired].filter((key) => !undeployed.has(`${name}.${key}`)));
    const expectedConditional = new Set(Object.keys(schema.properties).filter((key) => !expectedRequired.has(key)));
    for (const key of setDifference(expectedRequired, keys.required)) mismatches.push(`${name}.${key}: contract requires it but the generated decoder ${keys.conditional.has(key) ? 'treats it as optional' : 'does not accept it'}`);
    for (const key of setDifference(expectedConditional, keys.conditional)) mismatches.push(`${name}.${key}: ${contractRequired.has(key) ? `contract requires it, but it is undeployed (${undeployed.get(`${name}.${key}`)}) so the decoder must accept it present or absent; the generated decoder` : 'contract allows it to be absent but the generated decoder'} ${keys.required.has(key) ? 'requires it' : 'does not accept it'}`);
    for (const key of setDifference(new Set([...keys.required, ...keys.conditional]), new Set(Object.keys(schema.properties)))) mismatches.push(`${name}.${key}: generated decoder accepts a key outside the contract`);
  }
  for (const field of undeployed.keys()) {
    const [name, key] = field.split('.');
    if (!ir.schemas[name]?.required?.includes(key)) mismatches.push(`${field}: undeployed-required entry is not a required contract field`);
    // An undeployed field is only legitimate while its addition is still pending.
    // Once the locked contract carries it, both entries must go in the same change.
    if (!ir.pendingAdditions.some((entry) => entry.schema === name && entry.property === key && entry.required === true)) mismatches.push(`${field}: undeployed-required entry has no matching pendingContractAdditions entry; remove both together once the locked contract carries the field`);
  }
  return mismatches.sort();
}

function assertJourneyV3KeyCoverage(ir, sources) {
  const mismatches = journeyV3KeyCoverageMismatches(ir, sources);
  if (mismatches.length > 0) fail(`generated decoder keys differ from the contract:\n  ${mismatches.join('\n  ')}`);
}

// Test seam: replace the transition tables or mutate the rendered models to
// prove which drifts the gate catches.
export function journeyV3KeyCoverageMismatchesForTest(options, { pendingAdditions = pendingContractAdditions, undeployed = undeployedRequiredFields, transformModels = (source) => source } = {}) {
  const ir = validate({ ...options, enforceTrackedLock: false, pendingAdditions });
  return journeyV3KeyCoverageMismatches(ir, [transformModels(renderStrictModels(ir)), renderClosedErrors(ir)], undeployed);
}

export function journeyV3TransitionTablesForTest() {
  return Object.freeze({ pendingAdditions: [...pendingContractAdditions], undeployed: new Map(undeployedRequiredFields) });
}

function renderFiles(options, enforceTrackedLock, snapshot) {
  const ir = validate({ ...options, enforceTrackedLock, enforceSchemasProjection: enforceTrackedLock || options.enforceSchemasProjection === true, snapshot });
  const lockBytes = snapshot?.lockBytes ?? regular(options.lockPath, 'lock');
  const lock = duplicateFreeJson(lockBytes.toString('utf8'), 'lock');
  const generatedHeader = (source) => {
    const generated = source.replace(/^\/\/ Test-only [^\n]+\n/, '// Generated from the locked Journey V3 contract.\n');
    const firstLineEnd = generated.indexOf('\n');
    if (!generated.startsWith('// Generated ') || firstLineEnd < 0) fail('generated Dart header is not canonical');
    return `// GENERATED CODE - DO NOT MODIFY BY HAND\n// dart format width=200\n${generated}`;
  };
  const files = Object.freeze({
    'journey_v3_contract.dart': generatedHeader(renderDartContract(lock, ir.sessionIntegrity)),
    'journey_v3_enums.dart': generatedHeader(renderDartEnums(ir)),
    'journey_v3_error.dart': generatedHeader(renderClosedErrors(ir)),
    'journey_v3_models.dart': generatedHeader(renderStrictModels(ir)),
    'journey_v3_validation.dart': generatedHeader(renderStrictValidation()),
  });
  assertJourneyV3KeyCoverage(ir, [files['journey_v3_models.dart'], files['journey_v3_error.dart']]);
  return files;
}

export function renderJourneyV3FilesForTest(options) {
  return renderFiles(options, false);
}

function formatRenderedDart(rendered, dartExecutable = 'dart') {
  const version = spawnSync(dartExecutable, ['--version'], { encoding: 'utf8', timeout: 10_000 });
  const versionText = `${version.stdout ?? ''}${version.stderr ?? ''}`.trim();
  if (version.error || version.status !== 0 || !versionText.startsWith(`Dart SDK version: ${formatterIdentity.sdkVersion} `)) fail(`Dart formatter is required at exact SDK ${formatterIdentity.sdkVersion}`);
  const formatRoot = mkdtempSync(join(tmpdir(), 'journey-v3-dart-format-'));
  try {
    const paths = generatedDartPaths.map((path) => join(formatRoot, path));
    for (let index = 0; index < paths.length; index += 1) writeFileSync(paths[index], rendered[generatedDartPaths[index]], { flag: 'wx', mode: 0o600 });
    const result = spawnSync(dartExecutable, ['format', ...paths], { encoding: 'utf8', timeout: 10_000 });
    if (result.error || result.status !== 0) fail('Dart formatter failed');
    return Object.freeze(Object.fromEntries(generatedDartPaths.map((path, index) => [path, regular(paths[index], `formatted ${path}`)])));
  } finally {
    rmSync(formatRoot, { recursive: true, force: true });
  }
}

function buildGeneration(options, enforceTrackedLock) {
  const snapshot = snapshotGenerationInput(options, enforceTrackedLock);
  if (enforceTrackedLock) validateNodeRuntime(options.nodeMajorVersion);
  const lock = duplicateFreeJson(snapshot.lockBytes.toString('utf8'), 'lock');
  const rendered = renderFiles(options, enforceTrackedLock, snapshot);
  const formatted = formatRenderedDart(rendered, options.dartExecutable);
  const files = generatedDartPaths.map((path) => Object.freeze({ path, sha256: sha256(formatted[path]) }));
  const treeSha256 = sha256(Buffer.from(files.map(({ path, sha256: digest }) => `${path}\0${digest}\n`).join(''), 'utf8'));
  const receipt = Object.freeze({
    schemaVersion: 2,
    generator: Object.freeze({ ...generatorIdentity, sourceSha256: sha256(snapshot.generatorBytes), formatter: formatterIdentity }),
    mobileRepository: mobileSourceIdentity(snapshot),
    runtime: Object.freeze({ node: nodeRuntime }),
    command: logicalCommand,
    configSha256: configSha256(),
    lockSha256: sha256(snapshot.lockBytes),
    producer: lock.producer,
    artifact: lock.artifact,
    payload: lock.payload,
    publicationReceiptSha256: lock.publicationReceiptSha256,
    resources: lock.resources,
    supportedFeatures,
    files,
    treeSha256,
  });
  const receiptBytes = Buffer.from(`${JSON.stringify(receipt, null, 2)}\n`, 'utf8');
  assertSnapshotUnchanged(options, snapshot);
  return Object.freeze({
    files: Object.freeze(Object.fromEntries([
      ...generatedDartPaths.map((path) => [path, formatted[path]]),
      [generationReceiptName, receiptBytes],
    ])),
    receipt,
    snapshot,
  });
}

export function buildJourneyV3GenerationForDrift(options) {
  const generation = buildGeneration(options, true);
  assertSnapshotUnchanged(options, generation.snapshot);
  return Object.freeze({ files: generation.files, receipt: generation.receipt });
}

export function selectJourneyV3GenerationReceiptForDrift(receiptBytes) {
  const receipt = duplicateFreeJson(Buffer.from(receiptBytes).toString('utf8'), 'generation receipt');
  exactKeys(receipt, ['schemaVersion', 'generator', 'mobileRepository', 'runtime', 'command', 'configSha256', 'lockSha256', 'producer', 'artifact', 'payload', 'publicationReceiptSha256', 'resources', 'supportedFeatures', 'files', 'treeSha256'], 'generation receipt');
  exactKeys(receipt.generator, ['id', 'version', 'sourceSha256', 'formatter'], 'generation receipt.generator');
  exactKeys(receipt.mobileRepository, ['repository', 'sourceFiles', 'generationSourceTreeSha256'], 'generation receipt.mobileRepository');
  exactKeys(receipt.runtime, ['node'], 'generation receipt.runtime'); exactKeys(receipt.runtime.node, ['command', 'majorVersion'], 'generation receipt.runtime.node');
  exactKeys(receipt.command, ['program', 'script', 'arguments'], 'generation receipt.command');
  const sourceFiles = receipt.mobileRepository.sourceFiles;
  if (Array.isArray(sourceFiles)) sourceFiles.forEach((sourceFile, index) => exactKeys(sourceFile, ['path', 'sha256'], `generation receipt.mobileRepository.sourceFiles ${index}`));
  if (receipt.schemaVersion !== 2 || receipt.generator.id !== generatorIdentity.id || receipt.generator.version !== generatorIdentity.version || !/^[a-f0-9]{64}$/.test(receipt.generator.sourceSha256) || JSON.stringify(receipt.generator.formatter) !== JSON.stringify(formatterIdentity) || receipt.mobileRepository.repository !== mobileRepository || !Array.isArray(sourceFiles) || sourceFiles.length !== mobileSourcePaths.length || sourceFiles.some(({ path, sha256: digest }, index) => path !== mobileSourcePaths[index] || !/^[a-f0-9]{64}$/.test(digest)) || !/^[a-f0-9]{64}$/.test(receipt.mobileRepository.generationSourceTreeSha256) || receipt.mobileRepository.generationSourceTreeSha256 !== sha256(Buffer.from(sourceFiles.map(({ path, sha256: digest }) => `${path}\0${digest}\n`).join(''), 'utf8')) || JSON.stringify(receipt.runtime.node) !== JSON.stringify(nodeRuntime) || JSON.stringify(receipt.command) !== JSON.stringify(logicalCommand) || receipt.configSha256 !== configSha256()) fail('generation receipt has unsupported v2 generator identity');
  return Object.freeze(receipt);
}

export function journeyV3ReceiptV2ContractForTest(snapshot) { return Object.freeze({ generator: Object.freeze({ ...generatorIdentity, formatter: formatterIdentity }), mobileRepository: mobileSourceIdentity(snapshot), runtime: Object.freeze({ node: nodeRuntime }), command: logicalCommand, configSha256: configSha256() }); }

export function validateJourneyV3NodeRuntimeForTest(nodeMajorVersion) { return validateNodeRuntime(nodeMajorVersion); }

function assertOutputParent(outputRoot) {
  const parent = dirname(outputRoot);
  let stat;
  try { stat = lstatSync(parent); } catch { fail('output parent must be an existing directory'); }
  if (!stat.isDirectory() || stat.isSymbolicLink()) fail('output parent must be a real non-symlink directory');
}

function createExclusive(path, bytes, createdPaths) {
  let fd;
  try {
    fd = openSync(path, constants.O_CREAT | constants.O_EXCL | constants.O_WRONLY | constants.O_NOFOLLOW, 0o600);
    createdPaths.push(path);
    writeFileSync(fd, bytes);
  } catch (error) {
    if (error.message.startsWith('generate-journey-v3-client:')) throw error;
    fail(`cannot create ${path}`);
  } finally {
    if (fd !== undefined) closeSync(fd);
  }
}

function publishGeneration(options, generation) {
  const outputRoot = resolve(options.outputRoot);
  const receiptPath = resolve(options.receiptPath);
  if (receiptPath !== join(outputRoot, generationReceiptName)) fail('receipt must be the exact output-root generation receipt');
  assertOutputParent(outputRoot);
  try { mkdirSync(outputRoot, { mode: 0o700 }); } catch { fail('output root must be absent'); }
  const createdPaths = [];
  try {
    for (const path of generatedDartPaths) createExclusive(join(outputRoot, path), generation.files[path], createdPaths);
    if (options.beforeReceiptForTest !== undefined) options.beforeReceiptForTest();
    assertSnapshotUnchanged(options, generation.snapshot);
    createExclusive(receiptPath, generation.files[generationReceiptName], createdPaths);
  } catch (error) {
    for (const path of createdPaths.reverse()) { try { unlinkSync(path); } catch {} }
    try { rmdirSync(outputRoot); } catch {}
    throw error;
  }
  return Object.freeze({ outputRoot, receiptPath, receipt: generation.receipt });
}

export function generateJourneyV3ClientForTest(options) {
  return publishGeneration(options, buildGeneration(options, false));
}

function parseArguments(argv) { if (argv.length !== 8 || argv[0] !== '--contract-root' || argv[2] !== '--lock' || argv[4] !== '--output-root' || argv[6] !== '--receipt') fail('usage is --contract-root <root> --lock <lock> --output-root <absent> --receipt <output>/journey_v3_generation_receipt.json'); return { contractRoot: argv[1], lockPath: argv[3], outputRoot: argv[5], receiptPath: argv[7] }; }
export function validateJourneyV3ClientInputForTest(options) { return validate({ ...options, enforceTrackedLock: false, enforceSchemasProjection: options.enforceSchemasProjection === true }); }
if (process.argv[1] === generatorSourcePath) try { const options = parseArguments(process.argv.slice(2)); publishGeneration(options, buildGeneration(options, true)); } catch (error) { process.stderr.write(`${error.message}\n`); process.exitCode = 1; }
