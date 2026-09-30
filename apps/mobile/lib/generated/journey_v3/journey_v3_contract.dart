// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=200
// Generated from the locked Journey V3 contract.
export 'journey_v3_enums.dart';
export 'journey_v3_error.dart';
export 'journey_v3_models.dart';
export 'journey_v3_validation.dart';

const String journeyV3ProducerRepository = "AquilaXk/easysubway-backend";
const String journeyV3ProducerSha = "2ba587b7bc65c3f9009fae7f8e41bacfd275a34d";
const String journeyV3ManifestDigest = "sha256:a4438e1b8a232eab129a2ae9e6337b19260a3c311ea922b9ba9a2ea424325750";
const String journeyV3PayloadSha256 = "1dbb28055067242473ffd04a781a1aca1340b6d586323c4c7e915c4f574c2ddf";
const String journeyV3PublicationReceiptSha256 = "67155916efeb09d953f8cf959521991b3edd9d6006c5f2c62539461a3ce6e9bd";
const String journeyV3SessionIntegritySha256 = "06e4fce1260ef807c5a1cc226789ea9e952d2c49f0a50bd0bd7d954b4f1910ad";
const String journeyV3SessionIntegritySpecJson =
    "{\"artifactKind\":\"journey-v3-session-integrity\",\"nonce\":{\"encoding\":\"BASE64URL_NO_PADDING\",\"entropyBytes\":16,\"lifecycle\":\"ONE_PER_SESSION_ISSUANCE\",\"pattern\":\"^[A-Za-z0-9_-]{21}[AQgw]\$\",\"source\":\"CSPRNG\"},\"operationId\":\"issueJourneySession\",\"requestHash\":{\"algorithm\":\"SHA-256\",\"canonicalPayloadUtf8Template\":\"{\\\"clientNonce\\\":\\\"<clientNonce>\\\",\\\"purpose\\\":\\\"journey:v3:session\\\",\\\"version\\\":1}\",\"encoding\":\"BASE64URL_NO_PADDING\",\"pattern\":\"^[A-Za-z0-9_-]{42}[AEIMQUYcgkosw048]\$\",\"purpose\":\"journey:v3:session\",\"requestType\":\"PLAY_INTEGRITY_STANDARD\",\"sensitivePlaintextAllowed\":false,\"version\":1},\"schemaVersion\":\"JOURNEY_V3_SESSION_INTEGRITY_V1\",\"session\":{\"scope\":\"journey:v3\",\"ttlSeconds\":600},\"verdict\":{\"configuredCertificateSha256Encoding\":\"BASE64URL_NO_PADDING\",\"configuredCertificateSha256Required\":true,\"expectedAppPackageName\":\"com.easysubway.app\",\"expectedRequestPackageName\":\"com.easysubway.app\",\"futureTimestampAllowed\":false,\"maxAgeSeconds\":120,\"nonceClaimTtlSeconds\":120,\"nonceSingleUseRequired\":true,\"requestHashConstantTimeEqualityRequired\":true,\"requiredAppLicensingVerdict\":\"LICENSED\",\"requiredAppRecognitionVerdict\":\"PLAY_RECOGNIZED\",\"requiredDeviceRecognitionVerdict\":\"MEETS_DEVICE_INTEGRITY\"}}";
