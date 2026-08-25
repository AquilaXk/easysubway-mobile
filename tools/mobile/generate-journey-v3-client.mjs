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
  ['/api/v3/station-timetables/search', { id: 'searchStationTimetables', responses: ['200', '400', '404', '503', '401', '429'], request: 'StationTimetableSearchRequest', success: 'StationTimetableSearchSuccess' }],
]);
const expectedErrorTuples = [
  ['searchJourneys', 400, 'INVALID_JOURNEY_REQUEST'], ['searchJourneys', 404, 'STATION_NOT_FOUND'], ['searchJourneys', 422, 'ROUTE_NOT_FOUND'], ['searchJourneys', 422, 'ACCESSIBILITY_CONSTRAINT_UNSATISFIED'], ['searchJourneys', 503, 'ROUTING_BUNDLE_UNAVAILABLE'], ['searchJourneys', 503, 'ROUTING_BUNDLE_STALE'], ['searchJourneys', 503, 'TIMETABLE_UNAVAILABLE'], ['searchJourneys', 503, 'TIMETABLE_STALE'], ['searchJourneys', 503, 'REALTIME_REQUIRED_UNAVAILABLE'], ['searchJourneys', 503, 'ROUTING_IDENTITY_MISMATCH'], ['searchJourneys', 503, 'ROUTE_SERVICE_UNAVAILABLE'], ['searchJourneys', 504, 'JOURNEY_SEARCH_TIMEOUT'], ['searchJourneys', 401, 'ROUTE_SESSION_REQUIRED'], ['searchJourneys', 429, 'ROUTE_RATE_LIMITED'], ['issueJourneySession', 400, 'INVALID_JOURNEY_SESSION_REQUEST'], ['issueJourneySession', 403, 'ROUTE_SESSION_ATTESTATION_REJECTED'], ['issueJourneySession', 503, 'ROUTE_SESSION_ATTESTATION_UNAVAILABLE'],
  ['searchStationTimetables', 400, 'INVALID_JOURNEY_REQUEST'], ['searchStationTimetables', 404, 'STATION_LINE_NOT_FOUND'], ['searchStationTimetables', 404, 'TIMETABLE_NOT_COVERED'], ['searchStationTimetables', 503, 'TIMETABLE_UNAVAILABLE'], ['searchStationTimetables', 503, 'TIMETABLE_STALE'], ['searchStationTimetables', 503, 'TIMETABLE_IDENTITY_MISMATCH'], ['searchStationTimetables', 401, 'ROUTE_SESSION_REQUIRED'], ['searchStationTimetables', 429, 'ROUTE_RATE_LIMITED'],
];
const sha256 = (bytes) => createHash('sha256').update(bytes).digest('hex');
const fail = (message) => { throw new Error(`generate-journey-v3-client: ${message}`); };
const isObject = (value) => value !== null && typeof value === 'object' && !Array.isArray(value);
const expectedSchemasProjectionSha256 = '2fd5f6106faee5b1faff6e4a7241d30a188a89d8e55f135326fe34deee596d98';

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
  if (raw.startsWith('[') && raw.endsWith(']')) { const inner = raw.slice(1, -1); if (inner === '') return []; if (/[{}]/.test(inner)) fail(`${label} has unsupported inline construct`); return inner.split(',').map((part) => { const item = part.trim(); if (!item || item !== part.trim()) fail(`${label} has noncanonical inline array`); return parseScalar(item, label); }); }
  if (/^[^\s][^#{}[\]]*$/.test(raw)) return raw;
  fail(`${label} has unsupported YAML scalar`);
}

function parseYaml(text) {
  if (!text.endsWith('\n') || /\t|(^|\s)[&*!]|(^|\s)<<:|(^|\s)[>|]/m.test(text)) fail('OpenAPI has unsupported YAML construct');
  const lines = text.split('\n').slice(0, -1).map((line, index) => ({ line, number: index + 1 }));
  if (lines.some(({ line }) => line === '' || /[ \t]$/.test(line))) fail('OpenAPI has noncanonical YAML whitespace');
  let index = 0;
  const current = () => lines[index];
  const indentOf = (line) => line.match(/^ */)[0].length;
  const keyValue = (body, label) => { const match = /^("(?:[^"\\]|\\.)+"|\$ref|\/[A-Za-z0-9_./{}-]*|[A-Za-z][A-Za-z0-9_./$-]*):(?: ?(.*))?$/.exec(body); if (!match) fail(`${label} has unsupported YAML mapping`); const key = match[1].startsWith('"') ? parseScalar(match[1], label) : match[1]; return [key, match[2] ?? '']; };
  const block = (indent) => {
    if (!current() || indentOf(current().line) !== indent) fail(`OpenAPI line ${current()?.number ?? 'EOF'} has noncanonical indentation`);
    const sequence = current().line.slice(indent).startsWith('-'); const result = sequence ? [] : {};
    while (current() && indentOf(current().line) === indent) {
      const body = current().line.slice(indent);
      if (sequence) {
        if (!body.startsWith('- ') || body === '-') fail(`OpenAPI line ${current().number} has unsupported YAML sequence`);
        const rest = body.slice(2); index += 1;
        if (/^[A-Za-z$][A-Za-z0-9_$-]*:/.test(rest)) { const [key, raw] = keyValue(rest, `OpenAPI line ${lines[index - 1].number}`); const entry = {}; if (raw === '') entry[key] = current() && indentOf(current().line) > indent ? block(indent + 2) : fail(`OpenAPI line ${lines[index - 1].number} needs child`); else entry[key] = parseScalar(raw, `OpenAPI line ${lines[index - 1].number}`); if (current() && indentOf(current().line) === indent + 2 && !current().line.slice(indent + 2).startsWith('-')) { const tail = block(indent + 2); for (const [tailKey, tailValue] of Object.entries(tail)) { if (tailKey in entry) fail(`OpenAPI line ${current()?.number ?? 'EOF'} has duplicate key ${tailKey}`); entry[tailKey] = tailValue; } } result.push(entry); } else result.push(parseScalar(rest, `OpenAPI line ${lines[index - 1].number}`));
      } else {
        if (body.startsWith('- ')) fail(`OpenAPI line ${current().number} mixes YAML sequence and mapping`); const [key, raw] = keyValue(body, `OpenAPI line ${current().number}`); if (key in result) fail(`OpenAPI line ${current().number} has duplicate key ${key}`); index += 1; result[key] = raw === '' ? (current() && indentOf(current().line) > indent ? block(indent + 2) : fail(`OpenAPI line ${lines[index - 1].number} needs child`)) : parseScalar(raw, `OpenAPI line ${lines[index - 1].number}`);
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
  const nullableFields = new Set(['JourneySourceIdentity.realtimeSnapshotId', 'Journey.realtimeDepartureTime', 'Journey.realtimeArrivalTime', 'JourneyRideLeg.realtimeDepartureTime', 'JourneyRideLeg.realtimeArrivalTime']);
  const schema = (value, label) => { if (!isObject(value)) fail(`${label} must be a schema object`); if ('$ref' in value) { assertAllowed(value, ['$ref'], label); visit(ref(value.$ref, label)); return; } if ('oneOf' in value) { assertAllowed(value, ['oneOf'], label); const descriptor = { JourneyDeparture: { tag: 'mode', refs: ['JourneyDepartureNow', 'JourneyDepartureScheduled'] }, JourneyLeg: { tag: 'type', refs: ['JourneyEntryLeg', 'JourneyRideLeg', 'JourneyTransferLeg', 'JourneyExitLeg'] }, StationTimetableSelector: { tag: 'kind', refs: ['StationTimetableServiceDateSelector', 'StationTimetableDayTypeSelector', 'StationTimetableNextDeparturesSelector'] } }[label]; if (!descriptor || value.oneOf.length !== descriptor.refs.length) fail(`${label} must be the exact closed tagged oneOf`); const tags = new Set(); for (const [index, part] of value.oneOf.entries()) { if (!isObject(part) || Object.keys(part).length !== 1 || ref(part.$ref, label) !== descriptor.refs[index]) fail(`${label} oneOf is unsupported`); const target = descriptor.refs[index]; visit(target); const tag = schemas[target]?.properties?.[descriptor.tag]?.enum; if (!Array.isArray(tag) || tag.length !== 1 || tags.has(tag[0])) fail(`${label} oneOf is not tagged by ${descriptor.tag}`); tags.add(tag[0]); } return; } if (value.type === 'object') { assertAllowed(value, ['type', 'additionalProperties', 'required', 'properties', 'not'], label); if (value.additionalProperties !== false || !Array.isArray(value.required) || !isObject(value.properties) || new Set(value.required).size !== value.required.length || Object.keys(value.properties).length !== value.required.length || value.required.some((key) => !(key in value.properties))) fail(`${label} must have an exact closed required property set`); for (const [key, child] of Object.entries(value.properties)) { if (!/^[A-Za-z][A-Za-z0-9]*$/.test(key)) fail(`${label} has unsupported property`); schema(child, `${label}.${key}`); } if ('not' in value && (!isObject(value.not) || !Array.isArray(value.not.required) || !isObject(value.not.properties))) fail(`${label} has unsupported not constraint`); return; } if (value.type === 'string') { assertAllowed(value, ['type', 'minLength', 'maxLength', 'pattern', 'format', 'enum', 'nullable'], label); for (const key of ['minLength', 'maxLength']) if (key in value && (!Number.isInteger(value[key]) || value[key] < 0)) fail(`${label} has invalid ${key}`); if ('minLength' in value && 'maxLength' in value && value.minLength > value.maxLength) fail(`${label} has unordered lengths`); if ('pattern' in value) { if (typeof value.pattern !== 'string' || value.pattern.length === 0) fail(`${label} has invalid pattern`); try { new RegExp(value.pattern); } catch { fail(`${label} has invalid pattern`); } } if ('format' in value && !['date', 'date-time'].includes(value.format)) fail(`${label} has unsupported string format`); if ('enum' in value && (!Array.isArray(value.enum) || value.enum.length === 0 || value.enum.some((item) => typeof item !== 'string') || new Set(value.enum).size !== value.enum.length)) fail(`${label} has invalid string enum`); if ('nullable' in value && (value.nullable !== true || !nullableFields.has(label))) fail(`${label} has unsupported nullable string`); return; } if (value.type === 'integer') { assertAllowed(value, ['type', 'minimum', 'maximum'], label); for (const key of ['minimum', 'maximum']) if (key in value && !Number.isInteger(value[key])) fail(`${label} has invalid ${key}`); if ('minimum' in value && 'maximum' in value && value.minimum > value.maximum) fail(`${label} has unordered integer bounds`); return; } if (value.type === 'boolean') { assertAllowed(value, ['type'], label); return; } if (value.type === 'array') { assertAllowed(value, ['type', 'minItems', 'maxItems', 'uniqueItems', 'items'], label); for (const key of ['minItems', 'maxItems']) if (key in value && (!Number.isInteger(value[key]) || value[key] < 0)) fail(`${label} has invalid ${key}`); if ('minItems' in value && 'maxItems' in value && value.minItems > value.maxItems) fail(`${label} has unordered array bounds`); if ('uniqueItems' in value && typeof value.uniqueItems !== 'boolean') fail(`${label} has invalid uniqueItems`); if (!('items' in value)) fail(`${label} array items are required`); schema(value.items, `${label}.items`); return; } fail(`${label} has unsupported schema type`); };
  for (const name of Object.keys(schemas)) visit(name);
  if (enforceSchemasProjection) {
    const projectionSha256 = sha256(Buffer.from(canonicalJson(schemas), 'utf8'));
    if (projectionSha256 !== expectedSchemasProjectionSha256) fail(`components.schemas projection SHA-256 does not match ${projectionSha256}`);
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
    assertAllowed(operation, ['operationId', 'summary', ...(protectedOperation ? ['security'] : []), ...(expectation.id === 'searchJourneys' ? ['x-easysubway-time-policy-contract'] : []), 'requestBody', 'responses'], path);
    if (operation.operationId !== expectation.id || !isObject(operation.requestBody) || operation.requestBody.required !== true || responseSchema({ content: operation.requestBody.content }, `${path} request`) !== expectation.request || !isObject(operation.responses) || expectation.responses.some((status) => !(status in operation.responses)) || Object.keys(operation.responses).length !== expectation.responses.length) fail(`${path} operation contract is unsupported`);
    if (protectedOperation && (!Array.isArray(operation.security) || operation.security.length !== 1 || JSON.stringify(operation.security[0]) !== JSON.stringify({ JourneySessionBearer: [] }))) fail(`${expectation.id} must require JourneySessionBearer`);
    if (expectation.id === 'searchJourneys') { exactKeys(operation['x-easysubway-time-policy-contract'], ['TIMETABLE_REQUIRED', 'REALTIME_REQUIRED'], 'search time policy'); if (operation['x-easysubway-time-policy-contract'].TIMETABLE_REQUIRED !== 'realtime-fields-null' || operation['x-easysubway-time-policy-contract'].REALTIME_REQUIRED !== 'realtime-fields-required-non-null') fail('search time policy values are unsupported'); }
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

function validate({ contractRoot, lockPath, enforceTrackedLock, enforceSchemasProjection, snapshot }) {
  if (enforceTrackedLock && resolve(lockPath) !== trackedLock) fail('lock must be the tracked journey-v3-client lock'); const lockBytes = snapshot?.lockBytes ?? regular(lockPath, 'lock'); const lock = duplicateFreeJson(lockBytes.toString('utf8'), 'lock'); validateLock(lock); validateStage(lock, lockBytes, contractRoot, snapshot);
  const catalogBytes = snapshot?.resourceBytes[resourcePaths[0]] ?? regular(join(contractRoot, resourcePaths[0]), 'error catalog'); const dispositionBytes = snapshot?.resourceBytes[resourcePaths[1]] ?? regular(join(contractRoot, resourcePaths[1]), 'error disposition'); const sessionIntegrityBytes = snapshot?.resourceBytes[resourcePaths[2]] ?? regular(join(contractRoot, resourcePaths[2]), 'session integrity'); const yaml = (snapshot?.resourceBytes[resourcePaths[3]] ?? regular(join(contractRoot, resourcePaths[3]), 'OpenAPI')).toString('utf8'); const catalog = duplicateFreeJson(catalogBytes.toString('utf8'), 'error catalog'); const disposition = duplicateFreeJson(dispositionBytes.toString('utf8'), 'error disposition'); const sessionIntegrity = validateSessionIntegrity(sessionIntegrityBytes); if (disposition.sourceCatalog?.sha256 !== sha256(catalogBytes)) fail('error disposition source catalog SHA-256 does not match'); const document = parseYaml(yaml); const operations = validateOperations(document); const schemas = validateSchemas(document.components.schemas, enforceSchemasProjection); validateOperationSchemaReferences(operations, schemas); const requestNot = schemas.JourneySearchRequest?.not; exactKeys(requestNot, ['required', 'properties'], 'JourneySearchRequest.not'); exactKeys(requestNot.properties, ['mobilityProfile', 'constraintMode'], 'JourneySearchRequest.not.properties'); if (JSON.stringify(requestNot.required) !== JSON.stringify(['mobilityProfile', 'constraintMode']) || JSON.stringify(requestNot.properties.mobilityProfile?.enum) !== JSON.stringify(['NO_STAIRS']) || JSON.stringify(requestNot.properties.constraintMode?.enum) !== JSON.stringify(['NONE'])) fail('JourneySearchRequest must prohibit NO_STAIRS plus NONE'); const errors = validateErrors(catalog, disposition); const errorCodes = schemas.JourneyErrorCode?.enum; const catalogCodes = new Set(errors.map((entry) => entry.code)); if (!Array.isArray(errorCodes) || errorCodes.length !== catalogCodes.size || new Set(errorCodes).size !== errorCodes.length || errorCodes.some((code) => !catalogCodes.has(code))) fail('JourneyErrorCode must exactly bind the declared catalog'); return Object.freeze({ operations: Object.freeze(operations), schemas: Object.freeze(schemas), errorCatalog: Object.freeze(errors), errorDispositions: errors, sessionIntegrity });
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
  return replaceRequired(source, "'timePolicy': timePolicy.wire, 'mobilityProfile': mobilityProfile.wire", "'timePolicy': timePolicy.wire, 'walkingPace': walkingPace.wire, 'mobilityProfile': mobilityProfile.wire", 'search request walking pace JSON encoding');
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

class JourneyRideLeg extends JourneyLeg {
  final String lineId; final String tripId; final String directionStationId; final String fromStationId; final String toStationId;
  final DateTime plannedDepartureTime; final DateTime plannedArrivalTime; final DateTime? realtimeDepartureTime; final DateTime? realtimeArrivalTime;
  const JourneyRideLeg({required this.lineId, required this.tripId, required this.directionStationId, required this.fromStationId, required this.toStationId, required this.plannedDepartureTime, required this.plannedArrivalTime, required this.realtimeDepartureTime, required this.realtimeArrivalTime});
  factory JourneyRideLeg.fromJson(Map<String, Object?> json) {
    JourneyV3Validation.exactKeys(json, {'type', 'lineId', 'tripId', 'directionStationId', 'fromStationId', 'toStationId', 'plannedDepartureTime', 'plannedArrivalTime', 'realtimeDepartureTime', 'realtimeArrivalTime'});
    if (JourneyLegTypeWire.fromWire(json['type']) != JourneyLegType.ride) throw const FormatException('leg type');
    return JourneyRideLeg(lineId: JourneyV3Validation.nonBlank(json['lineId'], 'lineId'), tripId: JourneyV3Validation.nonBlank(json['tripId'], 'tripId'), directionStationId: JourneyV3Validation.nonBlank(json['directionStationId'], 'directionStationId'), fromStationId: JourneyV3Validation.nonBlank(json['fromStationId'], 'fromStationId'), toStationId: JourneyV3Validation.nonBlank(json['toStationId'], 'toStationId'), plannedDepartureTime: JourneyV3Validation.rfc3339(json['plannedDepartureTime'], 'plannedDepartureTime'), plannedArrivalTime: JourneyV3Validation.rfc3339(json['plannedArrivalTime'], 'plannedArrivalTime'), realtimeDepartureTime: JourneyV3Validation.nullable(json, 'realtimeDepartureTime', (value) => JourneyV3Validation.rfc3339(value, 'realtimeDepartureTime')), realtimeArrivalTime: JourneyV3Validation.nullable(json, 'realtimeArrivalTime', (value) => JourneyV3Validation.rfc3339(value, 'realtimeArrivalTime')));
  }
  @override Map<String, Object?> toJson() => {'type': JourneyLegType.ride.wire, 'lineId': lineId, 'tripId': tripId, 'directionStationId': directionStationId, 'fromStationId': fromStationId, 'toStationId': toStationId, 'plannedDepartureTime': JourneyV3Validation.rfc3339Wire(plannedDepartureTime), 'plannedArrivalTime': JourneyV3Validation.rfc3339Wire(plannedArrivalTime), 'realtimeDepartureTime': realtimeDepartureTime == null ? null : JourneyV3Validation.rfc3339Wire(realtimeDepartureTime!), 'realtimeArrivalTime': realtimeArrivalTime == null ? null : JourneyV3Validation.rfc3339Wire(realtimeArrivalTime!)};
}

class JourneyTransferLeg extends JourneyLeg {
  final String fromStationId; final String toStationId; final int durationSeconds;
  const JourneyTransferLeg({required this.fromStationId, required this.toStationId, required this.durationSeconds});
  factory JourneyTransferLeg.fromJson(Map<String, Object?> json) {
    JourneyV3Validation.exactKeys(json, {'type', 'fromStationId', 'toStationId', 'durationSeconds'});
    if (JourneyLegTypeWire.fromWire(json['type']) != JourneyLegType.transfer) throw const FormatException('leg type');
    return JourneyTransferLeg(fromStationId: JourneyV3Validation.nonBlank(json['fromStationId'], 'fromStationId'), toStationId: JourneyV3Validation.nonBlank(json['toStationId'], 'toStationId'), durationSeconds: JourneyV3Validation.integer(json['durationSeconds'], 'durationSeconds', 0));
  }
  @override Map<String, Object?> toJson() => {'type': JourneyLegType.transfer.wire, 'fromStationId': fromStationId, 'toStationId': toStationId, 'durationSeconds': durationSeconds};
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

function renderStrictModels() {
  let source = renderWalkingPaceResponseModels(renderModels());
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
class StationTimetableDeparture { final JourneyDate serviceDate; final int secondsFromServiceDayStart; final DateTime departureAt; final StationTimetableServicePattern servicePattern; final StationTimetableServiceClass serviceClass; const StationTimetableDeparture({required this.serviceDate,required this.secondsFromServiceDayStart,required this.departureAt,required this.servicePattern,required this.serviceClass}); factory StationTimetableDeparture.fromJson(Map<String,Object?> json) { JourneyV3Validation.exactKeys(json, {'serviceDate','secondsFromServiceDayStart','departureAt','servicePattern','serviceClass'}); return StationTimetableDeparture(serviceDate:JourneyDate.parse(json['serviceDate']),secondsFromServiceDayStart:JourneyV3Validation.integer(json['secondsFromServiceDayStart'],'secondsFromServiceDayStart',0,107999),departureAt:JourneyV3Validation.rfc3339(json['departureAt'],'departureAt'),servicePattern:StationTimetableServicePatternWire.fromWire(json['servicePattern']),serviceClass:StationTimetableServiceClassWire.fromWire(json['serviceClass'])); } Map<String,Object?> toJson()=>{'serviceDate':serviceDate.toString(),'secondsFromServiceDayStart':secondsFromServiceDayStart,'departureAt':JourneyV3Validation.rfc3339Wire(departureAt),'servicePattern':servicePattern.wire,'serviceClass':serviceClass.wire}; }
class StationTimetableDirectionGroup { final String directionName; final List<StationTimetableDeparture> departures; const StationTimetableDirectionGroup({required this.directionName,required this.departures}); factory StationTimetableDirectionGroup.fromJson(Map<String,Object?> json) { JourneyV3Validation.exactKeys(json, {'directionName','departures'}); return StationTimetableDirectionGroup(directionName:JourneyV3Validation.nonBlank(json['directionName'],'directionName'),departures:JourneyV3Validation.list(json['departures'],'departures',(v){if(v is! Map<String,Object?>) throw const FormatException('departure must be object');return StationTimetableDeparture.fromJson(v);})); } Map<String,Object?> toJson()=>{'directionName':directionName,'departures':departures.map((v)=>v.toJson()).toList(growable:false)}; }
class StationTimetableSourceIdentity { final String timetableArtifactId; final String timetableSnapshotSha256; final String canonicalStationVersion; final String canonicalStationSetSha256; final String sourceLineageSha256; final String evidenceHash; final DateTime freshUntil; const StationTimetableSourceIdentity({required this.timetableArtifactId,required this.timetableSnapshotSha256,required this.canonicalStationVersion,required this.canonicalStationSetSha256,required this.sourceLineageSha256,required this.evidenceHash,required this.freshUntil}); factory StationTimetableSourceIdentity.fromJson(Map<String,Object?> json) { JourneyV3Validation.exactKeys(json, {'timetableArtifactId','timetableSnapshotSha256','canonicalStationVersion','canonicalStationSetSha256','sourceLineageSha256','evidenceHash','freshUntil'}); return StationTimetableSourceIdentity(timetableArtifactId:JourneyV3Validation.nonBlank(json['timetableArtifactId'],'timetableArtifactId'),timetableSnapshotSha256:JourneyV3Validation.sha256(json['timetableSnapshotSha256'],'timetableSnapshotSha256'),canonicalStationVersion:JourneyV3Validation.nonBlank(json['canonicalStationVersion'],'canonicalStationVersion'),canonicalStationSetSha256:JourneyV3Validation.sha256(json['canonicalStationSetSha256'],'canonicalStationSetSha256'),sourceLineageSha256:JourneyV3Validation.sha256(json['sourceLineageSha256'],'sourceLineageSha256'),evidenceHash:JourneyV3Validation.sha256(json['evidenceHash'],'evidenceHash'),freshUntil:JourneyV3Validation.rfc3339(json['freshUntil'],'freshUntil')); } Map<String,Object?> toJson()=>{'timetableArtifactId':timetableArtifactId,'timetableSnapshotSha256':timetableSnapshotSha256,'canonicalStationVersion':canonicalStationVersion,'canonicalStationSetSha256':canonicalStationSetSha256,'sourceLineageSha256':sourceLineageSha256,'evidenceHash':evidenceHash,'freshUntil':JourneyV3Validation.rfc3339Wire(freshUntil)}; }
class StationTimetableSearchSuccess { final StationTimetableSearchContractVersion contractVersion; final String stationId; final String lineId; final StationTimetableSelector selector; final StationTimetableDayType resolvedDayType; final StationTimetableServiceTimezone serviceTimezone; final List<StationTimetableDirectionGroup> directionGroups; final StationTimetableSourceIdentity sourceIdentity; const StationTimetableSearchSuccess({required this.contractVersion,required this.stationId,required this.lineId,required this.selector,required this.resolvedDayType,required this.serviceTimezone,required this.directionGroups,required this.sourceIdentity}); factory StationTimetableSearchSuccess.fromJson(Map<String,Object?> json) { JourneyV3Validation.exactKeys(json, {'contractVersion','stationId','lineId','selector','resolvedDayType','serviceTimezone','directionGroups','sourceIdentity'}); final selector=json['selector']; final sourceIdentity=json['sourceIdentity']; if(selector is! Map<String,Object?>||sourceIdentity is! Map<String,Object?>) throw const FormatException('nested timetable object'); return StationTimetableSearchSuccess(contractVersion:StationTimetableSearchContractVersionWire.fromWire(json['contractVersion']),stationId:JourneyV3Validation.nonBlank(json['stationId'],'stationId'),lineId:JourneyV3Validation.nonBlank(json['lineId'],'lineId'),selector:StationTimetableSelector.fromJson(selector),resolvedDayType:StationTimetableDayTypeWire.fromWire(json['resolvedDayType']),serviceTimezone:StationTimetableServiceTimezoneWire.fromWire(json['serviceTimezone']),directionGroups:JourneyV3Validation.list(json['directionGroups'],'directionGroups',(v){if(v is! Map<String,Object?>) throw const FormatException('direction group must be object');return StationTimetableDirectionGroup.fromJson(v);}),sourceIdentity:StationTimetableSourceIdentity.fromJson(sourceIdentity)); } Map<String,Object?> toJson()=>{'contractVersion':contractVersion.wire,'stationId':stationId,'lineId':lineId,'selector':selector.toJson(),'resolvedDayType':resolvedDayType.wire,'serviceTimezone':serviceTimezone.wire,'directionGroups':directionGroups.map((v)=>v.toJson()).toList(growable:false),'sourceIdentity':sourceIdentity.toJson()}; }
`;
}

export function renderJourneyV3ModelsForTest(options) { validate({ ...options, enforceTrackedLock: false }); return renderStrictModels(); }
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
  return Object.freeze({
    'journey_v3_contract.dart': generatedHeader(renderDartContract(lock, ir.sessionIntegrity)),
    'journey_v3_enums.dart': generatedHeader(renderDartEnums(ir)),
    'journey_v3_error.dart': generatedHeader(renderClosedErrors(ir)),
    'journey_v3_models.dart': generatedHeader(renderStrictModels()),
    'journey_v3_validation.dart': generatedHeader(renderStrictValidation()),
  });
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
