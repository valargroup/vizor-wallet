import 'dart:convert';

import 'package:flutter_rust_bridge/flutter_rust_bridge.dart'
    show AnyhowException;

import '../../rust/api/voting.dart' as rust_voting;
import 'voting_http.dart';
import 'voting_models.dart';

/// Hash-pinned static trust anchor used to discover the mutable voting config.
///
/// The URL itself is expected to stay stable in the app, while the fetched JSON
/// points at the current dynamic service configuration. The checksum query
/// parameter is stripped before fetching and verified against the raw body.
const kDefaultStaticVotingConfigSource =
    'https://raw.githubusercontent.com/valargroup/token-holder-voting-config/'
    '2785311d45758e85567d70a1f13709fa01b62c6b/prod/static-voting-config.json'
    '?checksum=sha256:bed0116f961226b256a574b52461ce81d9f5294a57e190987dc155f07eb1e431';

class VotingConfigChecksumMismatch implements Exception {
  final Uri uri;
  final String expected;
  final String actual;

  const VotingConfigChecksumMismatch({
    required this.uri,
    required this.expected,
    required this.actual,
  });

  @override
  String toString() =>
      'VotingConfigChecksumMismatch($uri): expected $expected, got $actual';
}

class StaticVotingConfigSourceMalformed implements Exception {
  final String message;

  const StaticVotingConfigSourceMalformed(this.message);

  @override
  String toString() => 'StaticVotingConfigSourceMalformed: $message';
}

class StaticVotingConfigSource {
  final String raw;
  final Uri uri;
  final String? sha256Hex;

  const StaticVotingConfigSource({
    required this.raw,
    required this.uri,
    this.sha256Hex,
  });

  /// Parses a source URL of the form `https://...?...checksum=sha256:<hex>`.
  ///
  /// The checksum is metadata for this client, not part of the resource URL, so
  /// callers fetch [uri] and verify the body against [sha256Hex] when present.
  static StaticVotingConfigSource parse(String raw) {
    final parsed = Uri.tryParse(raw);
    if (parsed == null || parsed.scheme != 'https' || parsed.host.isEmpty) {
      throw StaticVotingConfigSourceMalformed('not an HTTPS URL: $raw');
    }

    final checksum = parsed.queryParameters['checksum'];
    String? sha256Hex;
    if (checksum != null) {
      const prefix = 'sha256:';
      if (!checksum.startsWith(prefix)) {
        throw const StaticVotingConfigSourceMalformed(
          'checksum must start with sha256:',
        );
      }
      sha256Hex = checksum.substring(prefix.length);
      if (sha256Hex.length != 64 ||
          !RegExp(r'^[0-9a-f]+$').hasMatch(sha256Hex)) {
        throw StaticVotingConfigSourceMalformed(
          'sha256 must be 64 lowercase hex chars; got ${sha256Hex.length}',
        );
      }
    }

    final strippedQuery = Map<String, String>.from(parsed.queryParameters)
      ..remove('checksum');
    return StaticVotingConfigSource(
      raw: raw.trim(),
      uri: Uri(
        scheme: parsed.scheme,
        userInfo: parsed.userInfo,
        host: parsed.host,
        port: parsed.hasPort ? parsed.port : null,
        path: parsed.path,
        queryParameters: strippedQuery.isEmpty ? null : strippedQuery,
        fragment: parsed.fragment.isEmpty ? null : parsed.fragment,
      ),
      sha256Hex: sha256Hex,
    );
  }
}

class ResolvedStaticVotingConfig {
  final StaticVotingConfig staticConfig;
  final String dynamicConfigUrl;
  final String sourceFingerprint;
  final String trustedKeyFingerprint;
  final String resolvedStaticJson;

  const ResolvedStaticVotingConfig({
    required this.staticConfig,
    required this.dynamicConfigUrl,
    required this.sourceFingerprint,
    required this.trustedKeyFingerprint,
    required this.resolvedStaticJson,
  });
}

class ResolvedDynamicVotingConfig {
  final List<String> authenticatedRoundIds;
  final String dynamicConfigFingerprint;
  final String summaryJson;
  final VotingConfigSwitchKind switchKind;
  final String resolvedConfigJson;

  const ResolvedDynamicVotingConfig({
    required this.authenticatedRoundIds,
    required this.dynamicConfigFingerprint,
    required this.summaryJson,
    required this.switchKind,
    required this.resolvedConfigJson,
  });
}

abstract interface class VotingConfigResolver {
  Future<ResolvedStaticVotingConfig> resolveStaticConfig({
    required StaticVotingConfigSource source,
    required List<int> staticConfigBytes,
  });

  Future<ResolvedDynamicVotingConfig> resolveDynamicConfig({
    required String resolvedStaticJson,
    required List<int> dynamicConfigBytes,
    String? previousSummaryJson,
  });
}

class RustVotingConfigResolver implements VotingConfigResolver {
  const RustVotingConfigResolver();

  @override
  Future<ResolvedStaticVotingConfig> resolveStaticConfig({
    required StaticVotingConfigSource source,
    required List<int> staticConfigBytes,
  }) async {
    try {
      final resolved = await rust_voting.resolveStaticVotingConfig(
        source: source.raw,
        staticConfigBytes: staticConfigBytes,
      );
      final staticConfig = StaticVotingConfig.fromJson(
        decodeVotingJsonObject(utf8.decode(staticConfigBytes)),
      );
      staticConfig.validate();
      return ResolvedStaticVotingConfig(
        staticConfig: staticConfig,
        dynamicConfigUrl: resolved.dynamicConfigUrl,
        sourceFingerprint: resolved.sourceFingerprint,
        trustedKeyFingerprint: resolved.trustedKeyFingerprint,
        resolvedStaticJson: resolved.resolvedStaticJson,
      );
    } on AnyhowException catch (error) {
      throw _mapRustConfigError(error.message);
    }
  }

  @override
  Future<ResolvedDynamicVotingConfig> resolveDynamicConfig({
    required String resolvedStaticJson,
    required List<int> dynamicConfigBytes,
    String? previousSummaryJson,
  }) async {
    try {
      final resolved = await rust_voting.resolveDynamicVotingConfig(
        resolvedStaticJson: resolvedStaticJson,
        dynamicConfigBytes: dynamicConfigBytes,
        previousSummaryJson: previousSummaryJson,
      );
      return ResolvedDynamicVotingConfig(
        authenticatedRoundIds: resolved.authenticatedRoundIds,
        dynamicConfigFingerprint: resolved.dynamicConfigFingerprint,
        summaryJson: resolved.summaryJson,
        switchKind: VotingConfigSwitchKind.fromWireName(resolved.switchKind),
        resolvedConfigJson: resolved.resolvedConfigJson,
      );
    } on AnyhowException catch (error) {
      throw _mapRustConfigError(error.message);
    }
  }
}

/// Loads the two-stage voting configuration and fails closed on any mismatch.
///
/// The static config is the trust anchor: it may be hash-pinned by the source
/// URL and contains the dynamic config URL plus trusted signing keys. The
/// dynamic config then supplies service endpoints, supported protocol versions,
/// and the authenticated round registry used by higher layers.
class VotingConfigLoader {
  VotingConfigLoader({
    required VotingHttpClient httpClient,
    StaticVotingConfigSource? staticConfigSource,
    VotingConfigResolver resolver = const RustVotingConfigResolver(),
    Duration timeout = const Duration(seconds: 10),
  }) : _httpClient = httpClient,
       _staticConfigSource =
           staticConfigSource ??
           StaticVotingConfigSource.parse(kDefaultStaticVotingConfigSource),
       _resolver = resolver,
       _timeout = timeout;

  final VotingHttpClient _httpClient;
  final StaticVotingConfigSource _staticConfigSource;
  final VotingConfigResolver _resolver;
  final Duration _timeout;

  /// Fetches the static trust anchor first, then follows its dynamic config URL.
  Future<VotingConfig> load({String? previousSummaryJson}) async {
    final staticConfig = await _loadResolvedStaticConfig();
    return loadDynamicConfig(
      Uri.parse(staticConfig.dynamicConfigUrl),
      resolvedStaticJson: staticConfig.resolvedStaticJson,
      previousSummaryJson: previousSummaryJson,
    );
  }

  /// Fetches and validates only the static trust anchor.
  ///
  /// This is exposed separately so providers can surface more precise failures
  /// and tests can verify checksum behavior without contacting the dynamic URL.
  Future<StaticVotingConfig> loadStaticConfig() async {
    return (await _loadResolvedStaticConfig()).staticConfig;
  }

  Future<ResolvedStaticVotingConfig> _loadResolvedStaticConfig() async {
    final source = _staticConfigSource;
    final response = await _httpClient.get(source.uri, timeout: _timeout);
    if (response.statusCode != 200) {
      throw VotingHttpException(
        uri: source.uri,
        statusCode: response.statusCode,
        body: response.bodyText,
      );
    }
    return _resolver.resolveStaticConfig(
      source: source,
      staticConfigBytes: response.bodyBytes,
    );
  }

  /// Fetches and validates a dynamic service configuration.
  ///
  /// There is intentionally no bundled fallback: stale endpoint or round data
  /// could make the wallet submit to the wrong service or authenticate the wrong
  /// round, so malformed or unavailable config remains an explicit error.
  Future<VotingConfig> loadDynamicConfig(
    Uri dynamicConfigUrl, {
    String? resolvedStaticJson,
    String? previousSummaryJson,
  }) async {
    final response = await _httpClient.get(dynamicConfigUrl, timeout: _timeout);
    if (response.statusCode != 200) {
      throw VotingHttpException(
        uri: dynamicConfigUrl,
        statusCode: response.statusCode,
        body: response.bodyText,
      );
    }
    final resolved = resolvedStaticJson == null
        ? null
        : await _resolver.resolveDynamicConfig(
            resolvedStaticJson: resolvedStaticJson,
            dynamicConfigBytes: response.bodyBytes,
            previousSummaryJson: previousSummaryJson,
          );
    final config = VotingConfig.fromJson(
      response.decodeJsonObject(),
      authenticatedRoundIds: resolved?.authenticatedRoundIds,
      summaryJson: resolved?.summaryJson,
      dynamicConfigFingerprint: resolved?.dynamicConfigFingerprint,
      switchKind: resolved?.switchKind ?? VotingConfigSwitchKind.initialLoad,
    );
    config.validate();
    return config;
  }
}

Exception _mapRustConfigError(String message) {
  const remotePrefix = 'remote_authentication_failed: ';
  if (message.startsWith(remotePrefix)) {
    return VotingConfigRemoteAuthenticationFailed(
      message.substring(remotePrefix.length),
    );
  }

  const unsupportedPrefix = 'unsupported_version: ';
  if (message.startsWith(unsupportedPrefix)) {
    final rest = message.substring(unsupportedPrefix.length);
    final separator = rest.indexOf(': ');
    if (separator > 0) {
      return VotingConfigUnsupportedVersion(
        component: rest.substring(0, separator),
        advertised: rest.substring(separator + 2),
      );
    }
  }

  const decodePrefix = 'decode_failed: ';
  if (message.startsWith(decodePrefix)) {
    return VotingConfigDecodeException(message.substring(decodePrefix.length));
  }

  const invalidInputPrefix = 'invalid_input: ';
  if (message.startsWith(invalidInputPrefix)) {
    return VotingConfigDecodeException(
      message.substring(invalidInputPrefix.length),
    );
  }

  return VotingConfigDecodeException(message);
}
