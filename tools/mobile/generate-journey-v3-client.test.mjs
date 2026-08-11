import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { cpSync, existsSync, lstatSync, mkdtempSync, mkdirSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, relative } from 'node:path';
import test from 'node:test';
import { renderJourneyV3DartLiteralSeamForTest, renderJourneyV3ErrorsAndBarrelForTest, renderJourneyV3FilesForTest, renderJourneyV3ModelsForTest, renderJourneyV3RequestModelsForTest, renderJourneyV3ResponseModelsForTest, renderJourneyV3ValidationAndEnumsForTest, validateJourneyV3ClientInputForTest } from './generate-journey-v3-client.mjs';

const repository = join(import.meta.dirname, '..', '..');
const generator = join(repository, 'tools/mobile/generate-journey-v3-client.mjs');
const producerFixture = join(repository, 'tools/mobile/fixtures/journey-v3-contract-v2');
const trackedLock = join(repository, 'contracts/mobile/journey-v3-client.lock.json');
const sha256 = (value) => createHash('sha256').update(value).digest('hex');
function tokenFiles(root, token) { const found = []; const walk = (directory) => { for (const entry of readdirSync(directory).sort()) { const file = join(directory, entry); const stat = lstatSync(file); if (stat.isSymbolicLink()) continue; if (stat.isDirectory()) walk(file); else if (stat.isFile() && readFileSync(file).includes(token)) found.push(relative(root, file).split('\\').join('/')); } }; walk(join(root, 'tools')); return found.sort(); }
const codes = ['INVALID_JOURNEY_REQUEST', 'STATION_NOT_FOUND', 'ROUTE_NOT_FOUND', 'ACCESSIBILITY_CONSTRAINT_UNSATISFIED', 'ROUTING_BUNDLE_UNAVAILABLE', 'ROUTING_BUNDLE_STALE', 'TIMETABLE_UNAVAILABLE', 'TIMETABLE_STALE', 'REALTIME_REQUIRED_UNAVAILABLE', 'ROUTING_IDENTITY_MISMATCH', 'ROUTE_SERVICE_UNAVAILABLE', 'JOURNEY_SEARCH_TIMEOUT', 'ROUTE_SESSION_REQUIRED', 'ROUTE_RATE_LIMITED', 'INVALID_JOURNEY_SESSION_REQUEST', 'ROUTE_SESSION_ATTESTATION_REJECTED', 'ROUTE_SESSION_ATTESTATION_UNAVAILABLE'];
const entries = codes.map((code, index) => ({ operation: index < 14 ? 'searchJourneys' : 'issueJourneySession', httpStatus: [400, 404, 422, 422, 503, 503, 503, 503, 503, 503, 503, 504, 401, 429, 400, 403, 503][index], code }));
const openapi = `openapi: 3.0.3
info:
  title: Journey
  version: 3.0.0
paths:
  /api/v3/journeys/session:
    post:
      operationId: issueJourneySession
      summary: issue
      requestBody:
        required: true
        content:
          application/json:
            schema:
              $ref: "#/components/schemas/JourneySessionRequest"
      responses:
        "200":
          description: ok
          content:
            application/json:
              schema:
                $ref: "#/components/schemas/JourneySessionResponse"
        "400":
          description: error
          content:
            application/json:
              schema:
                $ref: "#/components/schemas/JourneyError"
        "403":
          description: error
          content:
            application/json:
              schema:
                $ref: "#/components/schemas/JourneyError"
        "503":
          description: error
          content:
            application/json:
              schema:
                $ref: "#/components/schemas/JourneyError"
  /api/v3/journeys/search:
    post:
      operationId: searchJourneys
      summary: search
      security:
        - JourneySessionBearer: []
      x-easysubway-time-policy-contract:
        TIMETABLE_REQUIRED: realtime-fields-null
        REALTIME_REQUIRED: realtime-fields-required-non-null
      requestBody:
        required: true
        content:
          application/json:
            schema:
              $ref: "#/components/schemas/JourneySearchRequest"
      responses:
        "200":
          description: ok
          content:
            application/json:
              schema:
                $ref: "#/components/schemas/JourneySearchSuccess"
        "400":
          description: error
          content:
            application/json:
              schema:
                $ref: "#/components/schemas/JourneyError"
        "404":
          description: error
          content:
            application/json:
              schema:
                $ref: "#/components/schemas/JourneyError"
        "422":
          description: error
          content:
            application/json:
              schema:
                $ref: "#/components/schemas/JourneyError"
        "503":
          description: error
          content:
            application/json:
              schema:
                $ref: "#/components/schemas/JourneyError"
        "504":
          description: error
          content:
            application/json:
              schema:
                $ref: "#/components/schemas/JourneyError"
        "401":
          description: error
          content:
            application/json:
              schema:
                $ref: "#/components/schemas/JourneyError"
        "429":
          description: error
          content:
            application/json:
              schema:
                $ref: "#/components/schemas/JourneyError"
components:
  securitySchemes:
    JourneySessionBearer:
      type: http
      scheme: bearer
      bearerFormat: opaque-route-session
  schemas:
    JourneySessionRequest:
      type: object
      additionalProperties: false
      required: [value]
      properties:
        value:
          type: string
          minLength: 1
    JourneySessionResponse:
      type: object
      additionalProperties: false
      required: [value]
      properties:
        value:
          type: string
    JourneySearchRequest:
      type: object
      additionalProperties: false
      required: [requestId, originStationId, destinationStationId, departure, timePolicy, mobilityProfile, constraintMode, maxTransfers, alternativeCount]
      properties:
        requestId:
          type: string
          pattern: "^[0-7][0-9A-HJKMNP-TV-Z]{25}$"
        originStationId:
          type: string
          minLength: 1
        destinationStationId:
          type: string
          minLength: 1
        departure:
          $ref: "#/components/schemas/JourneyDeparture"
        timePolicy:
          $ref: "#/components/schemas/TimePolicy"
        mobilityProfile:
          $ref: "#/components/schemas/MobilityProfile"
        constraintMode:
          $ref: "#/components/schemas/ConstraintMode"
        maxTransfers:
          type: integer
          minimum: 0
          maximum: 3
        alternativeCount:
          type: integer
          minimum: 1
          maximum: 3
      not:
        required: [mobilityProfile, constraintMode]
        properties:
          mobilityProfile:
            enum: [NO_STAIRS]
          constraintMode:
            enum: [NONE]
    JourneySearchSuccess:
      type: object
      additionalProperties: false
      required: [leg]
      properties:
        leg:
          $ref: "#/components/schemas/JourneyLeg"
    JourneyDeparture:
      oneOf:
        - $ref: "#/components/schemas/JourneyDepartureNow"
        - $ref: "#/components/schemas/JourneyDepartureScheduled"
    JourneyDepartureNow:
      type: object
      additionalProperties: false
      required: [mode]
      properties:
        mode:
          type: string
          enum: [NOW]
    JourneyDepartureScheduled:
      type: object
      additionalProperties: false
      required: [mode, requestedAt]
      properties:
        mode:
          type: string
          enum: [SCHEDULED]
        requestedAt:
          type: string
          format: date-time
    TimePolicy:
      type: string
      enum: [TIMETABLE_REQUIRED, REALTIME_REQUIRED]
    MobilityProfile:
      type: string
      enum: [STANDARD, SLOW, NO_STAIRS, STEP_FREE]
    ConstraintMode:
      type: string
      enum: [NONE, REQUIRE_STEP_FREE]
    JourneyLeg:
      oneOf:
        - $ref: "#/components/schemas/JourneyEntryLeg"
        - $ref: "#/components/schemas/JourneyRideLeg"
        - $ref: "#/components/schemas/JourneyTransferLeg"
        - $ref: "#/components/schemas/JourneyExitLeg"
    JourneyEntryLeg:
      type: object
      additionalProperties: false
      required: [type]
      properties:
        type:
          type: string
          enum: [ENTRY]
    JourneyRideLeg:
      type: object
      additionalProperties: false
      required: [type]
      properties:
        type:
          type: string
          enum: [RIDE]
    JourneyTransferLeg:
      type: object
      additionalProperties: false
      required: [type]
      properties:
        type:
          type: string
          enum: [TRANSFER]
    JourneyExitLeg:
      type: object
      additionalProperties: false
      required: [type]
      properties:
        type:
          type: string
          enum: [EXIT]
    JourneyErrorCode:
      type: string
      enum:
${codes.map((code) => `        - ${code}`).join('\n')}
    JourneyError:
      type: object
      additionalProperties: false
      required: [code]
      properties:
        code:
          $ref: "#/components/schemas/JourneyErrorCode"
`;

function fixture(root) {
  const contractRoot = join(root, 'contract'); const api = join(contractRoot, 'contracts/api'); mkdirSync(api, { recursive: true });
  const catalog = JSON.stringify({ schemaVersion: 'JOURNEY_ERROR_CATALOG_V1', artifactKind: 'journey-v3-error-catalog', applicationErrors: entries.slice(0, 12), ingressErrors: entries.slice(12) });
  const disposition = JSON.stringify({ schemaVersion: 'JOURNEY_ERROR_DISPOSITION_V1', artifactKind: 'journey-v3-error-disposition', sourceCatalog: { path: 'journey-v3-error-catalog.json', schemaVersion: 'JOURNEY_ERROR_CATALOG_V1', sha256: sha256(catalog) }, entries: entries.map(({ operation, httpStatus, code }) => ({ operation, httpStatus, machineCode: code, semanticCategory: 'SERVICE_UNAVAILABLE', exposure: 'MOBILE_USER_VISIBLE', userVisible: true, publicMessageKey: 'journey.error.test', canonicalKoreanCopy: '오류', mobileResourceKey: 'journeyErrorTest', mobilePresentation: 'FAILURE_SCREEN', retryDisposition: 'FORBIDDEN', primaryActionKey: null, secondaryActionKey: null, safeDiagnosticKey: 'journey.diagnostic.test', sensitiveDetailPolicy: 'NEVER_PUBLIC' })) });
  const sessionIntegrity = readFileSync(join(producerFixture, 'contracts/api/journey-v3-session-integrity.json'), 'utf8');
  writeFileSync(join(api, 'journey-v3-error-catalog.json'), catalog); writeFileSync(join(api, 'journey-v3-error-disposition.json'), disposition); writeFileSync(join(api, 'journey-v3-session-integrity.json'), sessionIntegrity); writeFileSync(join(api, 'journey-v3.openapi.yaml'), openapi);
  const resources = [['journey-v3-error-catalog', 'contracts/api/journey-v3-error-catalog.json', 'application/json', catalog], ['journey-v3-error-disposition', 'contracts/api/journey-v3-error-disposition.json', 'application/json', disposition], ['journey-v3-session-integrity', 'contracts/api/journey-v3-session-integrity.json', 'application/json', sessionIntegrity], ['journey-v3-openapi', 'contracts/api/journey-v3.openapi.yaml', 'application/yaml', openapi]].map(([id, path, mediaType, content]) => ({ id, path, owner: 'AquilaXk/easysubway-backend', mediaType, sha256: sha256(content) }));
  const lock = { schemaVersion: 2, component: 'backend', bundleVersion: '2.0.0', producer: { repository: 'AquilaXk/easysubway-backend', gitSha: 'd'.repeat(40) }, artifact: { repository: 'ghcr.io/aquilaxk/easysubway-backend-contracts', manifestDigest: `sha256:${'a'.repeat(64)}`, artifactType: 'application/vnd.easysubway.journey.contract-bundle.v2' }, payload: { fileName: 'journey-v3-contract-bundle-v2.json', mediaType: 'application/vnd.easysubway.journey.contract-bundle.v2+json', sha256: 'b'.repeat(64) }, publicationReceiptSha256: 'c'.repeat(64), resources }; const lockPath = join(root, 'lock.json'); writeFileSync(lockPath, `${JSON.stringify(lock)}\n`);
  const receipt = { schemaVersion: 1, lockSha256: sha256(readFileSync(lockPath)), payloadSha256: lock.payload.sha256, publicationReceiptSha256: lock.publicationReceiptSha256, artifact: lock.artifact, resources: Object.fromEntries(resources.map(({ path, sha256: digest }) => [path, digest])) }; writeFileSync(join(contractRoot, 'journey-v3-contract-stage-receipt.json'), JSON.stringify(receipt)); return { contractRoot, lockPath };
}

function rebind(value) {
  const lock = JSON.parse(readFileSync(value.lockPath));
  for (const resource of lock.resources) resource.sha256 = sha256(readFileSync(join(value.contractRoot, resource.path)));
  writeFileSync(value.lockPath, JSON.stringify(lock));
  writeFileSync(join(value.contractRoot, 'journey-v3-contract-stage-receipt.json'), JSON.stringify({ schemaVersion: 1, lockSha256: sha256(readFileSync(value.lockPath)), payloadSha256: lock.payload.sha256, publicationReceiptSha256: lock.publicationReceiptSha256, artifact: lock.artifact, resources: Object.fromEntries(lock.resources.map(({ path, sha256: digest }) => [path, digest])) }));
}

function exactProducerFixture(root) {
  const contractRoot = join(root, 'contract'); const api = join(contractRoot, 'contracts/api'); cpSync(join(producerFixture, 'contracts/api'), api, { recursive: true });
  const lockPath = join(root, 'lock.json'); cpSync(trackedLock, lockPath); const lock = JSON.parse(readFileSync(lockPath)); writeFileSync(join(contractRoot, 'journey-v3-contract-stage-receipt.json'), JSON.stringify({ schemaVersion: 1, lockSha256: sha256(readFileSync(lockPath)), payloadSha256: lock.payload.sha256, publicationReceiptSha256: lock.publicationReceiptSha256, artifact: lock.artifact, resources: Object.fromEntries(lock.resources.map(({ path, sha256: digest }) => [path, digest])) }));
  return { contractRoot, lockPath };
}

test('builds closed producer-shaped IR including tagged variants and disposition bindings', () => { const root = mkdtempSync(join(tmpdir(), 'journey-generator-')); try { const value = fixture(root); const ir = validateJourneyV3ClientInputForTest(value); assert.equal(ir.operations.length, 2); assert.equal(ir.errorCatalog.length, 17); assert.equal(ir.schemas.JourneyDeparture.oneOf.length, 2); assert.equal(ir.schemas.JourneyLeg.oneOf.length, 4); assert.equal(ir.errorDispositions.length, 17); assert.equal(Object.isFrozen(ir.errorDispositions[0]), true); assert.equal(ir.errorDispositions[0].code, 'INVALID_JOURNEY_REQUEST'); } finally { rmSync(root, { recursive: true, force: true }); } });
test('validates the exact locked four-resource producer bytes without sibling repository or network', () => { const root = mkdtempSync(join(tmpdir(), 'journey-generator-')); try { const ir = validateJourneyV3ClientInputForTest(exactProducerFixture(root)); assert.equal(ir.operations.length, 2); assert.equal(ir.errorCatalog.length, 17); assert.equal(ir.errorDispositions.length, 17); assert.equal(ir.sessionIntegrity.session.ttlSeconds, 600); } finally { rmSync(root, { recursive: true, force: true }); } });
test('rejects every closed session-integrity semantic mutation even after lock and receipt rebinding', () => { const root = mkdtempSync(join(tmpdir(), 'journey-generator-')); try { for (const [name, from, to] of [['nonce-source', '"source": "CSPRNG"', '"source": "PSEUDO"'], ['request-hash-version', '"version": 1', '"version": 2'], ['certificate-required', '"configuredCertificateSha256Required": true', '"configuredCertificateSha256Required": false'], ['session-ttl', '"ttlSeconds": 600', '"ttlSeconds": 601']]) { const value = exactProducerFixture(join(root, name)); const path = join(value.contractRoot, 'contracts/api/journey-v3-session-integrity.json'); writeFileSync(path, readFileSync(path, 'utf8').replace(from, to)); rebind(value); assert.throws(() => validateJourneyV3ClientInputForTest(value), /session integrity must match the closed published schema/); } } finally { rmSync(root, { recursive: true, force: true }); } });
test('rejects a session-integrity stage receipt mismatch before generation', () => { const root = mkdtempSync(join(tmpdir(), 'journey-generator-')); try { const value = exactProducerFixture(root); const receiptPath = join(value.contractRoot, 'journey-v3-contract-stage-receipt.json'); const receipt = JSON.parse(readFileSync(receiptPath)); receipt.resources['contracts/api/journey-v3-session-integrity.json'] = '0'.repeat(64); writeFileSync(receiptPath, JSON.stringify(receipt)); assert.throws(() => validateJourneyV3ClientInputForTest(value), /journey-v3-session-integrity\.json SHA-256 does not match staged lock/); } finally { rmSync(root, { recursive: true, force: true }); } });
test('rejects self-consistently rebound top-level and nested session-integrity key reorders', () => { const root = mkdtempSync(join(tmpdir(), 'journey-generator-')); try { for (const nested of [false, true]) { const value = exactProducerFixture(join(root, `${nested}`)); const path = join(value.contractRoot, 'contracts/api/journey-v3-session-integrity.json'); const session = JSON.parse(readFileSync(path)); const reordered = nested ? { ...session, verdict: { expectedAppPackageName: session.verdict.expectedAppPackageName, expectedRequestPackageName: session.verdict.expectedRequestPackageName, maxAgeSeconds: session.verdict.maxAgeSeconds, futureTimestampAllowed: session.verdict.futureTimestampAllowed, requiredAppRecognitionVerdict: session.verdict.requiredAppRecognitionVerdict, requiredAppLicensingVerdict: session.verdict.requiredAppLicensingVerdict, requiredDeviceRecognitionVerdict: session.verdict.requiredDeviceRecognitionVerdict, configuredCertificateSha256Required: session.verdict.configuredCertificateSha256Required, configuredCertificateSha256Encoding: session.verdict.configuredCertificateSha256Encoding, requestHashConstantTimeEqualityRequired: session.verdict.requestHashConstantTimeEqualityRequired, nonceSingleUseRequired: session.verdict.nonceSingleUseRequired, nonceClaimTtlSeconds: session.verdict.nonceClaimTtlSeconds } } : { artifactKind: session.artifactKind, schemaVersion: session.schemaVersion, operationId: session.operationId, nonce: session.nonce, requestHash: session.requestHash, verdict: session.verdict, session: session.session }; writeFileSync(path, `${JSON.stringify(reordered)}\n`); rebind(value); assert.throws(() => validateJourneyV3ClientInputForTest(value), /session integrity keys must use the published order/); } } finally { rmSync(root, { recursive: true, force: true }); } });
test('rejects semantically rebound components.schemas projections before rendering', () => { const root = mkdtempSync(join(tmpdir(), 'journey-generator-')); try { for (const [name, from, to] of [['token-length', 'maxLength: 16384', 'maxLength: 1024'], ['transfer-bound', 'maximum: 3', 'maximum: 4'], ['required-property-rename', '        - requestId\n', '        - requestIdentifier\n']]) { const value = exactProducerFixture(join(root, name)); const path = join(value.contractRoot, 'contracts/api/journey-v3.openapi.yaml'); let source = readFileSync(path, 'utf8').replace(from, to); if (name === 'required-property-rename') source = source.replace('        requestId:\n', '        requestIdentifier:\n'); writeFileSync(path, source); rebind(value); assert.throws(() => renderJourneyV3FilesForTest({ ...value, enforceSchemasProjection: true }), /components.schemas projection SHA-256/); } } finally { rmSync(root, { recursive: true, force: true }); } });
test('renders complete closed validation and enum sources from exact producer IR', () => { const root = mkdtempSync(join(tmpdir(), 'journey-generator-')); try { const input = exactProducerFixture(root); const first = renderJourneyV3ValidationAndEnumsForTest(input); const second = renderJourneyV3ValidationAndEnumsForTest(input); assert.deepEqual(first, second); for (const token of ['JOURNEY_SEARCH_V3', 'JOURNEY_ERROR_V1', 'journey:v3', 'NOW', 'SCHEDULED', 'TIMETABLE_REQUIRED', 'REALTIME_REQUIRED', 'NO_STAIRS', 'ENTRY', 'RIDE', 'TRANSFER', 'EXIT', 'REQUEST_CORRECTION', 'ACCESSIBILITY_UNSATISFIED', 'SERVICE_UNAVAILABLE', 'journey.action.editRequest', 'journey.action.reauthenticate', ...codes]) assert.match(first.enums, new RegExp(`"${token}"`)); for (const source of Object.values(first)) { assert.doesNotMatch(source, /default:|unknown|placeholder|TODO/); } assert.match(first.validation, /JourneyDate/); assert.match(first.validation, /invalid RFC3339 date-time/); assert.match(first.validation, /value\.toUtc\(\)\.toIso8601String\(\)/); assert.match(first.validation, /List<T>\.unmodifiable/); } finally { rmSync(root, { recursive: true, force: true }); } });
test('rebinding every semantic mutation still rejects stale receipt, YAML, policy and constraints precisely', () => { const root = mkdtempSync(join(tmpdir(), 'journey-generator-')); try { const stale = fixture(join(root, 'stale')); writeFileSync(join(stale.contractRoot, 'contracts/api/journey-v3.openapi.yaml'), 'openapi: 3.0.3\n'); assert.throws(() => validateJourneyV3ClientInputForTest(stale), /SHA-256/); const tag = fixture(join(root, 'tag')); const tagPath = join(tag.contractRoot, 'contracts/api/journey-v3.openapi.yaml'); writeFileSync(tagPath, readFileSync(tagPath, 'utf8').replace('required: [mode]', 'required: [type]').replace('        mode:\n          type: string\n          enum: [NOW]', '        type:\n          type: string\n          enum: [NOW]')); rebind(tag); assert.throws(() => validateJourneyV3ClientInputForTest(tag), /tagged by mode/); const policy = fixture(join(root, 'policy')); const policyPath = join(policy.contractRoot, 'contracts/api/journey-v3.openapi.yaml'); writeFileSync(policyPath, readFileSync(policyPath, 'utf8').replace('TIMETABLE_REQUIRED: realtime-fields-null', 'TIMETABLE_REQUIRED: wrong')); rebind(policy); assert.throws(() => validateJourneyV3ClientInputForTest(policy), /time policy values/); const not = fixture(join(root, 'not')); const notPath = join(not.contractRoot, 'contracts/api/journey-v3.openapi.yaml'); writeFileSync(notPath, readFileSync(notPath, 'utf8').replace('enum: [NO_STAIRS]', 'enum: [STANDARD]')); rebind(not); assert.throws(() => validateJourneyV3ClientInputForTest(not), /NO_STAIRS plus NONE/); const duplicate = fixture(join(root, 'duplicate')); const path = join(duplicate.contractRoot, 'contracts/api/journey-v3-error-catalog.json'); const text = '{"schemaVersion":"x","schemaVersion":"x"}'; writeFileSync(path, text); rebind(duplicate); assert.throws(() => validateJourneyV3ClientInputForTest(duplicate), /duplicate key schemaVersion/); } finally { rmSync(root, { recursive: true, force: true }); } });
test('rejects a rebound extra not key and malformed supported pattern precisely', () => { const root = mkdtempSync(join(tmpdir(), 'journey-generator-')); try { const extra = fixture(join(root, 'extra')); const extraPath = join(extra.contractRoot, 'contracts/api/journey-v3.openapi.yaml'); writeFileSync(extraPath, readFileSync(extraPath, 'utf8').replace('        properties:\n          mobilityProfile:', '        extra: true\n        properties:\n          mobilityProfile:')); rebind(extra); assert.throws(() => validateJourneyV3ClientInputForTest(extra), /JourneySearchRequest.not has unexpected or missing fields/); const pattern = fixture(join(root, 'pattern')); const patternPath = join(pattern.contractRoot, 'contracts/api/journey-v3.openapi.yaml'); writeFileSync(patternPath, readFileSync(patternPath, 'utf8').replace('pattern: "^[0-7][0-9A-HJKMNP-TV-Z]{25}$"', 'pattern: "["')); rebind(pattern); assert.throws(() => validateJourneyV3ClientInputForTest(pattern), /JourneySearchRequest.requestId has invalid pattern/); } finally { rmSync(root, { recursive: true, force: true }); } });
test('rejects operations whose declared request or response schema is absent from components', () => { const root = mkdtempSync(join(tmpdir(), 'journey-generator-')); try { const value = fixture(root); const path = join(value.contractRoot, 'contracts/api/journey-v3.openapi.yaml'); writeFileSync(path, readFileSync(path, 'utf8').replace('    JourneySessionRequest:\n', '    MissingRequest:\n')); rebind(value); assert.throws(() => validateJourneyV3ClientInputForTest(value), /operation issueJourneySession references missing schema JourneySessionRequest/); } finally { rmSync(root, { recursive: true, force: true }); } });
test('rejects generated enum declaration and wire-token name collisions', () => { const root = mkdtempSync(join(tmpdir(), 'journey-generator-')); try { const declaration = fixture(join(root, 'declaration')); const declarationPath = join(declaration.contractRoot, 'contracts/api/journey-v3.openapi.yaml'); writeFileSync(declarationPath, `${readFileSync(declarationPath, 'utf8')}    JourneyOperation:\n      type: string\n      enum: [OTHER]\n`); rebind(declaration); assert.throws(() => renderJourneyV3FilesForTest(declaration), /generated enum name collision JourneyOperation/); const token = fixture(join(root, 'token')); const tokenPath = join(token.contractRoot, 'contracts/api/journey-v3.openapi.yaml'); writeFileSync(tokenPath, `${readFileSync(tokenPath, 'utf8')}    CollidingWire:\n      type: string\n      enum: [A-B, A_B]\n`); rebind(token); assert.throws(() => renderJourneyV3FilesForTest(token), /generated enum token collision CollidingWire/); } finally { rmSync(root, { recursive: true, force: true }); } });
test('production CLI accepts no alternate lock and creates no output', () => { const root = mkdtempSync(join(tmpdir(), 'journey-generator-')); try { const value = fixture(root); const output = join(root, 'output'); assert.throws(() => execFileSync(process.execPath, [generator, '--contract-root', value.contractRoot, '--lock', value.lockPath, '--output-root', output, '--receipt', join(output, 'journey_v3_generation_receipt.json')], { encoding: 'utf8', stdio: 'pipe' }), /lock must be the tracked/); assert.equal(existsSync(output), false); } finally { rmSync(root, { recursive: true, force: true }); } });
test('the test-only IR seam has no tracked production caller', () => { const references = tokenFiles(repository, 'validateJourneyV3ClientInputForTest'); assert.deepEqual(references, ['tools/mobile/generate-journey-v3-client.mjs', 'tools/mobile/generate-journey-v3-client.test.mjs']); });
test('renders deterministic strict session, search request, and tagged departure source', () => { const root = mkdtempSync(join(tmpdir(), 'journey-generator-')); try { const input = exactProducerFixture(root); const first = renderJourneyV3RequestModelsForTest(input); const second = renderJourneyV3RequestModelsForTest(input); assert.equal(first, second); for (const token of ['class JourneySessionRequest', 'integrityToken', 'clientNonce', 'class JourneySessionResponse', 'issuedAt', 'expiresAt', 'sealed class JourneyDeparture', 'JourneyDepartureNow', 'JourneyDepartureScheduled', 'class JourneySearchRequest', 'requestId', 'originStationId', 'destinationStationId', 'alternativeCount', 'JourneyV3Validation.exactKeys', 'JourneyV3Validation.ulid', 'JourneyV3Validation.nonBlank', 'JourneyV3Validation.integer', 'JourneyV3Validation.rfc3339', 'NO_STAIRS plus NONE is forbidden', 'JourneyDeparture.fromJson', 'departure.toJson()']) assert.match(first, new RegExp(token.replace(/[()]/g, '\\$&'))); assert.doesNotMatch(first, / as [A-Z]|json\['[^']+'\] as/); } finally { rmSync(root, { recursive: true, force: true }); } });
test('renders deterministic strict response models with nullable and policy tokens', () => { const root = mkdtempSync(join(tmpdir(), 'journey-generator-')); try { const input=exactProducerFixture(root); const source=renderJourneyV3ResponseModelsForTest(input); assert.equal(source,renderJourneyV3ResponseModelsForTest(input)); for(const token of ['class JourneySourceIdentity','routeBundleSha256','realtimeSnapshotId','class JourneyRequestPolicy','class JourneyAccessibility','reasonCodes','class Journey','realtimeDepartureTime','realtimeArrivalTime','List<JourneyLeg> legs','class JourneySearchSuccess','sourceIdentity','requestPolicy','journeys','JourneyV3Validation.nullable','JourneyV3Validation.list','JourneyLeg.fromJson','JourneyDate.parse','TIMETABLE_REQUIRED realtime contract','REALTIME_REQUIRED realtime contract']) assert.match(source,new RegExp(token.replace(/[()]/g,'\\$&'))); assert.ok(source.includes('realtimeDepartureTime==null?null:')); assert.doesNotMatch(source,/json\['[^']+'\] as|default:|placeholder|TODO/); } finally { rmSync(root,{recursive:true,force:true}); } });
test('renders public request construction and source snapshot policy as fail-closed validation', () => { const root = mkdtempSync(join(tmpdir(), 'journey-generator-dart-')); try { const files = renderJourneyV3FilesForTest(exactProducerFixture(join(root, 'input'))); for (const [path, source] of Object.entries(files)) writeFileSync(join(root, path), source); const harness = `import 'journey_v3_contract.dart';\nvoid expectFormat(void Function() action) { try { action(); } on FormatException { return; } throw StateError('FormatException expected'); }\nvoid main() { expectFormat(() => JourneySearchRequest(requestId: 'invalid', originStationId: 'origin', destinationStationId: 'destination', departure: const JourneyDepartureNow(), timePolicy: TimePolicy.timetableRequired, mobilityProfile: MobilityProfile.standard, constraintMode: ConstraintMode.none, maxTransfers: 1, alternativeCount: 1)); expectFormat(() => JourneySessionRequest(integrityToken: '', clientNonce: '1234567890123456789012')); }\n`; const harnessPath = join(root, 'request_validation_test.dart'); writeFileSync(harnessPath, harness); execFileSync('dart', ['run', harnessPath], { cwd: root, stdio: 'pipe', timeout: 5000 }); const source = files['journey_v3_models.dart']; assert.match(source, /TIMETABLE_REQUIRED source realtime contract/); assert.match(source, /REALTIME_REQUIRED source realtime contract/); } finally { rmSync(root, { recursive: true, force: true }); } });
test('generated Dart rejects sourceIdentity realtime snapshot policy counterexamples', () => { const root = mkdtempSync(join(tmpdir(), 'journey-generator-dart-')); try { const files = renderJourneyV3FilesForTest(exactProducerFixture(join(root, 'input'))); for (const [path, source] of Object.entries(files)) writeFileSync(join(root, path), source); const harness = `import 'journey_v3_contract.dart';\nvoid expectFormat(void Function() action) { try { action(); } on FormatException { return; } throw StateError('FormatException expected'); }\nMap<String,Object?> response(String policy, String? snapshot) { final realtime=policy=='REALTIME_REQUIRED'; final time=realtime?'2026-08-09T00:00:30Z':null; return {'contractVersion':'JOURNEY_SEARCH_V3','requestId':'00000000000000000000000000','queryId':'query','calculatedAt':'2026-08-09T00:00:00Z','validUntil':'2026-08-09T00:01:00Z','effectiveDepartureTime':'2026-08-09T00:00:00Z','serviceDate':'2026-08-09','serviceTimezone':'Asia/Seoul','sourceIdentity':{'routeBundleId':'route','routeBundleSha256':'${'a'.repeat(64)}','timetableSnapshotId':'time','accessibilitySnapshotId':'access','realtimeSnapshotId':snapshot},'requestPolicy':{'timePolicy':policy,'mobilityProfile':'STANDARD','constraintMode':'NONE','maxTransfers':1,'alternativeCount':1},'journeys':[{'journeyId':'journey','status':'FOUND','planSource':'SERVER_TIMETABLE_RAPTOR','plannedDepartureTime':'2026-08-09T00:00:00Z','plannedArrivalTime':'2026-08-09T00:10:00Z','realtimeDepartureTime':time,'realtimeArrivalTime':time,'durationSeconds':600,'transferCount':0,'walkingDistanceMeters':0,'timeSource':realtime?'REALTIME':'TIMETABLE','accessibility':{'result':'VERIFIED','stairFree':true,'reasonCodes':[]},'legs':[{'type':'RIDE','lineId':'line','tripId':'trip','directionStationId':'direction','fromStationId':'from','toStationId':'to','plannedDepartureTime':'2026-08-09T00:00:00Z','plannedArrivalTime':'2026-08-09T00:10:00Z','realtimeDepartureTime':time,'realtimeArrivalTime':time}]}]}; }\nvoid main() { expectFormat(() => JourneySearchSuccess.fromJson(response('TIMETABLE_REQUIRED','unexpected'))); expectFormat(() => JourneySearchSuccess.fromJson(response('REALTIME_REQUIRED',null))); }\n`; const harnessPath = join(root, 'source_identity_policy_test.dart'); writeFileSync(harnessPath, harness); execFileSync('dart', ['run', harnessPath], { cwd: root, stdio: 'pipe', timeout: 5000 }); } finally { rmSync(root, { recursive: true, force: true }); } });
test('generated Dart accepts the exact nonce and rejects a trailing newline', () => { const root = mkdtempSync(join(tmpdir(), 'journey-generator-dart-')); try { const files = renderJourneyV3FilesForTest(exactProducerFixture(join(root, 'input'))); for (const [path, source] of Object.entries(files)) writeFileSync(join(root, path), source); const harness = `import 'journey_v3_contract.dart';\nvoid main(){final ok=JourneySessionRequest(integrityToken:'token',clientNonce:'1234567890123456789012');if(ok.toJson()['clientNonce']!='1234567890123456789012')throw StateError('exact nonce rejected');try{JourneySessionRequest(integrityToken:'token',clientNonce:'1234567890123456789012\\n');}on FormatException{return;}throw StateError('trailing newline accepted');}\n`; const path = join(root, 'nonce_test.dart'); writeFileSync(path, harness); execFileSync('dart', ['run', path], { cwd: root, stdio: 'pipe', timeout: 5000 }); } finally { rmSync(root, { recursive: true, force: true }); } });
test('renders Dart literals that preserve apostrophes, backslashes, dollars, and controls', () => { const root = mkdtempSync(join(tmpdir(), 'journey-generator-')); try { const value = fixture(root); const dispositionPath = join(value.contractRoot, 'contracts/api/journey-v3-error-disposition.json'); const disposition = JSON.parse(readFileSync(dispositionPath)); disposition.entries[0].canonicalKoreanCopy = "don't \\ $\n\u0001"; writeFileSync(dispositionPath, JSON.stringify(disposition)); rebind(value); const error = renderJourneyV3ErrorsAndBarrelForTest(value).error; assert.ok(error.includes(String.raw`canonicalKoreanCopy: "don't \\ \$\n\u0001"`)); } finally { rmSync(root, { recursive: true, force: true }); } });
test('renders special enum and lock literals as Dart-safe round trips', () => { const root = mkdtempSync(join(tmpdir(), 'journey-generator-dart-')); try { const special = "Alpha'\\$\n\u0001"; const values = ["repo'\\$\n\u0001", "sha'\\$\n\u0001", "manifest'\\$\n\u0001", "payload'\\$\n\u0001", "receipt'\\$\n\u0001"]; const [repository, gitSha, manifestDigest, payloadSha256, publicationReceiptSha256] = values; const rendered = renderJourneyV3DartLiteralSeamForTest({ enumToken: special, lock: { producer: { repository, gitSha }, artifact: { manifestDigest }, payload: { sha256: payloadSha256 }, publicationReceiptSha256 } }); for (const value of values) assert.ok(rendered.contract.includes(JSON.stringify(value).replaceAll('$', '\\$'))); writeFileSync(join(root, 'enum.dart'), rendered.enums); const harness = `import 'enum.dart';\nvoid main(){if(SpecialWireWire.fromWire(${JSON.stringify(special).replaceAll('$', '\\$')})!=SpecialWire.alpha)throw StateError('wire mismatch');if(SpecialWire.alpha.wire!=${JSON.stringify(special).replaceAll('$', '\\$')})throw StateError('round trip mismatch');}\n`; const path = join(root, 'literal_test.dart'); writeFileSync(path, harness); execFileSync('dart', ['run', path], { cwd: root, stdio: 'pipe', timeout: 5000 }); } finally { rmSync(root, { recursive: true, force: true }); } });
test('combines every strict model and all tagged leg variants without stubs', () => { const root = mkdtempSync(join(tmpdir(), 'journey-generator-')); try { const input = exactProducerFixture(root); const source = renderJourneyV3ModelsForTest(input); assert.equal(source, renderJourneyV3ModelsForTest(input)); for (const token of ['class JourneySessionRequest', 'class JourneySearchRequest', 'sealed class JourneyDeparture', 'sealed class JourneyLeg', 'class JourneyEntryLeg', 'class JourneyRideLeg', 'class JourneyTransferLeg', 'class JourneyExitLeg', 'class JourneySearchSuccess', "'departure': departure.toJson()", "'type': JourneyLegType.ride.wire", 'JourneyV3Validation.nullable', 'JourneyV3Validation.rfc3339Wire', 'TIMETABLE_REQUIRED realtime contract', 'REALTIME_REQUIRED realtime contract']) assert.match(source, new RegExp(token.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'))); assert.doesNotMatch(source, /UnimplementedError|abstract interface class JourneyLeg|destination\.toJson|placeholder|TODO|default:/); } finally { rmSync(root, { recursive: true, force: true }); } });
test('renders strict 17-context errors and a no-transport contract barrel', () => { const root=mkdtempSync(join(tmpdir(),'journey-generator-')); try { const source=renderJourneyV3ErrorsAndBarrelForTest(exactProducerFixture(root)); assert.equal(source.error,renderJourneyV3ErrorsAndBarrelForTest(exactProducerFixture(join(root,'again'))).error); for(const code of codes) assert.match(source.error,new RegExp(code)); for(const token of ['class JourneyV3Error','JourneyV3Validation.exactKeys','JourneyV3Validation.ulid','unknown Journey error context','semanticCategory','canonicalKoreanCopy','primaryActionKey','secondaryActionKey','sensitiveDetailPolicy','journeyV3ProducerSha','journeyV3ManifestDigest','journeyV3PayloadSha256','journeyV3SessionIntegritySha256','journeyV3SessionIntegritySpecJson','JOURNEY_V3_SESSION_INTEGRITY_V1','nonceClaimTtlSeconds']) assert.match(`${source.error}\n${source.contract}`,new RegExp(token.replace(/[.*+?^${}()|[\]\\]/g,'\\$&'))); assert.doesNotMatch(`${source.error}\n${source.contract}`,/http:|Dio|retry\(|fallback|TODO|placeholder/); } finally { rmSync(root,{recursive:true,force:true}); } });

test('renders the exact deterministic five-file generated client tree without stubs', () => { const root = mkdtempSync(join(tmpdir(), 'journey-generator-')); try { const input = exactProducerFixture(root); const first = renderJourneyV3FilesForTest(input); const second = renderJourneyV3FilesForTest(input); assert.deepEqual(first, second); assert.deepEqual(Object.keys(first).sort(), ['journey_v3_contract.dart', 'journey_v3_enums.dart', 'journey_v3_error.dart', 'journey_v3_models.dart', 'journey_v3_validation.dart']); for (const [path, source] of Object.entries(first)) { assert.ok(source.endsWith('\n'), `${path} must be LF-terminated`); assert.ok(source.startsWith('// GENERATED CODE - DO NOT MODIFY BY HAND\n'), `${path} must use the canonical generated header`); assert.doesNotMatch(source, /Test-only|UnimplementedError|abstract interface class JourneyLeg|destination\.toJson|placeholder|TODO|default:/); } assert.match(first['journey_v3_contract.dart'], /journeyV3ManifestDigest/); assert.match(first['journey_v3_enums.dart'], /enum JourneyErrorCode/); assert.match(first['journey_v3_error.dart'], /JourneyErrorDispositions/); assert.match(first['journey_v3_models.dart'], /sealed class JourneyLeg/); assert.match(first['journey_v3_validation.dart'], /abstract final class JourneyV3Validation/); } finally { rmSync(root, { recursive: true, force: true }); } });

test('renders braced flow-control bodies for Journey policy and calendar validation', () => { const root = mkdtempSync(join(tmpdir(), 'journey-generator-')); try { const files = renderJourneyV3FilesForTest(exactProducerFixture(root)); for (const source of [files['journey_v3_models.dart'], files['journey_v3_validation.dart']]) assert.doesNotMatch(source, /\)\n\s+throw const FormatException/); for (const token of ["if(policy.timePolicy==TimePolicy.timetableRequired&&(journey.realtimeDepartureTime!=null||journey.realtimeArrivalTime!=null||journey.timeSource!=JourneyTimeSource.timetable)){throw", "if(policy.timePolicy==TimePolicy.realtimeRequired&&(journey.realtimeDepartureTime==null||journey.realtimeArrivalTime==null||journey.timeSource!=JourneyTimeSource.realtime)){throw", "if(policy.timePolicy==TimePolicy.timetableRequired&&(leg.realtimeDepartureTime!=null||leg.realtimeArrivalTime!=null)){throw", "if(policy.timePolicy==TimePolicy.realtimeRequired&&(leg.realtimeDepartureTime==null||leg.realtimeArrivalTime==null)){throw", 'if (calendar.year != year || calendar.month != month || calendar.day != day || calendar.hour != hour || calendar.minute != minute || calendar.second != second) { throw']) assert.ok(`${files['journey_v3_models.dart']}\n${files['journey_v3_validation.dart']}`.includes(token)); } finally { rmSync(root, { recursive: true, force: true }); } });

test('generated Dart compiles and rejects invalid date-time, ride policy, and error context', () => { const root = mkdtempSync(join(tmpdir(), 'journey-generator-dart-')); try { const files = renderJourneyV3FilesForTest(exactProducerFixture(join(root, 'input'))); for (const [path, source] of Object.entries(files)) writeFileSync(join(root, path), source); const harness = `import 'journey_v3_contract.dart';\n\nvoid expectFormat(void Function() action) { try { action(); } on FormatException { return; } throw StateError('FormatException expected'); }\nMap<String,Object?> response(String policy, bool journeyRealtime, bool rideRealtime) => {'contractVersion':'JOURNEY_SEARCH_V3','requestId':'00000000000000000000000000','queryId':'query','calculatedAt':'2026-08-09T00:00:00Z','validUntil':'2026-08-09T00:01:00Z','effectiveDepartureTime':'2026-08-09T00:00:00Z','serviceDate':'2026-08-09','serviceTimezone':'Asia/Seoul','sourceIdentity':{'routeBundleId':'route','routeBundleSha256':'${'a'.repeat(64)}','timetableSnapshotId':'time','accessibilitySnapshotId':'access','realtimeSnapshotId':journeyRealtime?'real':null},'requestPolicy':{'timePolicy':policy,'mobilityProfile':'STANDARD','constraintMode':'NONE','maxTransfers':1,'alternativeCount':1},'journeys':[{'journeyId':'journey','status':'FOUND','planSource':'SERVER_TIMETABLE_RAPTOR','plannedDepartureTime':'2026-08-09T00:00:00Z','plannedArrivalTime':'2026-08-09T00:10:00Z','realtimeDepartureTime':journeyRealtime?'2026-08-09T00:00:30Z':null,'realtimeArrivalTime':journeyRealtime?'2026-08-09T00:10:30Z':null,'durationSeconds':600,'transferCount':0,'walkingDistanceMeters':0,'timeSource':journeyRealtime?'REALTIME':'TIMETABLE','accessibility':{'result':'VERIFIED','stairFree':true,'reasonCodes':[]},'legs':[{'type':'RIDE','lineId':'line','tripId':'trip','directionStationId':'direction','fromStationId':'from','toStationId':'to','plannedDepartureTime':'2026-08-09T00:00:00Z','plannedArrivalTime':'2026-08-09T00:10:00Z','realtimeDepartureTime':rideRealtime?'2026-08-09T00:00:30Z':null,'realtimeArrivalTime':rideRealtime?'2026-08-09T00:10:30Z':null}]}]};\nvoid main(){expectFormat(()=>JourneyV3Validation.rfc3339('2026-02-30T24:61:61Z','date'));if(!JourneyV3Validation.rfc3339Wire(DateTime(2026,8,9)).endsWith('Z'))throw StateError('date-time must be UTC');expectFormat(()=>JourneySearchSuccess.fromJson(response('TIMETABLE_REQUIRED',false,true)));expectFormat(()=>JourneySearchSuccess.fromJson(response('REALTIME_REQUIRED',true,false)));final error={'contractVersion':'JOURNEY_ERROR_V1','requestId':'00000000000000000000000000','code':'INVALID_JOURNEY_REQUEST','retryable':false,'occurredAt':'2026-08-09T00:00:00Z'};final parsed=JourneyV3Error.fromResponse(JourneyOperation.searchJourneys,400,error);final disposition=JourneyErrorDispositions.lookup(JourneyOperation.searchJourneys,400,parsed.code);if(disposition.semanticCategory!=JourneyErrorSemanticCategory.requestCorrection||disposition.primaryActionKey!=JourneyErrorActionKey.journeyActionEditRequest)throw StateError('closed disposition mismatch');expectFormat(()=>JourneyV3Error.fromResponse(JourneyOperation.searchJourneys,503,error));}\n`; const harnessPath = join(root, 'contract_test.dart'); writeFileSync(harnessPath, harness); execFileSync('dart', ['run', harnessPath], { cwd: root, stdio: 'pipe', timeout: 5000 }); } finally { rmSync(root, { recursive: true, force: true }); } });
