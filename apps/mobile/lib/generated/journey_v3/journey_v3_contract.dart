// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=200
// Generated from the locked Journey V3 contract.
export 'journey_v3_enums.dart';
export 'journey_v3_error.dart';
export 'journey_v3_models.dart';
export 'journey_v3_validation.dart';

const String journeyV3ProducerRepository = "AquilaXk/easysubway-backend";
const String journeyV3ProducerSha = "4a1da5b75dbc185652e91c70575b7caadd523ada";
const String journeyV3ManifestDigest = "sha256:6220d43b7d7136a7078b0dbd2019b9e4695f330358d7ba24eb1cb302d898d862";
const String journeyV3PayloadSha256 = "8968213141405ff41fa1e2a8b99b5b2ad1cbacc9290d235c3dac6cb8d5415d02";
const String journeyV3PublicationReceiptSha256 = "1b6241ad1642f0e1169080f344222c43e8e0b48f7df81b0f04b76b0e3e85beaf";
const String journeyV3SessionIntegritySha256 = "06e4fce1260ef807c5a1cc226789ea9e952d2c49f0a50bd0bd7d954b4f1910ad";
const String journeyV3SessionIntegritySpecJson =
    "{\"artifactKind\":\"journey-v3-session-integrity\",\"nonce\":{\"encoding\":\"BASE64URL_NO_PADDING\",\"entropyBytes\":16,\"lifecycle\":\"ONE_PER_SESSION_ISSUANCE\",\"pattern\":\"^[A-Za-z0-9_-]{21}[AQgw]\$\",\"source\":\"CSPRNG\"},\"operationId\":\"issueJourneySession\",\"requestHash\":{\"algorithm\":\"SHA-256\",\"canonicalPayloadUtf8Template\":\"{\\\"clientNonce\\\":\\\"<clientNonce>\\\",\\\"purpose\\\":\\\"journey:v3:session\\\",\\\"version\\\":1}\",\"encoding\":\"BASE64URL_NO_PADDING\",\"pattern\":\"^[A-Za-z0-9_-]{42}[AEIMQUYcgkosw048]\$\",\"purpose\":\"journey:v3:session\",\"requestType\":\"PLAY_INTEGRITY_STANDARD\",\"sensitivePlaintextAllowed\":false,\"version\":1},\"schemaVersion\":\"JOURNEY_V3_SESSION_INTEGRITY_V1\",\"session\":{\"scope\":\"journey:v3\",\"ttlSeconds\":600},\"verdict\":{\"configuredCertificateSha256Encoding\":\"BASE64URL_NO_PADDING\",\"configuredCertificateSha256Required\":true,\"expectedAppPackageName\":\"com.easysubway.app\",\"expectedRequestPackageName\":\"com.easysubway.app\",\"futureTimestampAllowed\":false,\"maxAgeSeconds\":120,\"nonceClaimTtlSeconds\":120,\"nonceSingleUseRequired\":true,\"requestHashConstantTimeEqualityRequired\":true,\"requiredAppLicensingVerdict\":\"LICENSED\",\"requiredAppRecognitionVerdict\":\"PLAY_RECOGNIZED\",\"requiredDeviceRecognitionVerdict\":\"MEETS_DEVICE_INTEGRITY\"}}";
