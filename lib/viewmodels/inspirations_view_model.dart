import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';

import 'package:nousmind/models/inspiration.dart';
import 'package:nousmind/services/ai/ai_image_ocr.dart';
import 'package:nousmind/services/inspiration_image_store.dart';
import 'package:nousmind/services/inspiration_repository.dart';
import 'package:nousmind/viewmodels/settings_view_model.dart';

/// Holds the in-memory list of active inspirations and persists every change.
///
/// Exposes an immutable view sorted newest-first via [inspirations] and
/// notifies listeners after each mutation. Storage writes are awaited so
/// the on-disk state matches the in-memory state when the call returns.
class InspirationsViewModel extends ChangeNotifier {
  InspirationsViewModel(this._repository, this._imageStore, this._settings) {
    _bootstrap();
  }

  final InspirationRepository _repository;
  final InspirationImageStore _imageStore;
  final SettingsViewModel _settings;
  final List<Inspiration> _items = <Inspiration>[];

  int _trashCount = 0;

  bool _loaded = false;
  bool get isLoaded => _loaded;

  /// Newest-first unmodifiable view of the current list of active inspirations.
  List<Inspiration> get inspirations => List.unmodifiable(_items);

  /// Number of inspirations currently in the trash.
  int get trashCount => _trashCount;

  Future<void> _bootstrap() async {
    final loaded = await _repository.getAll();
    _trashCount = await _repository.countTrash();
    _items
      ..clear()
      ..addAll(loaded)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    _loaded = true;
    notifyListeners();
    await _purgeExpiredTrash();
  }

  /// Reloads the in-memory list from the database.
  Future<void> refresh() => _bootstrap();

  /// Refreshes the cached trash count.
  Future<void> refreshTrashCount() async {
    _trashCount = await _repository.countTrash();
    notifyListeners();
  }

  /// Fetches the trashed inspirations from the database.
  Future<List<Inspiration>> refreshAndFetchTrash() async {
    final items = await _repository.getAllTrash();
    _trashCount = items.length;
    return items;
  }

  /// Inserts a new inspiration at the top of the list and persists it.
  Future<Inspiration> add({required String text, String? imagePath}) async {
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final inspiration = Inspiration(
      id: id,
      text: text,
      imagePath: imagePath,
      createdAt: DateTime.now(),
    );
    _items.insert(0, inspiration);
    await _repository.insert(inspiration);
    notifyListeners();

    if (imagePath != null) {
      _runOcrAndSave(id, imagePath);
    }

    return inspiration;
  }

  /// Replaces the inspiration with the same [Inspiration.id] and persists it.
  Future<void> update(Inspiration inspiration) async {
    final index = _items.indexWhere((i) => i.id == inspiration.id);
    if (index == -1) {
      return;
    }
    final oldInspiration = _items[index];
    final bool pathChanged = oldInspiration.imagePath != inspiration.imagePath;

    Inspiration updatedInspiration = inspiration;
    if (pathChanged) {
      updatedInspiration = inspiration.copyWith(clearOcrText: true);
    } else {
      updatedInspiration = inspiration.copyWith(
        ocrText: oldInspiration.ocrText,
      );
    }

    _items[index] = updatedInspiration;
    _items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    await _repository.update(updatedInspiration);
    notifyListeners();

    if (pathChanged && inspiration.imagePath != null) {
      _runOcrAndSave(inspiration.id, inspiration.imagePath!);
    }
  }

  Future<void> _runOcrAndSave(String id, String imagePath) async {
    try {
      final ocrText = await runOcr(
        imagePath: imagePath,
        useChinese: _settings.settings.chineseOcrEnabled,
      );
      final index = _items.indexWhere((i) => i.id == id);
      if (index != -1) {
        final current = _items[index];
        if (current.imagePath == imagePath) {
          final updated = current.copyWith(ocrText: ocrText);
          _items[index] = updated;
          await _repository.update(updated);
          notifyListeners();
        }
      }
    } catch (e, stackTrace) {
      developer.log(
        'OCR background task failed',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Soft-deletes the inspiration with [id] from the list, keeping its image
  /// file on disk for potential recovery.
  Future<void> delete(String id, {DateTime? now}) async {
    final index = _items.indexWhere((i) => i.id == id);
    if (index == -1) {
      return;
    }
    final deletedAt = now ?? DateTime.now();
    _items.removeAt(index);
    _trashCount += 1;
    notifyListeners();
    await _repository.softDelete(id, deletedAt);
  }

  /// Restores a soft-deleted inspiration back to the active list.
  Future<void> restore(String id) async {
    final original = await _repository.findById(id);
    if (original == null) return;
    final restored = original.copyWith(isDeleted: false, clearDeletedAt: true);
    _items.removeWhere((i) => i.id == id);
    _items.insert(0, restored);
    _items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    _trashCount = (_trashCount - 1).clamp(0, 1 << 30);
    notifyListeners();
    await _repository.restore(id);
  }

  /// Batch-restores multiple soft-deleted inspirations.
  Future<int> restoreAll(List<String> ids) async {
    if (ids.isEmpty) return 0;
    final trashed = await _repository.getAllTrash();
    final toRestore = <Inspiration>[];
    for (final i in trashed) {
      if (ids.contains(i.id)) {
        toRestore.add(i.copyWith(isDeleted: false, clearDeletedAt: true));
      }
    }
    if (toRestore.isEmpty) return 0;
    _items.removeWhere((i) => ids.contains(i.id));
    _items.addAll(toRestore);
    _items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    _trashCount = (_trashCount - toRestore.length).clamp(0, 1 << 30);
    notifyListeners();
    await _repository.restoreByIds(ids);
    return toRestore.length;
  }

  /// Permanently removes every trashed inspiration and its image from disk.
  Future<int> purgeTrash() async {
    final trashed = await _repository.getAllTrash();
    if (trashed.isEmpty) return 0;
    final ids = trashed.map((i) => i.id).toList();
    await _repository.permanentDeleteByIds(ids);
    for (final i in trashed) {
      final imagePath = i.imagePath;
      if (imagePath != null) {
        try {
          await _imageStore.deleteByPath(imagePath);
        } on Exception catch (error, stackTrace) {
          developer.log(
            'Failed to delete trashed inspiration image',
            error: error,
            stackTrace: stackTrace,
          );
        }
      }
    }
    _trashCount = 0;
    notifyListeners();
    return trashed.length;
  }

  /// Searches inspirations whose text matches [query].
  Future<List<Inspiration>> search(String query) async {
    if (query.trim().isEmpty) {
      return _items.toList();
    }
    return _repository.search(query.trim());
  }

  Future<void> _purgeExpiredTrash() async {
    final cutoff = DateTime.now().subtract(const Duration(days: 30));
    final purgedImagePaths = await _repository.purgeTrashOlderThan(cutoff);
    if (purgedImagePaths.isNotEmpty) {
      for (final path in purgedImagePaths) {
        if (path == null) continue;
        try {
          await _imageStore.deleteByPath(path);
        } on Exception catch (error, stackTrace) {
          developer.log(
            'Failed to delete expired trashed inspiration image during purge',
            error: error,
            stackTrace: stackTrace,
          );
        }
      }
      _trashCount = await _repository.countTrash();
      notifyListeners();
    }
  }

  /// Hook for app foreground resume.
  Future<void> onAppResumed() => _purgeExpiredTrash();

  /// Removes every active inspiration and its associated image file.
  Future<int> clearAll() async {
    final all = List<Inspiration>.from(_items);
    for (final inspiration in all) {
      await _imageStore.deleteByPath(inspiration.imagePath);
    }
    final removed = await _repository.clearAll();
    _items.clear();
    notifyListeners();
    return removed;
  }
}
