/// A single reminder entry persisted in local storage.
class Reminder {
  Reminder({
    required this.id,
    required this.title,
    required this.reminderTime,
    this.imagePath,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  /// Stable, time-based identifier (microseconds since epoch as a string).
  final String id;

  /// User-provided title shown in the list and editor.
  final String title;

  /// When the reminder is set for.
  final DateTime reminderTime;

  /// Optional path to an attached image stored in the app's image directory.
  final String? imagePath;

  /// When the reminder was first created.
  final DateTime createdAt;

  Reminder copyWith({
    String? title,
    DateTime? reminderTime,
    String? imagePath,
    bool clearImage = false,
  }) => Reminder(
    id: id,
    title: title ?? this.title,
    reminderTime: reminderTime ?? this.reminderTime,
    imagePath: clearImage ? null : (imagePath ?? this.imagePath),
    createdAt: createdAt,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'reminder_time': reminderTime.toIso8601String(),
    'created_at': createdAt.toIso8601String(),
    if (imagePath != null) 'image_path': imagePath,
  };

  factory Reminder.fromJson(Map<String, dynamic> json) => Reminder(
    id: json['id'] as String,
    title: json['title'] as String,
    reminderTime: DateTime.parse(json['reminder_time'] as String),
    imagePath: json['image_path'] as String?,
    createdAt: json['created_at'] != null
        ? DateTime.parse(json['created_at'] as String)
        : null,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'title': title,
    'reminder_time': reminderTime.toIso8601String(),
    'image_path': imagePath,
    'created_at': createdAt.toIso8601String(),
  };

  factory Reminder.fromMap(Map<String, dynamic> map) => Reminder(
    id: map['id'] as String,
    title: map['title'] as String,
    reminderTime: DateTime.parse(map['reminder_time'] as String),
    imagePath: map['image_path'] as String?,
    createdAt: DateTime.parse(map['created_at'] as String),
  );
}
