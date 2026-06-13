import 'dart:developer' as developer;
import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Copies picked images into the app's documents directory so they survive
/// gallery edits / deletions and aren't tied to a transient cache path.
///
/// Compression is delegated entirely to [ImagePicker] at pick time via
/// `maxWidth` and `imageQuality`; this store just persists whatever the
/// picker produced, preserving its original extension (HEIF stays HEIF,
/// JPEG stays JPEG, etc.).
class InspirationImageStore {
  InspirationImageStore(this._imagesDir);

  /// Builds a store rooted at `<app docs>/inspiration_images`, creating the
  /// directory if it does not yet exist.
  static Future<InspirationImageStore> create() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'inspiration_images'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return InspirationImageStore(dir);
  }

  final Directory _imagesDir;

  /// The directory where inspiration images live.
  Directory get imagesDir => _imagesDir;

  /// Copies [source] into the managed directory and returns its absolute path.
  ///
  /// The destination filename keeps the source's extension so the file's
  /// format is preserved on disk.
  Future<String> save({
    required String inspirationId,
    required XFile source,
  }) async {
    final safeId = inspirationId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final ext = p.extension(source.path);
    final basename = ext.isEmpty ? safeId : '$safeId$ext';
    final dest = File(p.join(_imagesDir.path, basename));
    await File(source.path).copy(dest.path);
    return dest.path;
  }

  /// Deletes the file at [absolutePath] if it lives inside [imagesDir].
  ///
  /// Silently ignores missing files or paths outside the managed directory,
  /// so it's always safe to call even when the file has already been removed
  /// or the stored path is stale.
  Future<void> deleteByPath(String? absolutePath) async {
    if (absolutePath == null) {
      return;
    }
    if (!p.isWithin(_imagesDir.path, absolutePath)) {
      return;
    }
    final file = File(absolutePath);
    if (!await file.exists()) {
      return;
    }
    try {
      await file.delete();
    } on FileSystemException catch (error, stackTrace) {
      developer.log(
        'Failed to delete inspiration image',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
}
