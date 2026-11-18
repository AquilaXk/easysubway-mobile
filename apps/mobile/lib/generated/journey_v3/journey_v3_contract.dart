// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=200
// Generated from the locked Journey V3 contract.
export 'journey_v3_enums.dart';
export 'journey_v3_error.dart';
export 'journey_v3_models.dart';
export 'journey_v3_validation.dart';

const String journeyV3ProducerRepository = "AquilaXk/easysubway-backend";
const String journeyV3ProducerSha = "83e6b51eb0320b0ee17548e5a3ed1a937b063c49";
const String journeyV3ManifestDigest = "sha256:afaa0950c457985e69ca6bddc794f903c4041c85b5cecbdfe0372de36fbd8b9b";
const String journeyV3PayloadSha256 = "5315d8fef12fb36ce30cb29de531fff855cdec0b7df41f42917a6eb6a4ce8909";
const String journeyV3PublicationReceiptSha256 = "cf8c3c20c0194a241d658be1c57a5a6908dfd70bbbc19eebd8626ee8774ae1a2";
const String journeyV3SessionIntegritySha256 = "06e4fce1260ef807c5a1cc226789ea9e952d2c49f0a50bd0bd7d954b4f1910ad";
const String journeyV3SessionIntegritySpecJson =
    "{\"artifactKind\":\"journey-v3-session-integrity\",\"nonce\":{\"encoding\":\"BASE64URL_NO_PADDING\",\"entropyBytes\":16,\"lifecycle\":\"ONE_PER_SESSION_ISSUANCE\",\"pattern\":\"^[A-Za-z0-9_-]{21}[AQgw]\$\",\"source\":\"CSPRNG\"},\"operationId\":\"issueJourneySession\",\"requestHash\":{\"algorithm\":\"SHA-256\",\"canonicalPayloadUtf8Template\":\"{\\\"clientNonce\\\":\\\"<clientNonce>\\\",\\\"purpose\\\":\\\"journey:v3:session\\\",\\\"version\\\":1}\",\"encoding\":\"BASE64URL_NO_PADDING\",\"pattern\":\"^[A-Za-z0-9_-]{42}[AEIMQUYcgkosw048]\$\",\"purpose\":\"journey:v3:session\",\"requestType\":\"PLAY_INTEGRITY_STANDARD\",\"sensitivePlaintextAllowed\":false,\"version\":1},\"schemaVersion\":\"JOURNEY_V3_SESSION_INTEGRITY_V1\",\"session\":{\"scope\":\"journey:v3\",\"ttlSeconds\":600},\"verdict\":{\"configuredCertificateSha256Encoding\":\"BASE64URL_NO_PADDING\",\"configuredCertificateSha256Required\":true,\"expectedAppPackageName\":\"com.easysubway.app\",\"expectedRequestPackageName\":\"com.easysubway.app\",\"futureTimestampAllowed\":false,\"maxAgeSeconds\":120,\"nonceClaimTtlSeconds\":120,\"nonceSingleUseRequired\":true,\"requestHashConstantTimeEqualityRequired\":true,\"requiredAppLicensingVerdict\":\"LICENSED\",\"requiredAppRecognitionVerdict\":\"PLAY_RECOGNIZED\",\"requiredDeviceRecognitionVerdict\":\"MEETS_DEVICE_INTEGRITY\"}}";
