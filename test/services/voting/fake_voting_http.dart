import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:zcash_wallet/src/services/voting/voting_config_loader.dart';
import 'package:zcash_wallet/src/services/voting/voting_http.dart';
import 'package:zcash_wallet/src/services/voting/voting_models.dart';

class FakeVotingHttpClient implements VotingHttpClient {
  final Map<String, Object> responses;
  final requests = <FakeVotingHttpRequest>[];

  FakeVotingHttpClient({this.responses = const {}});

  @override
  Future<VotingHttpResponse> get(Uri uri, {Duration? timeout}) async {
    requests.add(FakeVotingHttpRequest('GET', uri, timeout: timeout));
    return _responseFor(uri);
  }

  @override
  Future<VotingHttpResponse> postJson(
    Uri uri,
    Map<String, dynamic> body, {
    Duration? timeout,
  }) async {
    requests.add(
      FakeVotingHttpRequest('POST', uri, body: body, timeout: timeout),
    );
    return _responseFor(uri);
  }

  VotingHttpResponse _responseFor(Uri uri) {
    final configured = responses[uri.toString()] ?? responses[uri.path];
    final response = configured is SequentialVotingHttpResponses
        ? configured.next()
        : configured;
    if (response == null) {
      return jsonResponse({'ok': true});
    }
    if (response is Exception) {
      throw response;
    }
    if (response is Error) {
      throw response;
    }
    if (response is VotingHttpResponse) {
      return response;
    }
    if (response is Map<String, dynamic>) {
      return jsonResponse(response);
    }
    if (response is List) {
      return jsonResponse(response);
    }
    if (response is String) {
      return textResponse(response);
    }
    throw StateError('Unsupported fake response: $response');
  }
}

class FakeVotingHttpRequest {
  final String method;
  final Uri uri;
  final Map<String, dynamic>? body;
  final Duration? timeout;

  const FakeVotingHttpRequest(this.method, this.uri, {this.body, this.timeout});
}

class SequentialVotingHttpResponses {
  SequentialVotingHttpResponses(this._responses);

  final List<Object> _responses;
  int _index = 0;

  Object next() {
    if (_responses.isEmpty) {
      throw StateError('SequentialVotingHttpResponses cannot be empty');
    }
    final index = _index < _responses.length ? _index : _responses.length - 1;
    _index += 1;
    return _responses[index];
  }
}

VotingHttpResponse jsonResponse(Object body, {int statusCode = 200}) {
  return VotingHttpResponse(
    statusCode: statusCode,
    bodyBytes: Uint8List.fromList(utf8.encode(jsonEncode(body))),
  );
}

VotingHttpResponse textResponse(String body, {int statusCode = 200}) {
  return VotingHttpResponse(
    statusCode: statusCode,
    bodyBytes: Uint8List.fromList(utf8.encode(body)),
  );
}

TimeoutException timeoutResponse() => TimeoutException('timed out');

class FakeVotingConfigResolver implements VotingConfigResolver {
  const FakeVotingConfigResolver({
    this.staticError,
    this.dynamicError,
    this.authenticatedRoundIds,
    this.switchKind = VotingConfigSwitchKind.initialLoad,
  });

  final Object? staticError;
  final Object? dynamicError;
  final List<String>? authenticatedRoundIds;
  final VotingConfigSwitchKind switchKind;

  @override
  Future<ResolvedStaticVotingConfig> resolveStaticConfig({
    required StaticVotingConfigSource source,
    required List<int> staticConfigBytes,
  }) async {
    final error = staticError;
    if (error != null) throw error;
    final expected = source.sha256Hex;
    if (expected != null) {
      final actual = sha256.convert(staticConfigBytes).toString();
      if (actual != expected) {
        throw VotingConfigRemoteAuthenticationFailed(
          'static config hash-pin mismatch: expected $expected, got $actual',
        );
      }
    }
    final staticConfig = StaticVotingConfig.fromJson(
      decodeVotingJsonObject(utf8.decode(staticConfigBytes)),
    );
    staticConfig.validate();
    return ResolvedStaticVotingConfig(
      staticConfig: staticConfig,
      dynamicConfigUrl: staticConfig.dynamicConfigUrl.toString(),
      sourceFingerprint: 'source',
      trustedKeyFingerprint: 'keys',
      resolvedStaticJson: '{}',
    );
  }

  @override
  Future<ResolvedDynamicVotingConfig> resolveDynamicConfig({
    required String resolvedStaticJson,
    required List<int> dynamicConfigBytes,
    String? previousSummaryJson,
  }) async {
    final error = dynamicError;
    if (error != null) throw error;
    final dynamicConfig = decodeVotingJsonObject(
      utf8.decode(dynamicConfigBytes),
    );
    final rounds = dynamicConfig['rounds'];
    final ids =
        authenticatedRoundIds ??
        (rounds is Map
            ? rounds.keys.map((key) => key.toString()).toList(growable: false)
            : const <String>[]);
    return ResolvedDynamicVotingConfig(
      authenticatedRoundIds: ids,
      dynamicConfigFingerprint: sha256.convert(dynamicConfigBytes).toString(),
      summaryJson: jsonEncode({'authenticated_round_ids': ids}),
      switchKind: switchKind,
      resolvedConfigJson: jsonEncode({'authenticated_round_ids': ids}),
    );
  }
}
