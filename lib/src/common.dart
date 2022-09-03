import 'package:isen_aurion_client/src/error.dart';

String regexMatch(String source, String input, String? errorMessage) {
  var pattern = RegExp(source);
  var match = pattern.firstMatch(input);

  if (match != null && match.groupCount >= 1) {
    return match.group(1)!;
  }
  throw ParameterNotFound(errorMessage ?? "");
}
