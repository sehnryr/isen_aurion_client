/// Exception thrown when a failed authentication happens.
/// [message] should be set to indicate what could cause this exception.
class AuthenticationException implements Exception {
  final String message;

  AuthenticationException(this.message);
}

/// Exception thrown when a specific parameter could not be found.
/// [message] should be set to indicate what could cause this exception.
class ParameterNotFound implements Exception {
  final String message;

  ParameterNotFound(this.message);
}
