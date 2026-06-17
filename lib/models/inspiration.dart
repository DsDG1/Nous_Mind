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
    this.ocrText,
    this.isDeleted = false,
    this.deletedAt,
  });

  /// Stable, time-based identifier (microseconds since epoch as a string).
  final String id;

  /// User-provided text content shown in the list and editor.
  final String text;

  /// Absolute path to the inspiration's image on disk, or null if none.
  final String? imagePath;

  /// When the inspiration was first created.
  final DateTime createdAt;

  /// OCR text recognized from the image, used for searching.
  final String? ocrText;

  /// Whether the inspiration has been moved to the trash.
  final bool isDeleted;

  /// Instant the inspiration was soft-deleted, or null when active.
  final DateTime? deletedAt;

  /// Returns a copy with the given fields replaced.
  ///
  /// [clearImage] lets callers explicitly set [imagePath] back to null;
  /// without it, passing [imagePath] as null would be indistinguishable from
  /// "leave unchanged" because of the [??] operator.
  Inspiration copyWith({
    String? text,
    String? imagePath,
    bool clearImage = false,
    String? ocrText,
    bool clearOcrText = false,
    bool? isDeleted,
    DateTime? deletedAt,
    bool clearDeletedAt = false,
  }) => Inspiration(
    id: id,
    text: text ?? this.text,
    imagePath: clearImage ? null : (imagePath ?? this.imagePath),
    createdAt: createdAt,
    ocrText: clearOcrText ? null : (ocrText ?? this.ocrText),
    isDeleted: isDeleted ?? this.isDeleted,
    deletedAt: clearDeletedAt ? null : (deletedAt ?? this.deletedAt),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'text': text,
    'image_path': imagePath,
    'created_at': createdAt.toIso8601String(),
    'ocr_text': ocrText,
    'is_deleted': isDeleted ? 1 : 0,
    'deleted_at': deletedAt?.toIso8601String(),
  };

  factory Inspiration.fromJson(Map<String, dynamic> json) => Inspiration(
    id: json['id'] as String,
    text: json['text'] as String,
    imagePath: json['image_path'] as String?,
    createdAt: DateTime.parse(json['created_at'] as String),
    ocrText: json['ocr_text'] as String?,
    isDeleted: (json['is_deleted'] as int? ?? 0) == 1,
    deletedAt: json['deleted_at'] == null
        ? null
        : DateTime.parse(json['deleted_at'] as String),
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'text': text,
    'created_at': createdAt.toIso8601String(),
    'image_path': imagePath,
    'ocr_text': ocrText,
    'is_deleted': isDeleted ? 1 : 0,
    'deleted_at': deletedAt?.toIso8601String(),
  };

  factory Inspiration.fromMap(Map<String, dynamic> map) => Inspiration(
    id: map['id'] as String,
    text: map['text'] as String,
    imagePath: map['image_path'] as String?,
    createdAt: DateTime.parse(map['created_at'] as String),
    ocrText: map['ocr_text'] as String?,
    isDeleted: (map['is_deleted'] as int? ?? 0) == 1,
    deletedAt: map['deleted_at'] == null
        ? null
        : DateTime.parse(map['deleted_at'] as String),
  );
}
