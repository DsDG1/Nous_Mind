import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:nousmind/models/inspiration.dart';
import 'package:nousmind/viewmodels/inspirations_view_model.dart';
import 'package:nousmind/widgets/empty_state.dart';
import 'package:nousmind/widgets/inspiration_list_item.dart';

/// Home screen for the inspirations tab: shows all inspirations, hosts the
/// FAB to add a new one, and routes taps to the editor and left-swipes to
/// delete.
class InspirationsHomePage extends StatefulWidget {
  const InspirationsHomePage({super.key});

  @override
  State<InspirationsHomePage> createState() => _InspirationsHomePageState();
}

class _InspirationsHomePageState extends State<InspirationsHomePage> {
  final String _query = '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('灵感'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: '搜索',
            onPressed: () => _showSearch(context),
          ),
        ],
      ),
      body: Consumer<InspirationsViewModel>(
        builder: (context, viewModel, _) {
          if (!viewModel.isLoaded) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = _query.isEmpty
              ? viewModel.inspirations
              : viewModel.inspirations
                    .where(
                      (i) =>
                          i.text.toLowerCase().contains(_query.toLowerCase()),
                    )
                    .toList();
          if (items.isEmpty) {
            return EmptyState(
              icon: _query.isEmpty ? Icons.lightbulb_outline : Icons.search_off,
              title: _query.isEmpty ? '还没有灵感' : '没有匹配结果',
              subtitle: _query.isEmpty ? '点击右下角 + 记录一条' : '换个关键词试试',
            );
          }
          return ListView.separated(
            itemCount: items.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final inspiration = items[index];
              return InspirationListItem(
                inspiration: inspiration,
                onTap: () => _openEditor(context, inspiration),
                onDelete: () => _delete(context, viewModel, inspiration.id),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'inspirations-fab',
        onPressed: () => _openEditor(context, null),
        tooltip: '添加灵感',
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showSearch(BuildContext context) {
    showSearch(
      context: context,
      delegate: _InspirationSearchDelegate(
        viewModel: context.read<InspirationsViewModel>(),
        onTap: (inspiration) {
          context.push('/inspirations/editor', extra: inspiration);
        },
        onDelete: (id) {
          context.read<InspirationsViewModel>().delete(id);
        },
      ),
    );
  }

  Future<void> _openEditor(BuildContext context, Inspiration? existing) async {
    await context.push('/inspirations/editor', extra: existing);
  }

  Future<void> _delete(
    BuildContext context,
    InspirationsViewModel viewModel,
    String id,
  ) async {
    await viewModel.delete(id);
  }
}

class _InspirationSearchDelegate extends SearchDelegate<String> {
  _InspirationSearchDelegate({
    required this.viewModel,
    required this.onTap,
    required this.onDelete,
  });

  final InspirationsViewModel viewModel;
  final void Function(Inspiration) onTap;
  final void Function(String) onDelete;

  @override
  String get searchFieldLabel => '搜索灵感...';

  @override
  List<Widget>? buildActions(BuildContext context) {
    return [
      if (query.isNotEmpty)
        IconButton(icon: const Icon(Icons.clear), onPressed: () => query = ''),
    ];
  }

  @override
  Widget? buildLeading(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back),
      onPressed: () => close(context, ''),
    );
  }

  @override
  Widget buildResults(BuildContext context) => _buildList(context);

  @override
  Widget buildSuggestions(BuildContext context) => _buildList(context);

  Widget _buildList(BuildContext context) {
    final results = viewModel.inspirations
        .where((i) => i.text.toLowerCase().contains(query.toLowerCase()))
        .toList();
    if (results.isEmpty) {
      return const EmptyState(
        icon: Icons.search_off,
        title: '没有匹配结果',
        subtitle: '换个关键词试试',
      );
    }
    return ListView.separated(
      itemCount: results.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final inspiration = results[index];
        return InspirationListItem(
          inspiration: inspiration,
          onTap: () {
            close(context, inspiration.id);
            onTap(inspiration);
          },
          onDelete: () => onDelete(inspiration.id),
        );
      },
    );
  }
}
