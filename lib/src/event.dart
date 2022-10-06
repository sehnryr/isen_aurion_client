/// Possible event types
enum EventType {
  course,
  exam,
  leave,
  meeting,
  practicalWork,
  supervisedWork,
  undefined,
}

/// Schedule event class.
class Event {
  final int id;
  final EventType type;
  final DateTime start;
  final DateTime end;
  final String room;
  final String subject;
  final String chapter;
  final List<String> participants;

  const Event({
    required this.id,
    required this.type,
    required this.start,
    required this.end,
    required this.room,
    required this.subject,
    required this.chapter,
    required this.participants,
  });

  @override
  String toString() => subject;

  DateTime get day => DateTime(
        start.year,
        start.month,
        start.day,
      );
}
