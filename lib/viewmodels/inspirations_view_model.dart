import 'package:flutter/foundation.dart';

import '../models/inspiration.dart';
import '../services/inspiration_image_store.dart';
import '../services/inspiration_repository.dart';

/// Holds the in-memory list of inspirations and persists every change.
///
/// Exposes an immutable view sorted newest-first via [inspirations] and
/// notifies listeners after each mutation. Storage writes are awaited so
/// the on-disk state matches the in-memory state when the call returns.
class InspirationsViewModel extends ChangeNotifier {
  InspirationsViewModel(this._repository, this._imageStore) {
    _bootstrap();
  }

  final InspirationRepository _repository;
  final InspirationImageStore _imageStore;
  final List<Inspiration> _items = <Inspiration>[];

  bool _loaded = false;
  bool get isLoaded => _loaded;

  /// Newest-first unmodifiable view of the current list.
  List<Inspiration> get inspirations => List.unmodifiable(_items);

  Future<void> _bootstrap() async {
    final loaded = await _repository.getAll();
    _items
      ..clear()
      ..addAll(loaded)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    _loaded = true;
    notifyListeners();
  }

  /// Inserts a new inspiration at the top of the list and persists it.
  ///
  /// [imagePath] is the absolute path returned by [InspirationImageStore.save];
  /// pass null when the user picked no image.
  Future<Inspiration> add({required String text, String? imagePath}) async {
    final inspiration = Inspiration(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      text: text,
      imagePath: imagePath,
      createdAt: DateTime.now(),
    );
    _items.insert(0, inspiration);
    await _repository.insert(inspiration);
    notifyListeners();
    return inspiration;
  }

  /// Replaces the inspiration with the same [Inspiration.id] and persists
  /// it. Does not delete any old image file — callers should compare
  /// the previous and new [Inspiration.imagePath] and call
  /// [InspirationImageStore.deleteByPath] for the stale path.
  Future<void> update(Inspiration inspiration) async {
    final index = _items.indexWhere((i) => i.id == inspiration.id);
    if (index == -1) {
      return;
    }
    _items[index] = inspiration;
    _items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    await _repository.update(inspiration);
    notifyListeners();
  }

  /// Removes the inspiration with [id] from the list, deletes its image
  /// file if any, and persists the change.
  Future<void> delete(String id) async {
    final index = _items.indexWhere((i) => i.id == id);
    if (index == -1) {
      return;
    }
    final removed = _items.removeAt(index);
    await _imageStore.deleteByPath(removed.imagePath);
    await _repository.delete(id);
    notifyListeners();
  }

  /// Searches inspirations whose text matches [query] using FTS5.
  /// Returns results sorted by relevance.
  Future<List<Inspiration>> search(String query) async {
    if (query.trim().isEmpty) {
      return _items.toList();
    }
    return _repository.search(query.trim());
  }
}
