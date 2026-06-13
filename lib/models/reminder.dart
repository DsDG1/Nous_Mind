/// A single reminder entry persisted in local storage.
class Reminder {
  const Reminder({
    required this.id,
    required this.title,
    required this.reminderTime,
  });

  /// Stable, time-based identifier (microseconds since epoch as a string).
  final String id;

  /// User-provided title shown in the list and editor.
  final String title;

  /// When the reminder is set for.
  final DateTime reminderTime;

  Reminder copyWith({String? title, DateTime? reminderTime}) => Reminder(
    id: id,
    title: title ?? this.title,
    reminderTime: reminderTime ?? this.reminderTime,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'reminder_time': reminderTime.toIso8601String(),
  };

  factory Reminder.fromJson(Map<String, dynamic> json) => Reminder(
    id: json['id'] as String,
    title: json['title'] as String,
    reminderTime: DateTime.parse(json['reminder_time'] as String),
  );
}
