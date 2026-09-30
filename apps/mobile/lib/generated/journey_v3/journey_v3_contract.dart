// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=200
// Generated from the locked Journey V3 contract.
export 'journey_v3_enums.dart';
export 'journey_v3_error.dart';
export 'journey_v3_models.dart';
export 'journey_v3_validation.dart';

const String journeyV3ProducerRepository = "AquilaXk/easysubway-backend";
const String journeyV3ProducerSha = "7c5657ad6941e497ac864277a570c95c681d7e41";
const String journeyV3ManifestDigest = "sha256:959f19500183b77cf913e2c6920597181ea90b664546bf6dff6a2571d09cef2a";
const String journeyV3PayloadSha256 = "f7bb8569973b19c5fced17854ed7a9492d95bc93429ed133e35a8b2fe2b97992";
const String journeyV3PublicationReceiptSha256 = "7d7eade6fbba12bb27483cc7ebb8b4bf7072e70f9815145e29d6e0c699e31a45";
const String journeyV3SessionIntegritySha256 = "06e4fce1260ef807c5a1cc226789ea9e952d2c49f0a50bd0bd7d954b4f1910ad";
const String journeyV3SessionIntegritySpecJson =
    "{\"artifactKind\":\"journey-v3-session-integrity\",\"nonce\":{\"encoding\":\"BASE64URL_NO_PADDING\",\"entropyBytes\":16,\"lifecycle\":\"ONE_PER_SESSION_ISSUANCE\",\"pattern\":\"^[A-Za-z0-9_-]{21}[AQgw]\$\",\"source\":\"CSPRNG\"},\"operationId\":\"issueJourneySession\",\"requestHash\":{\"algorithm\":\"SHA-256\",\"canonicalPayloadUtf8Template\":\"{\\\"clientNonce\\\":\\\"<clientNonce>\\\",\\\"purpose\\\":\\\"journey:v3:session\\\",\\\"version\\\":1}\",\"encoding\":\"BASE64URL_NO_PADDING\",\"pattern\":\"^[A-Za-z0-9_-]{42}[AEIMQUYcgkosw048]\$\",\"purpose\":\"journey:v3:session\",\"requestType\":\"PLAY_INTEGRITY_STANDARD\",\"sensitivePlaintextAllowed\":false,\"version\":1},\"schemaVersion\":\"JOURNEY_V3_SESSION_INTEGRITY_V1\",\"session\":{\"scope\":\"journey:v3\",\"ttlSeconds\":600},\"verdict\":{\"configuredCertificateSha256Encoding\":\"BASE64URL_NO_PADDING\",\"configuredCertificateSha256Required\":true,\"expectedAppPackageName\":\"com.easysubway.app\",\"expectedRequestPackageName\":\"com.easysubway.app\",\"futureTimestampAllowed\":false,\"maxAgeSeconds\":120,\"nonceClaimTtlSeconds\":120,\"nonceSingleUseRequired\":true,\"requestHashConstantTimeEqualityRequired\":true,\"requiredAppLicensingVerdict\":\"LICENSED\",\"requiredAppRecognitionVerdict\":\"PLAY_RECOGNIZED\",\"requiredDeviceRecognitionVerdict\":\"MEETS_DEVICE_INTEGRITY\"}}";
