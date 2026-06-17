import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'package:nousmind/models/tag.dart';
import 'package:nousmind/services/tag_repository.dart';

/// Owns the in-memory tag list and routes every mutation through
/// the persistent [TagRepository]. Mutations on built-in tags are
/// silently ignored — the UI hides the controls, but a defensive
/// check here prevents a future caller from accidentally writing
/// to a reserved id.
///
/// Like [RemindersViewModel], the view model rebuilds UI in the
/// same frame as `notifyListeners`; the DB write is awaited after.
/// The brief window where in-memory and on-disk state disagree is
/// bounded by the next event-loop tick and is acceptable because
/// the worst-case observable (a reload before the write lands) is
/// the previous stable state, not a corrupted row.
class TagsViewModel extends ChangeNotifier {
  TagsViewModel(this._repository) {
    _bootstrap();
  }

  static const int customTagCap = 10;

  final TagRepository _repository;
  final List<Tag> _tags = <Tag>[];
  bool _loaded = false;
  bool get isLoaded => _loaded;

  /// Unmodifiable view of the current tag list, in display order.
  List<Tag> get tags => List.unmodifiable(_tags);

  /// Lookup by id. Returns `null` for both unknown ids and the
  /// `null` sentinel (callers usually want a `Tag?` either way).
  Tag? byId(String? id) {
    if (id == null) return null;
    for (final tag in _tags) {
      if (tag.id == id) return tag;
    }
    return null;
  }

  /// Number of custom (non-built-in) tags. Used by the settings
  /// subpage to disable the add button when the cap is hit.
  int get customCount => _tags.where((t) => !t.builtIn).length;

  /// Reloads from the database. Used after a destructive
  /// repository action (e.g. a hard reset from data settings) so
  /// the in-memory state mirrors disk.
  Future<void> refresh() async {
    final loaded = await _repository.getAll();
    _tags
      ..clear()
      ..addAll(loaded);
    _loaded = true;
    notifyListeners();
  }

  Future<void> _bootstrap() async {
    try {
      final loaded = await _repository.getAll();
      _tags
        ..clear()
        ..addAll(loaded);
    } on Exception catch (error, stackTrace) {
      developer.log(
        'Failed to load tags',
        error: error,
        stackTrace: stackTrace,
      );
    } finally {
      _loaded = true;
      notifyListeners();
    }
  }

  /// Inserts a new custom tag. Refuses to insert when the cap is
  /// reached or when the name is empty / already in use.
  /// Returns the new tag on success, `null` on refusal.
  Future<Tag?> add({required String name, required int color}) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return null;
    if (_tags.any((t) => t.name == trimmed)) return null;
    if (customCount >= customTagCap) return null;

    final tag = Tag(
      id: _generateId(),
      name: trimmed,
      color: color,
      builtIn: false,
      // Custom tags sort after the built-ins (which use
      // sortOrder 0..3 and 100); 50 is the "custom bucket" so a
      // future reorder feature has room to slot them in.
      sortOrder: 50,
    );
    _tags.add(tag);
    notifyListeners();
    try {
      await _repository.insert(tag);
    } on Exception catch (error, stackTrace) {
      developer.log(
        'Failed to insert tag',
        error: error,
        stackTrace: stackTrace,
      );
      _tags.remove(tag);
      notifyListeners();
      rethrow;
    }
    return tag;
  }

  /// Renames a custom tag. No-op for built-ins. Trims the new name
  /// and refuses empty / duplicate values.
  Future<void> rename(String id, String newName) async {
    final found = _findIndex(id);
    if (found == null || found.$1.builtIn) return;
    final trimmed = newName.trim();
    if (trimmed.isEmpty) return;
    if (trimmed == found.$1.name) return;
    if (_tags.any((t) => t.id != id && t.name == trimmed)) return;
    final updated = found.$1.copyWith(name: trimmed);
    _tags[found.$2] = updated;
    notifyListeners();
    try {
      await _repository.update(updated);
    } on Exception catch (error, stackTrace) {
      developer.log(
        'Failed to rename tag',
        error: error,
        stackTrace: stackTrace,
      );
      _tags[found.$2] = found.$1;
      notifyListeners();
      rethrow;
    }
  }

  /// Recolors a custom tag. No-op for built-ins.
  Future<void> recolor(String id, int newColor) async {
    final found = _findIndex(id);
    if (found == null || found.$1.builtIn) return;
    if (found.$1.color == newColor) return;
    final updated = found.$1.copyWith(color: newColor);
    _tags[found.$2] = updated;
    notifyListeners();
    try {
      await _repository.update(updated);
    } on Exception catch (error, stackTrace) {
      developer.log(
        'Failed to recolor tag',
        error: error,
        stackTrace: stackTrace,
      );
      _tags[found.$2] = found.$1;
      notifyListeners();
      rethrow;
    }
  }

  /// Deletes a custom tag. No-op for built-ins. Re-throws
  /// [TagInUseException] from the repository unchanged so the
  /// caller can show the right error.
  Future<void> deleteCustom(String id) async {
    final found = _findIndex(id);
    if (found == null || found.$1.builtIn) return;
    _tags.removeAt(found.$2);
    notifyListeners();
    try {
      await _repository.delete(id);
    } on Exception catch (error, stackTrace) {
      developer.log(
        'Failed to delete tag',
        error: error,
        stackTrace: stackTrace,
      );
      _tags.insert(found.$2, found.$1);
      notifyListeners();
      rethrow;
    }
  }

  /// Helper: find a tag and its index. Returns a (Tag, int) record
  /// so the index stays stable across `List` mutations; callers
  /// access fields via `$1` / `$2` because named-record field
  /// inference is brittle across the public `flutter_lints`
  /// baseline.
  (Tag, int)? _findIndex(String id) {
    for (var i = 0; i < _tags.length; i++) {
      if (_tags[i].id == id) return (_tags[i], i);
    }
    return null;
  }

  /// Random UUID4 (hex). `Random.secure` is intentional — tag
  /// ids are not a security boundary, but using the secure RNG
  /// avoids depending on the test-friendly `Random()` factory and
  /// matches the convention used by `ai_response_parser.dart`.
  String _generateId() {
    final rand = Random.secure();
    String hex(int bytes) {
      return List.generate(
        bytes,
        (_) => rand.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
    }
    return '${hex(4)}-${hex(2)}-${hex(2)}-${hex(2)}-${hex(6)}';
  }
}
