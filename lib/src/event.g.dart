// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'event.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Event _$EventFromJson(Map<String, dynamic> json) => Event(
      id: json['id'] as int,
      type: $enumDecode(_$EventTypeEnumMap, json['type']),
      start: DateTime.parse(json['start'] as String),
      end: DateTime.parse(json['end'] as String),
      room: json['room'] as String,
      subject: json['subject'] as String,
      chapter: json['chapter'] as String,
      participants: (json['participants'] as List<dynamic>)
          .map((e) => e as String)
          .toList(),
    );

Map<String, dynamic> _$EventToJson(Event instance) => <String, dynamic>{
      'id': instance.id,
      'type': _$EventTypeEnumMap[instance.type]!,
      'start': instance.start.toIso8601String(),
      'end': instance.end.toIso8601String(),
      'room': instance.room,
      'subject': instance.subject,
      'chapter': instance.chapter,
      'participants': instance.participants,
    };

const _$EventTypeEnumMap = {
  EventType.course: 'course',
  EventType.exam: 'exam',
  EventType.leave: 'leave',
  EventType.meeting: 'meeting',
  EventType.practicalWork: 'practicalWork',
  EventType.supervisedWork: 'supervisedWork',
  EventType.undefined: 'undefined',
};
