import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { cpSync, mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';
import { validateJourneyV3ClientInputForTest } from './generate-journey-v3-client.mjs';

const repository = join(import.meta.dirname, '..', '..');
const generator = join(repository, 'tools/mobile/generate-journey-v3-client.mjs');
const producerFixture = join(repository, 'tools/mobile/fixtures/journey-v3-contract-v2');
const trackedLock = join(repository, 'contracts/mobile/journey-v3-client.lock.json');
const sha256 = (value) => createHash('sha256').update(value).digest('hex');
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
  writeFileSync(join(api, 'journey-v3-error-catalog.json'), catalog); writeFileSync(join(api, 'journey-v3-error-disposition.json'), disposition); writeFileSync(join(api, 'journey-v3.openapi.yaml'), openapi);
  const resources = [['journey-v3-error-catalog', 'contracts/api/journey-v3-error-catalog.json', 'application/json', catalog], ['journey-v3-error-disposition', 'contracts/api/journey-v3-error-disposition.json', 'application/json', disposition], ['journey-v3-openapi', 'contracts/api/journey-v3.openapi.yaml', 'application/yaml', openapi]].map(([id, path, mediaType, content]) => ({ id, path, owner: 'AquilaXk/easysubway-backend', mediaType, sha256: sha256(content) }));
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
  const lock = JSON.parse(readFileSync(trackedLock)); writeFileSync(join(contractRoot, 'journey-v3-contract-stage-receipt.json'), JSON.stringify({ schemaVersion: 1, lockSha256: sha256(readFileSync(trackedLock)), payloadSha256: lock.payload.sha256, publicationReceiptSha256: lock.publicationReceiptSha256, artifact: lock.artifact, resources: Object.fromEntries(lock.resources.map(({ path, sha256: digest }) => [path, digest])) }));
  return { contractRoot, lockPath: trackedLock };
}

test('builds closed producer-shaped IR including tagged variants and disposition bindings', () => { const root = mkdtempSync(join(tmpdir(), 'journey-generator-')); try { const value = fixture(root); const ir = validateJourneyV3ClientInputForTest(value); assert.equal(ir.operations.length, 2); assert.equal(ir.errorCatalog.length, 17); assert.equal(ir.schemas.JourneyDeparture.oneOf.length, 2); assert.equal(ir.schemas.JourneyLeg.oneOf.length, 4); assert.equal(ir.errorDispositions.length, 17); assert.equal(Object.isFrozen(ir.errorDispositions[0]), true); assert.equal(ir.errorDispositions[0].code, 'INVALID_JOURNEY_REQUEST'); } finally { rmSync(root, { recursive: true, force: true }); } });
test('validates the exact locked d789995d producer bytes without sibling repository or network', () => { const root = mkdtempSync(join(tmpdir(), 'journey-generator-')); try { const ir = validateJourneyV3ClientInputForTest(exactProducerFixture(root)); assert.equal(ir.operations.length, 2); assert.equal(ir.errorCatalog.length, 17); assert.equal(ir.errorDispositions.length, 17); } finally { rmSync(root, { recursive: true, force: true }); } });
test('rebinding every semantic mutation still rejects stale receipt, YAML, policy and constraints precisely', () => { const root = mkdtempSync(join(tmpdir(), 'journey-generator-')); try { const stale = fixture(join(root, 'stale')); writeFileSync(join(stale.contractRoot, 'contracts/api/journey-v3.openapi.yaml'), 'openapi: 3.0.3\n'); assert.throws(() => validateJourneyV3ClientInputForTest(stale), /SHA-256/); const tag = fixture(join(root, 'tag')); const tagPath = join(tag.contractRoot, 'contracts/api/journey-v3.openapi.yaml'); writeFileSync(tagPath, readFileSync(tagPath, 'utf8').replace('required: [mode]', 'required: [type]').replace('        mode:\n          type: string\n          enum: [NOW]', '        type:\n          type: string\n          enum: [NOW]')); rebind(tag); assert.throws(() => validateJourneyV3ClientInputForTest(tag), /tagged by mode/); const policy = fixture(join(root, 'policy')); const policyPath = join(policy.contractRoot, 'contracts/api/journey-v3.openapi.yaml'); writeFileSync(policyPath, readFileSync(policyPath, 'utf8').replace('TIMETABLE_REQUIRED: realtime-fields-null', 'TIMETABLE_REQUIRED: wrong')); rebind(policy); assert.throws(() => validateJourneyV3ClientInputForTest(policy), /time policy values/); const not = fixture(join(root, 'not')); const notPath = join(not.contractRoot, 'contracts/api/journey-v3.openapi.yaml'); writeFileSync(notPath, readFileSync(notPath, 'utf8').replace('enum: [NO_STAIRS]', 'enum: [STANDARD]')); rebind(not); assert.throws(() => validateJourneyV3ClientInputForTest(not), /NO_STAIRS plus NONE/); const duplicate = fixture(join(root, 'duplicate')); const path = join(duplicate.contractRoot, 'contracts/api/journey-v3-error-catalog.json'); const text = '{"schemaVersion":"x","schemaVersion":"x"}'; writeFileSync(path, text); rebind(duplicate); assert.throws(() => validateJourneyV3ClientInputForTest(duplicate), /duplicate key schemaVersion/); } finally { rmSync(root, { recursive: true, force: true }); } });
test('rejects a rebound extra not key and malformed supported pattern precisely', () => { const root = mkdtempSync(join(tmpdir(), 'journey-generator-')); try { const extra = fixture(join(root, 'extra')); const extraPath = join(extra.contractRoot, 'contracts/api/journey-v3.openapi.yaml'); writeFileSync(extraPath, readFileSync(extraPath, 'utf8').replace('        properties:\n          mobilityProfile:', '        extra: true\n        properties:\n          mobilityProfile:')); rebind(extra); assert.throws(() => validateJourneyV3ClientInputForTest(extra), /JourneySearchRequest.not has unexpected or missing fields/); const pattern = fixture(join(root, 'pattern')); const patternPath = join(pattern.contractRoot, 'contracts/api/journey-v3.openapi.yaml'); writeFileSync(patternPath, readFileSync(patternPath, 'utf8').replace('pattern: "^[0-7][0-9A-HJKMNP-TV-Z]{25}$"', 'pattern: "["')); rebind(pattern); assert.throws(() => validateJourneyV3ClientInputForTest(pattern), /JourneySearchRequest.requestId has invalid pattern/); } finally { rmSync(root, { recursive: true, force: true }); } });
test('production CLI accepts no alternate lock and creates no output before renderer B', () => { const root = mkdtempSync(join(tmpdir(), 'journey-generator-')); try { const value = fixture(root); const output = join(root, 'output'); assert.throws(() => execFileSync(process.execPath, [generator, '--contract-root', value.contractRoot, '--lock', value.lockPath, '--output-root', output, '--receipt', join(output, 'journey_v3_generation_receipt.json')], { encoding: 'utf8', stdio: 'pipe' }), /lock must be the tracked/); assert.throws(() => readFileSync(output)); } finally { rmSync(root, { recursive: true, force: true }); } });
test('the test-only IR seam has no tracked production caller', () => { const references = execFileSync('rg', ['-l', 'validateJourneyV3ClientInputForTest', 'tools'], { cwd: repository, encoding: 'utf8' }).trim().split('\n').sort(); assert.deepEqual(references, ['tools/mobile/generate-journey-v3-client.mjs', 'tools/mobile/generate-journey-v3-client.test.mjs']); });
