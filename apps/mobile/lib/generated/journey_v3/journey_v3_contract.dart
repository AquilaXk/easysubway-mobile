// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=200
// Generated from the locked Journey V3 contract.
export 'journey_v3_enums.dart';
export 'journey_v3_error.dart';
export 'journey_v3_models.dart';
export 'journey_v3_validation.dart';

const String journeyV3ProducerRepository = "AquilaXk/easysubway-backend";
const String journeyV3ProducerSha = "1c25e586270f0e40b5fcad32820ff9e9e3ff985f";
const String journeyV3ManifestDigest = "sha256:6d3b428a6e069739b98d040f6d10c5e20af10725d8656aeaaad190d5bf9fa3b1";
const String journeyV3PayloadSha256 = "1bdffede5aa577411d77a6c8ec4f18de8ea25c61b54f227e985386b81b65625f";
const String journeyV3PublicationReceiptSha256 = "dcb93a99c86f9a7790e33ceebc8c9392bb65178db1c0d2b6c0eeea5b8e75a6cd";
const String journeyV3SessionIntegritySha256 = "06e4fce1260ef807c5a1cc226789ea9e952d2c49f0a50bd0bd7d954b4f1910ad";
const String journeyV3SessionIntegritySpecJson =
    "{\"artifactKind\":\"journey-v3-session-integrity\",\"nonce\":{\"encoding\":\"BASE64URL_NO_PADDING\",\"entropyBytes\":16,\"lifecycle\":\"ONE_PER_SESSION_ISSUANCE\",\"pattern\":\"^[A-Za-z0-9_-]{21}[AQgw]\$\",\"source\":\"CSPRNG\"},\"operationId\":\"issueJourneySession\",\"requestHash\":{\"algorithm\":\"SHA-256\",\"canonicalPayloadUtf8Template\":\"{\\\"clientNonce\\\":\\\"<clientNonce>\\\",\\\"purpose\\\":\\\"journey:v3:session\\\",\\\"version\\\":1}\",\"encoding\":\"BASE64URL_NO_PADDING\",\"pattern\":\"^[A-Za-z0-9_-]{42}[AEIMQUYcgkosw048]\$\",\"purpose\":\"journey:v3:session\",\"requestType\":\"PLAY_INTEGRITY_STANDARD\",\"sensitivePlaintextAllowed\":false,\"version\":1},\"schemaVersion\":\"JOURNEY_V3_SESSION_INTEGRITY_V1\",\"session\":{\"scope\":\"journey:v3\",\"ttlSeconds\":600},\"verdict\":{\"configuredCertificateSha256Encoding\":\"BASE64URL_NO_PADDING\",\"configuredCertificateSha256Required\":true,\"expectedAppPackageName\":\"com.easysubway.app\",\"expectedRequestPackageName\":\"com.easysubway.app\",\"futureTimestampAllowed\":false,\"maxAgeSeconds\":120,\"nonceClaimTtlSeconds\":120,\"nonceSingleUseRequired\":true,\"requestHashConstantTimeEqualityRequired\":true,\"requiredAppLicensingVerdict\":\"LICENSED\",\"requiredAppRecognitionVerdict\":\"PLAY_RECOGNIZED\",\"requiredDeviceRecognitionVerdict\":\"MEETS_DEVICE_INTEGRITY\"}}";
