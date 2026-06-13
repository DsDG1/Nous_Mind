/// A single inspiration entry persisted in local storage.
///
/// An inspiration is a short text note optionally accompanied by an image
/// that lives in the app's documents directory (see
/// [InspirationImageStore]). [imagePath] is the absolute path to that file
/// and may be null when the inspiration has no image.
class Inspiration {
  const Inspiration({
    required this.id,
    required this.text,
    required this.createdAt,
    this.imagePath,
  });

  /// Stable, time-based identifier (microseconds since epoch as a string).
  final String id;

  /// User-provided text content shown in the list and editor.
  final String text;

  /// Absolute path to the inspiration's image on disk, or null if none.
  final String? imagePath;

  /// When the inspiration was first created.
  final DateTime createdAt;

  /// Returns a copy with the given fields replaced.
  ///
  /// [clearImage] lets callers explicitly set [imagePath] back to null;
  /// without it, passing [imagePath] as null would be indistinguishable from
  /// "leave unchanged" because of the [??] operator.
  Inspiration copyWith({
    String? text,
    String? imagePath,
    bool clearImage = false,
  }) => Inspiration(
    id: id,
    text: text ?? this.text,
    imagePath: clearImage ? null : (imagePath ?? this.imagePath),
    createdAt: createdAt,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'text': text,
    'image_path': imagePath,
    'created_at': createdAt.toIso8601String(),
  };

  factory Inspiration.fromJson(Map<String, dynamic> json) => Inspiration(
    id: json['id'] as String,
    text: json['text'] as String,
    imagePath: json['image_path'] as String?,
    createdAt: DateTime.parse(json['created_at'] as String),
  );
}
