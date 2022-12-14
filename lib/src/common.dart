import 'package:isen_aurion_client/src/error.dart';
import 'package:isen_aurion_client/src/event.dart';

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

  List<String> result = [];
  if (data.startsWith(RegExp(r'\d\dh\d\d'))) {
    // if the event is from ISEN Ouest
    result = data.split(' - ');

    // if the chapter contains ' - ' it will be joined.
    if (result.length == 8) {
      var start = result.sublist(0, 4);
      result = result.sublist(4).reversed.toList();
      var end = result.sublist(0, 2).reversed.toList();
      result = result.sublist(2).reversed.toList();
      result = start + [result.join(' - ')] + end;
    }

    if (RegExp(r'\d\dh\d\d - \d\dh\d\d').hasMatch(data)) {
      eventJson['room'] = result[6];
    } else {
      eventJson['room'] = result[1];
    }

    eventJson['subject'] = result[3];
    eventJson['chapter'] = result[4];
    eventJson['participants'] = result[5].split(' / ');

    if (result.length != 7) {
      throw Exception(
          'Event is not in the expected format. Could not be parsed.');
    }
  } else if (data.split('\n').length == 6 &&
      RegExp(r'\d\d:\d\d - \d\d:\d\d').hasMatch(data.split('\n')[4])) {
    // if the event is from ISEN Lille
    result = data.split('\n');
    eventJson['room'] = '${result[0]} - ${result[1]}';
    eventJson['subject'] = result[2];
    eventJson['chapter'] = '';
    eventJson['participants'] = result[5].split(' / ');
  } else {
    throw Exception(
        'Event is not in the expected format. Could not be parsed.');
  }

  return Event.fromJson(eventJson);
}

/// Gets the [EventType] of a [String].
EventType mapType(String rawType) {
  switch (rawType) {
    case "CONGES":
      return EventType.leave;
    case "CM":
    case "COURS":
      return EventType.course;
    case "est-epreuve":
    case "EVALUATION":
      return EventType.exam;
    case "REUNION":
      return EventType.meeting;
    case "TD":
    case "COURS_TD":
      return EventType.supervisedWork;
    case "TP":
      return EventType.practicalWork;
    default:
      return EventType.undefined;
  }
}
