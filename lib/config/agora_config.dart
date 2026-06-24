/// Agora credentials for Scholaxia live classes.
/// App ID: from console.agora.io → your project
/// Token: temporary token generated for testing (expires in 24h).
/// Replace with a token-server flow before going to production.
class AgoraConfig {
  AgoraConfig._();

  static const String appId = '2735ab34da634131bd67bdaa9a200d8b';

  /// Temp token generated from Agora console — valid for 24 hours.
  /// For production: fetch a fresh token from your backend per channel+uid.
  static const String? token =
      '007eJxTYMgI+3Mq/+H3vQWWxhcE1FKsKh81ft7sfXNWzOwd5vUL3jcoMBiZG5smJhmbpCSaGZsYGhsmpZiZJ6UkJlomGhkYpFgklaooZjUEMjL4lF9iZGSAQBCfj6E4OSM/J7EiM1G3JLW4hIEBAEm3JO0=';

  /// The channel this temp token was generated for.
  /// When you move to production, generate tokens per-channel dynamically.
  static const String defaultChannel = 'scholaxia-live';
}
