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
Event? parseEvent(Map<String, dynamic> rawEvent) {
  if (rawEvent.length != 7) {
    return null;
  }

  Map<String, dynamic> eventJson = {
    'id': int.parse(rawEvent['id']),
    'type': mapType(rawEvent['className']).name,
    'start': rawEvent['start'],
    'end': rawEvent['end'],
  };

  String data = rawEvent['title'];
  // https://regex101.com/r/xfG2EU/1
  var result = RegExp(r'((?:(?<= - )|^)(?:(?! - ).)*?)(?: - |$)')
      .allMatches(data)
      .toList();

  if (RegExp(r'\d\dh\d\d - \d\dh\d\d').hasMatch(data)) {
    eventJson['room'] = result[6].group(1)!;
    eventJson['subject'] = result[3].group(1)!;
    eventJson['chapter'] = result[4].group(1)!;
    eventJson['participants'] = result[5].group(1)!.split(' / ');
  } else {
    eventJson['room'] = result[1].group(1)!;
    eventJson['subject'] = result[3].group(1)!;
    eventJson['chapter'] = result[4].group(1)!;
    eventJson['participants'] = result[5].group(1)!.split(' / ');
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
