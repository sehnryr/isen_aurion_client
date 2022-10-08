import 'package:isen_aurion_client/event.dart';
import 'package:isen_aurion_client/src/error.dart';

String regexMatch(String source, String input, String? errorMessage) {
  var pattern = RegExp(source);
  var match = pattern.firstMatch(input);

  if (match != null && match.groupCount >= 1) {
    return match.group(1)!;
  }
  throw ParameterNotFound(errorMessage ?? "");
}

/// Parses Aurion's return schedule format to a [List] of [Event].
///
/// Throws [ParameterNotFound] if the schedule is not in the expected format.
Event parseEvent(Map<String, dynamic> rawEvent) {
  if (rawEvent.length != 7) {
    throw ParameterNotFound("Event is not in the expected format.");
  }

  Map<String, dynamic> eventJson = {
    'id': int.parse(rawEvent['id']),
    'type': mapType(rawEvent['className']).name,
    'start': rawEvent['start'],
    'end': rawEvent['end'],
  };

  String data = rawEvent['title'];
  var result = data.split(' - ');

  if (result.length != 7) {
    throw Exception(
        'Event is not in the expected format. Could not be parsed.');
  }

  if (RegExp(r'\d\dh\d\d - \d\dh\d\d').hasMatch(data)) {
    eventJson['room'] = result[6];
    eventJson['subject'] = result[3];
    eventJson['chapter'] = result[4];
    eventJson['participants'] = result[5].split(' / ');
  } else {
    eventJson['room'] = result[1];
    eventJson['subject'] = result[3];
    eventJson['chapter'] = result[4];
    eventJson['participants'] = result[5].split(' / ');
  }

  return Event.fromJson(eventJson);
}

/// Gets the [EventType] of a [String].
EventType mapType(String rawType) {
  switch (rawType) {
    case "CONGES":
      return EventType.leave;
    case "COURS":
      return EventType.course;
    case "est-epreuve":
    case "EVALUATION":
      return EventType.exam;
    case "REUNION":
      return EventType.meeting;
    case "TD":
      return EventType.supervisedWork;
    case "TP":
      return EventType.practicalWork;
    default:
      return EventType.undefined;
  }
}
