import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/inspiration.dart';
import '../viewmodels/inspirations_view_model.dart';
import '../widgets/empty_state.dart';
import '../widgets/inspiration_list_item.dart';

/// Home screen for the inspirations tab: shows all inspirations, hosts the
/// FAB to add a new one, and routes taps to the editor and left-swipes to
/// delete.
class InspirationsHomePage extends StatelessWidget {
  const InspirationsHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('灵感')),
      body: Consumer<InspirationsViewModel>(
        builder: (context, viewModel, _) {
          if (!viewModel.isLoaded) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = viewModel.inspirations;
          if (items.isEmpty) {
            return const EmptyState(
              icon: Icons.lightbulb_outline,
              title: '还没有灵感',
              subtitle: '点击右下角 + 记录一条',
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
        onPressed: () => _openEditor(context, null),
        tooltip: '添加灵感',
        child: const Icon(Icons.add),
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
