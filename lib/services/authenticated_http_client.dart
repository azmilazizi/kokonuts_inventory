import 'package:http/http.dart' as http;

/// Builds an authorization header value for a given token.
typedef AuthorizationHeaderBuilder = String Function(String token);

/// Represents the pieces of authentication information required to build
/// headers for an outgoing HTTP request.
class AuthTokenPayload {
  const AuthTokenPayload({
    required this.authorizationToken,
    required this.authtoken,
    required this.rawAuthtoken,
  });

  /// The credential portion that should be passed to the Authorization header
  /// builder (generally the token without its scheme).
  final String authorizationToken;

  /// The value that should be applied to the `authtoken` header.
  final String authtoken;

  /// The raw authtoken value exactly as it was provided by the backend.
  final String rawAuthtoken;

  bool get hasAuthorizationToken => authorizationToken.trim().isNotEmpty;

  bool get hasAuthtoken =>
      authtoken.trim().isNotEmpty || rawAuthtoken.trim().isNotEmpty;

  /// Returns the header-ready authtoken value, preferring the raw token when
  /// available to match backend expectations precisely.
  String? get resolvedAuthtoken {
    final rawValue = rawAuthtoken.trim();
    if (rawValue.isNotEmpty) {
      return rawValue;
    }
    final normalizedValue = authtoken.trim();
    if (normalizedValue.isNotEmpty) {
      return normalizedValue;
    }
    return null;
  }
}

/// An HTTP client that injects authentication headers into each request.
class AuthenticatedHttpClient extends http.BaseClient {
  AuthenticatedHttpClient({
    required Future<AuthTokenPayload?> Function() tokenProvider,
    http.Client? innerClient,
    AuthorizationHeaderBuilder? authorizationBuilder,
  })  : _tokenProvider = tokenProvider,
        _innerClient = innerClient ?? http.Client(),
        _authorizationBuilder = authorizationBuilder ??
            ((token) => token.isEmpty ? token : 'Bearer $token');

  final Future<AuthTokenPayload?> Function() _tokenProvider;
  final http.Client _innerClient;
  final AuthorizationHeaderBuilder _authorizationBuilder;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final payload = await _tokenProvider();
    if (payload != null) {
      final token = payload.authorizationToken.trim();
      final existingAuthorization = request.headers['Authorization'];
      final shouldInjectAuthorization =
          existingAuthorization == null || existingAuthorization.trim().isEmpty;
      if (shouldInjectAuthorization && token.isNotEmpty) {
        final authorizationValue = _authorizationBuilder(token).trim();
        if (authorizationValue.isNotEmpty) {
          request.headers['Authorization'] = authorizationValue;
        }
      }

      final existingAuthtoken = request.headers['authtoken'];
      final shouldInjectAuthtoken =
          existingAuthtoken == null || existingAuthtoken.trim().isEmpty;
      if (shouldInjectAuthtoken && payload.hasAuthtoken) {
        final authtokenValue = payload.resolvedAuthtoken;
        if (authtokenValue != null && authtokenValue.isNotEmpty) {
          request.headers['authtoken'] = authtokenValue;
        }
      }
    }
    return _innerClient.send(request);
  }

  @override
  void close() {
    _innerClient.close();
    super.close();
  }
}
